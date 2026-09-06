import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sip_ua/sip_ua.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/sip_manager.dart';

class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen({super.key});

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with SingleTickerProviderStateMixin {
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
      if (!mounted) return;
      context.read<SipManager>().logIncomingFirstFrame();
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
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
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

    final callerId = call?.remote_identity ?? 'Cuộc gọi đến';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        sip.hangupCall();
        _popBack();
      },
      child: Scaffold(
        backgroundColor: AppConstants.backgroundLight,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20.0,
                            vertical: 20.0,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(height: 16),

                                  const Text(
                                    'CUỘC GỌI ĐẾN',
                                    style: TextStyle(
                                      color: AppConstants.accentGreen,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 2,
                                    ),
                                  ),

                                  const SizedBox(height: 24),

                                  // Pulsing Avatar Ring Animation
                                  AnimatedBuilder(
                                    animation: _animController,
                                    builder: (context, child) {
                                      return Container(
                                        padding: EdgeInsets.all(
                                          18.0 * _animController.value,
                                        ),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: AppConstants.accentGreen
                                              .withValues(
                                                alpha:
                                                    0.15 *
                                                    _animController.value,
                                              ),
                                        ),
                                        child: Container(
                                          width: 120,
                                          height: 120,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: AppConstants.surfaceLight,
                                            border: Border.all(
                                              color: AppConstants.accentGreen,
                                              width: 2.5,
                                            ),
                                            boxShadow: const [
                                              BoxShadow(
                                                color: Color(0x3321A366),
                                                blurRadius: 24,
                                                spreadRadius: 6,
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.phone_in_talk,
                                            size: 54,
                                            color: AppConstants.accentGreen,
                                          ),
                                        ),
                                      );
                                    },
                                  ),

                                  const SizedBox(height: 20),

                                  // Caller Display Name & Number
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12.0,
                                    ),
                                    child: Text(
                                      callerId,
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      softWrap: true,
                                      style: const TextStyle(
                                        color: AppConstants.textPrimary,
                                        fontSize: 26,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Đang đổ chuông…',
                                    style: TextStyle(
                                      color: AppConstants.textSecondary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 24),

                              // Accept (Green) and Decline (Red) Action Buttons
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0,
                                ),
                                child: Row(
                                  children: [
                                    // Decline Button
                                    Expanded(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Semantics(
                                            button: true,
                                            label: 'Từ chối cuộc gọi',
                                            child: Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                onTap: () {
                                                  sip.hangupCall();
                                                  _popBack();
                                                },
                                                borderRadius:
                                                    BorderRadius.circular(34),
                                                child: Container(
                                                  width: 68,
                                                  height: 68,
                                                  decoration:
                                                      const BoxDecoration(
                                                        color: AppConstants
                                                            .accentRed,
                                                        shape: BoxShape.circle,
                                                        boxShadow: [
                                                          BoxShadow(
                                                            color: Color(
                                                              0x4DE5484D,
                                                            ),
                                                            blurRadius: 16,
                                                            spreadRadius: 4,
                                                          ),
                                                        ],
                                                      ),
                                                  child: const Icon(
                                                    Icons.call_end,
                                                    color: Colors.white,
                                                    size: 32,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          const FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              'Từ chối',
                                              style: TextStyle(
                                                color: AppConstants.textPrimary,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Accept Button
                                    Expanded(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Semantics(
                                            button: true,
                                            label: 'Trả lời cuộc gọi',
                                            child: Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                onTap: () => sip.answerCall(),
                                                borderRadius:
                                                    BorderRadius.circular(34),
                                                child: Container(
                                                  width: 68,
                                                  height: 68,
                                                  decoration:
                                                      const BoxDecoration(
                                                        color: AppConstants
                                                            .accentGreen,
                                                        shape: BoxShape.circle,
                                                        boxShadow: [
                                                          BoxShadow(
                                                            color: Color(
                                                              0x4D21A366,
                                                            ),
                                                            blurRadius: 16,
                                                            spreadRadius: 4,
                                                          ),
                                                        ],
                                                      ),
                                                  child: const Icon(
                                                    Icons.phone,
                                                    color: Colors.white,
                                                    size: 32,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          const FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              'Trả lời',
                                              style: TextStyle(
                                                color: AppConstants.textPrimary,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 16),
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
