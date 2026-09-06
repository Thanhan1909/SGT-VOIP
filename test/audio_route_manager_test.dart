import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_sip_softphone/core/services/audio_manager.dart';
import 'package:flutter_sip_softphone/core/services/audio_route_adapter.dart';

class MockAudioRouteAdapter implements AudioRouteAdapter {
  final List<String> callLog = [];
  bool shouldFail = false;

  @override
  Future<void> setSpeakerphoneOn(bool enabled) async {
    callLog.add('setSpeakerphoneOn($enabled)');
    if (shouldFail) {
      throw Exception('Native platform audio error');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AudioManager audioManager;
  late MockAudioRouteAdapter mockAdapter;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('xyz.luan/audioplayers'),
          (MethodCall methodCall) async => 1,
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('xyz.luan/audioplayers.global'),
          (MethodCall methodCall) async => 1,
        );

    audioManager = AudioManager();
    mockAdapter = MockAudioRouteAdapter();
    audioManager.setAudioRouteAdapterForTesting(mockAdapter);
    audioManager.setAudioPlayerEnabledForTesting(false);
    audioManager.resetForTesting();
  });

  tearDown(() {
    audioManager.resetForTesting();
  });

  group('AudioManager Audio Routing & Crash Prevention Tests', () {
    test(
      'prepareForCall resets state without invoking native audio route before media is ready',
      () async {
        audioManager.prepareForCall('call-101');

        expect(audioManager.activeCallId, 'call-101');
        expect(audioManager.isSpeakerOn, isFalse);
        expect(audioManager.isMediaReady, isFalse);
        // CRITICAL: Native setSpeakerphoneOn must NOT be called in prepareForCall!
        expect(mockAdapter.callLog, isEmpty);
      },
    );

    test('prepareForCall is idempotent for the same callId', () async {
      audioManager.prepareForCall('call-101');
      audioManager.prepareForCall('call-101');

      expect(audioManager.activeCallId, 'call-101');
      expect(mockAdapter.callLog, isEmpty);
    });

    test(
      'toggleSpeakerphone is rejected when media is not ready, preventing early native crash',
      () async {
        audioManager.prepareForCall('call-101');
        expect(audioManager.isMediaReady, isFalse);

        final success = await audioManager.toggleSpeakerphone(
          callId: 'call-101',
        );

        expect(success, isFalse);
        expect(audioManager.isSpeakerOn, isFalse);
        expect(mockAdapter.callLog, isEmpty);
      },
    );

    test(
      'ensureDefaultAudioRoute applies earpiece route once media is ready and only once',
      () async {
        audioManager.prepareForCall('call-101');

        await audioManager.ensureDefaultAudioRoute('call-101');
        expect(audioManager.isMediaReady, isTrue);
        expect(mockAdapter.callLog, ['setSpeakerphoneOn(false)']);

        // Subsequent calls for the same callId do not duplicate the native call
        await audioManager.ensureDefaultAudioRoute('call-101');
        expect(mockAdapter.callLog, ['setSpeakerphoneOn(false)']);
      },
    );

    test(
      'Order of native calls: prepare -> ensureDefaultAudioRoute -> toggleSpeaker -> reset',
      () async {
        audioManager.prepareForCall('call-101');
        expect(mockAdapter.callLog, isEmpty);

        await audioManager.ensureDefaultAudioRoute('call-101');
        expect(mockAdapter.callLog, ['setSpeakerphoneOn(false)']);

        final toggled = await audioManager.toggleSpeakerphone(
          callId: 'call-101',
        );
        expect(toggled, isTrue);
        expect(audioManager.isSpeakerOn, isTrue);
        expect(mockAdapter.callLog, [
          'setSpeakerphoneOn(false)',
          'setSpeakerphoneOn(true)',
        ]);

        await audioManager.resetOnCallEnded('call-101');
        expect(audioManager.activeCallId, isNull);
        expect(audioManager.isSpeakerOn, isFalse);
        expect(mockAdapter.callLog, [
          'setSpeakerphoneOn(false)',
          'setSpeakerphoneOn(true)',
          'setSpeakerphoneOn(false)',
        ]);
      },
    );

    test(
      'Call-ID protection: stale callbacks from older call cannot alter active call',
      () async {
        audioManager.prepareForCall('call-current');
        await audioManager.ensureDefaultAudioRoute('call-current');
        mockAdapter.callLog.clear();

        // Stale toggle from previous call-old
        final staleToggle = await audioManager.setSpeakerphone(
          true,
          callId: 'call-old',
        );
        expect(staleToggle, isFalse);
        expect(audioManager.isSpeakerOn, isFalse);
        expect(mockAdapter.callLog, isEmpty);

        // Stale reset from call-old
        await audioManager.resetOnCallEnded('call-old');
        expect(audioManager.activeCallId, 'call-current');
        expect(audioManager.isMediaReady, isTrue);
        expect(mockAdapter.callLog, isEmpty);
      },
    );

    test(
      'Native error during toggle does not corrupt Dart UI state and returns false',
      () async {
        audioManager.prepareForCall('call-101');
        await audioManager.ensureDefaultAudioRoute('call-101');
        mockAdapter.callLog.clear();

        mockAdapter.shouldFail = true;

        final success = await audioManager.toggleSpeakerphone(
          callId: 'call-101',
        );

        expect(success, isFalse);
        // State remains false, not wrongly flipped to true
        expect(audioManager.isSpeakerOn, isFalse);
      },
    );

    test(
      'resetOnCallEnded skips native route if media was never ready (e.g. failed before progress)',
      () async {
        audioManager.prepareForCall('call-failed-early');
        expect(audioManager.isMediaReady, isFalse);

        await audioManager.resetOnCallEnded('call-failed-early');
        expect(mockAdapter.callLog, isEmpty);
      },
    );

    test(
      'playRingtone and stopAll execute cleanly with structured logging and no exceptions',
      () async {
        audioManager.prepareForCall('call-ring-101');
        await audioManager.playRingtone(callId: 'call-ring-101');
        await audioManager.stopAll(reason: 'test_stop');
        expect(audioManager.activeCallId, 'call-ring-101');
      },
    );
  });
}
