import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/sip_manager.dart';
import '../widgets/status_indicator.dart';

class DialpadScreen extends StatefulWidget {
  const DialpadScreen({Key? key}) : super(key: key);

  @override
  State<DialpadScreen> createState() => _DialpadScreenState();
}

class _DialpadScreenState extends State<DialpadScreen> {
  final TextEditingController _numberController = TextEditingController();

  static const List<Map<String, String>> _keys = [
    {'main': '1', 'sub': '.'},
    {'main': '2', 'sub': 'ABC'},
    {'main': '3', 'sub': 'DEF'},
    {'main': '4', 'sub': 'GHI'},
    {'main': '5', 'sub': 'JKL'},
    {'main': '6', 'sub': 'MNO'},
    {'main': '7', 'sub': 'PQRS'},
    {'main': '8', 'sub': 'TUV'},
    {'main': '9', 'sub': 'WXYZ'},
    {'main': '*', 'sub': '+'},
    {'main': '0', 'sub': '+'},
    {'main': '#', 'sub': ''},
  ];

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  void _onKeyPress(String key) {
    HapticFeedback.lightImpact();
    setState(() {
      _numberController.text += key;
    });
  }

  void _onBackspace() {
    HapticFeedback.selectionClick();
    final text = _numberController.text;
    if (text.isNotEmpty) {
      setState(() {
        _numberController.text = text.substring(0, text.length - 1);
      });
    }
  }

  void _onClear() {
    HapticFeedback.mediumImpact();
    setState(() {
      _numberController.clear();
    });
  }

  void _makeCall(SipManager sip) {
    final number = _numberController.text.trim();
    if (number.isNotEmpty) {
      HapticFeedback.heavyImpact();
      sip.makeCall(number);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập số điện thoại hoặc số máy nhánh!'),
          backgroundColor: AppConstants.accentAmber,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sip = context.watch<SipManager>();

    return Scaffold(
      backgroundColor: AppConstants.primaryDark,
      appBar: AppBar(
        backgroundColor: AppConstants.primaryDark,
        elevation: 0,
        title: const Text(
          'SGT Softphone',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10.0),
            child: StatusIndicator(
              status: sip.connectionStatus,
              statusText: sip.statusMessage,
              onTap: () {
                sip.register();
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white70),
            onPressed: () {
              Navigator.pushNamed(context, '/settings');
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 8),

                          // Number Input Display Area
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppConstants.surfaceDark,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _numberController,
                                    readOnly: true,
                                    showCursor: true,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 2,
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: 'Nhập số máy...',
                                      hintStyle: TextStyle(
                                        color: Colors.white24,
                                        fontSize: 20,
                                        letterSpacing: 0,
                                      ),
                                      border: InputBorder.none,
                                    ),
                                  ),
                                ),
                                if (_numberController.text.isNotEmpty)
                                  GestureDetector(
                                    onTap: _onBackspace,
                                    onLongPress: _onClear,
                                    child: const Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: Icon(
                                        Icons.backspace_outlined,
                                        color: AppConstants.textMuted,
                                        size: 24,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Quick Extension Tag Shortcuts
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _buildQuickTag('Odoo CSKH (1001)', '1001'),
                              _buildQuickTag('Mobile 1 (1002)', '1002'),
                              _buildQuickTag('Leader (1003)', '1003'),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // 3x4 Keypad Grid (Standard Rows without viewport overhead)
                          _buildKeypadGrid(),

                          const SizedBox(height: 20),

                          // Call Action Button
                          Center(
                            child: GestureDetector(
                              onTap: () => _makeCall(sip),
                              child: Container(
                                width: 68,
                                height: 68,
                                decoration: BoxDecoration(
                                  color: sip.connectionStatus == SipConnectionStatus.online
                                      ? AppConstants.accentGreen
                                      : Colors.grey.shade700,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    if (sip.connectionStatus == SipConnectionStatus.online)
                                      BoxShadow(
                                        color: AppConstants.accentGreen.withOpacity(0.4),
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

                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildKeypadGrid() {
    return Column(
      children: [
        _buildKeyRow(['1', '2', '3']),
        const SizedBox(height: 12),
        _buildKeyRow(['4', '5', '6']),
        const SizedBox(height: 12),
        _buildKeyRow(['7', '8', '9']),
        const SizedBox(height: 12),
        _buildKeyRow(['*', '0', '#']),
      ],
    );
  }

  Widget _buildKeyRow(List<String> keys) {
    return Row(
      children: keys.map((key) {
        final keyData = _keys.firstWhere((k) => k['main'] == key);
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6.0),
            child: AspectRatio(
              aspectRatio: 1.45,
              child: _buildKeyButton(keyData['main']!, keyData['sub']!),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildKeyButton(String mainText, String subText) {
    return InkWell(
      onTap: () => _onKeyPress(mainText),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppConstants.cardDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    mainText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (subText.isNotEmpty)
                    Text(
                      subText,
                      style: const TextStyle(
                        color: AppConstants.textMuted,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickTag(String label, String ext) {
    return ActionChip(
      backgroundColor: AppConstants.cardDark,
      label: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      onPressed: () {
        setState(() {
          _numberController.text = ext;
        });
      },
    );
  }
}
