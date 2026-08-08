# SComm Connector

> **Authentication:** Scomm does **not** exchange mailbox/IMAP credentials. Host apps inject an AppAuth (or other) access token via `SignalingAccessTokenProvider` and/or `ScommConnectorController.setAccessToken()`. Prefer passing the **user email** as `userId` (not an opaque JWT `sub`).

`scommconnector` is a Flutter package for connecting an app to the SComm backend. It provides session management, device identity registration, signaling, WebRTC session handling (via **libdatachannel** FFI), presence watching, and JSON message transport over a WebRTC data channel.

The main public API is exported from:

```dart
import 'package:scommconnector/scomm_connector.dart';
```

## Add The Package

For local development inside this repository:

```yaml
dependencies:
  scommconnector:
    path: ../scommCode/scommconnector
```

For Git usage:

```yaml
dependencies:
  scommconnector:
    git:
      url: https://github.com/scomm-ai/connect_sdk
      ref: main
```

Then run:

```sh
flutter pub get
```

## Native WebRTC (libdatachannel FFI)

This package is a Flutter **FFI plugin**. It builds and bundles
[libdatachannel](https://github.com/idrto/libdatachannel) for:

| Platform | Artifact |
|----------|----------|
| Android  | `libdatachannel.so` (CMake / NDK) |
| Windows  | `datachannel.dll` (CMake) |
| Linux    | `libdatachannel.so` (CMake) |
| iOS / macOS | static `libdatachannel.a` via CocoaPods script |

### Prebuilt binaries (preferred in CI)

App CI should download release assets instead of compiling mbedtls + libdatachannel:

```sh
./tool/download_native_prebuilts.sh   # tag from native/PREBUILT_TAG
```

CMake/Gradle/CocoaPods auto-use `native/prebuilt/<triple>/` when present.
Force a source build with `SCOMM_FORCE_SOURCE=1`. See [`native/prebuilt/README.md`](native/prebuilt/README.md).

Publish new assets via `.github/workflows/native-prebuilts.yml` (`native-v*` tags or workflow_dispatch).

After changing native code:

```sh
flutter clean
flutter pub get
flutter run
```

### Optional desktop helper build

```powershell
git submodule update --init --recursive
.\tool\ensure_mbedtls.ps1
.\tool\build_libdatachannel.ps1
```

Override the library path with `LIBDATACHANNEL_PATH` if needed.

### Branch

Native libdatachannel FFI + prebuilts live on **`main`**.

## Basic Setup

Initialize Flutter bindings first, then initialize the SComm dependency graph with your signaling server details.

```dart
import 'package:flutter/widgets.dart';
import 'package:scommconnector/scomm_connector.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Optional: receive package logs in your app (silent by default).
  ScommLog.setLogger(MyAppScommLogger());

  await runScommConnectorDI(
    'your-signaling-server-host',
    443,
    true,
  );

  final scomm = ScommConnectorController();
  await scomm.initialize();

  runApp(MyApp(scomm: scomm));
}
```

`ScommConnectorController` is a singleton, so `ScommConnectorController()` always returns the same controller instance.

## Logging (opt-in)

The package **never prints to the console on its own**. All internal logs go through `ScommLog`, which is a no-op until the host registers a logger.

```dart
class MyAppScommLogger implements ScommLogger {
  @override
  void debug(String message) => debugPrint(message);

  @override
  void info(String message) => debugPrint(message);

  @override
  void warning(String message, [Object? error, StackTrace? stackTrace]) {
    debugPrint('WARN $message ${error ?? ''}');
  }

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    debugPrint('ERROR $message ${error ?? ''}');
  }
}

ScommLog.setLogger(MyAppScommLogger());
// Later, to silence again:
ScommLog.setLogger(null);
```

## Authenticate A User

Inject the host AppAuth (or equivalent) access token. Always pass the **email** when you have it so device identity and URIs stay stable across restarts.

```dart
await scomm.setAccessToken(
  accessToken,
  userId: 'user@example.com', // prefer email over JWT sub
);
```

Recommended host pattern:

1. Register a `SignalingAccessTokenProvider` that returns the current AppAuth token and seeds the session with the profile **email**.
2. Optionally listen to AppAuth session changes and call `setAccessToken(token, userId: email)` again when the profile updates.

Helpers:

```dart
looksLikeEmail('user@example.com'); // true
normalizeSignalingUserId('User@Example.com'); // user@example.com
```

Logout:

```dart
await scomm.logout();
```

## Register Or Load A Device

Device identity is persisted **by email** (secure storage key), never by opaque JWT ids. After authentication with an email, register the current device once:

```dart
await scomm.registerDevice(
  'My Laptop',
  'desktop',
  DeviceMode.hybrid,
);
```

Available device modes:

```dart
DeviceMode.unspecified
DeviceMode.client
DeviceMode.provider
DeviceMode.hybrid
```

To reuse a saved device identity, load with the **same email** used at register time:

```dart
final identity = await scomm.loadMyCurrentDeviceIdentity('user@example.com');
final deviceId = identity?.deviceId;
```

If you pass a non-email lookup key (for example a JWT `sub`), load returns `null` and does not create a misleading registered state.

You can also manage identities with:

```dart
await scomm.listMyDevices();
await scomm.listDeviceServices(deviceId);
await scomm.updateDevice(
  deviceId: deviceId,
  deviceName: 'New Name',
  deviceType: 'desktop',
  mode: DeviceMode.hybrid,
);
await scomm.deleteDevice(deviceId);
```

## Start SComm Realtime

Call `start` after the user is authenticated and a device id is available. The local URI becomes `scomm:{email}/{deviceId}`.

```dart
await scomm.start(
  ScommStartConfig(
    deviceId: deviceId,
    serverAddress: 'your-signaling-server-host',
    serverPort: 443,
    useTls: true,
    email: 'user@example.com',
    iceServers: const [
      WebRtcIceServerConfig(
        urls: ['stun:stun.l.google.com:19302'],
      ),
      WebRtcIceServerConfig(
        urls: ['turn:turn.example.com:3478'],
        username: 'turn-user',
        credential: 'turn-password',
      ),
    ],
  ),
);
```

Use `restart(config)` to stop and start again with a new config, or `stop()` to stop signaling and WebRTC.

## Listen To State

`sessionState` gives the current snapshot. `stream` emits updates.

```dart
final state = scomm.sessionState;

scomm.stream.listen((state) {
  final ready = state.canStartRealtime;
  final connected = state.connectedRemoteUris;
  final activeRemote = state.activeRemoteUri;
});
```

Useful controller streams and snapshots:

```dart
scomm.stateChanges.listen((_) {
  final auth = scomm.sessionState.authState;
  final identity = scomm.identityState;
  final signaling = scomm.signalingState;
  final webrtc = scomm.webrtcState;
});

scomm.transferSpeeds.listen((speed) {
  // sentBytesPerSecond / receivedBytesPerSecond
});

scomm.iceRoutes.listen((route) {
  // route.toJson()
});
```

## Connect To Another Device

Device URIs use this shape:

```text
scomm:user@example.com/device-id
```

Start a connection request:

```dart
await scomm.sendConnectionRequestDetailed(
  toUri: 'scomm:peer@example.com/peer-device-id',
  serviceName: 'main',
  note: 'connect from my app',
  timeout: const Duration(seconds: 12),
);
```

The shorter method is also available:

```dart
await scomm.sendConnectionRequest('scomm:peer@example.com/peer-device-id');
```

Handle incoming connection requests:

```dart
scomm.scommConnectionIncomingRequests.listen((request) async {
  final requestId = request.connectionRequest?.requestId;
  if (requestId == null || requestId.isEmpty) return;

  await scomm.acceptConnectionRequest(requestId);
  // Or:
  // await scomm.rejectConnectionRequest(requestId, reason: 'Busy');
});
```

After accepting or initiating a connection, the controller binds the selected session streams automatically. If you manually change connection/session handling, call:

```dart
await scomm.bindSelectedSessionStreams();
```

### Select An Existing Connected Peer

Datachannel sends go to the **selected** session. To target a peer that is already connected (exact or soft URI match), without starting a new connection:

```dart
final selected = await scomm.selectSessionByRemoteUri(
  'scomm:peer@example.com/peer-device-id',
);
if (!selected) {
  // Not connected yet, or WebRTC status is not `connected`.
}
```

Soft matching normalizes case and `scomm:` vs `scomm://` prefixes. Selection succeeds only when that session’s WebRTC status is `connected`.

## Watch Presence

```dart
await scomm.watchPresence([
  'scomm:peer@example.com/peer-device-id',
]);

scomm.presenceEvents.listen((event) {
  // event.deviceUri / event.status
});

scomm.onlineDevicesStream.listen((onlineUris) {
  // list of online watched URIs
});
```

## Data Channel Messaging

Structured data channel messages use:

```dart
ScommRemoteMessage(
  type: ScommMessageType.request,
  requestId: 'request-id',
  service: 'service-name',
  action: 'action-name',
  data: {'key': 'value'},
)
```

### Listen For Messages

```dart
scomm.scommDataChannelMessages.listen((message) async {
  switch (message.type) {
    case ScommMessageType.request:
      await scomm.sendDatachannelResponse(
        requestId: message.requestId!,
        service: message.service,
        action: message.action,
        data: {'ok': true},
      );
      break;
    case ScommMessageType.response:
    case ScommMessageType.stream:
    case ScommMessageType.event:
      break;
  }
});
```

### Send A Request

Prefer selecting the peer first when more than one session may exist:

```dart
await scomm.selectSessionByRemoteUri('scomm:peer@example.com/peer-device-id');

final requestId = await scomm.sendDatachannelRequest(
  service: 'ollama',
  action: 'ping',
  data: const {},
);
```

### Send A Response

```dart
await scomm.sendDatachannelResponse(
  requestId: requestId,
  service: 'ollama',
  action: 'ping',
  data: {
    'available': true,
  },
);
```

### Send A Stream Chunk

```dart
await scomm.sendDatachannelStream(
  requestId: requestId,
  service: 'ollama',
  action: 'stream',
  data: {
    'chunk': 'partial text',
  },
);
```

### Send An Event

```dart
await scomm.sendDatachannelEvent(
  service: 'presence',
  action: 'ping',
  data: {
    'time': DateTime.now().toIso8601String(),
  },
);
```

You can also send a raw string over the main data channel:

```dart
await scomm.sendMessageOverDataChannel('raw message');
```

## Connection Status

```dart
scomm.isDataChannelOpen.listen((isOpen) {
  // selected session data channel open?
});

scomm.scommConnectionState.listen((state) {
  // WebRTC connection state for selected session
});
```

To stop the active WebRTC session:

```dart
await scomm.stopWebRtc();
```

To stop a specific remote URI:

```dart
await scomm.stopWebRtcForUri('scomm:peer@example.com/peer-device-id');
```

## Cleanup

When the app shuts down or the owning service is destroyed:

```dart
await scomm.dispose();
```

To clear shared preferences used by the package:

```dart
await clearCache();
```

## Typical Flow

```dart
ScommLog.setLogger(MyAppScommLogger());

await runScommConnectorDI(host, port, useTls);

final scomm = ScommConnectorController();
await scomm.initialize();

await scomm.setAccessToken(accessToken, userId: email);

await scomm.registerDevice('My Device', 'desktop', DeviceMode.hybrid);

final saved = await scomm.loadMyCurrentDeviceIdentity(email);
final deviceId = saved?.deviceId;
if (deviceId == null || deviceId.isEmpty) {
  throw StateError('Device was not saved after registration.');
}

await scomm.start(
  ScommStartConfig(
    deviceId: deviceId,
    serverAddress: host,
    serverPort: port,
    useTls: useTls,
    email: email,
    iceServers: const [
      WebRtcIceServerConfig(urls: ['stun:stun.l.google.com:19302']),
    ],
  ),
);

scomm.scommConnectionIncomingRequests.listen((request) async {
  final requestId = request.connectionRequest?.requestId;
  if (requestId != null && requestId.isNotEmpty) {
    await scomm.acceptConnectionRequest(requestId);
  }
});

scomm.scommDataChannelMessages.listen((message) {
  // handle request / response / stream / event
});
```

## Notes

- Call `runScommConnectorDI` before creating or using `ScommConnectorController`.
- Call `initialize` before auth/start so controller streams are subscribed.
- Prefer **email** for `setAccessToken(..., userId:)` and `loadMyCurrentDeviceIdentity`.
- Device local persistence is email-keyed; using JWT `sub` for load/save will miss the saved device.
- Package logs are silent until `ScommLog.setLogger(...)` is set.
- `start` requires an authenticated user and a valid registered device id.
- Connection requests and data channel messages require the signaling server to be reachable.
- Use `selectSessionByRemoteUri` before datachannel send when targeting a specific already-connected peer.
- TURN server credentials should come from secure configuration, not hardcoded source.
