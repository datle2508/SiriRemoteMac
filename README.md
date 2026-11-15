# SiriRemoteMac

Ứng dụng thanh menu cho macOS, dùng **Apple TV Siri Remote đời 1** (ghép Bluetooth) để điều khiển Mac: chuyển bài, phát/dừng, âm lượng, mở app, sleep, giữ/nhấn đúp nút.

> Chưa được kiểm thử rộng. Chỉ thử với Siri Remote đời 1 (pid `0x266`). Vuốt touchpad **không dùng được** (xem *Giới hạn*).

## Cài đặt

Yêu cầu: macOS 13 trở lên, Xcode Command Line Tools (`xcode-select --install`).

```
chmod +x build_app.sh
./build_app.sh
```
Script tạo `SiriRemoteMac.app` và `SiriRemoteMac.dmg`. Kéo app vào **Applications** và mở từ đó.

### Ký app để macOS nhớ quyền (khuyên làm một lần)
Mặc định app được ký ad-hoc, nên mỗi lần build lại macOS sẽ hỏi lại quyền. Để giữ quyền qua các lần build, tạo chứng chỉ cục bộ:
1. Keychain Access → Certificate Assistant → **Create a Certificate…**
2. Name: `SiriRemoteMac Local`, Identity Type: **Self Signed Root**, Certificate Type: **Code Signing**.

`build_app.sh` tự dùng chứng chỉ này nếu có (đổi tên bằng biến `SIGN_IDENTITY`).

### Quyền cần cấp
System Settings → Privacy & Security: bật **Accessibility** và **Input Monitoring** cho `SiriRemoteMac.app`, rồi thoát và mở lại app. Nếu thiếu Accessibility, các phím do app phát ra sẽ bị macOS bỏ qua; dòng đầu menu sẽ hiện cảnh báo ⚠.

### Ghép remote
Tắt Apple TV (hoặc rút nguồn) để remote không tự nối lại với nó. Vào System Settings → Bluetooth, giữ **Menu + Volume Up** khoảng 5 giây rồi bấm Connect.

### Khởi động cùng macOS
Menu 🎛 → **Khởi động cùng macOS** (chỉ khi chạy từ `.app`).

## Cấu hình nút

File `~/.siriremote.json` (tự tạo lần chạy đầu). Dùng **tên nút** làm khóa:

```json
{
  "menu": "media:previous",
  "menu+hold": "media:rewind",
  "home": "media:next",
  "home+hold": "sleep",
  "siri": "app:YouTube Music",
  "touchpad": "media:next",
  "touchpad+double": "media:previous",
  "playpause": "media:playpause",
  "volup": "media:volumeup",
  "voldown": "media:volumedown",
  "holdtime": "0.8",
  "doubletime": "0.3"
}
```

**Tên nút:** `menu`, `home`, `siri`, `touchpad`, `playpause`, `volup`, `voldown`. Vẫn dùng được mã HID dạng `"0C:0060"`.

**Hậu tố:** `+hold` (giữ nút), `+double` (nhấn đúp).

**Hành động**

| Hành động | Ý nghĩa |
|---|---|
| `key:cmd+shift+4`, `key:right`, `key:space` | Phát phím tắt |
| `media:playpause`, `next`, `previous`, `volumeup`, `volumedown`, `mute`, `fast`, `rewind` | Phím media. Giữ nút với `fast`/`rewind` sẽ tua liên tục |
| `scroll:up`, `scroll:down` | Cuộn trang (giữ để cuộn liên tục) |
| `app:Tên App` | Mở ứng dụng |
| `click` | Click chuột trái (không kết hợp với `+hold`/`+double`) |
| `sleep`, `displaysleep` | Cho Mac ngủ / tắt màn hình |
| `none` | Tắt hành động mặc định của nút |

**Thời gian:** `holdtime` (giây, 0.2–3.0, mặc định 0.8), `doubletime` (giây, 0.15–1.0, mặc định 0.3). Nút có `+double` sẽ chạy bấm nhanh trễ khoảng `doubletime`.

Cấu hình của bạn được **gộp** lên mặc định; dùng `"none"` để tắt một nút mặc định. Sau khi sửa, chọn **Nạp lại cấu hình** trong menu 🎛.

## Menu 🎛
- **Khởi động cùng macOS**
- **Chiếm quyền remote**: chỉ bật khi gán lại Vol/Play (tránh macOS xử lý trùng)
- **Ghi log nút bấm**: ghi `~/Library/Logs/SiriRemoteMac.log` để dò mã nút và kiểm tra quyền
- Mở file cấu hình, Nạp lại cấu hình, Mở file log, Thoát

## Xử lý sự cố
- **Nút bấm không có tác dụng:** kiểm tra dòng đầu menu có ⚠ thiếu Accessibility không. Bật *Ghi log nút bấm* và xem dòng `RUN ... accessibility=true/false`.
- **Quyền hỏi lại sau mỗi lần build:** tạo chứng chỉ ký như trên.
- **Lỗi `detritus not allowed` khi ký:** script đã xóa thuộc tính mở rộng (`xattr -cr`); nếu vẫn lỗi, chép thư mục ra nơi không đồng bộ iCloud.
- **Phím media không chuyển bài / không tua:** trình duyệt (ví dụ YouTube) thường chỉ nhận Play/Pause/Next/Previous, không nhận tua.
- **Play/Pause không phát lại sau khi dừng:** thường do macOS/app nhạc mất quyền nhận phím media, thử bằng phím F8 trên bàn phím.
- Không chạy cùng Remote Buddy hoặc SiriMote (tranh quyền với remote).

## Giới hạn
- **Vuốt touchpad không dùng được:** khi ghép với macOS, remote chỉ báo "đang chạm" chứ không gửi tọa độ qua HID, và các lệnh ghi để bật cảm ứng đều bị từ chối. Chỉ nhấn/giữ/nhấn đúp touchpad dùng được như một nút bấm.
- **Mic trên remote** không được macOS nhận như thiết bị âm thanh.
- Chạm nhẹ hai lần (không nhấn) không ghi nhận được.

## Cấu trúc
```
SiriRemoteMac.swift   mã nguồn app (một file)
build_app.sh          đóng gói .app và .dmg
icon/                 icon app (SVG + PNG 1024)
tools/Sniffer.swift   công cụ nghe gói HID để nghiên cứu (không chiếm quyền)
```

Công cụ nghe HID: `swiftc -O tools/Sniffer.swift -o sniffer && ./sniffer | tee sniffer.log`.
