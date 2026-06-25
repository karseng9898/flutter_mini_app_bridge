# flutter_mini_app_bridge

A Flutter package for communication between a Flutter SuperApp and web-based Mini Apps.

## Features

- Register and manage bridge methods.
- Access optional request metadata, including `miniAppId`.
- Create event payloads for Mini Apps.
- Apply execution timeouts and redact sensitive values from bridge logs.

## Installation

Add the package to `pubspec.yaml`:

```yaml
dependencies:
  flutter_mini_app_bridge: ^1.0.2
```

Then run:

```bash
flutter pub get
```

## Flutter usage

Create a controller and register a params-only method:

```dart
import 'package:flutter_mini_app_bridge/flutter_mini_app_bridge.dart';

final bridgeController = MiniAppBridgeController(
  logger: (message) => print(message),
  methodTimeout: const Duration(seconds: 30),
);

bridgeController.registerMethod(
  'exampleClass',
  'exampleMethod',
  (params) async {
    return BridgeResponse.success({
      'result': 'Hello from Flutter!',
    });
  },
);
```

Use `registerRequestHandler` when a method needs request metadata:

```dart
bridgeController.registerRequestHandler(
  'account',
  'getProfile',
  (request) async {
    return BridgeResponse.success({
      'miniAppId': request.miniAppId,
      'locale': request.meta['locale'],
    });
  },
);
```

Process an incoming request and send the returned JSON string back to the Mini App:

```dart
final response = await bridgeController.processRequest(messageFromMiniApp);
```

## JavaScript usage

Load the matching JavaScript bridge:

```html
<script src="https://unpkg.com/js-mini-app-bridge-plus@1.0.2/mini-app-bridge.min.js"></script>
```

Metadata is optional. Configure a default `miniAppId` when all calls belong to the same Mini App:

```js
window.superapp.setDefaultMeta({
  miniAppId: "wallet"
});

const response = await window.superapp.call(
  "exampleClass",
  "exampleMethod",
  { someParam: "value" }
);
```

Metadata may also be provided for one call and can contain custom keys:

```js
await window.superapp.call(
  "account",
  "getProfile",
  {},
  {
    meta: {
      miniAppId: "loyalty",
      locale: "en-MY"
    }
  }
);
```

The request payload uses this shape:

```json
{
  "id": "sa_...",
  "className": "account",
  "method": "getProfile",
  "params": {},
  "meta": {
    "miniAppId": "loyalty",
    "locale": "en-MY"
  }
}
```

## API reference

### Flutter

- `registerMethod(className, methodName, handler, {override})`: registers a params-only method.
- `registerRequestHandler(className, methodName, handler, {override})`: registers a handler that receives a `BridgeRequest` with `params`, `meta`, and `miniAppId`.
- `unregisterMethod(className, methodName)`: unregisters a method.
- `processRequest(message)`: processes an incoming JSON request.
- `createEventPayload(eventName, data)`: creates a JSON event payload.
- `unregisterAllMethods()`: clears all registered methods.

### JavaScript

- `window.superapp.call(className, methodName, params?, options?)`
- `window.superapp.setDefaultMeta(meta?)`
- `window.superapp.getDefaultMeta()`
- `window.superapp.clearDefaultMeta()`
- `window.superapp.addListener(eventName, callback)`
- `window.superapp.removeListener(eventName, callback)`
- `window.superapp.getParams(key?)`
- `window.superapp.receiveMessage(response)`

Credential-like values are redacted from bridge logs.

## License

This project is licensed under the MIT License.
