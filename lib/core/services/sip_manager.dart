import 'dart:async';
import 'package:flutter/foundation.dart'
    show kIsWeb, kDebugMode, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sip_ua/sip_ua.dart';
import '../constants/app_constants.dart';
import '../../data/models/sip_account.dart';
import 'audio_manager.dart';
import 'call_coordinator.dart';
import 'native_call_bridge.dart';

void _log(String tag, String msg) {
  final now = DateTime.now();
  final ts =
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
  debugPrint('[$ts][$tag] $msg');
}

enum CallScreenState { none, incoming, inCall }

enum SipConnectionStatus { offline, connecting, registering, online, error }

enum CallInitiationStatus {
  started,
  emptyNumber,
  sipOffline,
  transportDisconnected,
  unregistered,
  callAlreadyActive,
  alreadyDialing,
  microphoneDenied,
  microphonePermanentlyDenied,
  failed,
}

class CallInitiationResult {
  final CallInitiationStatus status;
  final String message;

  const CallInitiationResult(this.status, this.message);

  bool get isSuccess => status == CallInitiationStatus.started;

  factory CallInitiationResult.started() => const CallInitiationResult(
    CallInitiationStatus.started,
    'Đang khởi tạo cuộc gọi...',
  );

  factory CallInitiationResult.emptyNumber() => const CallInitiationResult(
    CallInitiationStatus.emptyNumber,
    'Vui lòng nhập số điện thoại hoặc số máy nhánh',
  );

  factory CallInitiationResult.sipOffline() => const CallInitiationResult(
    CallInitiationStatus.sipOffline,
    'SIP chưa online. Đang kết nối lại...',
  );

  factory CallInitiationResult.transportDisconnected() =>
      const CallInitiationResult(
        CallInitiationStatus.transportDisconnected,
        'WSS đã mất kết nối với máy chủ',
      );

  factory CallInitiationResult.unregistered() => const CallInitiationResult(
    CallInitiationStatus.unregistered,
    'Tài khoản chưa REGISTER với tổng đài',
  );

  factory CallInitiationResult.callAlreadyActive() =>
      const CallInitiationResult(
        CallInitiationStatus.callAlreadyActive,
        'Đang có cuộc gọi khác đang hoạt động',
      );

  factory CallInitiationResult.alreadyDialing() => const CallInitiationResult(
    CallInitiationStatus.alreadyDialing,
    'Đang khởi tạo cuộc gọi, vui lòng đợi',
  );

  factory CallInitiationResult.microphoneDenied() => const CallInitiationResult(
    CallInitiationStatus.microphoneDenied,
    'Microphone bị từ chối. Cần cấp quyền để gọi',
  );

  factory CallInitiationResult.microphonePermanentlyDenied() =>
      const CallInitiationResult(
        CallInitiationStatus.microphonePermanentlyDenied,
        'Microphone bị chặn vĩnh viễn. Vui lòng mở Cài đặt để cho phép',
      );

  factory CallInitiationResult.failed(String msg) =>
      CallInitiationResult(CallInitiationStatus.failed, msg);

  @override
  String toString() => 'CallInitiationResult($status, $message)';
}

