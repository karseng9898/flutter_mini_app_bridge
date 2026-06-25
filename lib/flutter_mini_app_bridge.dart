import 'dart:async';
import 'dart:convert';

final RegExp _sensitiveKeyPattern = RegExp(
  r'authorization|token|password|secret|cookie|api[-_]?key',
  caseSensitive: false,
);

dynamic _redactSensitiveData(dynamic value) {
  if (value is Map) {
    return value.map((key, nestedValue) {
      final keyString = key.toString();
      return MapEntry(
          keyString,
          _sensitiveKeyPattern.hasMatch(keyString)
              ? '[REDACTED]'
              : _redactSensitiveData(nestedValue));
    });
  }

  if (value is List) {
    return value.map(_redactSensitiveData).toList();
  }

  return value;
}

String _redactedJson(Object? value) {
  return jsonEncode(_redactSensitiveData(value));
}

/// A response from a bridge method call.
class BridgeResponse {
  /// The data returned by the bridge method.
  final Map<String, dynamic> data;

  /// Whether the bridge method call was successful.
  final bool success;

  /// Optional error message for failed calls.
  final String? errorMessage;

  /// Creates a response with the given data and success status.
  const BridgeResponse(
      {this.data = const {}, required this.success, this.errorMessage});

  /// Creates an error response with the given error message.
  factory BridgeResponse.error(String error) {
    return BridgeResponse(
        data: {'error': error}, success: false, errorMessage: error);
  }

  /// Creates a success response with the given data.
  factory BridgeResponse.success([Map<String, dynamic> result = const {}]) {
    return BridgeResponse(data: result, success: true);
  }

  /// Converts the response to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'data': data,
      if (errorMessage != null) 'error': errorMessage
    };
  }
}

/// A request from a mini-app bridge method call.
class BridgeRequest {
  /// Unique request identifier.
  final String id;

  /// Bridge class name.
  final String className;

  /// Bridge method name.
  final String method;

  /// Method parameters.
  final Map<String, dynamic> params;

  /// Header-like metadata sent outside [params].
  final Map<String, dynamic> meta;

  /// Creates a bridge request.
  const BridgeRequest({
    required this.id,
    required this.className,
    required this.method,
    this.params = const {},
    this.meta = const {},
  });

  /// Mini-app identifier from [meta], when provided.
  String? get miniAppId {
    final value = meta['miniAppId'];
    return value is String ? value : null;
  }

  /// Converts the request to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'className': className,
      'method': method,
      'params': params,
      if (meta.isNotEmpty) 'meta': meta,
    };
  }
}

/// Signature for bridge method handlers that only need params.
typedef BridgeMethodHandler = Future<BridgeResponse> Function(
    Map<String, dynamic> params);

/// Signature for bridge method handlers that need params and metadata.
typedef BridgeRequestHandler = Future<BridgeResponse> Function(
    BridgeRequest request);

/// Controller for managing bridge methods between web-based mini-apps and the Flutter SuperApp.
class MiniAppBridgeController {
  /// Registry of bridge methods organized by class name and method name.
  final Map<String, Map<String, BridgeRequestHandler>> _bridgeClasses = {};

  /// Logger function for debugging bridge calls.
  final void Function(String message)? logger;

  /// Duration for method execution timeout.
  final Duration methodTimeout;

  /// Creates a new bridge controller with optional logging and a configurable method timeout.
  MiniAppBridgeController(
      {this.logger, this.methodTimeout = const Duration(seconds: 30)});

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
  void registerMethod(
      String className, String methodName, BridgeMethodHandler handler,
      {bool override = true}) {
    registerRequestHandler(
        className, methodName, (request) => handler(request.params),
        override: override);
  }

