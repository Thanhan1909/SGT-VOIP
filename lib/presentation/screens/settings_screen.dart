import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/odoo_auth_service.dart';
import '../../core/services/sip_manager.dart';
import '../../core/services/web_push/web_push_manager.dart';
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
  bool _isSyncingOdoo = false;
  bool _isPushLoading = false;
  bool _isPushSubscribed = false;

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

    if (kIsWeb && WebPushManager.isSupported) {
      WebPushManager.getSubscription().then((sub) {
        if (mounted && sub != null) {
          setState(() => _isPushSubscribed = true);
        }
      });
    }
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

        await sip.connectWithAccount(updatedAccount);

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
              // Odoo & PWA Web Push Section
              _buildOdooAndWebPushSection(context, sip),
              const SizedBox(height: 20),

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
              if (kIsWeb)
                const Padding(
                  padding: EdgeInsets.only(top: 8.0),
                  child: Text(
                    '🔒 Bảo mật: Trên Web, mật khẩu SIP & TURN chỉ lưu trong bộ nhớ RAM của phiên làm việc, không lưu vào bộ nhớ máy.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppConstants.accentGreen,
                    ),
                  ),
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
                hint: 'wss://sgtvoip.duckdns.org/ws',
                icon: Icons.alt_route,
                validator: (v) {
                  if (v!.trim().isEmpty) return 'Nhập WSS URI';
                  if (!SipAccount.isValidWssUri(v)) {
                    return 'WSS URI phải có dạng wss://host/ws';
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

  Widget _buildOdooAndWebPushSection(BuildContext context, SipManager sip) {
    final odoo = OdooAuthService();
    const isWeb = kIsWeb;
    final isStandalone = isWeb && WebPushManager.isStandalone;

    return Container(
      decoration: BoxDecoration(
        color: AppConstants.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppConstants.accentBlue.withOpacity(0.3)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppConstants.accentBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.cloud_sync,
                  color: AppConstants.accentBlue,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tự Động Đồng Bộ Odoo',
                      style: TextStyle(
                        color: AppConstants.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      odoo.isAuthenticated
                          ? 'Đã liên kết Odoo (UID: ${odoo.userInfo?['uid']})'
                          : 'Đồng bộ extension, mật khẩu & TURN từ Odoo',
                      style: const TextStyle(
                        color: AppConstants.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.accentBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _isSyncingOdoo
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.sync, color: Colors.white, size: 18),
              label: Text(
                _isSyncingOdoo ? 'Đang đồng bộ...' : 'Đồng Bộ Cấu Hình Từ Odoo',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: _isSyncingOdoo ? null : () => _syncFromOdoo(sip),
            ),
          ),
          if (isWeb) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(height: 1),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color:
                        (_isPushSubscribed
                                ? AppConstants.accentGreen
                                : AppConstants.accentAmber)
                            .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _isPushSubscribed
                        ? Icons.notifications_active
                        : Icons.notifications_none,
                    color: _isPushSubscribed
                        ? AppConstants.accentGreen
                        : AppConstants.accentAmber,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Thông Báo Cuộc Gọi Web Push',
                        style: TextStyle(
                          color: AppConstants.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _isPushSubscribed
                            ? 'Đang bật nhận thông báo cuộc gọi đến'
                            : 'Nhận thông báo khi khóa màn hình (iPhone/Safari/Chrome)',
                        style: const TextStyle(
                          color: AppConstants.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (isStandalone)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppConstants.accentGreen.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppConstants.accentGreen.withOpacity(0.3),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: AppConstants.accentGreen,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Đang chạy ở chế độ Màn hình chính (PWA Standalone)',
                        style: TextStyle(
                          color: AppConstants.accentGreen,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppConstants.accentAmber.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppConstants.accentAmber.withOpacity(0.3),
                  ),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: AppConstants.accentAmber,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Mẹo iPhone: Nhấn nút Chia sẻ trong Safari > "Thêm vào MH chính" để nhận thông báo khi tắt màn hình.',
                        style: TextStyle(
                          color: AppConstants.textPrimary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: _isPushSubscribed
                        ? AppConstants.accentRed
                        : AppConstants.accentGreen,
                    width: 1.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: _isPushLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _isPushSubscribed
                            ? Icons.notifications_off
                            : Icons.notifications_active,
                        color: _isPushSubscribed
                            ? AppConstants.accentRed
                            : AppConstants.accentGreen,
                        size: 18,
                      ),
                label: Text(
                  _isPushLoading
                      ? 'Đang xử lý...'
                      : (_isPushSubscribed
                            ? 'Tắt Nhận Thông Báo Cuộc Gọi'
                            : 'Bật Thông Báo Cuộc Gọi'),
                  style: TextStyle(
                    color: _isPushSubscribed
                        ? AppConstants.accentRed
                        : AppConstants.accentGreen,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: _isPushLoading ? null : _toggleWebPush,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _syncFromOdoo(SipManager sip) async {
    setState(() => _isSyncingOdoo = true);
    try {
      final odoo = OdooAuthService();
      var acc = await odoo.fetchSipConfig();
      if (acc == null) {
        if (mounted) {
          final loggedIn = await _showOdooLoginDialog();
          if (loggedIn == true) {
            acc = await odoo.fetchSipConfig();
          }
        }
      }

      final account = acc;
      if (account != null) {
        setState(() {
          _extController.text = account.extension;
          _passController.text = account.password;
          _nameController.text = account.displayName;
          _domainController.text = account.domain;
          _wssController.text = account.wssUri;
          _stunController.text = account.stunUri;
          _turnController.text = account.turnUri;
          _turnUserController.text = account.turnUsername;
          _turnPassController.text = account.turnPassword;
          _forceRelayOnly = account.forceRelayOnly;
          _diagnosticLogging = account.diagnosticLogging;
        });

        await sip.connectWithAccount(account);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Đã đồng bộ máy nhánh ${account.extension} từ Odoo!',
              ),
              backgroundColor: AppConstants.accentGreen,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Không thể lấy cấu hình SIP từ Odoo. Vui lòng kiểm tra lại session.',
              ),
              backgroundColor: AppConstants.accentRed,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi đồng bộ Odoo: $e'),
            backgroundColor: AppConstants.accentRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncingOdoo = false);
    }
  }

  Future<bool?> _showOdooLoginDialog() async {
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool obscure = true;
    bool isLoading = false;
    String? errorMsg;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Row(
                children: [
                  Icon(Icons.business, color: AppConstants.accentBlue),
                  SizedBox(width: 8),
                  Text(
                    'Đăng nhập Odoo',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Đăng nhập tài khoản Odoo để tự động đồng bộ cấu hình máy nhánh và Web Push.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppConstants.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: userCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tài khoản / Email',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passCtrl,
                      obscureText: obscure,
                      decoration: InputDecoration(
                        labelText: 'Mật khẩu',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscure ? Icons.visibility_off : Icons.visibility,
                          ),
                          onPressed: () =>
                              setDialogState(() => obscure = !obscure),
                        ),
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                      ),
                    ),
                    if (errorMsg != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        errorMsg!,
                        style: const TextStyle(
                          color: AppConstants.accentRed,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(ctx, false),
                  child: const Text(
                    'Huỷ',
                    style: TextStyle(color: AppConstants.textSecondary),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.accentBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: isLoading
                      ? null
                      : () async {
                          final u = userCtrl.text.trim();
                          final p = passCtrl.text.trim();
                          if (u.isEmpty || p.isEmpty) {
                            setDialogState(
                              () => errorMsg =
                                  'Vui lòng nhập đầy đủ tài khoản và mật khẩu.',
                            );
                            return;
                          }
                          setDialogState(() {
                            isLoading = true;
                            errorMsg = null;
                          });
                          try {
                            final ok = await OdooAuthService().login(
                              login: u,
                              password: p,
                            );
                            if (ok) {
                              if (ctx.mounted) Navigator.pop(ctx, true);
                            } else {
                              setDialogState(() {
                                isLoading = false;
                                errorMsg =
                                    'Đăng nhập không thành công. Kiểm tra lại thông tin.';
                              });
                            }
                          } catch (err) {
                            setDialogState(() {
                              isLoading = false;
                              errorMsg = 'Lỗi kết nối Odoo: $err';
                            });
                          }
                        },
                  child: isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Đăng nhập',
                          style: TextStyle(color: Colors.white),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _toggleWebPush() async {
    if (!kIsWeb) return;
    if (!WebPushManager.isSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Trình duyệt hiện tại không hỗ trợ Web Push API.'),
          backgroundColor: AppConstants.accentAmber,
        ),
      );
      return;
    }

    setState(() => _isPushLoading = true);
    try {
      final odoo = OdooAuthService();

      if (_isPushSubscribed) {
        final sub = await WebPushManager.getSubscription();
        if (sub != null && sub['endpoint'] != null) {
          await odoo.unregisterWebPushSubscription(sub['endpoint'] as String);
        }
        await WebPushManager.unsubscribe();
        setState(() => _isPushSubscribed = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đã tắt nhận thông báo Web Push.'),
              backgroundColor: AppConstants.accentGreen,
            ),
          );
        }
      } else {
        final perm = await WebPushManager.requestPermission();
        if (perm != 'granted') {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Chưa cấp quyền thông báo. Vui lòng cho phép thông báo trong cài đặt trình duyệt.',
                ),
                backgroundColor: AppConstants.accentAmber,
              ),
            );
          }
          return;
        }

        final vapidKey = await odoo.fetchVapidPublicKey();
        if (vapidKey == null || vapidKey.isEmpty) {
          throw Exception('Không lấy được VAPID public key từ server.');
        }

        final sub = await WebPushManager.subscribe(vapidKey);
        final registered = await odoo.registerWebPushSubscription(sub);
        if (registered) {
          setState(() => _isPushSubscribed = true);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Đã kích hoạt thông báo cuộc gọi thành công!'),
                backgroundColor: AppConstants.accentGreen,
              ),
            );
          }
        } else {
          throw Exception('Không thể đăng ký endpoint Web Push với Odoo.');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi Web Push: $e'),
            backgroundColor: AppConstants.accentRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPushLoading = false);
    }
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
