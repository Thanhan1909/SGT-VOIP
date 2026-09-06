import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'audio_route_adapter.dart';

class AudioManager {
  static final AudioManager _instance = AudioManager._internal();
  factory AudioManager() => _instance;
  AudioManager._internal();

  AudioRouteAdapter _audioRouteAdapter = const DefaultAudioRouteAdapter();

  @visibleForTesting
  void setAudioRouteAdapterForTesting(AudioRouteAdapter adapter) {
    _audioRouteAdapter = adapter;
  }

  bool _audioPlayerEnabled = true;

  @visibleForTesting
  void setAudioPlayerEnabledForTesting(bool enabled) {
    _audioPlayerEnabled = enabled;
  }

  final AudioPlayer _ringtonePlayer = AudioPlayer();
  final AudioPlayer _ringbackPlayer = AudioPlayer();
  RTCVideoRenderer? _remoteAudioRenderer;
  bool _remoteAudioRendererInitialized = false;
  Uint8List? _ringtoneBytes;
  Uint8List? _ringbackBytes;

  bool _initialized = false;
  bool _isSpeakerOn = false;
  bool get isSpeakerOn => _isSpeakerOn;

  String? _activeCallId;
  String? get activeCallId => _activeCallId;
  bool _audioRouteInitializedForCall = false;
  bool _isMediaReady = false;
  bool get isMediaReady => _isMediaReady;

  /// Resets audio state when preparing for a new call (incoming or outgoing).
  ///
  /// CRITICAL: Synchronously resets Dart state without invoking native audio routing.
  /// Deduplicates calls so that calling prepareForCall multiple times for the same
  /// [callId] is a safe no-op.
  void prepareForCall(String? callId) {
    if (callId != null && _activeCallId == callId) {
      return;
    }
    _activeCallId = callId;
    _audioRouteInitializedForCall = false;
    _isSpeakerOn = false;
    _isMediaReady = false;
  }

  /// Updates active Call-ID without re-triggering prepareForCall.
  void updateCallId(String? callId) {
    if (callId != null && callId.isNotEmpty) {
      _activeCallId = callId;
    }
  }

  /// Ensures default audio route (earpiece) is applied safely once per call.
  ///
  /// Only executes once the media / audio session is active. If the user has
  /// already explicitly pressed the Speakerphone button, their choice is respected.
  Future<void> ensureDefaultAudioRoute(String? callId) async {
    if (callId != null && _activeCallId != null && _activeCallId != callId) {
      debugPrint(
        '[AudioManager] ensureDefaultAudioRoute ignored for mismatched callId: $callId (active: $_activeCallId)',
      );
      return;
    }
    if (callId != null) {
      _activeCallId = callId;
    }
    _isMediaReady = true;

    if (_audioRouteInitializedForCall) {
      // Already configured once for this call. Do not override user's manual toggle.
      return;
    }
    _audioRouteInitializedForCall = true;

    if (!_isSpeakerOn && !kIsWeb) {
      try {
        await _audioRouteAdapter.setSpeakerphoneOn(false);
      } catch (e) {
        debugPrint('[AudioManager] ensureDefaultAudioRoute error: $e');
      }
    }
  }

  /// Resets audio routing and stops ringtones when call ends or fails.
  ///
  /// Guards by [callId] so stale callbacks from previous calls cannot reset
  /// or interrupt a newer active call.
  Future<void> resetOnCallEnded([String? callId]) async {
    if (callId != null && _activeCallId != null && _activeCallId != callId) {
      debugPrint(
        '[AudioManager] Ignoring resetOnCallEnded for stale callId $callId (active: $_activeCallId)',
      );
      return;
    }
    final wasMediaReady = _isMediaReady;
    _activeCallId = null;
    _audioRouteInitializedForCall = false;
    _isSpeakerOn = false;
    _isMediaReady = false;

    await stopAll();
    await detachRemoteStream(callId);

    if (!kIsWeb && wasMediaReady) {
      try {
        await _audioRouteAdapter.setSpeakerphoneOn(false);
      } catch (e) {
        debugPrint('[AudioManager] resetOnCallEnded error: $e');
      }
    }
  }

  Future<void> init() async {
    if (!_audioPlayerEnabled || _initialized) return;
    _ringtoneBytes ??= _buildWav(
      frequencies: const [853, 960],
      toneSeconds: 1.2,
      totalSeconds: 3,
    );
    _ringbackBytes ??= _buildWav(
      frequencies: const [440, 480],
      toneSeconds: 1.8,
      totalSeconds: 4,
    );
    try {
      await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
      await _ringbackPlayer.setReleaseMode(ReleaseMode.loop);
      _initialized = true;
      debugPrint(
        '[AudioManager] Initialized ringtone/ringback and audio routing',
      );
    } catch (e) {
      debugPrint('[AudioManager] AudioPlayer init warning: $e');
    }
  }

  Future<void> playRingtone() async {
    if (!_audioPlayerEnabled) return;
    try {
      await init();
      await _ringbackPlayer.stop();
      try {
        await HapticFeedback.vibrate();
      } catch (_) {}
      final bytes = _ringtoneBytes;
      if (bytes != null) {
        await _ringtonePlayer.play(BytesSource(bytes));
      }
    } catch (error) {
      debugPrint('[AudioManager] Ringtone warning: $error');
    }
  }

