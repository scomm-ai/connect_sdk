import 'package:test/test.dart';
import 'package:scommconnector/features/webrtc/data/services/webrtc_ice_route_stats_parser.dart';
import 'package:scommconnector/features/webrtc/domain/entities/webrtc_ice_route.dart';

void main() {
  const parser = WebRtcIceRouteStatsParser();

  test('parses host candidate pair', () {
    final route = parser.parseCandidatePair(
      localCandidate:
          'candidate:1 1 UDP 2122252543 192.168.1.2 54321 typ host',
      remoteCandidate:
          'candidate:2 1 UDP 2122252542 192.168.1.3 54322 typ host',
    );

    expect(route.routeType, WebRtcIceRouteType.host);
    expect(route.localCandidateType, WebRtcIceCandidateType.host);
    expect(route.remoteCandidateType, WebRtcIceCandidateType.host);
    expect(route.localProtocol, 'udp');
  });

  test('classifies relay when either side is relay', () {
    final route = parser.parseCandidatePair(
      localCandidate:
          'candidate:1 1 UDP 100 1.2.3.4 3478 typ relay raddr 10.0.0.1 rport 9',
      remoteCandidate:
          'candidate:2 1 UDP 200 5.6.7.8 9 typ srflx raddr 10.0.0.2 rport 9',
    );

    expect(route.routeType, WebRtcIceRouteType.relay);
    expect(route.localCandidateType, WebRtcIceCandidateType.relay);
    expect(route.remoteCandidateType, WebRtcIceCandidateType.srflx);
  });
}
