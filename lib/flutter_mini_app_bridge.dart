import 'dart:async';
import 'dart:convert';

/// A response from a bridge method call.
class BridgeResponse {
  /// The data returned by the bridge method.
  final Map<String, dynamic> data;

  /// Whether the bridge method call was successful.
  final bool success;

  /// Optional error message for failed calls.
  final String? errorMessage;

  /// Creates a response with the given data and success status.
  const BridgeResponse({this.data = const {}, required this.success, this.errorMessage});

  /// Creates an error response with the given error message.
  factory BridgeResponse.error(String error) {
    return BridgeResponse(data: {'error': error}, success: false, errorMessage: error);
  }

  /// Creates a success response with the given data.
  factory BridgeResponse.success([Map<String, dynamic> result = const {}]) {
    return BridgeResponse(data: result, success: true);
  }

  /// Converts the response to a JSON map.
  Map<String, dynamic> toJson() {
    return {'success': success, 'data': data, if (errorMessage != null) 'error': errorMessage};
  }
}

/// Signature for bridge method handlers.
typedef BridgeMethodHandler = Future<BridgeResponse> Function(Map<String, dynamic> params);

/// Controller for managing bridge methods between web-based mini-apps and the Flutter SuperApp.
class MiniAppBridgeController {
  /// Registry of bridge methods organized by class name and method name.
  final Map<String, Map<String, BridgeMethodHandler>> _bridgeClasses = {};

  /// Logger function for debugging bridge calls.
  final void Function(String message)? logger;

  /// Duration for method execution timeout.
  final Duration methodTimeout;

  /// Creates a new bridge controller with optional logging and a configurable method timeout.
  MiniAppBridgeController({this.logger, this.methodTimeout = const Duration(seconds: 30)});

  /// Logs a message if a logger is configured.
  void _log(String message) {
    logger?.call(message);
  }

  /// Registers a method handler for a specific class and method name.
  ///
  /// The [className] groups related methods together.
  /// The [methodName] is the specific function being registered.
  /// The [handler] is the function that will be called when the method is invoked.
  /// Set [override] to false to prevent overriding existing methods.
  void registerMethod(String className, String methodName, BridgeMethodHandler handler, {bool override = true}) {
    if (_bridgeClasses.containsKey(className) && _bridgeClasses[className]!.containsKey(methodName) && !override) {
      throw Exception('Method $className.$methodName already registered');
    }

    _bridgeClasses[className] = {...(_bridgeClasses[className] ?? {}), methodName: handler};

    _log('Registered method: $className.$methodName');
  }

  /// Unregisters a method handler.
  ///
  /// Returns true if the method was found and removed, false otherwise.
  bool unregisterMethod(String className, String methodName) {
    if (_bridgeClasses.containsKey(className) && _bridgeClasses[className]!.containsKey(methodName)) {
      _bridgeClasses[className]!.remove(methodName);

      if (_bridgeClasses[className]!.isEmpty) {
        _bridgeClasses.remove(className);
      }

      _log('Unregistered method: $className.$methodName');
      return true;
    }

    return false;
  }

  /// Checks if a method is registered.
  bool isMethodRegistered(String className, String methodName) {
    return _bridgeClasses.containsKey(className) && _bridgeClasses[className]!.containsKey(methodName);
  }

  /// Lists all registered method names for a given class.
  List<String> getRegisteredMethods(String className) {
    if (!_bridgeClasses.containsKey(className)) {
      return [];
    }

    return _bridgeClasses[className]!.keys.toList();
  }

  /// Lists all registered class names.
  List<String> getRegisteredClasses() {
    return _bridgeClasses.keys.toList();
  }

  /// Processes an incoming request from a mini-app.
  ///
  /// Returns a JSON string response to be sent back to the mini-app.
  Future<String> processRequest(String message) async {
    try {
      _log('Processing bridge request: $message');
      Map<String, dynamic> request = jsonDecode(message);

      // Validate request format
      if (!_validateRequest(request)) {
        return jsonEncode({'id': request['id'], 'success': false, 'error': 'Invalid request format'});
      }

      String requestId = request['id'];
      String className = request['className'];
      String method = request['method'];
      Map<String, dynamic> params = request['params'] ?? {};

      if (_bridgeClasses.containsKey(className) && _bridgeClasses[className]!.containsKey(method)) {
        try {
          _log('Invoking method: $className.$method');
          // Execute the method with a timeout
          var result = await _bridgeClasses[className]![method]!(params).timeout(methodTimeout);

          return jsonEncode({
            'id': requestId,
            'success': result.success,
            'data': result.data,
            if (result.errorMessage != null) 'error': result.errorMessage,
          });
        } on TimeoutException catch (e) {
          _log('Timeout in method $className.$method: $e');
          return jsonEncode({'id': requestId, 'success': false, 'error': 'Method execution timed out'});
        } catch (methodError) {
          _log('Error in method $className.$method: $methodError');
          return jsonEncode({'id': requestId, 'success': false, 'error': 'Method execution error: $methodError'});
        }
      } else {
        _log('Unknown method: $className.$method');
        return jsonEncode({'id': requestId, 'success': false, 'error': 'Unknown method: $className.$method'});
      }
    } catch (parsingError) {
      _log('Error parsing request: $parsingError');
      return jsonEncode({'success': false, 'error': 'Invalid request: $parsingError'});
    }
  }

  /// Creates a response payload for sending events to mini-apps.
  String createEventPayload(String eventName, Map<String, dynamic> data) {
    return jsonEncode({'event': eventName, 'data': data});
  }

  /// Validates that a request contains the required fields.
  bool _validateRequest(Map<String, dynamic> request) {
    return request.containsKey('id') && request.containsKey('className') && request.containsKey('method');
  }

  /// Unregisters all methods for a specific class.
  void unregisterClass(String className) {
    _bridgeClasses.remove(className);
    _log('Unregistered all methods for class: $className');
  }

  /// Unregisters all methods.
  void unregisterAllMethods() {
    _bridgeClasses.clear();
    _log('Unregistered all methods');
  }
}
