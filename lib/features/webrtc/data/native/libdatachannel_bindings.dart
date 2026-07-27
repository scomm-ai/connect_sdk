import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Low-level FFI bindings for libdatachannel C API (`rtc.h`).
class LibDataChannelBindings {
  LibDataChannelBindings(DynamicLibrary lib)
    : rtcPreload = lib
          .lookup<NativeFunction<Bool Function()>>('rtcPreload')
          .asFunction(),
      rtcCleanup = lib
          .lookup<NativeFunction<Void Function()>>('rtcCleanup')
          .asFunction(),
      rtcInitLogger = lib
          .lookup<
            NativeFunction<
              Void Function(Int32, Pointer<NativeFunction<RtcLogCallbackNative>>)
            >
          >('rtcInitLogger')
          .asFunction(),
      rtcCreatePeerConnection = lib
          .lookup<
            NativeFunction<Int32 Function(Pointer<RtcConfigurationNative>)>
          >('rtcCreatePeerConnection')
          .asFunction(),
      rtcClosePeerConnection = lib
          .lookup<NativeFunction<Int32 Function(Int32)>>('rtcClosePeerConnection')
          .asFunction(),
      rtcDeletePeerConnection = lib
          .lookup<NativeFunction<Int32 Function(Int32)>>(
            'rtcDeletePeerConnection',
          )
          .asFunction(),
      rtcSetLocalDescriptionCallback = lib
          .lookup<
            NativeFunction<
              Int32 Function(
                Int32,
                Pointer<NativeFunction<RtcDescriptionCallbackNative>>,
              )
            >
          >('rtcSetLocalDescriptionCallback')
          .asFunction(),
      rtcSetLocalCandidateCallback = lib
          .lookup<
            NativeFunction<
              Int32 Function(
                Int32,
                Pointer<NativeFunction<RtcCandidateCallbackNative>>,
              )
            >
          >('rtcSetLocalCandidateCallback')
          .asFunction(),
      rtcSetStateChangeCallback = lib
          .lookup<
            NativeFunction<
              Int32 Function(
                Int32,
                Pointer<NativeFunction<RtcStateChangeCallbackNative>>,
              )
            >
          >('rtcSetStateChangeCallback')
          .asFunction(),
      rtcSetIceStateChangeCallback = lib
          .lookup<
            NativeFunction<
              Int32 Function(
                Int32,
                Pointer<NativeFunction<RtcIceStateChangeCallbackNative>>,
              )
            >
          >('rtcSetIceStateChangeCallback')
          .asFunction(),
      rtcSetDataChannelCallback = lib
          .lookup<
            NativeFunction<
              Int32 Function(
                Int32,
                Pointer<NativeFunction<RtcDataChannelCallbackNative>>,
              )
            >
          >('rtcSetDataChannelCallback')
          .asFunction(),
      rtcSetLocalDescription = lib
          .lookup<NativeFunction<Int32 Function(Int32, Pointer<Utf8>)>>(
            'rtcSetLocalDescription',
          )
          .asFunction(),
      rtcSetRemoteDescription = lib
          .lookup<
            NativeFunction<Int32 Function(Int32, Pointer<Utf8>, Pointer<Utf8>)>
          >('rtcSetRemoteDescription')
          .asFunction(),
      rtcAddRemoteCandidate = lib
          .lookup<
            NativeFunction<Int32 Function(Int32, Pointer<Utf8>, Pointer<Utf8>)>
          >('rtcAddRemoteCandidate')
          .asFunction(),
      rtcGetLocalDescription = lib
          .lookup<
            NativeFunction<Int32 Function(Int32, Pointer<Utf8>, Int32)>
          >('rtcGetLocalDescription')
          .asFunction(),
      rtcGetRemoteDescription = lib
          .lookup<
            NativeFunction<Int32 Function(Int32, Pointer<Utf8>, Int32)>
          >('rtcGetRemoteDescription')
          .asFunction(),
      rtcGetLocalDescriptionType = lib
          .lookup<
            NativeFunction<Int32 Function(Int32, Pointer<Utf8>, Int32)>
          >('rtcGetLocalDescriptionType')
          .asFunction(),
      rtcGetRemoteDescriptionType = lib
          .lookup<
            NativeFunction<Int32 Function(Int32, Pointer<Utf8>, Int32)>
          >('rtcGetRemoteDescriptionType')
          .asFunction(),
      rtcGetSelectedCandidatePair = lib
          .lookup<
            NativeFunction<
              Int32 Function(
                Int32,
                Pointer<Utf8>,
                Int32,
                Pointer<Utf8>,
                Int32,
              )
            >
          >('rtcGetSelectedCandidatePair')
          .asFunction(),
      rtcCreateDataChannel = lib
          .lookup<NativeFunction<Int32 Function(Int32, Pointer<Utf8>)>>(
            'rtcCreateDataChannel',
          )
          .asFunction(),
      rtcDeleteDataChannel = lib
          .lookup<NativeFunction<Int32 Function(Int32)>>('rtcDeleteDataChannel')
          .asFunction(),
      rtcGetDataChannelLabel = lib
          .lookup<
            NativeFunction<Int32 Function(Int32, Pointer<Utf8>, Int32)>
          >('rtcGetDataChannelLabel')
          .asFunction(),
      rtcSetOpenCallback = lib
          .lookup<
            NativeFunction<
              Int32 Function(
                Int32,
                Pointer<NativeFunction<RtcOpenCallbackNative>>,
              )
            >
          >('rtcSetOpenCallback')
          .asFunction(),
      rtcSetClosedCallback = lib
          .lookup<
            NativeFunction<
              Int32 Function(
                Int32,
                Pointer<NativeFunction<RtcClosedCallbackNative>>,
              )
            >
          >('rtcSetClosedCallback')
          .asFunction(),
      rtcSetErrorCallback = lib
          .lookup<
            NativeFunction<
              Int32 Function(
                Int32,
                Pointer<NativeFunction<RtcErrorCallbackNative>>,
              )
            >
          >('rtcSetErrorCallback')
          .asFunction(),
      rtcSetMessageCallback = lib
          .lookup<
            NativeFunction<
              Int32 Function(
                Int32,
                Pointer<NativeFunction<RtcMessageCallbackNative>>,
              )
            >
          >('rtcSetMessageCallback')
          .asFunction(),
      rtcSendMessage = lib
          .lookup<
            NativeFunction<Int32 Function(Int32, Pointer<Utf8>, Int32)>
          >('rtcSendMessage')
          .asFunction(),
      rtcClose = lib
          .lookup<NativeFunction<Int32 Function(Int32)>>('rtcClose')
          .asFunction(),
      rtcDelete = lib
          .lookup<NativeFunction<Int32 Function(Int32)>>('rtcDelete')
          .asFunction(),
      rtcIsOpen = lib
          .lookup<NativeFunction<Bool Function(Int32)>>('rtcIsOpen')
          .asFunction();

