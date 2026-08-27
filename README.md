# 📱 SGT VoIP Flutter Mobile Softphone (Android & iOS)

Ứng dụng Mobile Softphone chuyên nghiệp xây dựng bằng **Flutter**, kết nối trực tiếp với hệ thống Tổng đài **Asterisk 20 LTS** thông qua giao thức **SIP over WSS (WebSocket Secure)** và **WebRTC (DTLS-SRTP)**. Ứng dụng hỗ trợ đàm thoại 2 chiều với khách hàng hoặc gọi nội bộ với nhân viên trên Odoo 19.

---

## 🏗️ Kiến Trúc & Luồng Kết Nối

```
┌─────────────────────────────────────────────────────────────┐
│                 FLUTTER MOBILE APP (Android / iOS)          │
│  - Extension: 1002                                          │
│  - sip_ua + flutter_webrtc                                  │
│  - Call Center Features: Mute, Speaker, Hold, DTMF, Transfer│
└──────────────────────────────┬──────────────────────────────┘
                               │
            WSS (Port 443) / DTLS-SRTP / ICE
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                 MÁY CHỦ UBUNTU (VMware LAN)                 │
│  IP LAN: 192.168.96.137 | Domain: sgtvoip.duckdns.org       │
│                                                             │
│  ┌───────────────────────┐       ┌──────────────────────┐  │
│  │   Nginx (Port 443)    │──────▶│ Asterisk 20 (8088)   │  │
│  │   SSL Termination     │       │ PJSIP WebRTC Engine  │  │
│  └───────────────────────┘       └──────────────────────┘  │
│                                              ▲              │
│  ┌───────────────────────┐                   │ RTP Media    │
│  │  CoTURN Server (3478) │───────────────────┘ (10000-20000)│
│  │  STUN + TURN Relay    │                                  │
│  └───────────────────────┘                                  │
└──────────────────────────────┬──────────────────────────────┘
                               │
            WSS (Port 443) / WebRTC Audio
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│             ODOO 19 CLIENT (sip_webrtc_softphone)           │
│  - Extension: 1001 (Admin / CSKH)                           │
└─────────────────────────────────────────────────────────────┘
```

---

## ⚡ Các Tính Năng Call Center Đã Xây Dựng

