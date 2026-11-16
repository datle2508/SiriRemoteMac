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

## Cảm ứng touchpad

App đọc cảm ứng qua framework riêng `MultitouchSupport` của Apple (cách mà HyperVibe, Remote Buddy… dùng). Không cần quyền thêm ngoài Accessibility.

- **Con trỏ + cuộn:** một ngón di chuyển con trỏ, hai ngón cuộn; nhấn touchpad và di chuyển để kéo thả.
- **Chỉ vuốt / chạm:** không di chuyển con trỏ; vuốt nhanh 4 hướng (`swipeleft`, `swiperight`, `swipeup`, `swipedown`) và chạm 2 ngón (`twofingertap`) chạy hành động bạn gán.
- Tùy chọn: chạm nhẹ để click, cuộn tự nhiên, tốc độ con trỏ/cuộn. Bật/tắt nhanh ở menu 🎛 → **Bật cảm ứng touchpad**.

Khóa trong `~/.siriremote.json`: `touchmode` (`cursor`/`swipe`/`off`), `touchspeed`, `scrollspeed`, `naturalscroll`, `tapclick`, `touchfamily`. Cử chỉ cũng có thể đặt riêng cho từng app.

Nếu không thấy phản hồi cảm ứng: bật **Ghi log nút bấm**, tắt/bật remote, mở file log và xem các dòng `MT thiết bị #… family=…`. Nếu không có dòng nào ghi `← dùng`, thêm `family` của remote vào `touchfamily` (mặc định `160,145`; 160 là Siri Remote đời 1, 145 là đời 3). Nếu cuộn bị ngược chiều, bỏ tick *Cuộn tự nhiên*. Đây là API riêng của Apple nên có thể đổi giữa các bản macOS.

## Dùng với các đời Siri Remote khác

Cài đặt → tab **Remote**:
- **Đời remote:** để *Tự nhận* (theo product ID: `0x266` = đời 1) hoặc chọn tay. Đời 2/3 hiện thêm các nút click ring (giữa/↑/↓/←/→), Back, TV, Mute, Power ở tab *Nút bấm*. Mã HID các nút này **theo chuẩn Consumer Control, chưa kiểm chứng trên máy thật**.
- **Học nút mới…:** bấm nút trên remote để app ghi nhận mã và đặt tên; dùng khi nút chưa có hoặc mã mặc định không đúng. Lưu trong khóa `custombuttons` của `~/.siriremote.json`.
- **Mã cảm ứng (family):** đời 1 = `160`, đời 3 = `145` (luôn thử cả hai). Đời khác: bật *Ghi log nút bấm*, xem dòng `MT thiết bị #… family=…` rồi thêm mã vào đây.

## Cài đặt bằng giao diện

Menu 🎛 → **Cài đặt nút…** (⌘,). Chọn nút, chọn hành động cho *Bấm / Giữ / Nhấn đúp* từ danh sách (hoặc *Mở ứng dụng…*, *Phím tắt…* để tự đặt). Thay đổi được lưu ngay vào `~/.siriremote.json`.

**Cấu hình riêng cho từng app:** ở ô *Áp dụng cho*, bấm **＋ Thêm app** (chọn app đang chạy hoặc từ thư mục Applications). Khi app đó đang ở trên cùng, các nút được cấu hình riêng sẽ thay cho mặc định; nút để *Giống mặc định* vẫn dùng cấu hình chung. Ví dụ: Keynote dùng ← → để chuyển slide, YouTube Music dùng Menu/Home chuyển bài.

## Cấu hình bằng file JSON


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

Cấu hình riêng cho từng app nằm trong khóa `apps` (khóa con là bundle id của app, dùng được `none` để tắt một nút trong app đó):

```json
{
  "home": "media:next",
  "apps": {
    "com.apple.iWork.Keynote": { "home": "key:right", "menu": "key:left" }
  }
}
```

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
- **Tọa độ cảm ứng không có trong báo cáo HID** của remote; app đọc qua `MultitouchSupport` (xem phần *Cảm ứng touchpad*). Phần này chưa được kiểm thử trên mọi đời remote/macOS.
- **Mic trên remote** không được macOS nhận như thiết bị âm thanh.
- Chạm nhẹ hai lần (không nhấn) chưa được hỗ trợ; dùng nhấn đúp touchpad.

## Cấu trúc
```
SiriRemoteMac.swift   mã nguồn app (một file)
build_app.sh          đóng gói .app và .dmg
icon/                 icon app (SVG + PNG 1024)
tools/Sniffer.swift   công cụ nghe gói HID để nghiên cứu (không chiếm quyền)
```

Công cụ nghe HID: `swiftc -O tools/Sniffer.swift -o sniffer && ./sniffer | tee sniffer.log`.
