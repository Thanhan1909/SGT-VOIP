import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_sip_softphone/core/services/push_token_manager.dart';

class FakeHttpHeaders implements HttpHeaders {
  final Map<String, String> values = {};
  ContentType? _contentType;

  @override
  ContentType? get contentType => _contentType;

  @override
  set contentType(ContentType? type) {
    _contentType = type;
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = value.toString();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  @override
  final int statusCode;
  final String bodyText;

  FakeHttpClientResponse(this.statusCode, this.bodyText);

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([utf8.encode(bodyText)]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeHttpClientRequest implements HttpClientRequest {
  final Uri url;
  final int responseStatus;
  final String responseBody;
  final void Function(Uri url, Map<String, String> headers, String body)?
  onRequest;
  final StringBuffer _buffer = StringBuffer();

  @override
  final HttpHeaders headers = FakeHttpHeaders();

  FakeHttpClientRequest(
    this.url,
    this.responseStatus,
    this.responseBody,
    this.onRequest,
  );

  @override
  void write(Object? obj) {
    _buffer.write(obj);
  }

  @override
  Future<HttpClientResponse> close() async {
    final fakeHeaders = headers as FakeHttpHeaders;
    onRequest?.call(url, fakeHeaders.values, _buffer.toString());
    return FakeHttpClientResponse(responseStatus, responseBody);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeHttpClient implements HttpClient {
  final int statusCode;
  final String responseBody;
  final void Function(Uri url, Map<String, String> headers, String body)?
  onRequest;

  FakeHttpClient({
    this.statusCode = 200,
    this.responseBody = '{"success": true}',
    this.onRequest,
  });

  @override
  Duration? connectionTimeout;

  @override
  void close({bool force = false}) {}

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    return FakeHttpClientRequest(url, statusCode, responseBody, onRequest);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PushTokenManager Tests', () {
    test('1. maskToken hides sensitive token characters', () {
      expect(PushTokenManager.maskToken(''), equals('***'));
      expect(PushTokenManager.maskToken('12345'), equals('***'));
      expect(
        PushTokenManager.maskToken('fcm_token_abcdef1234567890'),
        equals('fcm_...7890'),
      );
    });

    test('2. registerToken sends correct payload and auth header', () async {
      Uri? capturedUrl;
      Map<String, String>? capturedHeaders;
      String? capturedBody;

      final fakeClient = FakeHttpClient(
        statusCode: 200,
        responseBody: '{"success": true}',
        onRequest: (url, headers, body) {
          capturedUrl = url;
          capturedHeaders = headers;
          capturedBody = body;
        },
      );

      final manager = PushTokenManager(
        gatewayBaseUrl: 'http://127.0.0.1:8085',
        deviceAuthToken: 'test_device_secret',
        clientFactory: () => fakeClient,
      );

      final success = await manager.registerToken(
        extension: '202',
        platform: 'android',
        deviceId: 'device-test-01',
        pushToken: 'fcm_secret_token_12345678',
        appVersion: '1.0.0',
      );

      expect(success, isTrue);
      expect(capturedUrl?.path, equals('/api/v1/devices/register'));
      expect(
        capturedHeaders?['x-device-auth-token'],
        equals('test_device_secret'),
      );

      final parsed = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(parsed['extension'], equals('202'));
      expect(parsed['platform'], equals('android'));
      expect(parsed['device_id'], equals('device-test-01'));
      expect(parsed['push_token'], equals('fcm_secret_token_12345678'));
    });

    test('3. registerToken returns false on non-200 status', () async {
      final fakeClient = FakeHttpClient(
        statusCode: 401,
        responseBody: '{"detail": "Unauthorized"}',
      );

      final manager = PushTokenManager(
        gatewayBaseUrl: 'http://127.0.0.1:8085',
        deviceAuthToken: 'invalid_secret',
        clientFactory: () => fakeClient,
      );

      final success = await manager.registerToken(
        extension: '202',
        platform: 'android',
        deviceId: 'device-test-01',
        pushToken: 'fcm_token_test',
      );

      expect(success, isFalse);
    });

    test('4. revokeToken sends correct extension and deviceId', () async {
      Uri? capturedUrl;
      Map<String, String>? capturedHeaders;
      String? capturedBody;

      final fakeClient = FakeHttpClient(
        statusCode: 200,
        responseBody: '{"success": true}',
        onRequest: (url, headers, body) {
          capturedUrl = url;
          capturedHeaders = headers;
          capturedBody = body;
        },
      );

      final manager = PushTokenManager(
        gatewayBaseUrl: 'http://127.0.0.1:8085',
        deviceAuthToken: 'test_device_secret',
        clientFactory: () => fakeClient,
      );

      final success = await manager.revokeToken(
        extension: '202',
        deviceId: 'device-test-01',
      );

      expect(success, isTrue);
      expect(capturedUrl?.path, equals('/api/v1/devices/revoke'));
      expect(
        capturedHeaders?['x-device-auth-token'],
        equals('test_device_secret'),
      );

      final parsed = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(parsed['extension'], equals('202'));
      expect(parsed['device_id'], equals('device-test-01'));
    });

    test('5. defaultUrl fallback provides valid URL', () {
      final url = PushTokenManager.defaultUrl();
      expect(url, isNotEmpty);
      expect(url.startsWith('http://') || url.startsWith('https://'), isTrue);
    });

    test('6. registerToken omits X-Device-Auth-Token when empty', () async {
      Map<String, String>? capturedHeaders;
      final fakeClient = FakeHttpClient(
        statusCode: 200,
        responseBody: '{"success": true}',
        onRequest: (url, headers, body) {
          capturedHeaders = headers;
        },
      );
      final manager = PushTokenManager(
        gatewayBaseUrl: 'http://127.0.0.1:8085',
        deviceAuthToken: '',
        clientFactory: () => fakeClient,
      );
      final success = await manager.registerToken(
        extension: '201',
        platform: 'android',
        deviceId: 'device-test-02',
        pushToken: 'fcm_test_token',
      );
      expect(success, isTrue);
      expect(capturedHeaders?['x-device-auth-token'], isNull);
    });
  });
}
