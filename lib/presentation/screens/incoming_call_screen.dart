import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sip_ua/sip_ua.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/sip_manager.dart';

class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen({Key? key}) : super(key: key);

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  bool _isPopping = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkCallActive();
    });
  }

  void _checkCallActive() {
    if (!mounted || _isPopping) return;
    final sip = context.read<SipManager>();
    if (sip.currentCall == null ||
        sip.callState?.state == CallStateEnum.ENDED ||
        sip.callState?.state == CallStateEnum.FAILED) {
      _popBack();
    }
  }

  void _popBack() {
    if (_isPopping || !mounted) return;
    _isPopping = true;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sip = context.watch<SipManager>();
    final call = sip.currentCall;
    final state = sip.callState?.state;

    // Auto-exit nếu cuộc gọi đã kết thúc
    if (call == null ||
        state == CallStateEnum.ENDED ||
        state == CallStateEnum.FAILED) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _popBack();
      });
    }

    final callerId = call?.remote_identity ?? 'Khách hàng';

    return WillPopScope(
      onWillPop: () async {
        sip.hangupCall();
        _popBack();
        return false;
      },
      child: Scaffold(
        backgroundColor: AppConstants.primaryDark,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: IntrinsicHeight(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
                          child: Column(
                            children: [
                              const SizedBox(height: 20),

                              const Text(
                                'CUỘC GỌI ĐẾN...',
                                style: TextStyle(
                                  color: AppConstants.accentGreen,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                ),
                              ),

                              const Spacer(flex: 1),

                              // Pulsing Avatar Ring Animation
                              AnimatedBuilder(
                                animation: _animController,
                                builder: (context, child) {
                                  return Container(
                                    padding: EdgeInsets.all(18.0 * _animController.value),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppConstants.accentGreen.withOpacity(0.15 * _animController.value),
                                    ),
                                    child: Container(
                                      width: 120,
                                      height: 120,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: AppConstants.cardDark,
                                        border: Border.all(color: AppConstants.accentGreen, width: 2),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppConstants.accentGreen.withOpacity(0.3),
                                            blurRadius: 20,
                                            spreadRadius: 6,
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.phone_in_talk,
                                        size: 56,
                                        color: AppConstants.accentGreen,
                                      ),
                                    ),
                                  );
                                },
                              ),

                              const SizedBox(height: 20),

                              // Caller Display Name & Number
                              Text(
                                callerId,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Tổng đài Asterisk 20 (WSS / WebRTC)',
                                style: TextStyle(
                                  color: AppConstants.textMuted,
                                  fontSize: 13,
                                ),
                              ),

                              const Spacer(flex: 2),

                              // Accept (Green) and Decline (Red) Action Buttons
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    // Decline Button
                                    Column(
                                      children: [
                                        GestureDetector(
                                          onTap: () {
                                            sip.hangupCall();
                                            _popBack();
                                          },
                                          child: Container(
                                            width: 68,
                                            height: 68,
                                            decoration: BoxDecoration(
                                              color: AppConstants.accentRed,
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: AppConstants.accentRed.withOpacity(0.4),
                                                  blurRadius: 16,
                                                  spreadRadius: 4,
                                                ),
                                              ],
                                            ),
                                            child: const Icon(Icons.call_end, color: Colors.white, size: 32),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        const Text(
                                          'Từ chối',
                                          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13),
                                        ),
                                      ],
                                    ),

                                    // Accept Button
                                    Column(
                                      children: [
                                        GestureDetector(
                                          onTap: () => sip.answerCall(),
                                          child: Container(
                                            width: 68,
                                            height: 68,
                                            decoration: BoxDecoration(
                                              color: AppConstants.accentGreen,
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: AppConstants.accentGreen.withOpacity(0.4),
                                                  blurRadius: 16,
                                                  spreadRadius: 4,
                                                ),
                                              ],
                                            ),
                                            child: const Icon(Icons.phone, color: Colors.white, size: 32),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        const Text(
                                          'Trả lời',
                                          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              const Spacer(flex: 1),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
