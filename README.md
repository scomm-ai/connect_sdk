# SComm Connector

> **Authentication:** Scomm no longer exchanges mailbox/IMAP credentials. Host apps inject AppAuth tokens via `SignalingAccessTokenProvider` and `ScommConnectorController.setAccessToken()`. See the stack migration guide: [../README.md](../README.md).

`scommconnector` is a Flutter package for connecting an app to the SComm backend. It provides session management, device identity registration, signaling, WebRTC session handling, presence watching, and JSON message transport over a WebRTC data channel.

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
      url: https://github.com/dev10m-adv/scommconnector_flutter
      ref: main
```

Then run:

```sh
flutter pub get
```

## Basic Setup

Initialize Flutter bindings first, then initialize the SComm dependency graph with your signaling server details.

```dart
import 'package:flutter/widgets.dart';
import 'package:scommconnector/scomm_connector.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

## Authenticate A User

The package supports IMAP credentials and external provider token exchange.

### IMAP Login

```dart
await scomm.login(
  ScommImapLoginConfig(
    email: 'user@example.com',
    password: 'imap-password',
    host: 'imap.example.com',
    port: 993,
    useTls: true,
  ),
);
```

### Google, Outlook, Or Other Provider Token Login

```dart
await scomm.login(
  ScommTokenExchangeLoginConfig(
    provider: 'Google',
    externalAccessToken: accessToken,
    email: 'user@example.com',
  ),
);
```

Use `provider: 'Outlook'` for Outlook token exchange.

## Register Or Load A Device

After authentication, register the current device once:

```dart
await scomm.registerDevice(
  'My Laptop',
  'desktop',
  DeviceMode.hybrid,
);
```

Available device modes are:

```dart
DeviceMode.unspecified
DeviceMode.client
DeviceMode.provider
DeviceMode.hybrid
```

To reuse a saved device identity:

```dart
final identity = await scomm.loadMyCurrentDeviceIdentity('user@example.com');
final deviceId = identity?.deviceId;
```

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

Call `start` after the user is authenticated and a device id is available.

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
  print('sent=${speed.sentBytesPerSecond}, received=${speed.receivedBytesPerSecond}');
});

scomm.iceRoutes.listen((route) {
  print(route.toJson());
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

## Watch Presence

```dart
await scomm.watchPresence([
  'scomm:peer@example.com/peer-device-id',
]);

scomm.presenceEvents.listen((event) {
  print('${event.deviceUri} is ${event.status}');
});

scomm.onlineDevicesStream.listen((onlineUris) {
  print('Online devices: $onlineUris');
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
      print('Response: ${message.data}');
      break;
    case ScommMessageType.stream:
      print('Stream chunk: ${message.data}');
      break;
    case ScommMessageType.event:
      print('Event: ${message.data}');
      break;
  }
});
```

### Send A Request

```dart
final requestId = await scomm.sendDatachannelRequest(
  service: 'ollama',
  action: 'generate',
  data: {
    'prompt': 'Hello',
  },
);
```

### Send A Response

```dart
await scomm.sendDatachannelResponse(
  requestId: requestId,
  service: 'ollama',
  action: 'generate',
  data: {
    'text': 'Hello back',
  },
);
```

### Send A Stream Chunk

```dart
await scomm.sendDatachannelStream(
  requestId: requestId,
  service: 'ollama',
  action: 'generate',
  data: {
    'chunk': 'partial text',
    'done': false,
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
  print('Data channel open: $isOpen');
});

scomm.scommConnectionState.listen((state) {
  print('WebRTC connection state: $state');
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
await runScommConnectorDI(host, port, useTls);

final scomm = ScommConnectorController();
await scomm.initialize();

await scomm.login(
  ScommImapLoginConfig(
    email: email,
    password: password,
    host: imapHost,
    port: 993,
    useTls: true,
  ),
);

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
  print(message.toJson());
});
```

## Notes

- Call `runScommConnectorDI` before creating or using `ScommConnectorController`.
- Call `initialize` before login/start so controller streams are subscribed.
- `start` requires an authenticated user and a valid registered device id.
- Connection requests and data channel messages require the signaling server to be reachable.
- TURN server credentials should come from secure configuration, not hardcoded source.
