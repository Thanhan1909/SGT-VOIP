import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/sip_manager.dart';
import '../../data/models/sip_account.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

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
      backgroundColor: AppConstants.backgroundLight,
      appBar: AppBar(
        backgroundColor: AppConstants.surfaceLight,
        elevation: 0,
        title: const Text(
          'Cài Đặt Tổng Đài SIP',
          style: TextStyle(
            color: AppConstants.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        iconTheme: const IconThemeData(color: AppConstants.textPrimary),
        actions: [
          IconButton(
            icon: const Icon(Icons.restore, color: AppConstants.textSecondary),
            tooltip: 'Khôi phục mặc định',
            onPressed: _resetDefaults,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thông tin máy nhánh
              _buildSectionTitle('THÔNG TIN MÁY NHÁNH'),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _extController,
                label: 'Số máy nhánh (Extension)',
                hint: '201',
                icon: Icons.tag,
                validator: (v) => v!.trim().isEmpty ? 'Nhập extension' : null,
              ),
              const SizedBox(height: 10),
              _buildTextField(
                controller: _passController,
                label: 'Mật khẩu SIP (Password)',
                hint: '••••••••',
                icon: Icons.lock_outline,
                isPassword: true,
                obscure: _obscurePassword,
                onToggleObscure: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                validator: (v) => v!.trim().isEmpty ? 'Nhập password' : null,
              ),
              const SizedBox(height: 10),
              _buildTextField(
                controller: _nameController,
                label: 'Tên hiển thị (Display Name)',
                hint: 'CSKH 201',
                icon: Icons.person_outline,
              ),

              const SizedBox(height: 24),

              // Cấu hình kết nối SIP & WSS
              _buildSectionTitle('KẾT NỐI TỔNG ĐÀI'),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _domainController,
                label: 'SIP Domain / IP',
                hint: 'sgt.vn',
                icon: Icons.domain,
                validator: (v) => v!.trim().isEmpty ? 'Nhập domain' : null,
              ),
              const SizedBox(height: 10),
              _buildTextField(
                controller: _wssController,
                label: 'WSS WebSocket URL',
                hint: 'wss://pbx.sgt.vn:8089/ws',
                icon: Icons.alt_route,
                validator: (v) {
                  if (v!.trim().isEmpty) return 'Nhập WSS URI';
                  if (!v.startsWith('ws://') && !v.startsWith('wss://')) {
                    return 'URI phải bắt đầu bằng ws:// hoặc wss://';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // Chẩn đoán kỹ thuật viên (Collapsible section, default collapsed)
              Container(
                decoration: BoxDecoration(
                  color: AppConstants.surfaceLight,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppConstants.borderLight),
                ),
                child: Theme(
                  data: Theme.of(
                    context,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    title: const Text(
                      'Chẩn đoán dành cho kỹ thuật viên',
                      style: TextStyle(
                        color: AppConstants.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: const Text(
                      'NAT, STUN/TURN, ICE Timeout và Thông số RTP',
                      style: TextStyle(
                        color: AppConstants.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    leading: const Icon(
                      Icons.build_circle_outlined,
                      color: AppConstants.accentAmber,
                    ),
                    onExpansionChanged: (isExpanded) {
                      sip.setDiagnosticUiActive(isExpanded);
                    },
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8.0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (sip.mediaState != 'idle') ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppConstants.backgroundLight,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppConstants.borderLight,
                                  ),
                                ),
                                child: Text(
                                  'Trạng thái: Media: ${sip.mediaState} | ICE: ${sip.iceState} | DTLS: ${sip.dtlsState}\n'
                                  'RTP Gửi/Nhận: ${sip.packetsSent} / ${sip.packetsReceived} | Codec: ${sip.negotiatedCodec}\n'
                                  'Candidate Pair: ${sip.selectedCandidatePair}',
                                  style: const TextStyle(
                                    color: AppConstants.textPrimary,
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            _buildTextField(
                              controller: _stunController,
                              label: 'STUN Server',
                              hint: 'stun:stun.l.google.com:19302',
                              icon: Icons.cloud_outlined,
                            ),
                            const SizedBox(height: 10),
                            _buildTextField(
                              controller: _turnController,
                              label: 'TURN Server',
                              hint: 'turn:turn.domain.com:3478',
                              icon: Icons.swap_calls_outlined,
                            ),
                            const SizedBox(height: 10),
                            _buildTextField(
                              controller: _turnUserController,
                              label: 'TURN Username',
                              hint: 'user',
                              icon: Icons.badge_outlined,
                            ),
                            const SizedBox(height: 10),
                            _buildTextField(
                              controller: _turnPassController,
                              label: 'TURN Password',
                              hint: '••••••••',
                              icon: Icons.key_outlined,
                              isPassword: true,
                              obscure: _obscureTurnPass,
                              onToggleObscure: () => setState(
                                () => _obscureTurnPass = !_obscureTurnPass,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _buildTextField(
                              controller: _iceTimeoutController,
                              label: 'ICE gathering timeout (ms)',
                              hint: '1000',
                              icon: Icons.timer_outlined,
                              validator: (v) {
                                final timeout = int.tryParse(v?.trim() ?? '');
                                if (timeout == null ||
                                    timeout < 500 ||
                                    timeout > 30000) {
                                  return 'Nhập giá trị từ 500 đến 30000 ms';
                                }
                                return null;
                              },
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'Chỉ dùng TURN relay (chẩn đoán)',
                                style: TextStyle(
                                  color: AppConstants.textPrimary,
                                ),
                              ),
                              subtitle: const Text(
                                'Bật để xác minh TURN. Cuộc gọi sẽ thất bại nếu TURN chưa hoạt động.',
                                style: TextStyle(
                                  color: AppConstants.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                              value: _forceRelayOnly,
                              activeThumbColor: AppConstants.accentAmber,
                              onChanged: (value) =>
                                  setState(() => _forceRelayOnly = value),
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'Ghi log WebRTC chi tiết',
                                style: TextStyle(
                                  color: AppConstants.textPrimary,
                                ),
                              ),
                              subtitle: const Text(
                                'Chỉ bật tạm thời khi chẩn đoán; log có thể chứa IP và số gọi.',
                                style: TextStyle(
                                  color: AppConstants.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                              value: _diagnosticLogging,
                              activeThumbColor: AppConstants.accentAmber,
                              onChanged: (value) =>
                                  setState(() => _diagnosticLogging = value),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Save & Re-register button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.accentGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 1,
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
                    side: const BorderSide(
                      color: AppConstants.accentRed,
                      width: 1.5,
                    ),
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
        color: AppConstants.textPrimary,
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
        color: AppConstants.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppConstants.borderLight),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        obscureText: isPassword && obscure,
        style: const TextStyle(color: AppConstants.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            color: AppConstants.textSecondary,
            fontSize: 13,
          ),
          hintText: hint,
          hintStyle: const TextStyle(color: AppConstants.textMuted),
          prefixIcon: Icon(icon, color: AppConstants.textSecondary, size: 20),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    obscure ? Icons.visibility_off : Icons.visibility,
                    color: AppConstants.textSecondary,
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