1. **Bàn phím quay số (Dialpad 3x4)**:
   - Bàn phím số đầy đủ có ký tự chữ cái (1-9, 0, *, #) với phản hồi rung nhẹ (Haptic Feedback).
   - Ô nhập số có nút xóa lùi (Backspace) và giữ để xóa hết.
   - Nút gọi thoại màu xanh nổi bật.
   - Nút tắt quay số nhanh các máy nhánh nội bộ: `1001` (Odoo CSKH), `1003` (Leader), `1004` (Kỹ thuật).

2. **Màn hình Đàm thoại (In-Call Screen)**:
   - Hiển thị thông tin người gọi, trạng thái kết nối và bộ đếm thời gian thực (`00:00`).
   - **Tắt tiếng (Mute/Unmute)**: Tắt/bật microphone.
   - **Loa ngoài (Speaker/Earpiece)**: Chuyển đổi linh hoạt giữa Loa trong và Loa ngoài.
   - **Bàn phím DTMF**: Bật popup bàn phím số để gửi tín hiệu DTMF (RFC2833) chọn nhánh IVR tự động.
   - **Giữ máy (Hold/Unhold)**: Tạm giữ cuộc gọi để Asterisk phát nhạc chờ (Music on Hold).
   - **Đá luồng / Chuyển cuộc gọi (Call Transfer)**: Mở dialog nhập số máy nhánh mục tiêu (VD: `1001` máy Odoo hoặc `1003` máy Leader) để thực hiện Blind/Attended Transfer thông qua bản tin `SIP REFER`.
   - **Nút Gác máy (End Call)** màu đỏ.

3. **Màn hình Nhận cuộc gọi (Incoming Call Screen)**:
   - Tự động bắt sự kiện `onNewSession` khi có cuộc gọi đến Extension 1002.
   - Hiển thị hiệu ứng vòng sóng chuông (Pulsing ring animation).
   - Rung và phát chuông báo.
   - Nút **Trả lời (Accept)** màu xanh và **Từ chối (Decline)** màu đỏ.

4. **Cài đặt & Lưu trữ cấu hình (`SharedPreferences`)**:
   - Cho phép chỉnh sửa: Extension, Mật khẩu, Domain, WSS URI, STUN/TURN Server và tài khoản xác thực.
   - Lưu trữ an toàn trên thiết bị và hỗ trợ nút Đăng ký lại (Re-register) tức thì.

---

## 📂 Cấu Trúc Mã Nguồn

```text
flutter_client/
├── pubspec.yaml                          # Khai báo thư viện (sip_ua, flutter_webrtc, etc.)
├── README.md                             # Hướng dẫn chạy và cấu hình (file này)
├── android/
│   └── app/src/main/AndroidManifest.xml  # Khai báo quyền VoIP, RECORD_AUDIO, INTERNET
├── ios/
│   └── Runner/Info.plist                 # Khai báo UIBackgroundModes (voip, audio), Microphone usage
└── lib/
    ├── core/
    │   ├── constants/
    │   │   └── app_constants.dart        # Cấu hình mặc định WSS, STUN/TURN, Theme Colors
    │   └── services/
    │       ├── audio_manager.dart        # Quản lý phát chuông, rung và định tuyến loa
    │       └── sip_manager.dart          # Singleton quản lý SIP UA, Session, ICE, DTMF, Transfer
    ├── data/
    │   └── models/
    │       └── sip_account.dart          # Model tài khoản SIP và SharedPreferences
    ├── presentation/
    │   ├── screens/
    │   │   ├── dialpad_screen.dart       # Màn hình bàn phím quay số & trạng thái SIP
    │   │   ├── in_call_screen.dart       # Màn hình đang đàm thoại với cụm phím điều khiển
    │   │   ├── incoming_call_screen.dart # Màn hình chuông reo nhận cuộc gọi
    │   │   └── settings_screen.dart      # Màn hình cấu hình tài khoản & máy chủ
    │   └── widgets/
    │       ├── dtmf_keypad_dialog.dart   # Modal bàn phím số DTMF in-call
    │       ├── status_indicator.dart     # Chấm trạng thái kết nối SIP (🟢/🟡/🔴)
    │       └── transfer_dialog.dart      # Modal nhập số nhánh để đá luồng cuộc gọi
    └── main.dart                         # Entrypoint, quyền truy cập, Route Navigator & Theme
```

---

## ⚙️ Cấu Hình Mẫu Extension 1002 Trên Asterisk (`pjsip.conf`)

Đảm bảo file `/etc/asterisk/pjsip.conf` trên máy chủ Ubuntu có cấu hình cho extension `1002`:

```ini
; --- Extension 1002 (Flutter Mobile) ---
[1002]
type=endpoint
context=from-internal
disallow=all
allow=opus,ulaw,alaw
auth=1002-auth
aors=1002-aor
webrtc=yes
dtls_auto_generate_cert=yes
dtls_verify=fingerprint
dtls_setup=actpass
use_avpf=yes
media_encryption=dtls
ice_support=yes
direct_media=no

[1002-auth]
type=auth
auth_type=userpass
username=1002
password=Password1234@

[1002-aor]
type=aor
max_contacts=5
remove_existing=yes
```

---

## 🚀 Hướng Dẫn Chạy Ứng Dụng (Getting Started)

### 1. Cài đặt các gói phụ thuộc:
```bash
cd flutter_client
flutter pub get
```

### 2. Chạy trên thiết bị thật hoặc máy ảo:
- Chạy trên thiết bị Android:
  ```bash
  flutter run -d android
  ```
- Chạy trên thiết bị iOS (yêu cầu macOS / Xcode):
  ```bash
  flutter run -d ios
  ```

---

## 🧪 Kịch Bản Kiểm Thử Đàm Thoại & Đá Luồng

1. **Kiểm tra đăng ký SIP**:
   - Mở app Flutter $\rightarrow$ Trạng thái góc trên sẽ hiện chấm xanh: 🟢 **Đã đăng ký (1002)**.
2. **Gọi thoại nội bộ**:
   - Từ App Flutter (1002), nhập số `1001` và bấm nút Gọi $\rightarrow$ Softphone trên Odoo 19 sẽ đổ chuông và hiển thị cuộc gọi đến.
   - Nhấn Trả lời trên Odoo $\rightarrow$ 2 bên đàm thoại thoại 2 chiều rõ nét qua codec Opus.
3. **Thử nghiệm Đá luồng (Call Transfer)**:
   - Trong khi đang đàm thoại giữa Flutter (1002) và Odoo (1001), trên App Flutter bấm nút **Đá luồng (Transfer)**.
   - Nhập số máy Leader `1003` và bấm **Chuyển Ngay** $\rightarrow$ Asterisk sẽ tự động chuyển tiếp luồng cuộc gọi sang máy `1003`.
