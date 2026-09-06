import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/odoo_auth_service.dart';
import '../../core/services/sip_manager.dart';

class CallLandingScreen extends StatefulWidget {
  final String callUuid;

  const CallLandingScreen({super.key, required this.callUuid});

  @override
  State<CallLandingScreen> createState() => _CallLandingScreenState();
}

class _CallLandingScreenState extends State<CallLandingScreen> {
  bool _isLoading = true;
  String _status =
      'checking'; // 'checking', 'ringing', 'expired', 'cancelled', 'error', 'login_required'
  String _message = 'Đang kiểm tra trạng thái cuộc gọi...';
  Map<String, dynamic>? _callData;

  @override
  void initState() {
    super.initState();
    _processIncomingCall();
  }

  Future<void> _processIncomingCall() async {
    setState(() {
      _isLoading = true;
      _status = 'checking';
      _message = 'Đang kiểm tra phiên đăng nhập Odoo...';
    });

    final authService = OdooAuthService.instance;
    final hasSession = await authService.checkSession();
    if (!hasSession) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _status = 'login_required';
        _message = 'Vui lòng đăng nhập Odoo để nhận cuộc gọi.';
      });
      return;
    }

    setState(() {
      _message = 'Đang xác thực trạng thái cuộc gọi từ tổng đài...';
    });

    // Query call state from server
    final call = await authService.getCallState(widget.callUuid);
    if (!mounted) return;

    if (call == null) {
      setState(() {
        _isLoading = false;
        _status = 'error';
        _message = 'Không tìm thấy thông tin cuộc gọi hoặc máy chủ bận.';
      });
      return;
    }

    _callData = call;
    final callStatus = call['status']?.toString() ?? 'unknown';
    final isRinging = call['is_ringing'] == true || callStatus == 'ringing';
    final isExpired = call['is_expired'] == true || callStatus == 'expired';

    if (isExpired ||
        callStatus == 'cancelled' ||
        callStatus == 'answered' ||
        callStatus == 'failed') {
      setState(() {
        _isLoading = false;
        _status = isExpired ? 'expired' : callStatus;
        _message = isExpired
            ? 'Cuộc gọi đã quá hạn nhận (45 giây) và được ghi nhận là cuộc gọi nhỡ.'
            : (callStatus == 'cancelled'
                  ? 'Người gọi đã hủy cuộc gọi.'
                  : 'Cuộc gọi đã kết thúc hoặc được trả lời trên thiết bị khác.');
      });
      return;
    }

    if (isRinging) {
      // Call is currently ringing! Fetch in-memory SIP config and connect
      setState(() {
        _status = 'ringing';
        _message = 'Đang kết nối WebSocket tổng đài để nhận cuộc gọi...';
      });

      final sipConfig = await authService.fetchSipConfig();
      if (!mounted) return;

      if (sipConfig == null || sipConfig.password.isEmpty) {
        setState(() {
          _isLoading = false;
          _status = 'error';
          _message = 'Không thể tải cấu hình SIP của bạn từ Odoo.';
        });
        return;
      }

      // Reconnect and register via SipManager
      final sipManager = Provider.of<SipManager>(context, listen: false);
      try {
        await sipManager.connectWithAccount(sipConfig);
        setState(() {
          _isLoading = false;
          _message =
              'Cuộc gọi đang đổ chuông từ ${call['caller_display_name'] ?? call['caller_extension']}...';
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _status = 'error';
          _message = 'Lỗi kết nối tổng đài SIP: $e';
        });
      }
    } else {
      setState(() {
        _isLoading = false;
        _status = 'ended';
        _message = 'Cuộc gọi không còn khả dụng.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.backgroundLight,
      appBar: AppBar(
        title: const Text('Cuộc gọi đến'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pushReplacementNamed('/'),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isLoading) ...[
                const CircularProgressIndicator(
                  color: AppConstants.accentGreen,
                ),
                const SizedBox(height: 24),
                Text(
                  _message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppConstants.textPrimary,
                  ),
                ),
              ] else if (_status == 'ringing') ...[
                Container(
                  width: 100,
                  height: 100,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppConstants.accentGreen,
                  ),
                  child: const Icon(
                    Icons.phone_in_talk,
                    size: 50,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  _callData?['caller_display_name']?.toString() ??
                      'Cuộc gọi đến',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Số máy nhánh: ${_callData?['caller_extension'] ?? ""}',
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppConstants.textSecondary,
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  icon: const Icon(Icons.call, color: Colors.white),
                  label: const Text(
                    'Vào màn hình cuộc gọi',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.accentGreen,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(context).pushReplacementNamed('/incoming');
                  },
                ),
              ] else ...[
                Icon(
                  _status == 'expired' || _status == 'cancelled'
                      ? Icons.phone_missed
                      : Icons.info_outline,
                  size: 72,
                  color: _status == 'expired'
                      ? AppConstants.accentRed
                      : Colors.grey,
                ),
                const SizedBox(height: 20),
                Text(
                  _status == 'expired'
                      ? 'Cuộc gọi nhỡ'
                      : (_status == 'cancelled'
                            ? 'Cuộc gọi đã hủy'
                            : 'Thông báo cuộc gọi'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppConstants.textSecondary,
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () =>
                      Navigator.of(context).pushReplacementNamed('/'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.accentGreen,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 12,
                    ),
                  ),
                  child: const Text(
                    'Về màn hình chính',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
