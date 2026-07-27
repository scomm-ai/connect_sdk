import 'dart:async';

import '../../domain/entities/webrtc_ice_route.dart';
import '../native/libdatachannel_peer_connection.dart';
import 'webrtc_ice_route_stats_parser.dart';

class WebRtcIceRouteMonitor {
  WebRtcIceRouteMonitor(this._parser);

  final WebRtcIceRouteStatsParser _parser;

  final _controller = StreamController<WebRtcIceRoute>.broadcast();
  Timer? _timer;
  bool _refreshInFlight = false;
  WebRtcIceRoute _current = const WebRtcIceRoute();

  Stream<WebRtcIceRoute> get routes => _controller.stream;
  WebRtcIceRoute get current => _current;

  void start(LibDataChannelPeerConnection pc) {
    stop();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(refresh(pc));
    });
  }

  Future<WebRtcIceRoute> refresh(LibDataChannelPeerConnection pc) async {
    if (_refreshInFlight) return _current;

    _refreshInFlight = true;
    try {
      final pair = pc.selectedCandidatePair();
      final next = _parser.parseCandidatePair(
        localCandidate: pair?.local,
        remoteCandidate: pair?.remote,
      );
      if (_current != next) {
        _current = next;
        if (!_controller.isClosed) {
          _controller.add(next);
        }
      }
      return _current;
    } finally {
      _refreshInFlight = false;
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> dispose() async {
    stop();
    await _controller.close();
  }
}
