import 'dart:convert';

import 'package:flutter_mini_app_bridge/flutter_mini_app_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MiniAppBridgeController', () {
    late MiniAppBridgeController controller;
    List<String> logs = [];

    setUp(() {
      logs = [];
      controller = MiniAppBridgeController(
        logger: (message) => logs.add(message),
        methodTimeout: const Duration(milliseconds: 100),
      );
    });

    group('Method Registration', () {
      test('should register and verify a method', () {
        controller.registerMethod(
          'TestClass',
          'testMethod',
          (params) async => BridgeResponse.success({'result': 'success'}),
        );

        expect(controller.isMethodRegistered('TestClass', 'testMethod'), true);
        expect(controller.getRegisteredClasses(), ['TestClass']);
        expect(controller.getRegisteredMethods('TestClass'), ['testMethod']);
      });

      test('should not override when override is false', () {
        controller.registerMethod(
          'TestClass',
          'testMethod',
          (params) async => BridgeResponse.success({'result': 'original'}),
        );

        expect(
          () => controller.registerMethod(
            'TestClass',
            'testMethod',
            (params) async => BridgeResponse.success({'result': 'new'}),
            override: false,
          ),
          throwsException,
        );
      });

      test('should override when override is true', () {
        controller.registerMethod(
          'TestClass',
          'testMethod',
          (params) async => BridgeResponse.success({'result': 'original'}),
        );

        controller.registerMethod(
          'TestClass',
          'testMethod',
          (params) async => BridgeResponse.success({'result': 'new'}),
        );

        expect(controller.isMethodRegistered('TestClass', 'testMethod'), true);
      });

      test('getRegisteredMethods returns empty list for non-existent class', () {
        expect(controller.getRegisteredMethods('NonExistentClass'), []);
      });
    });

    group('Method Unregistration', () {
      setUp(() {
        controller.registerMethod('TestClass', 'method1', (params) async => BridgeResponse.success());
        controller.registerMethod('TestClass', 'method2', (params) async => BridgeResponse.success());
        controller.registerMethod('OtherClass', 'method1', (params) async => BridgeResponse.success());
      });

      test('should unregister a specific method', () {
        expect(controller.unregisterMethod('TestClass', 'method1'), true);
        expect(controller.isMethodRegistered('TestClass', 'method1'), false);
        expect(controller.isMethodRegistered('TestClass', 'method2'), true);
      });

      test('should return false when unregistering non-existent method', () {
        expect(controller.unregisterMethod('TestClass', 'nonExistentMethod'), false);
        expect(controller.unregisterMethod('NonExistentClass', 'method1'), false);
      });

      test('should unregister all methods for a class', () {
        controller.unregisterClass('TestClass');
        expect(controller.isMethodRegistered('TestClass', 'method1'), false);
        expect(controller.isMethodRegistered('TestClass', 'method2'), false);
        expect(controller.isMethodRegistered('OtherClass', 'method1'), true);
      });

      test('should unregister all methods', () {
        controller.unregisterAllMethods();
        expect(controller.getRegisteredClasses(), []);
        expect(controller.isMethodRegistered('TestClass', 'method1'), false);
        expect(controller.isMethodRegistered('OtherClass', 'method1'), false);
      });
    });

    group('Request Processing', () {
      setUp(() {
        controller.registerMethod(
          'TestClass',
          'successMethod',
          (params) async => BridgeResponse.success({'result': params['input']}),
        );

        controller.registerMethod('TestClass', 'errorMethod', (params) async => BridgeResponse.error('Error occurred'));

        controller.registerMethod('TestClass', 'timeoutMethod', (params) async {
          await Future.delayed(const Duration(milliseconds: 200));
          return BridgeResponse.success();
        });

        controller.registerMethod('TestClass', 'exceptionMethod', (params) async => throw Exception('Test exception'));
      });

      test('should process valid request successfully', () async {
        String request = jsonEncode({
          'id': '123',
          'className': 'TestClass',
          'method': 'successMethod',
          'params': {'input': 'test-value'},
        });

        String response = await controller.processRequest(request);
        Map<String, dynamic> result = jsonDecode(response);

        expect(result['id'], '123');
        expect(result['success'], true);
        expect(result['data']['result'], 'test-value');
      });

      test('should handle error responses', () async {
        String request = jsonEncode({'id': '123', 'className': 'TestClass', 'method': 'errorMethod', 'params': {}});

        String response = await controller.processRequest(request);
        Map<String, dynamic> result = jsonDecode(response);

        expect(result['success'], false);
        expect(result['error'], 'Error occurred');
      });

      test('should handle method timeout', () async {
        String request = jsonEncode({'id': '123', 'className': 'TestClass', 'method': 'timeoutMethod', 'params': {}});

        String response = await controller.processRequest(request);
        Map<String, dynamic> result = jsonDecode(response);

        expect(result['success'], false);
        expect(result['error'], contains('timed out'));
      });

      test('should handle method exception', () async {
        String request = jsonEncode({'id': '123', 'className': 'TestClass', 'method': 'exceptionMethod', 'params': {}});

        String response = await controller.processRequest(request);
        Map<String, dynamic> result = jsonDecode(response);

        expect(result['success'], false);
        expect(result['error'], contains('Method execution error'));
      });

      test('should handle unknown method', () async {
        String request = jsonEncode({'id': '123', 'className': 'TestClass', 'method': 'unknownMethod', 'params': {}});

        String response = await controller.processRequest(request);
        Map<String, dynamic> result = jsonDecode(response);

        expect(result['success'], false);
        expect(result['error'], contains('Unknown method'));
      });

      test('should handle invalid JSON', () async {
        String response = await controller.processRequest('{invalid json}');
        Map<String, dynamic> result = jsonDecode(response);

        expect(result['success'], false);
        expect(result['error'], contains('Invalid request'));
      });

      test('should handle request with missing fields', () async {
        String request = jsonEncode({
          'id': '123',
          // Missing className and method
        });

        String response = await controller.processRequest(request);
        Map<String, dynamic> result = jsonDecode(response);

        expect(result['success'], false);
        expect(result['error'], contains('Invalid request format'));
      });
    });

    group('Bridge Response', () {
      test('should create success response', () {
        final response = BridgeResponse.success({'result': 'test'});

        expect(response.success, true);
        expect(response.data['result'], 'test');
        expect(response.errorMessage, null);
      });

      test('should create error response', () {
        final response = BridgeResponse.error('Test error');

        expect(response.success, false);
        expect(response.data['error'], 'Test error');
        expect(response.errorMessage, 'Test error');
      });

      test('should convert to JSON correctly', () {
        final success = BridgeResponse.success({'result': 'test'});
        final error = BridgeResponse.error('Test error');

        expect(success.toJson(), {
          'success': true,
          'data': {'result': 'test'},
        });

        expect(error.toJson(), {
          'success': false,
          'data': {'error': 'Test error'},
          'error': 'Test error',
        });
      });
    });

    test('should create event payload', () {
      String payload = controller.createEventPayload('testEvent', {'data': 'testData'});
      Map<String, dynamic> result = jsonDecode(payload);

      expect(result['event'], 'testEvent');
      expect(result['data']['data'], 'testData');
    });
  });
}
