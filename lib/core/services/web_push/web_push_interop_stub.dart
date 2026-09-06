// Stub implementation for mobile and desktop platforms where Web Push is unsupported.

class WebPushInterop {
  static bool get isSupported => false;
  static bool get isStandalone => false;
  static String get permission => 'unsupported';

  static Future<String> requestPermission() async => 'unsupported';
  static Future<String?> getSubscription() async => null;
  static Future<String> subscribe(String vapidPublicKey) async {
    throw UnsupportedError('Web Push is not supported on this platform.');
  }

  static Future<bool> unsubscribe() async => false;
}