  final bool Function() rtcPreload;
  final void Function() rtcCleanup;
  final void Function(
    int level,
    Pointer<NativeFunction<RtcLogCallbackNative>> cb,
  )
  rtcInitLogger;

  final int Function(Pointer<RtcConfigurationNative> config)
  rtcCreatePeerConnection;
  final int Function(int pc) rtcClosePeerConnection;
  final int Function(int pc) rtcDeletePeerConnection;

  final int Function(
    int pc,
    Pointer<NativeFunction<RtcDescriptionCallbackNative>> cb,
  )
  rtcSetLocalDescriptionCallback;
  final int Function(
    int pc,
    Pointer<NativeFunction<RtcCandidateCallbackNative>> cb,
  )
  rtcSetLocalCandidateCallback;
  final int Function(
    int pc,
    Pointer<NativeFunction<RtcStateChangeCallbackNative>> cb,
  )
  rtcSetStateChangeCallback;
  final int Function(
    int pc,
    Pointer<NativeFunction<RtcIceStateChangeCallbackNative>> cb,
  )
  rtcSetIceStateChangeCallback;
  final int Function(
    int pc,
    Pointer<NativeFunction<RtcDataChannelCallbackNative>> cb,
  )
  rtcSetDataChannelCallback;

  final int Function(int pc, Pointer<Utf8> type) rtcSetLocalDescription;
  final int Function(int pc, Pointer<Utf8> sdp, Pointer<Utf8> type)
  rtcSetRemoteDescription;
  final int Function(int pc, Pointer<Utf8> cand, Pointer<Utf8> mid)
  rtcAddRemoteCandidate;

  final int Function(int pc, Pointer<Utf8> buffer, int size)
  rtcGetLocalDescription;
  final int Function(int pc, Pointer<Utf8> buffer, int size)
  rtcGetRemoteDescription;
  final int Function(int pc, Pointer<Utf8> buffer, int size)
  rtcGetLocalDescriptionType;
  final int Function(int pc, Pointer<Utf8> buffer, int size)
  rtcGetRemoteDescriptionType;
  final int Function(
    int pc,
    Pointer<Utf8> local,
    int localSize,
    Pointer<Utf8> remote,
    int remoteSize,
  )
  rtcGetSelectedCandidatePair;

