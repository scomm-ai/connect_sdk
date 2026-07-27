import '../../domain/entities/webrtc_ice_route.dart';

/// Parses ICE route info from libdatachannel selected candidate pair strings.
class WebRtcIceRouteStatsParser {
  const WebRtcIceRouteStatsParser();

  WebRtcIceRoute parseCandidatePair({
    String? localCandidate,
    String? remoteCandidate,
  }) {
    if ((localCandidate == null || localCandidate.isEmpty) &&
        (remoteCandidate == null || remoteCandidate.isEmpty)) {
      return const WebRtcIceRoute();
    }

    final localType = _parseCandidateTypeFromSdp(localCandidate);
    final remoteType = _parseCandidateTypeFromSdp(remoteCandidate);

    return WebRtcIceRoute(
      routeType: _classifyRoute(localType, remoteType),
      localCandidateType: localType,
      remoteCandidateType: remoteType,
      localProtocol: _parseProtocol(localCandidate),
      remoteProtocol: _parseProtocol(remoteCandidate),
      candidatePairId: _pairId(localCandidate, remoteCandidate),
    );
  }

  WebRtcIceRouteType _classifyRoute(
    WebRtcIceCandidateType localType,
    WebRtcIceCandidateType remoteType,
  ) {
    if (localType == WebRtcIceCandidateType.relay ||
        remoteType == WebRtcIceCandidateType.relay) {
      return WebRtcIceRouteType.relay;
    }

    if (localType == WebRtcIceCandidateType.srflx ||
        remoteType == WebRtcIceCandidateType.srflx ||
        localType == WebRtcIceCandidateType.prflx ||
        remoteType == WebRtcIceCandidateType.prflx) {
      return WebRtcIceRouteType.srflx;
    }

    if (localType == WebRtcIceCandidateType.host &&
        remoteType == WebRtcIceCandidateType.host) {
      return WebRtcIceRouteType.host;
    }

    return WebRtcIceRouteType.unknown;
  }

  WebRtcIceCandidateType _parseCandidateTypeFromSdp(String? candidate) {
    if (candidate == null || candidate.isEmpty) {
      return WebRtcIceCandidateType.unknown;
    }

    // candidate:... typ host/srflx/prflx/relay ...
    final match = RegExp(
      r'\btyp\s+(host|srflx|prflx|relay)\b',
      caseSensitive: false,
    ).firstMatch(candidate);
    return _parseCandidateType(match?.group(1));
  }

  String? _parseProtocol(String? candidate) {
    if (candidate == null || candidate.isEmpty) return null;
    final match = RegExp(
      r'\b(udp|tcp)\b',
      caseSensitive: false,
    ).firstMatch(candidate);
    return match?.group(1)?.toLowerCase();
  }

  String? _pairId(String? local, String? remote) {
    if ((local == null || local.isEmpty) &&
        (remote == null || remote.isEmpty)) {
      return null;
    }
    return '${local ?? ''}|${remote ?? ''}';
  }

  WebRtcIceCandidateType _parseCandidateType(Object? rawValue) {
    final normalized = rawValue?.toString().toLowerCase().trim();
    switch (normalized) {
      case 'host':
        return WebRtcIceCandidateType.host;
      case 'srflx':
        return WebRtcIceCandidateType.srflx;
      case 'prflx':
        return WebRtcIceCandidateType.prflx;
      case 'relay':
        return WebRtcIceCandidateType.relay;
      default:
        return WebRtcIceCandidateType.unknown;
    }
  }
}
