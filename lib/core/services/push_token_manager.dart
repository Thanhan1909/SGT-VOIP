import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class PushTokenManager {
  final String gatewayBaseUrl;
  final String deviceAuthToken;
  final HttpClient Function()? clientFactory;

  PushTokenManager({
    String? gatewayBaseUrl,
    this.deviceAuthToken = const String.fromEnvironment(
      'SGT_DEVICE_AUTH_TOKEN',
      defaultValue: 'sgt_device_auth_secret_2026',
    ),
    this.clientFactory,
  }) : gatewayBaseUrl = _validateUrl(gatewayBaseUrl ?? defaultUrl());

  HttpClient _createClient() =>
      clientFactory != null ? clientFactory!() : HttpClient();

  static String defaultUrl() {
    const definedUrl = String.fromEnvironment('SGT_PUSH_GATEWAY_URL');
    if (definedUrl.isNotEmpty) {
      if (kReleaseMode && !definedUrl.startsWith('https://')) {
        throw ArgumentError(
          'Production push gateway URL must use HTTPS: $definedUrl',
        );
      }
      return definedUrl;
    }
    if (kReleaseMode) {
      return 'https://sgtvoip.duckdns.org/push';
    }
    if (!kIsWeb && Platform.isAndroid) {
      return 'http://10.0.2.2:8085';
    }
    return 'http://127.0.0.1:8085';
  }

  static String _validateUrl(String url) {
    if (kReleaseMode && !url.startsWith('https://')) {
      throw ArgumentError('Production push gateway URL must use HTTPS: $url');
    }
    return url;
  }

  static String maskToken(String token) {
    if (token.length <= 8) return '***';
    return '${token.substring(0, 4)}...${token.substring(token.length - 4)}';
  }

  Future<bool> registerToken({
    required String extension,
    required String platform,
    required String deviceId,
    required String pushToken,
    String? appVersion,
    String pushEnvironment = 'production',
  }) async {
    if (kIsWeb) return false;
    try {
      final uri = Uri.parse('$gatewayBaseUrl/api/v1/devices/register');
      final client = _createClient()
        ..connectionTimeout = const Duration(seconds: 4);
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      if (deviceAuthToken.isNotEmpty) {
        req.headers.set('X-Device-Auth-Token', deviceAuthToken);
      }

      final body = jsonEncode({
        'extension': extension,
        'platform': platform,
        'device_id': deviceId,
        'push_token': pushToken,
        'push_environment': pushEnvironment,
        'app_version': appVersion ?? '1.0.0',
      });

      req.write(body);
      final resp = await req.close();
      client.close();

      if (resp.statusCode == HttpStatus.ok) {
        debugPrint(
          '[PushTokenManager] Token ${maskToken(pushToken)} registered successfully for ext=$extension',
        );
        return true;
      } else {
        debugPrint(
          '[PushTokenManager] Failed to register token: status=${resp.statusCode}',
        );
        return false;
      }
    } catch (e) {
      debugPrint('[PushTokenManager] Error registering token with gateway: $e');
      return false;
    }
  }

  Future<bool> revokeToken({
    required String extension,
    required String deviceId,
  }) async {
    if (kIsWeb) return false;
    try {
      final uri = Uri.parse('$gatewayBaseUrl/api/v1/devices/revoke');
      final client = _createClient()
        ..connectionTimeout = const Duration(seconds: 3);
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      if (deviceAuthToken.isNotEmpty) {
        req.headers.set('X-Device-Auth-Token', deviceAuthToken);
      }

      final body = jsonEncode({'extension': extension, 'device_id': deviceId});

      req.write(body);
      final resp = await req.close();
      client.close();

      return resp.statusCode == HttpStatus.ok;
    } catch (e) {
      debugPrint('[PushTokenManager] Error revoking token: $e');
      return false;
    }
  }
}
