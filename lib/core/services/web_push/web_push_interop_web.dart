import 'dart:js_interop';

@JS('SgtWebPush.isSupported')
external bool _isSupported();

@JS('SgtWebPush.isStandalone')
external bool _isStandalone();

@JS('SgtWebPush.getPermission')
external JSString _getPermission();

@JS('SgtWebPush.requestPermission')
external JSPromise<JSString> _requestPermission();

@JS('SgtWebPush.getSubscription')
external JSPromise<JSAny?> _getSubscription();

@JS('SgtWebPush.subscribe')
external JSPromise<JSString> _subscribe(JSString vapidPublicKey);

@JS('SgtWebPush.unsubscribe')
external JSPromise<JSBoolean> _unsubscribe();

class WebPushInterop {
  static bool get isSupported {
    try {
      return _isSupported();
    } catch (_) {
      return false;
    }
  }

  static bool get isStandalone {
    try {
      return _isStandalone();
    } catch (_) {
      return false;
    }
  }

  static String get permission {
    try {
      return _getPermission().toDart;
    } catch (_) {
      return 'unsupported';
    }
  }

  static Future<String> requestPermission() async {
    try {
      final jsStr = await _requestPermission().toDart;
      return jsStr.toDart;
    } catch (e) {
      return 'denied';
    }
  }

  static Future<String?> getSubscription() async {
    try {
      final res = await _getSubscription().toDart;
      if (res == null) return null;
      if (res.isA<JSString>()) {
        return (res as JSString).toDart;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<String> subscribe(String vapidPublicKey) async {
    final jsStr = await _subscribe(vapidPublicKey.toJS).toDart;
    return jsStr.toDart;
  }

  static Future<bool> unsubscribe() async {
    try {
      final jsBool = await _unsubscribe().toDart;
      return jsBool.toDart;
    } catch (_) {
      return false;
    }
  }
}