class SipManager extends ChangeNotifier
    with WidgetsBindingObserver
    implements SipUaHelperListener, CallHandlerDelegate {
  static final SipManager _instance = SipManager._internal();
  factory SipManager() => _instance;
  SipManager._internal();

  SIPUAHelper _helper = SIPUAHelper();
  final AudioManager _audioManager = AudioManager();
  CallCoordinator? _callCoordinator;

  CallCoordinator get callCoordinator => _callCoordinator ??= CallCoordinator(
    nativeCallBridge: MethodChannelNativeCallBridge(),
    delegate: this,
  );

  @visibleForTesting
  void setCallCoordinatorForTesting(CallCoordinator? coordinator) {
    _callCoordinator = coordinator;
    _callCoordinator?.delegate = this;
  }

  @override
  bool get hasActiveCall => _currentCall != null;

  @override
  Future<void> ensureConnected() async {
    if (_connectionStatus != SipConnectionStatus.online && _account != null) {
      await register(newAccount: _account);
    }
  }

  SipAccount? _account;
  SipConnectionStatus _connectionStatus = SipConnectionStatus.offline;
  String _statusMessage = 'Chưa kết nối';

  bool _isDialing = false;
  String? _pendingTargetNumber;

  Call? _currentCall;
  CallState? _callState;
  bool _isMuted = false;
  bool _isOnHold = false;
  int _callDurationSeconds = 0;
  Timer? _callTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3;
  bool _isReconfiguring = false;
  bool _isRegistering = false;
  bool _hasTerminalAuthError = false;

  // WebRTC Observability & Diagnostic metrics
  Timer? _statsTimer;
  bool _forceRelayOnly = false;
  bool _diagnosticLogging = false;
  List<Map<String, String>> _iceServers = const [];
  int _packetsSent = 0;
  int _packetsReceived = 0;
  int _bytesSent = 0;
  int _bytesReceived = 0;
  int _packetsLost = 0;
  double _jitter = 0.0;
  double _roundTripTime = 0.0;
  String _selectedCandidatePair = 'Đang thương lượng...';
  String _signalingState = 'new';
  String _iceState = 'new';
  String _peerConnectionState = 'new';
  String _dtlsState = 'new';
  String _negotiatedCodec = 'unknown';
  String _mediaState = 'idle';
  bool _loggedSessionDescriptions = false;
  bool _isDiagnosticUiActive = false;
  int _navigationGeneration = 0;
  final Map<String, Stopwatch> _callStopwatches = {};

  // Global navigator key for navigating to incoming / in-call screens
  GlobalKey<NavigatorState>? navigatorKey;

  // Getters
  SIPUAHelper get helper => _helper;
  SipAccount? get account => _account;
  SipConnectionStatus get connectionStatus => _connectionStatus;
  String get statusMessage => _statusMessage;
  bool get isDialing => _isDialing;
  String? get pendingTargetNumber => _pendingTargetNumber;
  Call? get currentCall => _currentCall;
  CallState? get callState => _callState;
  bool get isMuted => _isMuted;
  bool get isOnHold => _isOnHold;
  bool get isSpeakerOn => _audioManager.isSpeakerOn;
  int get callDurationSeconds => _callDurationSeconds;
  int get reconnectAttempts => _reconnectAttempts;
  bool get hasTerminalAuthError => _hasTerminalAuthError;
  bool get isRegistering => _isRegistering;
  bool get forceRelayOnly => _forceRelayOnly;
  int get packetsSent => _packetsSent;
  int get packetsReceived => _packetsReceived;
  int get bytesSent => _bytesSent;
  int get bytesReceived => _bytesReceived;
  int get packetsLost => _packetsLost;
  double get jitter => _jitter;
  double get roundTripTime => _roundTripTime;
  String get selectedCandidatePair => _selectedCandidatePair;
  String get signalingState => _signalingState;
  String get iceState => _iceState;
  String get peerConnectionState => _peerConnectionState;
  String get dtlsState => _dtlsState;
  String get negotiatedCodec => _negotiatedCodec;
  String get mediaState => _mediaState;
  bool get isDiagnosticUiActive => _isDiagnosticUiActive;
  int get navigationGeneration => _navigationGeneration;

  void setDiagnosticUiActive(bool active) {
    _isDiagnosticUiActive = active;
    if (active) {
      notifyListeners();
    }
  }

  void _logCallTiming(String? callIdOrTag, String event, {String? extra}) {
    final id = (callIdOrTag != null && callIdOrTag.isNotEmpty)
        ? callIdOrTag
        : 'unknown';
    final sw = _callStopwatches.putIfAbsent(id, () {
      final s = Stopwatch()..start();
      return s;
    });
    final elapsedMs = sw.elapsedMilliseconds;
    final extraStr = extra != null && extra.isNotEmpty ? ' | $extra' : '';
    _log('TIMING_CALL', '[$id] $event elapsed=${elapsedMs}ms$extraStr');
  }

  void logIncomingFirstFrame() {
    final callId = _currentCall?.id ?? 'incoming';
    _logCallTiming(callId, 'INCOMING_FIRST_FRAME');
  }

  String get friendlyCallStatus {
    if (_isDialing) return 'Đang gọi…';
    final call = _currentCall;
    final state = _callState?.state;
    if (call == null && !_isDialing) return 'Cuộc gọi kết thúc';
    if (_isOnHold) return 'Đang giữ máy';
    switch (state) {
      case CallStateEnum.CALL_INITIATION:
        return call?.direction.toUpperCase() == 'INCOMING'
            ? 'Đang đổ chuông…'
            : 'Đang gọi…';
      case CallStateEnum.CONNECTING:
        return 'Đang kết nối…';
      case CallStateEnum.PROGRESS:
        return 'Đang đổ chuông…';
      case CallStateEnum.ACCEPTED:
      case CallStateEnum.CONFIRMED:
      case CallStateEnum.STREAM:
        return 'Đang đàm thoại';
      case CallStateEnum.HOLD:
        return 'Đang giữ máy';
      case CallStateEnum.ENDED:
        return 'Cuộc gọi kết thúc';
      case CallStateEnum.FAILED:
        return 'Không thể kết nối';
      default:
        return (_callState?.state == CallStateEnum.CONFIRMED ||
                _callState?.state == CallStateEnum.ACCEPTED)
            ? 'Đang đàm thoại'
            : 'Đang kết nối…';
    }
  }

  void setForceRelayOnly(bool value) {
    _forceRelayOnly = value;
    notifyListeners();
  }

  String get formattedDuration {
    final mins = (_callDurationSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (_callDurationSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  Future<void> initialize({GlobalKey<NavigatorState>? navKey}) async {
    navigatorKey = navKey;
    WidgetsBinding.instance.addObserver(this);
    _helper.addSipUaHelperListener(this);
    await _audioManager.init();
    _account = await SipAccount.loadFromPrefs();
    _forceRelayOnly = _account!.forceRelayOnly;
    _diagnosticLogging = _account!.diagnosticLogging;
    if (_hasRequiredAccountSettings(_account!)) {
      await register();
    } else {
      _connectionStatus = SipConnectionStatus.offline;
      _statusMessage = 'Chưa cấu hình tài khoản SIP';
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _log('SipManager', 'didChangeAppLifecycleState: $state');
    if (state == AppLifecycleState.resumed) {
      if (_currentCall == null &&
          !_hasTerminalAuthError &&
          (!_helper.connected ||
              !_helper.registered ||
              _connectionStatus != SipConnectionStatus.online)) {
        _log(
          'SipManager',
          'App resumed & SIP offline -> Triggering immediate register()',
        );
        _reconnectAttempts = 0;
        register();
      }
    }
  }

  Future<void> register({
    SipAccount? newAccount,
    bool resetAttempts = false,
  }) async {
    if (newAccount != null) {
      _account = newAccount;
      _reconnectAttempts = 0;
      _hasTerminalAuthError = false;
      await _account!.saveToPrefs();
    } else if (resetAttempts) {
      _reconnectAttempts = 0;
      _hasTerminalAuthError = false;
    }

    if (_isRegistering && newAccount == null) {
      _log(
        'SipManager',
        'register() skipped: another registration operation is already in progress',
      );
      return;
    }

    _isRegistering = true;
    try {
      _account ??= await SipAccount.loadFromPrefs();

      final acc = _account!;
      if (!_hasRequiredAccountSettings(acc)) {
        _connectionStatus = SipConnectionStatus.error;
        _statusMessage = 'Thiếu WSS, domain, extension hoặc mật khẩu SIP';
        notifyListeners();
        return;
      }
      _forceRelayOnly = acc.forceRelayOnly;
      _diagnosticLogging = acc.diagnosticLogging;
      _connectionStatus = SipConnectionStatus.connecting;
      _statusMessage = 'Đang kết nối WSS...';
      notifyListeners();

      final settings = UaSettings();

      // Explicitly set transportType to WS (Fixes Null check operator crash in sip_ua)
      settings.transportType = TransportType.WS;
      settings.webSocketUrl = acc.wssUri;
      // A debug APK is still distributed to real devices by CI, therefore it
      // must not silently trust an invalid certificate. Local developers can
      // opt in explicitly with SGT_ALLOW_BAD_CERTIFICATE=true; release and
      // profile builds always require a valid certificate.
      settings.webSocketSettings.allowBadCertificate =
          kDebugMode && AppConstants.allowBadCertificateInDebug;
      settings.webSocketSettings.transport_scheme = acc.wssUri.startsWith('wss')
          ? 'wss'
          : 'ws';
      settings.uri = 'sip:${acc.extension}@${acc.domain}';
      settings.authorizationUser = acc.extension;
      settings.password = acc.password;
      settings.realm = 'asterisk';
      settings.displayName = acc.displayName.isNotEmpty
          ? acc.displayName
          : acc.extension;
      settings.userAgent = 'Flutter SGT VoIP Softphone / Asterisk 20';
      settings.register = true;
      // 25s auto-refresh registration via sip_ua registrator (fires at 20s < 32s Asterisk idle timeout)
      settings.register_expires = 25;
      settings.iceGatheringTimeout = acc.iceGatheringTimeoutMs;

      // Cấu hình đầy đủ STUN và TURN cho NAT Traversal (4G/Wi-Fi)
      final iceServers = <Map<String, String>>[
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ];
      if (acc.stunUri.isNotEmpty && !acc.stunUri.contains('google.com')) {
        iceServers.add({'urls': acc.stunUri});
      }
      for (final uri
          in acc.turnUri
              .split(RegExp(r'[,\n]'))
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)) {
        final turnMap = <String, String>{'urls': uri};
        if (acc.turnUsername.isNotEmpty) {
          turnMap['username'] = acc.turnUsername;
        }
        if (acc.turnPassword.isNotEmpty) {
          turnMap['credential'] = acc.turnPassword;
        }
        iceServers.add(turnMap);
      }

      settings.iceServers = iceServers;
      _iceServers = List.unmodifiable(iceServers);
      settings.dtmfMode = DtmfMode.RFC2833;

      if (_helper.connected || _helper.registered) {
        _isReconfiguring = true;
        _reconnectTimer?.cancel();
        _helper.stop();
        await Future.delayed(const Duration(milliseconds: 150));
        _isReconfiguring = false;
      }

      _helper.start(settings);
    } catch (e) {
      debugPrint('[SipManager] Register error: $e');
      _connectionStatus = SipConnectionStatus.error;
      _statusMessage = 'Lỗi kết nối: $e';
      notifyListeners();
      _scheduleReconnect();
    } finally {
      _isRegistering = false;
    }
  }

  void retryRegistration() {
    _log('SipManager', 'Manual registration retry triggered');
    _reconnectAttempts = 0;
    _hasTerminalAuthError = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    register(resetAttempts: true);
  }

  Future<void> unregister() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    try {
      _isReconfiguring = true;
      _helper.unregister(true);
      _helper.stop();
      _isReconfiguring = false;
      _connectionStatus = SipConnectionStatus.offline;
      _statusMessage = 'Đã ngắt kết nối';
      notifyListeners();
    } catch (e) {
      debugPrint('[SipManager] Unregister error: $e');
    }
  }

  // ── Call Actions ──────────────────────────────────────────────────────────

  Future<CallInitiationResult> makeCall(String targetNumber) async {
    final cleanNumber = targetNumber.trim();
    _logCallTiming(cleanNumber, 'DIAL_CLICK', extra: 'target=$cleanNumber');

    if (cleanNumber.isEmpty) {
      _log('CALL_VALIDATE', 'makeCall rejected: cleanNumber is empty');
      return CallInitiationResult.emptyNumber();
    }

    if (_isDialing) {
      _log(
        'CALL_VALIDATE',
        'makeCall rejected: already dialing ($cleanNumber)',
      );
      return CallInitiationResult.alreadyDialing();
    }

    if (_currentCall != null) {
      _log('CALL_VALIDATE', 'makeCall rejected: a call is already active');
      return CallInitiationResult.callAlreadyActive();
    }

    final isCustomOnline = _connectionStatus == SipConnectionStatus.online;
    final isHelperConnected = _helper.connected;
    final isHelperRegistered = _helper.registered;

    _log(
      'CALL_STATUS',
      'Pre-call check: connectionStatus=$_connectionStatus, helperConnected=$isHelperConnected, helperRegistered=$isHelperRegistered',
    );

    if (!isCustomOnline || !isHelperConnected || !isHelperRegistered) {
      final msg = !isHelperConnected
          ? 'WSS đã mất kết nối với máy chủ'
          : (!isHelperRegistered
                ? 'Tài khoản chưa REGISTER với tổng đài'
                : 'SIP chưa online. Đang kết nối lại...');
      _statusMessage = msg;
      _log(
        'CALL_STATUS',
        'State mismatch or offline: connectionStatus=$_connectionStatus, helperConnected=$isHelperConnected, helperRegistered=$isHelperRegistered',
      );
      notifyListeners();
      if (!isHelperConnected) {
        return CallInitiationResult.transportDisconnected();
      } else if (!isHelperRegistered) {
        return CallInitiationResult.unregistered();
      } else {
        return CallInitiationResult.sipOffline();
      }
    }

    final acc = _account;
    if (acc == null || !_hasRequiredAccountSettings(acc)) {
      _statusMessage = 'Thiếu cấu hình tài khoản SIP';
      _log(
        'CALL_VALIDATE',
        'makeCall rejected: missing account or required settings',
      );
      notifyListeners();
      return CallInitiationResult.failed('Thiếu cấu hình tài khoản SIP');
    }

    _isDialing = true;
    _pendingTargetNumber = cleanNumber;
    notifyListeners();

    // 1. Request Microphone Runtime Permission on iOS/Android
    if (!kIsWeb) {
      try {
        var micStatus = await Permission.microphone.status;
        _log('CALL_MIC', 'Microphone permission status: $micStatus');
        if (micStatus.isPermanentlyDenied) {
          _isDialing = false;
          _pendingTargetNumber = null;
          notifyListeners();
          _log('CALL_MIC', 'Microphone permission permanently denied');
          return CallInitiationResult.microphonePermanentlyDenied();
        }
        if (!micStatus.isGranted) {
          micStatus = await Permission.microphone.request();
          _log('CALL_MIC', 'Microphone permission requested: $micStatus');
          if (micStatus.isPermanentlyDenied) {
            _isDialing = false;
            _pendingTargetNumber = null;
            notifyListeners();
            return CallInitiationResult.microphonePermanentlyDenied();
          }
          if (!micStatus.isGranted) {
            _isDialing = false;
            _pendingTargetNumber = null;
            _statusMessage = 'Cần cấp quyền Microphone để gọi';
            notifyListeners();
            return CallInitiationResult.microphoneDenied();
          }
        }
        _logCallTiming(
          cleanNumber,
          'MIC_CHECK_DONE',
          extra: 'status=$micStatus',
        );
      } catch (e) {
        _isDialing = false;
        _pendingTargetNumber = null;
        notifyListeners();
        _log('CALL_MIC', 'Error requesting microphone permission: $e');
        return CallInitiationResult.failed('Lỗi kiểm tra quyền Microphone: $e');
      }
    }

    try {
      final targetUri = 'sip:$cleanNumber@${acc.domain}';
      _log('CALL_DIAL', 'Dialing target: $cleanNumber (URI: $targetUri)');
      _logCallTiming(cleanNumber, 'CALL_HELPER_START', extra: 'uri=$targetUri');

      // Only pass the values that differ from SIPUAHelper defaults. Passing
      // buildCallOptions() back as customOptions makes sip_ua 0.6.0 merge two
      // complete option trees recursively. On Flutter web, nested map literals
      // in that package are LinkedMap<dynamic, dynamic>, which cannot be cast
      // to Map<String, dynamic> by MapHelper.merge.
      final mediaConstraints = <String, dynamic>{'audio': true, 'video': false};

      // Reset timer and WebRTC diagnostics before initiating
      _stopCallTimer();
      _callDurationSeconds = 0;
      _resetWebRtcDiagnostics();

      final callOptions = <String, dynamic>{};
      callOptions['mediaConstraints'] = mediaConstraints;
      _applyIceTransportPolicy(callOptions);

      // Pre-configure audio manager state for outgoing call
      _audioManager.prepareForCall(cleanNumber);

      _log('CALL_HELPER', 'Calling _helper.call for $cleanNumber...');
      final started = await _helper.call(
        targetUri,
        voiceonly: true,
        customOptions: callOptions,
      );
      _log('CALL_HELPER', '_helper.call returned $started for $cleanNumber');
      _logCallTiming(
        cleanNumber,
        'CALL_HELPER_RETURNED',
        extra: 'started=$started',
      );

      if (!started) {
        _isDialing = false;
        _pendingTargetNumber = null;
        _statusMessage = 'Không thể tạo phiên gọi SIP';
        notifyListeners();
        return CallInitiationResult.failed(
          'Không thể tạo phiên gọi SIP (SIPUAHelper.call trả về false)',
        );
      }

      return CallInitiationResult.started();
    } catch (e, stack) {
      _isDialing = false;
      _pendingTargetNumber = null;
      _log('CALL_ERROR', 'Exception during makeCall: $e\n$stack');
      _statusMessage = 'Lỗi khởi tạo cuộc gọi: $e';
      notifyListeners();
      return CallInitiationResult.failed('Lỗi khởi tạo cuộc gọi: $e');
    }
  }

  @override
  Future<void> answerCall() async {
    final call = _currentCall;
    if (call != null) {
      try {
        _log('TIMING', '>>> answerCall clicked by user (id=${call.id})');
        _logCallTiming(call.id, 'ANSWER_CLICK');
        if (!kIsWeb) {
          var micStatus = await Permission.microphone.status;
          if (!micStatus.isGranted) {
            micStatus = await Permission.microphone.request();
            if (!micStatus.isGranted) {
              _log('CALL_MIC', 'Microphone permission denied on answerCall');
              _statusMessage = 'Cần cấp quyền Microphone để trả lời cuộc gọi';
              notifyListeners();
              return;
            }
          }
        }
        await _audioManager.stopAll();
        await _audioManager.ensureDefaultAudioRoute(call.id);
        _log('TIMING', 'Answering call id=${call.id}...');
        final answerOptions = _helper.buildCallOptions(true);
        _applyIceTransportPolicy(answerOptions);
        call.answer(answerOptions);
        _startCallTimer();
        _navigateToInCall();
        notifyListeners();
      } catch (e, stack) {
        _log('SipManager', 'Error during answerCall: $e\n$stack');
      }
    }
  }

  @override
  void hangupCall() {
    _isDialing = false;
    _pendingTargetNumber = null;
    final callId = _currentCall?.id;
    if (callId != null) {
      _logCallTiming(callId, 'HANGUP_CLICK');
      _audioManager.resetOnCallEnded(callId);
    }
    _audioManager.stopAll();
    _audioManager.detachRemoteStream(callId);
    _stopCallTimer();
    _stopWebRtcStatsCollection();
    _callDurationSeconds = 0;
    if (_currentCall != null) {
      try {
        _currentCall!.hangup();
      } catch (e) {
        debugPrint('[SipManager] Hangup error: $e');
      }
    }
    _currentCall = null;
    _callState = null;
    _navigateBackToDialpad();
    notifyListeners();
  }

  void toggleMute() {
    if (_currentCall == null) return;
    if (_isMuted) {
      _currentCall!.unmute(true, false);
    } else {
      _currentCall!.mute(true, false);
    }
  }

  void toggleHold() {
    if (_currentCall == null) return;
    _isOnHold = !_isOnHold;
    if (_isOnHold) {
      _currentCall!.hold();
    } else {
      _currentCall!.unhold();
    }
    notifyListeners();
  }

  Future<bool> toggleSpeaker() async {
    final success = await _audioManager.toggleSpeakerphone(
      callId: _currentCall?.id,
    );
    if (success) {
      notifyListeners();
    }
    return success;
  }

  void sendDTMF(String tone) {
    if (_currentCall != null &&
        _currentCall!.state == CallStateEnum.CONFIRMED) {
      try {
        _currentCall!.sendDTMF(tone);
      } catch (e) {
        debugPrint('[SipManager] sendDTMF error: $e');
      }
    }
  }

  /// Đá luồng / Chuyển cuộc gọi (Hỗ trợ cả SIP REFER và DTMF ##)
  Future<bool> transferCall(String targetExtension) async {
    if (_currentCall == null || targetExtension.trim().isEmpty) return false;
    final target = targetExtension.trim();
    final targetUri = target.contains('@')
        ? target
        : '$target@${_account!.domain}';

    debugPrint('[SipManager] Transferring call to: $targetUri');
    try {
      // 1. Chuyển cuộc gọi chuẩn SIP REFER
      _currentCall!.refer('sip:$targetUri');
      return true;
    } catch (e) {
      debugPrint('[SipManager] SIP REFER failed ($e), falling back to DTMF ##');
      try {
        // 2. Dự phòng bằng DTMF Feature ##
        _currentCall!.sendDTMF('##$target');
        return true;
      } catch (dtmfErr) {
        debugPrint('[SipManager] DTMF Transfer error: $dtmfErr');
        return false;
      }
    }
  }

  void transferViaDTMF(String targetExtension) {
    if (_currentCall != null) {
      _currentCall!.sendDTMF('##${targetExtension.trim()}');
    }
  }

  // ── Call Timer Helpers ───────────────────────────────────────────────────

  void _startCallTimer() {
    if (_callTimer != null && _callTimer!.isActive) {
      return;
    }
    _stopCallTimer();
    _callDurationSeconds = 0;
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _callDurationSeconds++;
      notifyListeners();
    });
  }

  void _stopCallTimer() {
    _callTimer?.cancel();
    _callTimer = null;
    _callDurationSeconds = 0;
    _stopWebRtcStatsCollection();
  }

  // ── WebRTC Observability Stats Helpers ────────────────────────────────────

  void _startWebRtcStatsCollection() {
    if (_statsTimer?.isActive == true) return;
    Future<void> collect() async {
      final call = _currentCall;
      if (call == null) {
        _stopWebRtcStatsCollection();
        return;
      }
      final pc = call.peerConnection;
      if (pc == null) return;

      try {
        final previousPacketsSent = _packetsSent;
        final previousPacketsReceived = _packetsReceived;
        final reports = await pc.getStats();
        final reportsById = {for (final report in reports) report.id: report};
        _signalingState = '${await pc.getSignalingState()}'.split('.').last;
        _iceState = '${await pc.getIceConnectionState()}'.split('.').last;
        _peerConnectionState = '${await pc.getConnectionState()}'
            .split('.')
            .last;

        if (!_loggedSessionDescriptions) {
          final local = await pc.getLocalDescription();
          final remote = await pc.getRemoteDescription();
          if (local?.sdp != null || remote?.sdp != null) {
            _diag(
              'WEBRTC_SDP',
              'local=${_summarizeSdp(local?.sdp)} remote=${_summarizeSdp(remote?.sdp)}',
            );
            _loggedSessionDescriptions = true;
          }
        }

        for (final report in reports) {
          final vals = report.values;
          if (report.type == 'inbound-rtp' &&
              (vals['kind'] == 'audio' || vals['mediaType'] == 'audio')) {
            _packetsReceived =
                int.tryParse('${vals['packetsReceived']}') ?? _packetsReceived;
            _bytesReceived =
                int.tryParse('${vals['bytesReceived']}') ?? _bytesReceived;
            _packetsLost =
                int.tryParse('${vals['packetsLost']}') ?? _packetsLost;
            _jitter = double.tryParse('${vals['jitter']}') ?? _jitter;
            final codec = reportsById['${vals['codecId']}'];
            if (codec != null) {
              _negotiatedCodec =
                  '${codec.values['mimeType'] ?? codec.values['codec'] ?? 'unknown'}';
            }
          } else if (report.type == 'outbound-rtp' &&
              (vals['kind'] == 'audio' || vals['mediaType'] == 'audio')) {
            _packetsSent =
                int.tryParse('${vals['packetsSent']}') ?? _packetsSent;
            _bytesSent = int.tryParse('${vals['bytesSent']}') ?? _bytesSent;
          } else if (report.type == 'candidate-pair' &&
              vals['state'] == 'succeeded' &&
              (vals['nominated'] == true ||
                  vals['selected'] == true ||
                  (int.tryParse('${vals['bytesSent']}') ?? 0) > 0 ||
                  (int.tryParse('${vals['bytesReceived']}') ?? 0) > 0)) {
            _roundTripTime =
                double.tryParse('${vals['currentRoundTripTime']}') ??
                _roundTripTime;
            final local = reportsById['${vals['localCandidateId']}'];
            final remote = reportsById['${vals['remoteCandidateId']}'];
            _selectedCandidatePair =
                '${_candidateLabel(local?.values)} <-> ${_candidateLabel(remote?.values)} '
                '(RTT: ${(_roundTripTime * 1000).toStringAsFixed(1)}ms)';
          } else if (report.type == 'transport') {
            _dtlsState = '${vals['dtlsState'] ?? _dtlsState}';
          }
        }

        final sending = _packetsSent > previousPacketsSent;
        final receiving = _packetsReceived > previousPacketsReceived;
        if (sending && receiving) {
          _mediaState = 'flowing';
        } else if (sending || receiving) {
          _mediaState = 'one-way';
        } else if (_packetsSent == 0 && _packetsReceived == 0) {
          _mediaState = 'negotiating';
        } else {
          _mediaState = 'stalled';
        }

        _diag(
          'WEBRTC_STATS',
          '[Call-ID: ${call.id}] '
              'Rcvd: $_packetsReceived pkts (${_bytesReceived}B) | '
              'Sent: $_packetsSent pkts (${_bytesSent}B) | '
              'Lost: $_packetsLost | Jitter: ${_jitter.toStringAsFixed(3)}s | '
              'Codec: $_negotiatedCodec | ICE: $_iceState | DTLS: $_dtlsState | '
              'Media: $_mediaState | Pair: $_selectedCandidatePair',
        );
        if (_isDiagnosticUiActive) {
          notifyListeners();
        }
      } catch (e) {
        _log('WEBRTC_STATS', 'Collection error: $e');
      }
    }

    collect();
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) => collect());
  }

  void _stopWebRtcStatsCollection() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  void _resetWebRtcDiagnostics() {
    _packetsSent = 0;
    _packetsReceived = 0;
    _bytesSent = 0;
    _bytesReceived = 0;
    _packetsLost = 0;
    _jitter = 0.0;
    _roundTripTime = 0.0;
    _selectedCandidatePair = 'Đang thương lượng...';
    _signalingState = 'new';
    _iceState = 'new';
    _peerConnectionState = 'new';
    _dtlsState = 'new';
    _negotiatedCodec = 'unknown';
    _mediaState = 'idle';
    _loggedSessionDescriptions = false;
  }

  bool _hasRequiredAccountSettings(SipAccount account) {
    return account.wssUri.trim().isNotEmpty &&
        account.domain.trim().isNotEmpty &&
        account.extension.trim().isNotEmpty &&
        account.password.isNotEmpty;
  }

  void _applyIceTransportPolicy(Map<String, dynamic> options) {
    final existing = options['pcConfig'];
    final pcConfig = existing is Map
        ? Map<String, dynamic>.from(existing)
        : <String, dynamic>{};
    pcConfig.putIfAbsent('iceServers', () => _iceServers);
    pcConfig['iceTransportPolicy'] = _forceRelayOnly ? 'relay' : 'all';
    options['pcConfig'] = pcConfig;
  }

  void _diag(String tag, String message) {
    if (_diagnosticLogging) {
      _log(tag, message);
    }
  }

  String _candidateLabel(Map<dynamic, dynamic>? values) {
    if (values == null) return 'unknown';
    final type = values['candidateType'] ?? 'unknown';
    final protocol = values['protocol'] ?? '';
    final address = values['address'] ?? values['ip'] ?? '';
    final port = values['port'] ?? '';
    return '$type/$protocol $address:$port'.trim();
  }

  String _summarizeSdp(String? sdp) {
    if (sdp == null || sdp.isEmpty) return 'none';
    return sdp
        .split(RegExp(r'\r?\n'))
        .where(
          (line) =>
              line.startsWith('m=audio') ||
              line.startsWith('a=rtpmap:') ||
              line.startsWith('a=fingerprint:') ||
              line.startsWith('a=candidate:'),
        )
        .join(' | ');
  }

  // ── SipUaHelperListener Callbacks ────────────────────────────────────────

  bool _isTerminalRegistrationError(RegistrationState state) {
    final cause = state.cause;
    if (cause == null) return false;
    final code = cause.status_code;
    if (code == 401 || code == 403 || code == 404 || code == 407) {
      return true;
    }
    final phrase = (cause.reason_phrase ?? '').toLowerCase();
    final causeStr = (cause.cause ?? '').toLowerCase();
    if (phrase.contains('forbidden') ||
        phrase.contains('unauthorized') ||
        phrase.contains('not found') ||
        causeStr.contains('forbidden') ||
        causeStr.contains('unauthorized')) {
      return true;
    }
    return false;
  }

  @override
  void registrationStateChanged(RegistrationState state) {
    _log(
      'TIMING',
      'registrationStateChanged: ${state.state} (cause=${state.cause?.toString()})',
    );
    switch (state.state) {
      case RegistrationStateEnum.REGISTERED:
        _reconnectAttempts = 0;
        _hasTerminalAuthError = false;
        _connectionStatus = SipConnectionStatus.online;
        _statusMessage = 'Đã đăng ký (${_account?.extension})';
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        break;
      case RegistrationStateEnum.UNREGISTERED:
        _connectionStatus = SipConnectionStatus.offline;
        _statusMessage = 'Chưa đăng ký';
        break;
      case RegistrationStateEnum.REGISTRATION_FAILED:
        _connectionStatus = SipConnectionStatus.error;
        if (_isTerminalRegistrationError(state)) {
          _hasTerminalAuthError = true;
          _reconnectTimer?.cancel();
          _reconnectTimer = null;
          final reason =
              state.cause?.reason_phrase ??
              state.cause?.cause ??
              'Sai tài khoản hoặc mật khẩu';
          _statusMessage = 'Đăng ký thất bại: $reason';
          _log(
            'SipManager',
            'Terminal registration failure: ${state.cause}. Auto-reconnect aborted to prevent PBX lock.',
          );
        } else {
          _statusMessage =
              'Đăng ký thất bại (${state.cause?.reason_phrase ?? state.cause?.toString() ?? 'Lỗi'}). Đang thử lại...';
          _scheduleReconnect();
        }
        break;
      case RegistrationStateEnum.NONE:
      default:
        _connectionStatus = SipConnectionStatus.offline;
        _statusMessage = 'Ngoại tuyến';
        break;
    }
    notifyListeners();
  }

  void _scheduleReconnect() {
    if (_currentCall != null || _isReconfiguring || _hasTerminalAuthError) {
      return;
    }
    _reconnectTimer?.cancel();
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _log(
        'SipManager',
        'Max auto-reconnect attempts reached ($_maxReconnectAttempts).',
      );
      _connectionStatus = SipConnectionStatus.error;
      _statusMessage =
          'Mất kết nối sau $_maxReconnectAttempts lần thử. Chạm biểu tượng để thử lại.';
      notifyListeners();
      return;
    }

    final delaySeconds = [2, 5, 10][_reconnectAttempts % 3];
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (_connectionStatus != SipConnectionStatus.online &&
          _currentCall == null &&
          !_isReconfiguring &&
          !_hasTerminalAuthError) {
        _reconnectAttempts++;
        _log(
          'SipManager',
          'Auto-reconnecting (attempt $_reconnectAttempts/$_maxReconnectAttempts in ${delaySeconds}s)...',
        );
        register();
      }
    });
  }

  @override
  void callStateChanged(Call call, CallState state) {
    _log(
      'TIMING',
      'callStateChanged: state=${state.state}, origin=${call.direction}, id=${call.id}',
    );
    _logCallTiming(
      call.id,
      'CALL_STATE_${state.state}',
      extra: 'origin=${call.direction}',
    );

    // Crucial: assign _currentCall and _callState BEFORE any navigation
    _currentCall = call;
    _callState = state;

    switch (state.state) {
      case CallStateEnum.CALL_INITIATION:
        _isDialing = false;
        _pendingTargetNumber = null;
        _stopCallTimer();
        _resetWebRtcDiagnostics();
        _callDurationSeconds = 0;
        if (call.direction.toUpperCase() == 'INCOMING') {
          _log(
            'CALL_INITIATION',
            '>>> INCOMING INVITE received! Starting ringtone and navigating to incoming call screen.',
          );
          _audioManager.prepareForCall(call.id);

          final isForeground =
              WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.resumed;
          final callerNumber = call.remote_identity ?? '';
          final callerName = 'Extension $callerNumber';

          final autoAnswered =
              _callCoordinator?.onIncomingCallReceived(
                callUuid: call.id ?? '',
                callerName: callerName,
                callerNumber: callerNumber,
                isAppForeground: isForeground,
              ) ??
              false;

          if (!autoAnswered) {
            _navigateToIncomingCall();
            _audioManager.playRingtone(callId: call.id);
          }
        } else {
          _log(
            'CALL_INITIATION',
            '>>> OUTGOING call initiated (id=${call.id}). Navigating to in-call screen.',
          );
          _logCallTiming(call.id, 'CALL_INITIATION_OUTGOING');
          _audioManager.updateCallId(call.id);
          _navigateToInCall();
        }
        break;

      case CallStateEnum.CONNECTING:
        _log('TIMING', 'Call is CONNECTING (ICE/signaling negotiation)');
        _logCallTiming(call.id, 'CONNECTING');
        _startWebRtcStatsCollection();
        break;

      case CallStateEnum.STREAM:
        final audioTracks = state.stream?.getAudioTracks() ?? [];
        _diag(
          'WEBRTC_MEDIA',
          'Stream received: origin=${state.originator}, ${audioTracks.length} audio track(s), enabled=${audioTracks.map((track) => track.enabled).toList()}',
        );
        _logCallTiming(call.id, 'STREAM_ATTACH');
        if (state.originator?.toLowerCase() == 'remote' &&
            state.stream != null &&
            audioTracks.isNotEmpty) {
          _audioManager.attachRemoteStream(state.stream!, call.id);
        }
        break;

      case CallStateEnum.PROGRESS:
        _log(
          'TIMING',
          'Call is PROGRESS (180/183 Ringing), origin=${call.direction}',
        );
        _logCallTiming(call.id, 'PROGRESS');
        _audioManager.ensureDefaultAudioRoute(call.id);
        if (call.direction.toUpperCase() == 'OUTGOING') {
          _audioManager.playRingback();
          _navigateToInCall();
        }
        _startWebRtcStatsCollection();
        break;

      case CallStateEnum.ACCEPTED:
        _log('TIMING', '>>> Call ACCEPTED (200 OK received/sent)');
        _logCallTiming(call.id, 'ACCEPTED');
        _audioManager.ensureDefaultAudioRoute(call.id);
        _audioManager.stopAll();
        _startCallTimer();
        _startWebRtcStatsCollection();
        _navigateToInCall();
        break;

      case CallStateEnum.CONFIRMED:
        _log('TIMING', '>>> Call CONFIRMED (ACK received/dialog established)');
        _logCallTiming(call.id, 'CONFIRMED');
        _callCoordinator?.onCallConfirmed(call.id ?? '');
        _audioManager.ensureDefaultAudioRoute(call.id);
        _audioManager.stopAll(reason: 'call_confirmed');
        _startCallTimer();
        _startWebRtcStatsCollection();
        _navigateToInCall();
        break;

      case CallStateEnum.HOLD:
        _isOnHold = true;
        _logCallTiming(call.id, 'HOLD');
        break;

      case CallStateEnum.UNHOLD:
        _isOnHold = false;
        _logCallTiming(call.id, 'UNHOLD');
        break;

      case CallStateEnum.MUTED:
        _isMuted = true;
        break;

      case CallStateEnum.UNMUTED:
        _isMuted = false;
        break;

      case CallStateEnum.ENDED:
      case CallStateEnum.FAILED:
        _log(
          'TIMING',
          '>>> Call ${state.state} (origin=${call.direction}, cause=${state.cause})',
        );
        _logCallTiming(
          call.id,
          'CALL_TERMINATED',
          extra: 'state=${state.state}, cause=${state.cause}',
        );
        _isDialing = false;
        _pendingTargetNumber = null;
        _stopCallTimer();
        _stopWebRtcStatsCollection();
        _callDurationSeconds = 0;
        _currentCall = null;
        _callState = null;
        _navigateBackToDialpad();
        _audioManager.resetOnCallEnded(call.id);
        _callCoordinator?.onCallTerminated(call.id ?? '');
        break;

      default:
        break;
    }
    notifyListeners();
  }

  @override
  void transportStateChanged(TransportState state) {
    _log('TIMING', 'transportStateChanged: ${state.state}');
    if (_isReconfiguring) return;
    if (state.state == TransportStateEnum.CONNECTED) {
      // NOTE: Do NOT reset _reconnectAttempts here!
      // Transport connection is only the WebSocket layer; SIP registration may still fail.
      // Resetting _reconnectAttempts here breaks the max retry counter and causes infinite reconnection loops.
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _connectionStatus = SipConnectionStatus.registering;
      _statusMessage = 'Đang đăng ký SIP...';
    } else if (state.state == TransportStateEnum.DISCONNECTED) {
      _connectionStatus = SipConnectionStatus.offline;
      _statusMessage = 'Mất kết nối WSS (Đang thử kết nối lại...)';
      _scheduleReconnect();
    }
    notifyListeners();
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {
    _diag('SipManager', 'New SIP message received: ${msg.request.body}');
  }

  @override
  void onNewNotify(Notify ntf) {
    _diag('SipManager', 'New SIP notify received: ${ntf.request?.body}');
  }

  // ── Navigation Routing Helpers ───────────────────────────────────────────

  CallScreenState _callScreenState = CallScreenState.none;
  CallScreenState get callScreenState => _callScreenState;

  void _navigateToIncomingCall() {
    _log(
      'SipManager',
      'Attempting navigation to incoming call screen. Current state: $_callScreenState',
    );
    if (_callScreenState == CallScreenState.none) {
      _callScreenState = CallScreenState.incoming;
      final currentGen = ++_navigationGeneration;
      _logCallTiming(
        _currentCall?.id ?? 'incoming',
        'NAV_INCOMING_REQUESTED',
        extra: 'gen=$currentGen',
      );
      navigatorKey?.currentState?.pushNamed('/incoming').then((_) {
        _log(
          'SipManager',
          'Incoming call screen popped/closed (gen=$currentGen, current=$_navigationGeneration)',
        );
        if (_navigationGeneration == currentGen) {
          _callScreenState = CallScreenState.none;
        }
      });
    } else {
      _log(
        'SipManager',
        'Skip navigating to incoming screen: already in state $_callScreenState',
      );
    }
  }

  void _navigateToInCall() {
    _log(
      'SipManager',
      'Attempting navigation to in-call screen. Current state: $_callScreenState',
    );
    if (_callScreenState == CallScreenState.incoming) {
      _log('SipManager', 'Replacing incoming call screen with in-call screen');
      _callScreenState = CallScreenState.inCall;
      final currentGen = ++_navigationGeneration;
      _logCallTiming(
        _currentCall?.id ?? 'in_call',
        'NAV_IN_CALL_REPLACE',
        extra: 'gen=$currentGen',
      );
      navigatorKey?.currentState?.pushReplacementNamed('/in_call').then((_) {
        _log(
          'SipManager',
          'In-call screen popped/closed (gen=$currentGen, current=$_navigationGeneration)',
        );
        if (_navigationGeneration == currentGen) {
          _callScreenState = CallScreenState.none;
        }
      });
    } else if (_callScreenState == CallScreenState.none) {
      _log('SipManager', 'Pushing in-call screen (direct/outgoing)');
      _callScreenState = CallScreenState.inCall;
      final currentGen = ++_navigationGeneration;
      _logCallTiming(
        _currentCall?.id ?? 'in_call',
        'NAV_IN_CALL_DIRECT',
        extra: 'gen=$currentGen',
      );
      navigatorKey?.currentState?.pushNamed('/in_call').then((_) {
        _log(
          'SipManager',
          'In-call screen popped/closed (gen=$currentGen, current=$_navigationGeneration)',
        );
        if (_navigationGeneration == currentGen) {
          _callScreenState = CallScreenState.none;
        }
      });
    } else {
      _log(
        'SipManager',
        'Skip navigating to in-call screen: already in state $_callScreenState',
      );
    }
  }

  void _navigateBackToDialpad() {
    _log(
      'SipManager',
      'Navigating back to dialpad from state: $_callScreenState',
    );
    _navigationGeneration++;
    if (_callScreenState != CallScreenState.none) {
      _callScreenState = CallScreenState.none;
      try {
        navigatorKey?.currentState?.popUntil((route) => route.isFirst);
      } catch (e) {
        _log('SipManager', 'Navigate back error: $e');
      }
    }
  }

  // ── Testing Helpers ───────────────────────────────────────────────────────

  @visibleForTesting
  void setHelperForTesting(SIPUAHelper helper) {
    _helper = helper;
  }

  @visibleForTesting
  void setConnectionStatusForTesting(SipConnectionStatus status) {
    _connectionStatus = status;
  }

  @visibleForTesting
  void setAccountForTesting(SipAccount account) {
    _account = account;
  }

  @visibleForTesting
  void setCurrentCallForTesting(Call? call, CallState? state) {
    _currentCall = call;
    _callState = state;
  }

  @visibleForTesting
  void setIsDialingForTesting(bool dialing) {
    _isDialing = dialing;
  }

  @visibleForTesting
  void resetForTesting() {
    _currentCall = null;
    _callState = null;
    _isDialing = false;
    _pendingTargetNumber = null;
    _callScreenState = CallScreenState.none;
    _navigationGeneration = 0;
    _connectionStatus = SipConnectionStatus.offline;
    _statusMessage = 'Chưa kết nối';
    _reconnectAttempts = 0;
    _hasTerminalAuthError = false;
    _isRegistering = false;
    _isReconfiguring = false;
    _isDiagnosticUiActive = false;
    _callTimer?.cancel();
    _callTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _statsTimer?.cancel();
    _statsTimer = null;
    _audioManager.resetState();
    _callStopwatches.clear();
  }

  @visibleForTesting
  void setReconnectAttemptsForTesting(int attempts) {
    _reconnectAttempts = attempts;
  }

  @visibleForTesting
  int get reconnectAttemptsForTesting => _reconnectAttempts;

  @visibleForTesting
  bool get hasTerminalAuthErrorForTesting => _hasTerminalAuthError;

  @visibleForTesting
  void setHasTerminalAuthErrorForTesting(bool hasError) {
    _hasTerminalAuthError = hasError;
  }

  @visibleForTesting
  bool isTerminalRegistrationErrorForTesting(RegistrationState state) {
    return _isTerminalRegistrationError(state);
  }

  @visibleForTesting
  int get navigationGenerationForTesting => _navigationGeneration;

  @visibleForTesting
  void setNavigationGenerationForTesting(int gen) {
    _navigationGeneration = gen;
  }
}
