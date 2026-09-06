import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/sip_manager.dart';
import '../../data/models/sip_account.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _extController;
  late TextEditingController _passController;
  late TextEditingController _nameController;
  late TextEditingController _domainController;
  late TextEditingController _wssController;
  late TextEditingController _stunController;
  late TextEditingController _turnController;
  late TextEditingController _turnUserController;
  late TextEditingController _turnPassController;
  late TextEditingController _iceTimeoutController;

  bool _obscurePassword = true;
  bool _obscureTurnPass = true;
  bool _isSaving = false;
  bool _forceRelayOnly = false;
  bool _diagnosticLogging = false;

  @override
  void initState() {
    super.initState();
    final sip = context.read<SipManager>();
    final acc = sip.account ?? SipAccount.defaultAccount();

    _extController = TextEditingController(text: acc.extension);
    _passController = TextEditingController(text: acc.password);
    _nameController = TextEditingController(text: acc.displayName);
    _domainController = TextEditingController(text: acc.domain);
    _wssController = TextEditingController(text: acc.wssUri);
    _stunController = TextEditingController(text: acc.stunUri);
    _turnController = TextEditingController(text: acc.turnUri);
    _turnUserController = TextEditingController(text: acc.turnUsername);
    _turnPassController = TextEditingController(text: acc.turnPassword);
    _iceTimeoutController = TextEditingController(
      text: acc.iceGatheringTimeoutMs.toString(),
    );
    _forceRelayOnly = acc.forceRelayOnly;
    _diagnosticLogging = acc.diagnosticLogging;
  }

  @override
  void dispose() {
    _extController.dispose();
    _passController.dispose();
    _nameController.dispose();
    _domainController.dispose();
    _wssController.dispose();
    _stunController.dispose();
    _turnController.dispose();
    _turnUserController.dispose();
    _turnPassController.dispose();
    _iceTimeoutController.dispose();
    super.dispose();
  }

  Future<void> _saveAndRegister(SipManager sip) async {
    if (_isSaving) return;
    if (_formKey.currentState!.validate()) {
      setState(() => _isSaving = true);
      try {
        final updatedAccount = SipAccount(
          extension: _extController.text.trim(),
          password: _passController.text.trim(),
          displayName: _nameController.text.trim(),
          domain: _domainController.text.trim(),
          wssUri: _wssController.text.trim(),
          stunUri: _stunController.text.trim(),
          turnUri: _turnController.text.trim(),
          turnUsername: _turnUserController.text.trim(),
          turnPassword: _turnPassController.text.trim(),
          iceGatheringTimeoutMs: int.parse(_iceTimeoutController.text.trim()),
          forceRelayOnly: _forceRelayOnly,
          diagnosticLogging: _diagnosticLogging,
        );

        await sip.register(newAccount: updatedAccount);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đã lưu cấu hình và gửi yêu cầu đăng ký SIP!'),
              backgroundColor: AppConstants.accentGreen,
            ),
          );
          Navigator.pop(context);
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Không thể lưu/đăng ký SIP: $error'),
              backgroundColor: AppConstants.accentRed,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isSaving = false);
        }
      }
    }
  }

  void _resetDefaults() {
    final def = SipAccount.defaultAccount();
    setState(() {
      _extController.text = def.extension;
      _passController.text = def.password;
      _nameController.text = def.displayName;
      _domainController.text = def.domain;
      _wssController.text = def.wssUri;
      _stunController.text = def.stunUri;
      _turnController.text = def.turnUri;
      _turnUserController.text = def.turnUsername;
      _turnPassController.text = def.turnPassword;
      _iceTimeoutController.text = def.iceGatheringTimeoutMs.toString();
      _forceRelayOnly = def.forceRelayOnly;
      _diagnosticLogging = def.diagnosticLogging;
    });
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
          'Cài Đặt Tổng Đài SIP',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.restore, color: Colors.white70),
            tooltip: 'Khôi phục mặc định',
            onPressed: _resetDefaults,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('Thông tin Tài khoản SIP (PJSIP)'),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _extController,
                label: 'SIP Extension / Username',
                hint: '202',
                icon: Icons.tag,
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (value.isEmpty) return 'Vui lòng nhập Extension';
                  if (!RegExp(r'^[A-Za-z0-9_.+\-]+$').hasMatch(value)) {
                    return 'Extension chứa ký tự không hợp lệ';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _passController,
                label: 'SIP Password',
                hint: 'Nhập SIP credential đã được cấp',
                icon: Icons.lock_outline,
                isPassword: true,
                obscure: _obscurePassword,
                onToggleObscure: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                validator: (v) =>
                    v!.isEmpty ? 'Vui lòng nhập Mật khẩu SIP' : null,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _nameController,
                label: 'Tên hiển thị (Caller ID)',
                hint: 'Nhân viên 202',
                icon: Icons.person_outline,
              ),
              const SizedBox(height: 24),

              _buildSectionTitle('Máy chủ Asterisk & WebSocket WSS'),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _domainController,
                label: 'SIP Domain / Realm',
                hint: 'sgtvoip.duckdns.org',
                icon: Icons.domain,
                validator: (v) => v!.isEmpty ? 'Vui lòng nhập Domain' : null,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _wssController,
                label: 'WebSocket Secure URI (WSS)',
                hint: 'wss://pbx.example.invalid/ws',
                icon: Icons.cloud_outlined,
                // Release builds require WSS; ws:// is only accepted by Android
                // debug network policy for local lab testing.
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (value.isEmpty) return 'Vui lòng nhập WSS URI';
                  final uri = Uri.tryParse(value);
                  if (uri == null ||
                      !uri.hasAuthority ||
                      (uri.scheme != 'wss' && uri.scheme != 'ws')) {
                    return 'URI phải có dạng wss://host/ws';
                  }
                  if (kReleaseMode && uri.scheme != 'wss') {
                    return 'Bản release chỉ cho phép WSS';
                  }
                  if (uri.path != '/ws') {
                    return 'WSS URI phải kết thúc chính xác bằng /ws';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              _buildSectionTitle('Cấu hình Xuyên NAT 4G/5G (STUN / TURN)'),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _stunController,
                label: 'STUN Server URI',
                hint: 'stun:stun.l.google.com:19302',
                icon: Icons.alt_route,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _turnController,
                label: 'TURN URI (phân cách bằng dấu phẩy)',
                hint:
                    'turn:turn.example.invalid:3478?transport=udp, turns:turn.example.invalid:5349',
                icon: Icons.swap_calls,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _turnUserController,
                label: 'TURN Username',
                hint: 'turn-user',
                icon: Icons.account_circle_outlined,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _turnPassController,
                label: 'TURN Password',
                hint: 'Nhập credential đã cấp, không dùng mật khẩu mẫu',
                icon: Icons.key_outlined,
                isPassword: true,
                obscure: _obscureTurnPass,
                onToggleObscure: () =>
                    setState(() => _obscureTurnPass = !_obscureTurnPass),
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _iceTimeoutController,
                label: 'ICE gathering timeout (ms)',
                hint: '8000',
                icon: Icons.timer_outlined,
                validator: (v) {
                  final timeout = int.tryParse(v?.trim() ?? '');
                  if (timeout == null || timeout < 1000 || timeout > 30000) {
                    return 'Nhập giá trị từ 1000 đến 30000 ms';
                  }
                  return null;
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Chỉ dùng TURN relay (chẩn đoán)',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Bật để xác minh TURN. Cuộc gọi sẽ thất bại nếu TURN chưa hoạt động.',
                  style: TextStyle(color: AppConstants.textMuted, fontSize: 12),
                ),
                value: _forceRelayOnly,
                activeColor: AppConstants.accentAmber,
                onChanged: (value) => setState(() => _forceRelayOnly = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Ghi log WebRTC chi tiết',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Chỉ bật tạm thời khi chẩn đoán; log có thể chứa IP và số gọi.',
                  style: TextStyle(color: AppConstants.textMuted, fontSize: 12),
                ),
                value: _diagnosticLogging,
                activeColor: AppConstants.accentAmber,
                onChanged: (value) =>
                    setState(() => _diagnosticLogging = value),
              ),
              const SizedBox(height: 32),

              // Save & Re-register button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.accentBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle, color: Colors.white),
                  label: Text(
                    _isSaving
                        ? 'Đang lưu & đăng ký...'
                        : 'Lưu & Đăng Ký Lại SIP',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: _isSaving ? null : () => _saveAndRegister(sip),
                ),
              ),

              const SizedBox(height: 14),

              // Unregister button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppConstants.accentRed),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(
                    Icons.power_settings_new,
                    color: AppConstants.accentRed,
                  ),
                  label: const Text(
                    'Ngắt Kết Nối Tổng Đài',
                    style: TextStyle(
                      color: AppConstants.accentRed,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: () {
                    sip.unregister();
                    Navigator.pop(context);
                  },
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: AppConstants.accentBlue,
        fontSize: 14,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    bool obscure = false,
    VoidCallback? onToggleObscure,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppConstants.surfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: TextFormField(
        controller: controller,
        obscureText: isPassword && obscure,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            color: AppConstants.textMuted,
            fontSize: 13,
          ),
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white24),
          prefixIcon: Icon(icon, color: Colors.white54, size: 20),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    obscure ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white54,
                    size: 20,
                  ),
                  onPressed: onToggleObscure,
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        validator: validator,
      ),
    );
  }
}