  final int Function(int pc, Pointer<Utf8> label) rtcCreateDataChannel;
  final int Function(int dc) rtcDeleteDataChannel;
  final int Function(int dc, Pointer<Utf8> buffer, int size)
  rtcGetDataChannelLabel;

  final int Function(
    int id,
    Pointer<NativeFunction<RtcOpenCallbackNative>> cb,
  )
  rtcSetOpenCallback;
  final int Function(
    int id,
    Pointer<NativeFunction<RtcClosedCallbackNative>> cb,
  )
  rtcSetClosedCallback;
  final int Function(
    int id,
    Pointer<NativeFunction<RtcErrorCallbackNative>> cb,
  )
  rtcSetErrorCallback;
  final int Function(
    int id,
    Pointer<NativeFunction<RtcMessageCallbackNative>> cb,
  )
  rtcSetMessageCallback;
  final int Function(int id, Pointer<Utf8> data, int size) rtcSendMessage;
  final int Function(int id) rtcClose;
  final int Function(int id) rtcDelete;
  final bool Function(int id) rtcIsOpen;
}

// Native callback typedefs
typedef RtcLogCallbackNative =
    Void Function(Int32 level, Pointer<Utf8> message);
typedef RtcDescriptionCallbackNative =
    Void Function(
      Int32 pc,
      Pointer<Utf8> sdp,
      Pointer<Utf8> type,
      Pointer<Void> ptr,
    );
typedef RtcCandidateCallbackNative =
    Void Function(
      Int32 pc,
      Pointer<Utf8> cand,
      Pointer<Utf8> mid,
      Pointer<Void> ptr,
    );
typedef RtcStateChangeCallbackNative =
    Void Function(Int32 pc, Int32 state, Pointer<Void> ptr);
typedef RtcIceStateChangeCallbackNative =
    Void Function(Int32 pc, Int32 state, Pointer<Void> ptr);
typedef RtcDataChannelCallbackNative =
    Void Function(Int32 pc, Int32 dc, Pointer<Void> ptr);
typedef RtcOpenCallbackNative = Void Function(Int32 id, Pointer<Void> ptr);
typedef RtcClosedCallbackNative = Void Function(Int32 id, Pointer<Void> ptr);
typedef RtcErrorCallbackNative =
    Void Function(Int32 id, Pointer<Utf8> error, Pointer<Void> ptr);
typedef RtcMessageCallbackNative =
    Void Function(
      Int32 id,
      Pointer<Utf8> message,
      Int32 size,
      Pointer<Void> ptr,
    );

/// Mirrors `rtcConfiguration` from rtc.h (layout-sensitive).
final class RtcConfigurationNative extends Struct {
  external Pointer<Pointer<Utf8>> iceServers;
  @Int32()
  external int iceServersCount;
  external Pointer<Utf8> proxyServer;
  external Pointer<Utf8> bindAddress;
  @Int32()
  external int certificateType;
  external Pointer<Utf8> certificatePemFile;
  external Pointer<Utf8> keyPemFile;
  external Pointer<Utf8> keyPemPass;
  @Int32()
  external int iceTransportPolicy;
  @Bool()
  external bool enableIceTcp;
  @Bool()
  external bool enableIceUdpMux;
  @Bool()
  external bool disableAutoNegotiation;
  @Bool()
  external bool forceMediaTransport;
  @Uint16()
  external int portRangeBegin;
  @Uint16()
  external int portRangeEnd;
  @Int32()
  external int mtu;
  @Int32()
  external int maxMessageSize;
}

/// libdatachannel peer connection states (`rtcState`).
abstract final class RtcState {
  static const int newState = 0;
  static const int connecting = 1;
  static const int connected = 2;
  static const int disconnected = 3;
  static const int failed = 4;
  static const int closed = 5;
}

/// libdatachannel ICE states (`rtcIceState`).
abstract final class RtcIceState {
  static const int newState = 0;
  static const int checking = 1;
  static const int connected = 2;
  static const int completed = 3;
  static const int failed = 4;
  static const int disconnected = 5;
  static const int closed = 6;
}

abstract final class RtcError {
  static const int success = 0;
  static const int invalid = -1;
  static const int failure = -2;
  static const int notAvail = -3;
  static const int tooSmall = -4;
}