  /// Registers a metadata-aware method handler for a specific class and method name.
  ///
  /// Use this when the handler needs access to [BridgeRequest.meta], such as
  /// mini-app identity or other request metadata.
  void registerRequestHandler(
      String className, String methodName, BridgeRequestHandler handler,
      {bool override = true}) {
    if (_bridgeClasses.containsKey(className) &&
        _bridgeClasses[className]!.containsKey(methodName) &&
        !override) {
      throw Exception('Method $className.$methodName already registered');
    }

    _bridgeClasses[className] = {
      ...(_bridgeClasses[className] ?? {}),
      methodName: handler
    };

    _log('Registered method: $className.$methodName');
  }

  /// Unregisters a method handler.
  ///
  /// Returns true if the method was found and removed, false otherwise.
  bool unregisterMethod(String className, String methodName) {
    if (_bridgeClasses.containsKey(className) &&
        _bridgeClasses[className]!.containsKey(methodName)) {
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
    return _bridgeClasses.containsKey(className) &&
        _bridgeClasses[className]!.containsKey(methodName);
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
      final dynamic decodedRequest = jsonDecode(message);
      if (decodedRequest is! Map<String, dynamic>) {
        _log('Invalid bridge request format');
        return jsonEncode(
            {'success': false, 'error': 'Invalid request format'});
      }

      final Map<String, dynamic> request =
          Map<String, dynamic>.from(decodedRequest);

      // Validate request format
      if (!_validateRequest(request)) {
        _log('Invalid bridge request format');
        return jsonEncode({
          if (request['id'] is String) 'id': request['id'],
          'success': false,
          'error': 'Invalid request format',
        });
      }

      _log('Processing bridge request: ${_redactedJson(request)}');

      final bridgeRequest = BridgeRequest(
        id: request['id'],
        className: request['className'],
        method: request['method'],
        params: _readOptionalMap(request, 'params'),
        meta: _readOptionalMap(request, 'meta'),
      );

      String requestId = bridgeRequest.id;
      String className = bridgeRequest.className;
      String method = bridgeRequest.method;

      if (_bridgeClasses.containsKey(className) &&
          _bridgeClasses[className]!.containsKey(method)) {
        try {
          _log('Invoking method: $className.$method');
          // Execute the method with a timeout
          var result = await _bridgeClasses[className]![method]!(bridgeRequest)
              .timeout(methodTimeout);

          return jsonEncode({
            'id': requestId,
            'success': result.success,
            'data': result.data,
            if (result.errorMessage != null) 'error': result.errorMessage,
          });
        } on TimeoutException catch (e) {
          _log('Timeout in method $className.$method: $e');
          return jsonEncode({
            'id': requestId,
            'success': false,
            'error': 'Method execution timed out'
          });
        } catch (methodError) {
          _log('Error in method $className.$method: $methodError');
          return jsonEncode({
            'id': requestId,
            'success': false,
            'error': 'Method execution error: $methodError'
          });
        }
      } else {
        _log('Unknown method: $className.$method');
        return jsonEncode({
          'id': requestId,
          'success': false,
          'error': 'Unknown method: $className.$method'
        });
      }
    } catch (parsingError) {
      _log('Error parsing request: $parsingError');
      return jsonEncode(
          {'success': false, 'error': 'Invalid request: $parsingError'});
    }
  }

  /// Creates a response payload for sending events to mini-apps.
  String createEventPayload(String eventName, Map<String, dynamic> data) {
    return jsonEncode({'event': eventName, 'data': data});
  }

  /// Validates that a request contains the required fields.
  bool _validateRequest(Map<String, dynamic> request) {
    return request['id'] is String &&
        request['className'] is String &&
        request['method'] is String &&
        _isOptionalMap(request['params']) &&
        _isOptionalMap(request['meta']);
  }

  /// Validates optional object fields.
  bool _isOptionalMap(dynamic value) {
    return value == null || value is Map;
  }

  /// Reads an optional object field as a string-keyed map.
  Map<String, dynamic> _readOptionalMap(
      Map<String, dynamic> request, String key) {
    final value = request[key];
    if (value == null) {
      return {};
    }
    return Map<String, dynamic>.from(value);
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
