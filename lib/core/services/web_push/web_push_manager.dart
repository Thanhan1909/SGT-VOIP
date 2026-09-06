import 'dart:convert';
import 'web_push_interop.dart';

class WebPushManager {
  static bool get isSupported => WebPushInterop.isSupported;
  static bool get isStandalone => WebPushInterop.isStandalone;
  static String get permission => WebPushInterop.permission;

  static Future<String> requestPermission() async {
    return await WebPushInterop.requestPermission();
  }

  static Future<Map<String, dynamic>?> getSubscription() async {
    final rawJson = await WebPushInterop.getSubscription();
    if (rawJson == null || rawJson.isEmpty) return null;
    try {
      return jsonDecode(rawJson) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> subscribe(String vapidPublicKey) async {
    final rawJson = await WebPushInterop.subscribe(vapidPublicKey);
    return jsonDecode(rawJson) as Map<String, dynamic>;
  }

  static Future<bool> unsubscribe() async {
    return await WebPushInterop.unsubscribe();
  }
}
