import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class PushTokenManager {
  final String gatewayBaseUrl;

  PushTokenManager({this.gatewayBaseUrl = 'http://127.0.0.1:8085'});

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
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 4);
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;

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
          '[PushTokenManager] Token registered successfully for ext=$extension',
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
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 3);
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;

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
