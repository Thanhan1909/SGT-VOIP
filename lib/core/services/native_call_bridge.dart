import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract class NativeCallBridge {
  Future<bool> showIncomingCall({
    required String callUuid,
    required String callerName,
    required String callerNumber,
  });

  Future<bool> dismissIncomingCall(String callUuid);

  Future<bool> canUseFullScreenIntent();

  Future<String?> getVoipToken();

  Stream<Map<String, String>> get callActionStream;

  Stream<String> get voipTokenStream;

  void dispose();
}

class MethodChannelNativeCallBridge implements NativeCallBridge {
  static const MethodChannel _channel = MethodChannel(
    'com.sgt.voip.softphone/native_call',
  );

  final StreamController<Map<String, String>> _callActionController =
      StreamController<Map<String, String>>.broadcast();
  final StreamController<String> _voipTokenController =
      StreamController<String>.broadcast();

  MethodChannelNativeCallBridge() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onCallAction':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final actionMap = args.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        );
        _callActionController.add(actionMap);
        break;

      case 'onVoipToken':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final token = args['token']?.toString() ?? '';
        if (token.isNotEmpty) {
          _voipTokenController.add(token);
        }
        break;

      default:
        debugPrint('[NativeCallBridge] Unhandled method: ${call.method}');
        break;
    }
  }

  @override
  Future<bool> showIncomingCall({
    required String callUuid,
    required String callerName,
    required String callerNumber,
  }) async {
    if (kIsWeb) return false;
    try {
      final res = await _channel.invokeMethod<bool>('showIncomingCall', {
        'callUuid': callUuid,
        'callerName': callerName,
        'callerNumber': callerNumber,
      });
      return res ?? false;
    } on MissingPluginException {
      debugPrint(
        '[NativeCallBridge] showIncomingCall not implemented on platform',
      );
      return false;
    } catch (e) {
      debugPrint('[NativeCallBridge] Error showIncomingCall: $e');
      return false;
    }
  }

  @override
  Future<bool> dismissIncomingCall(String callUuid) async {
    if (kIsWeb) return false;
    try {
      final res = await _channel.invokeMethod<bool>('dismissIncomingCall', {
        'callUuid': callUuid,
      });
      return res ?? false;
    } on MissingPluginException {
      return false;
    } catch (e) {
      debugPrint('[NativeCallBridge] Error dismissIncomingCall: $e');
      return false;
    }
  }

  @override
  Future<bool> canUseFullScreenIntent() async {
    if (kIsWeb) return false;
    try {
      final res = await _channel.invokeMethod<bool>('canUseFullScreenIntent');
      return res ?? true;
    } catch (e) {
      return true;
    }
  }

  @override
  Future<String?> getVoipToken() async {
    if (kIsWeb) return null;
    try {
      return await _channel.invokeMethod<String>('getVoipToken');
    } catch (e) {
      return null;
    }
  }

  @override
  Stream<Map<String, String>> get callActionStream =>
      _callActionController.stream;

  @override
  Stream<String> get voipTokenStream => _voipTokenController.stream;

  @override
  void dispose() {
    _callActionController.close();
    _voipTokenController.close();
  }
}