  Future<void> stopRingtone() async {
    if (!_audioPlayerEnabled) return;
    try {
      await _ringtonePlayer.stop();
    } catch (_) {}
  }

  Future<void> playRingback() async {
    if (!_audioPlayerEnabled) return;
    try {
      await init();
      await _ringtonePlayer.stop();
      final bytes = _ringbackBytes;
      if (bytes != null) {
        await _ringbackPlayer.play(BytesSource(bytes));
      }
    } catch (error) {
      debugPrint('[AudioManager] Ringback warning: $error');
    }
  }

  Future<void> stopRingback() async {
    if (!_audioPlayerEnabled) return;
    try {
      await _ringbackPlayer.stop();
    } catch (_) {}
  }

  Future<void> stopAll() async {
    if (!_audioPlayerEnabled) return;
    try {
      await Future.wait([_ringtonePlayer.stop(), _ringbackPlayer.stop()]);
    } catch (_) {}
  }

  /// Attaches the remote WebRTC stream to a renderer.
  Future<void> attachRemoteStream(MediaStream stream, [String? callId]) async {
    if (callId != null && _activeCallId != null && _activeCallId != callId) {
      debugPrint(
        '[AudioManager] Rejecting attachRemoteStream: callId mismatch ($callId vs $_activeCallId)',
      );
      return;
    }
    _isMediaReady = true;
    try {
      final renderer = _remoteAudioRenderer ??= RTCVideoRenderer();
      if (!_remoteAudioRendererInitialized) {
        await renderer.initialize();
        _remoteAudioRendererInitialized = true;
      }
      renderer.srcObject = stream;
      debugPrint(
        '[AudioManager] Remote WebRTC stream attached '
        '(${stream.getAudioTracks().length} audio track(s))',
      );
    } catch (error, stack) {
      debugPrint(
        '[AudioManager] Failed to attach remote WebRTC stream: '
        '$error\n$stack',
      );
    }
  }

  Future<void> detachRemoteStream([String? callId]) async {
    if (callId != null && _activeCallId != null && _activeCallId != callId) {
      debugPrint(
        '[AudioManager] Rejecting detachRemoteStream: callId mismatch ($callId vs $_activeCallId)',
      );
      return;
    }
    try {
      _remoteAudioRenderer?.srcObject = null;
      debugPrint('[AudioManager] Remote WebRTC stream detached');
    } catch (error) {
      debugPrint('[AudioManager] Failed to detach remote stream: $error');
    }
  }

  /// Toggles speakerphone with Call-ID validation and media readiness check.
  ///
  /// Returns [true] if and only if the native audio route was successfully changed.
  Future<bool> setSpeakerphone(bool enabled, {String? callId}) async {
    if (callId != null && _activeCallId != null && _activeCallId != callId) {
      debugPrint(
        '[AudioManager] Rejecting setSpeakerphone: callId mismatch ($callId vs $_activeCallId)',
      );
      return false;
    }
    if (!_isMediaReady) {
      debugPrint(
        '[AudioManager] setSpeakerphone rejected: media session is not ready yet',
      );
      return false;
    }
    try {
      if (!kIsWeb) {
        await _audioRouteAdapter.setSpeakerphoneOn(enabled);
      }
      _isSpeakerOn = enabled;
      _audioRouteInitializedForCall = true;
      return true;
    } catch (error) {
      debugPrint('[AudioManager] setSpeakerphone error: $error');
      return false;
    }
  }

  Future<bool> toggleSpeakerphone({String? callId}) async {
    return await setSpeakerphone(!_isSpeakerOn, callId: callId);
  }

  void resetState() {
    _activeCallId = null;
    _audioRouteInitializedForCall = false;
    _isSpeakerOn = false;
    _isMediaReady = false;
  }

  @visibleForTesting
  void resetForTesting() {
    resetState();
  }

  Uint8List _buildWav({
    required List<int> frequencies,
    required double toneSeconds,
    required double totalSeconds,
  }) {
    const sampleRate = 8000;
    final sampleCount = (sampleRate * totalSeconds).round();
    final toneSamples = (sampleRate * toneSeconds).round();
    final pcm = Int16List(sampleCount);
    for (var index = 0; index < toneSamples; index++) {
      final time = index / sampleRate;
      final sample =
          frequencies
              .map((frequency) => math.sin(2 * math.pi * frequency * time))
              .reduce((left, right) => left + right) /
          frequencies.length;
      pcm[index] = (sample * 5500).round();
    }

    final dataLength = pcm.lengthInBytes;
    final bytes = Uint8List(44 + dataLength);
    final data = ByteData.sublistView(bytes);
    void ascii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        data.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    data.setUint32(4, 36 + dataLength, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, sampleRate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    data.setUint32(40, dataLength, Endian.little);
    for (var i = 0; i < pcm.length; i++) {
      data.setInt16(44 + i * 2, pcm[i], Endian.little);
    }
    return bytes;
  }
}
