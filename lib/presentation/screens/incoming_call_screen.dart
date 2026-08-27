import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/sip_manager.dart';

class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen({Key? key}) : super(key: key);

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
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
    final callerId = call?.remote_identity ?? 'Khách hàng';

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: AppConstants.primaryDark,
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 50),

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
                    padding: EdgeInsets.all(20.0 * _animController.value),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppConstants.accentGreen.withOpacity(0.15 * _animController.value),
                    ),
                    child: Container(
                      width: 130,
                      height: 130,
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
                        size: 60,
                        color: AppConstants.accentGreen,
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 24),

              // Caller Display Name & Number
              Text(
                callerId,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tổng đài Asterisk 20 (WSS / WebRTC)',
                style: TextStyle(
                  color: AppConstants.textMuted,
                  fontSize: 14,
                ),
              ),

              const Spacer(flex: 2),

              // Accept (Green) and Decline (Red) Action Buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Decline Button
                    Column(
                      children: [
                        GestureDetector(
                          onTap: () => sip.hangupCall(),
                          child: Container(
                            width: 72,
                            height: 72,
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
                            child: const Icon(Icons.call_end, color: Colors.white, size: 34),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Từ chối',
                          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),

                    // Accept Button
                    Column(
                      children: [
                        GestureDetector(
                          onTap: () => sip.answerCall(),
                          child: Container(
                            width: 72,
                            height: 72,
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
                            child: const Icon(Icons.phone, color: Colors.white, size: 34),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Trả lời',
                          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
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
    );
  }
}
