// Localization.swift
// Đa ngôn ngữ nhẹ: chuỗi gốc viết bằng tiếng Việt, T() trả về bản tiếng Anh khi giao diện đặt là English.
// Ngôn ngữ chọn trong Cài đặt → Nâng cao (Auto / Tiếng Việt / English); đổi xong cần mở lại app.

import Foundation

/// "vi" hoặc "en": theo khóa "language" trong cấu hình; "auto" theo ngôn ngữ hệ thống (tiếng Việt → vi, còn lại → en).
let appLanguage: String = {
    let setting = ConfigFile.load().global["language"] ?? "auto"
    if setting == "vi" || setting == "en" { return setting }
    return (Locale.preferredLanguages.first ?? "en").hasPrefix("vi") ? "vi" : "en"
}()

func T(_ vi: String) -> String {
    appLanguage == "vi" ? vi : (englishStrings[vi] ?? vi)
}

/// Chuỗi có tham số: TF("Xóa cấu hình riêng của %@?", name)
func TF(_ vi: String, _ args: CVarArg...) -> String {
    String(format: T(vi), arguments: args)
}

private let englishStrings: [String: String] = [
    // Menu thanh trạng thái
    "Khởi động cùng macOS": "Launch at login",
    "Chiếm quyền remote (khi gán lại Vol/Play)": "Seize remote (when remapping Vol/Play)",
    "Ghi log nút bấm": "Log button presses",
    "Cài đặt…": "Settings…",
    "Chế độ cảm ứng": "Touch mode",
    "Nâng cao": "Advanced",
    "Mở file cấu hình": "Open config file",
    "Nạp lại cấu hình": "Reload config",
    "Mở file log": "Open log file",
    "Thoát": "Quit",
    "⚠ Thiếu quyền Accessibility (nút sẽ không có tác dụng)": "⚠ Accessibility permission missing (buttons will not work)",
    "Remote: đã kết nối": "Remote: connected",
    "Remote: chưa thấy (ghép qua Bluetooth)": "Remote: not found (pair via Bluetooth)",
    "Không bật được khởi động cùng macOS": "Could not enable launch at login",
    "Hãy chép SiriRemoteMac.app vào thư mục Applications rồi mở từ đó, hoặc thêm thủ công trong System Settings → General → Login Items.\n\n%@":
        "Copy SiriRemoteMac.app to the Applications folder and open it from there, or add it manually in System Settings → General → Login Items.\n\n%@",
    "Con trỏ": "Cursor", "Vuốt/chạm": "Swipe/Tap", "Tắt": "Off",
    // Hàng nút / cử chỉ
    "Click ring: giữa": "Click ring: center", "Vuốt trái": "Swipe left", "Vuốt phải": "Swipe right",
    "Vuốt lên": "Swipe up", "Vuốt xuống": "Swipe down", "Chạm 2 ngón": "Two-finger tap",
    "Nút “%@”": "Button “%@”",
    // Nhóm hành động
    "Phát / Dừng": "Play / Pause", "Bài kế tiếp": "Next track", "Bài trước": "Previous track",
    "Tua tới": "Fast forward", "Tua lui": "Rewind", "Tăng âm lượng": "Volume up", "Giảm âm lượng": "Volume down",
    "Tắt tiếng": "Mute", "Phím": "Keys", "Phím ←": "Key ←", "Phím →": "Key →", "Phím ↑": "Key ↑", "Phím ↓": "Key ↓",
    "Back (thử nghiệm: hiệu ứng vuốt)": "Back (experimental: swipe effect)",
    "Forward (thử nghiệm: hiệu ứng vuốt)": "Forward (experimental: swipe effect)",
    "Chuột": "Mouse", "Click chuột": "Left click", "Click phải": "Right click", "Cuộn lên": "Scroll up", "Cuộn xuống": "Scroll down",
    "Hệ thống": "System", "Exposé (cửa sổ của app)": "Exposé (app windows)", "Màn hình chờ": "Screen saver",
    "Hiện màn hình nền": "Show desktop", "Khóa màn hình": "Lock screen", "Cho Mac ngủ": "Sleep Mac", "Tắt màn hình": "Turn off display",
    "Đổi chế độ cảm ứng (con trỏ ↔ vuốt)": "Switch touch mode (cursor ↔ swipe)",
    // Mẫu
    "Chạm đúp 2 ngón": "Two-finger double tap", "Zoom": "Zoom",
    "Zoom thông minh (thử nghiệm)": "Smart zoom (experimental)",
    "Zoom nhanh (phóng to ↔ về cũ)": "Quick zoom (zoom in ↔ reset)",
    "Phóng to (⌘+)": "Zoom in (⌘+)", "Thu nhỏ (⌘−)": "Zoom out (⌘−)", "Kích thước thật (⌘0)": "Actual size (⌘0)",
    "Mẫu có sẵn": "Templates", "Nghe nhạc": "Listen to music", "Xem YouTube": "Watch YouTube",
    "Lướt TikTok": "Browse TikTok", "Duyệt web": "Web browsing", "Thuyết trình": "Presentation",
    // Cửa sổ cài đặt
    "Cài đặt": "Settings", "Áp dụng cho": "Apply to", "Thêm app": "Add app", "Xóa": "Delete", "Xóa app này": "Delete this app",
    "Cấp quyền…": "Grant access…", "Nút bấm": "Buttons", "Cảm ứng": "Touch",
    "Mọi thay đổi được lưu ngay. “↩ Mặc định” nghĩa là dùng cấu hình chung; cấu hình riêng áp dụng cho app đang ở trên cùng.":
        "Changes are saved immediately. “↩ Default” means the shared setting is used; per-app settings apply to the frontmost app.",
    "Không làm gì": "Do nothing", "Mở ": "Open ", "Phím ": "Key ", "Mặc định (mọi app)": "Default (all apps)",
    "↩ Mặc định: ": "↩ Default: ", "Mở ứng dụng…": "Open app…", "Phím tắt…": "Keyboard shortcut…",
    "Đã cấp quyền": "Access granted", "Thiếu quyền Accessibility": "Accessibility permission missing",
    "Remote đã kết nối": "Remote connected", "Remote chưa kết nối": "Remote not connected", "Cảm ứng: ": "Touch: ",
    "Phím trên remote": "Remote buttons", "Bấm": "Press", "Giữ": "Hold", "Nhấn đúp": "Double press",
    "Một ngón di chuyển con trỏ, hai ngón cuộn, vuốt nhanh chạy cử chỉ bên dưới.": "One finger moves the cursor, two fingers scroll, a quick swipe runs the gestures below.",
    "Vuốt / chạm": "Swipe / Tap",
    "Không di chuyển con trỏ; chỉ nhận cử chỉ vuốt và chạm bên dưới.": "The cursor does not move; only the swipe and tap gestures below are used.",
    "Bỏ qua touchpad.": "Ignore the touchpad.",
    "Mẹo: giữ nút Siri để đổi nhanh giữa các chế độ.": "Tip: hold the Siri button to switch modes quickly.",
    "Độ nhạy": "Sensitivity", "Tốc độ con trỏ": "Cursor speed", "Tốc độ cuộn": "Scroll speed",
    "Cảm giác như Magic Trackpad": "Magic Trackpad feel",
    "Cuộn tự nhiên (đảo chiều)": "Natural scrolling (reversed)",
    "Cuộn có quán tính (tiếp tục cuộn sau khi nhấc tay)": "Scroll momentum (keeps scrolling after lifting)",
    "Chạm nhẹ để click (chạm rồi đặt ngón xuống = kéo thả)": "Tap to click (tap then hold down = drag)",
    "Giữ yên con trỏ khi nhấn touchpad để click": "Keep the cursor steady when pressing to click",
    "Cử chỉ": "Gestures", "Hành động": "Action",
    "Cài đặt nâng cao áp dụng chung cho mọi app. Chọn “Mặc định (mọi app)” ở ô Áp dụng cho để chỉnh.":
        "Advanced settings apply to all apps. Choose “Default (all apps)” in “Apply to” to edit them.",
    "Tự nhận (khuyên dùng)": "Auto-detect (recommended)", "Đời 1 (A1513 / A1844)": "Gen 1 (A1513 / A1844)",
    "Đời 2 / 3 (A2540 / A2854, USB-C)": "Gen 2 / 3 (A2540 / A2854, USB-C)", "chưa thấy remote": "no remote found",
    "Đời remote": "Remote model", "đang nhận: %@": "detected: %@",
    "Đời 2/3 hiện thêm các nút click ring, Back, TV, Mute, Power ở tab Nút bấm (mã nút theo chuẩn HID, chưa kiểm chứng trên máy thật).":
        "Gen 2/3 adds the click ring, Back, TV, Mute and Power buttons to the Buttons tab (HID codes are standard but untested on real hardware).",
    "Thời gian": "Timing", "Giữ nút (giây)": "Hold time (s)", "      Nhấn đúp (giây)": "      Double press (s)",
    "Mã cảm ứng (family)": "Touch family ID",
    "Đời 1 = 160, đời 3 = 145 (luôn được thử). Với đời khác: bật “Ghi log nút bấm” (menu → Nâng cao), nối lại remote, xem dòng `family` trong log và thêm vào đây, cách nhau bằng dấu phẩy.":
        "Gen 1 = 160, gen 3 = 145 (always tried). For other models: enable “Log button presses” (menu → Advanced), reconnect the remote, find the `family` line in the log and add it here, comma-separated.",
    "Học nút mới…": "Learn new button…",
    "Dùng khi một nút chưa có trong danh sách: bấm “Học nút mới…”, bấm nút đó trên remote rồi đặt tên. Nút sẽ xuất hiện ở tab Nút bấm.":
        "Use when a button is not in the list: click “Learn new button…”, press it on the remote, then name it. It will appear in the Buttons tab.",
    "Nút tự học": "Learned buttons",
    "Hiệu ứng Back/Forward (nav:back, nav:forward)": "Back/Forward effect (nav:back, nav:forward)",
    "Quãng vuốt": "Swipe distance", "Đảo chiều": "Reverse direction",
    "Nếu thấy giật/lag: giảm Thời gian và Quãng vuốt; nếu không đổi trang: tăng Quãng vuốt.":
        "If it stutters or lags: reduce Timing and Swipe distance; if the page does not change: increase Swipe distance.",
    "Ngôn ngữ": "Language", "Tự động (theo hệ thống)": "Auto (system)", "Tiếng Việt": "Vietnamese", "English": "English",
    "Đổi ngôn ngữ có hiệu lực sau khi mở lại app.": "Language changes take effect after restarting the app.",
    "Mở lại ngay": "Restart now", "Để sau": "Later", "Cần mở lại app để đổi ngôn ngữ": "Restart required to change the language",
    "mặc định (mọi app)": "default (all apps)",
    "Áp dụng mẫu “%@” cho %@?": "Apply template “%@” to %@?",
    "Các nút và cử chỉ có trong mẫu sẽ được thay; những nút khác giữ nguyên.": "Buttons and gestures in the template are replaced; others stay unchanged.",
    "Áp dụng": "Apply", "Hủy": "Cancel", "Chọn từ thư mục Applications…": "Choose from Applications folder…",
    "Xóa cấu hình riêng của %@?": "Delete the custom settings for %@?",
    "Nhập phím tắt": "Enter keyboard shortcut",
    "Ví dụ: cmd+w, cmd+shift+4, ctrl+right, space. Phím bổ trợ: cmd, ctrl, alt, shift.":
        "Examples: cmd+w, cmd+shift+4, ctrl+right, space. Modifiers: cmd, ctrl, alt, shift.",
    "Phím không hợp lệ: %@": "Invalid key: %@",
    "Bấm một nút trên remote…": "Press a button on the remote…",
    "Nút đầu tiên bạn bấm sẽ được ghi nhận (không chạy hành động).": "The first button you press is recorded (its action will not run).",
    "Nút này đã có tên: %@": "This button already has a name: %@", "Mã nút: %@": "Button code: %@",
    "Đặt tên cho nút (mã %@)": "Name this button (code %@)",
    "Chữ thường, không dấu, không khoảng trắng. Ví dụ: ring_up": "Lowercase, no accents, no spaces. Example: ring_up",
    "Rê chuột lên nút trên hình hoặc bấm nút thật trên remote để thấy hàng tương ứng.":
        "Hover a button in the picture, or press a real button on the remote, to see its row.",
    "Touchpad của remote": "Remote touchpad", "Tuỳ chọn kỹ thuật": "Technical options",
    "Mã thiết bị cảm ứng": "Touch device ID",
    "Thường không cần chỉnh gì: app tự nhận touchpad của Siri Remote đời 1 và đời 3.":
        "Usually nothing to change: the app detects the touchpad of Siri Remote gen 1 and gen 3 automatically.",
    "Cảm ứng đang tắt — bật lại ở tab Cảm ứng": "Touch is off — turn it on in the Touch tab",
    "Đang nhận cảm ứng từ remote": "Receiving touch from the remote",
    "Chưa thấy remote — hãy kết nối qua Bluetooth": "No remote found — connect it via Bluetooth",
    "Remote đã kết nối nhưng chưa nhận được touchpad — thử tắt/bật remote": "Remote connected but no touchpad found — try turning the remote off and on",
    "Cuộn ngang ←": "Scroll left", "Cuộn ngang →": "Scroll right",
    "Cuộn tự nhiên (đảo chiều, áp dụng cả cho vuốt gán Cuộn)": "Natural scrolling (reversed, also for swipes set to Scroll)",
    "Độ mượt khi cuộn": "Scroll smoothness",
    "Độ mượt: thấp = trang bám sát ngón tay nhưng có thể giật theo nhịp Bluetooth; cao = trang trôi đều hơn nhưng chạy sau ngón một chút.":
        "Smoothness: low = the page tracks your finger closely but may stutter with Bluetooth timing; high = steadier motion with slightly more lag.",
    "Zoom thông minh (như Magic Trackpad)": "Smart zoom (like Magic Trackpad)",
    "Chạm đúp 1 ngón": "One-finger double tap",
    "Lưu": "Save", "Tên không hợp lệ hoặc đã tồn tại: %@": "Invalid or existing name: %@",
]
