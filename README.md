# flutter_mini_app_bridge

A Flutter package that provides a robust bridge between your Flutter SuperApp and web-based mini-apps. This package offers an easy way to register and invoke bridge methods on the Flutter side while seamlessly integrating with a JavaScript bridge.

## Features

- **Bridge Method Registration:** Register, invoke, and manage bridge methods with ease.
- **Event Management:** Listen for and dispatch events between Flutter and your mini-app.

## Installation

Add `flutter_mini_app_bridge` to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_mini_app_bridge: ^1.0.0
```

Then run:

```bash
flutter pub get
```

## Usage

### Flutter Side

1. **Import the Package:**

   ```dart
   import 'package:flutter_mini_app_bridge/flutter_mini_app_bridge.dart';
   ```

2. **Create an Instance of the Bridge Controller:**

   ```dart
   final bridgeController = MiniAppBridgeController(
     logger: (msg) => print(msg),
     methodTimeout: Duration(seconds: 30),
   );
   ```

3. **Register a Bridge Method:**

   ```dart
   bridgeController.registerMethod('exampleClass', 'exampleMethod', (params) async {
     return BridgeResponse.success({'result': 'Hello from Flutter!'});
   });
   ```

   Use `registerRequestHandler` when the method needs metadata such as
   `miniAppId` or `authorization`:

   ```dart
   bridgeController.registerRequestHandler('account', 'getProfile', (request) async {
     final miniAppId = request.miniAppId;
     final authorization = request.authorization;

     return BridgeResponse.success({
       'miniAppId': miniAppId,
       'hasAuthorization': authorization != null,
     });
   });
   ```

4. **Process Incoming Requests:**

   ```dart
   String response = await bridgeController.processRequest(messageFromMiniApp);
   // Send the response back to the mini-app
   ```

### JavaScript Side

1. **Include the Script in Your HTML:**

   ```html
   <script src="https://unpkg.com/js-mini-app-bridge-plus@1.0.0/mini-app-bridge.min.js"></script>
   ```

2. **Using the Bridge in Your Mini-App:**

   ```javascript
   superapp.setDefaultMeta({
     miniAppId: "wallet",
     authorization: "Bearer access-token"
   });

   superapp
     .call("exampleClass", "exampleMethod", { someParam: "value" })
     .then((response) => {
       console.log("Response from Flutter:", response);
     })
     .catch((error) => {
       console.error("Error calling Flutter method:", error);
     });
   ```

   You can also pass metadata for one call:

   ```javascript
   await superapp.call("account", "getProfile", {}, {
     meta: {
       miniAppId: "loyalty",
       authorization: "Bearer loyalty-token"
     }
   });
   ```

## API Reference

### Flutter Bridge Controller

- **registerMethod(className, methodName, handler, {override})**
  Registers a params-only bridge method.
- **registerRequestHandler(className, methodName, handler, {override})**
  Registers a metadata-aware bridge method. The handler receives a `BridgeRequest`
  with `params`, `meta`, `miniAppId`, and `authorization`.
- **unregisterMethod(className, methodName)**
  Unregisters a specific bridge method.
- **processRequest(message)**
  Processes an incoming mini-app request.
- **createEventPayload(eventName, data)**
  Creates a JSON payload for events.
- **unregisterAllMethods()**
  Clears all registered methods.

### JavaScript Bridge

- **window.superapp.call(className, methodName, params?)**
  Calls a native Flutter method. Pass `{ meta: {...} }` as the fourth argument
  for per-call metadata.
- **window.superapp.setDefaultMeta(meta?)**
  Sets metadata sent with every bridge request.
- **window.superapp.getDefaultMeta()**
  Returns configured default metadata.
- **window.superapp.clearDefaultMeta()**
  Clears configured default metadata.
- **window.superapp.addListener(eventName, callback)**
  Adds an event listener.
- **window.superapp.removeListener(eventName, callback)**
  Removes an event listener.
- **window.superapp.getParams(key?)**
  Retrieves stored parameters.
- **window.superapp.receiveMessage(response)**
  Processes incoming messages.

Sensitive values in fields such as `authorization`, `token`, `accessToken`,
`refreshToken`, `password`, `secret`, `cookie`, and `apiKey` are redacted from
bridge logs.

## Contributing

Contributions are welcome! Feel free to open issues or submit pull requests on [GitHub](https://github.com/karseng9898/flutter_mini_app_bridge).

## License

This project is licensed under the MIT License.
