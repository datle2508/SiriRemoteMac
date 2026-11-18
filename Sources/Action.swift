// Action.swift
// Hành động gán cho nút / cử chỉ (phím, media, mở app, cuộn, click...).

import Cocoa

// MARK: - Hành động

enum Action {
    case key(CGKeyCode, CGEventFlags)
    case media(Int)
    case app(String)
    case click
    case scroll(Int32)          // +1 lên, -1 xuống
    case hscroll(Int32)         // cuộn ngang: +1 sang trái, -1 sang phải
    case command(String, [String])
    case nav(Bool)                  // true = Back, false = Forward (hiệu ứng vuốt như Magic Trackpad)
    case rightClick                 // click chuột phải
    case zoomToggle                 // phóng to vài mức ↔ về kích thước thật (⌘= ×3 / ⌘0)
    case smartZoom                  // zoom thông minh như chạm đúp hai ngón trên Magic Trackpad
    case dock(String)               // thông báo gửi cho Dock (Mission Control, Exposé, Show Desktop)
    case toggleTouch                // đổi chế độ cảm ứng con trỏ ↔ vuốt/chạm

    private static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "return": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43,
        "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "delete": 51,
        "escape": 53, "home": 115, "pageup": 116, "end": 119, "pagedown": 121,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]
    private static let mediaKeys: [String: Int] = [
        "volumeup": 0, "volumedown": 1, "mute": 7, "playpause": 16, "next": 17, "previous": 18,
        "fast": 19, "rewind": 20,   // phím F9 / F7 thật trên bàn phím Apple thường gửi mã này
    ]

    /// "key:cmd+space", "media:playpause", "app:Keynote", "scroll:up", "click"
    static func parse(_ spec: String) -> Action? {
        if spec == "click" { return .click }
        if spec == "toggletouch" { return .toggleTouch }
        if spec == "rightclick" { return .rightClick }
        if spec == "nav:back" { return .nav(true) }
        if spec == "nav:forward" { return .nav(false) }
        if spec == "sleep" { return .command("/usr/bin/pmset", ["sleepnow"]) }
        if spec == "displaysleep" { return .command("/usr/bin/pmset", ["displaysleepnow"]) }
        if spec == "mission" { return .dock("com.apple.expose.awake") }
        if spec == "expose" { return .dock("com.apple.expose.front.awake") }   // Exposé: cửa sổ của app
        if spec == "zoomtoggle" { return .zoomToggle }
        if spec == "smartzoom" { return .smartZoom }
        if spec == "zoomin" { return .key(24, .maskCommand) }      // ⌘=
        if spec == "zoomout" { return .key(27, .maskCommand) }     // ⌘-
        if spec == "zoomreset" { return .key(29, .maskCommand) }   // ⌘0
        if spec == "showdesktop" { return .dock("com.apple.showdesktop.awake") }
        if spec == "screensaver" { return .command("/usr/bin/open", ["-a", "ScreenSaverEngine"]) }
        if spec == "lockscreen" { return .key(12, [.maskControl, .maskCommand]) }   // ⌃⌘Q
        let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let arg = parts[1]
        switch parts[0] {
        case "key":
            var flags: CGEventFlags = []
            var name = ""
            for p in arg.lowercased().split(separator: "+").map(String.init) {
                switch p {
                case "cmd", "command": flags.insert(.maskCommand)
                case "ctrl", "control": flags.insert(.maskControl)
                case "alt", "option": flags.insert(.maskAlternate)
                case "shift": flags.insert(.maskShift)
                default: name = p
                }
            }
            return keyCodes[name].map { .key($0, flags) }
        case "media": return mediaKeys[arg.lowercased()].map { .media($0) }
        case "app": return .app(arg)
        case "scroll":
            switch arg {
            case "up": return .scroll(1)
            case "down": return .scroll(-1)
            case "left": return .hscroll(1)
            case "right": return .hscroll(-1)
            default: return nil
            }
        default: return nil
        }
    }

    private static var zoomed = false

    func run() {
        if debugLog { log("RUN \(self) accessibility=\(AXIsProcessTrusted())") }
        switch self {
        case .key(let code, let flags):
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { continue }
                e.flags = flags
                e.post(tap: .cghidEventTap)
            }
            if !flags.isEmpty { releaseModifiers() }
        case .media(let key):
            postMediaKey(key, down: true)       // nhấn
            postMediaKey(key, down: false)      // thả
        case .app(let name):
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-a", name]
            try? p.run()
        case .command(let path, let args):
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = args
            try? p.run()
        case .rightClick:
            let pos = CGEvent(source: nil)?.location ?? .zero
            postMouse(.rightMouseDown, at: pos, button: .right)
            postMouse(.rightMouseUp, at: pos, button: .right)
        case .zoomToggle:
            Action.zoomed.toggle()
            let (code, n) = Action.zoomed ? (CGKeyCode(24), 3) : (CGKeyCode(29), 1)
            for _ in 0..<n { Action.key(code, .maskCommand).run() }
        case .smartZoom:
            postSmartMagnify()
        case .dock(let name):
            if !sendDockNotification(name) {            // dự phòng: phím tắt mặc định của macOS
                switch name {
                case "com.apple.expose.awake": Action.key(126, [.maskControl, .maskSecondaryFn]).run()
                case "com.apple.expose.front.awake": Action.key(125, [.maskControl, .maskSecondaryFn]).run()
                default: break
                }
            }
        case .toggleTouch:
            toggleTouchMode()
        case .nav(let back):
            navSwipe(back: back)
        case .click:                    // dùng khi click đi qua đường "giữ"/"nhấn đúp": nhấn rồi thả ngay
            let pos = CGEvent(source: nil)?.location ?? .zero
            postMouse(.leftMouseDown, at: pos)
            postMouse(.leftMouseUp, at: pos)
        case .scroll(let dir):
            smoothScroll(v: Double(dir) * 420 * scrollSpeed, h: 0)
        case .hscroll(let dir):
            smoothScroll(v: 0, h: Double(dir) * 420 * scrollSpeed)
        }
    }
}


/// Gửi một sự kiện phím media (NX_KEYTYPE_*) cho hệ thống.
func postMediaKey(_ key: Int, down: Bool, isRepeat: Bool = false) {
    let state = down ? 0xA : 0xB
    NSEvent.otherEvent(with: .systemDefined, location: .zero,
                       modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                       timestamp: 0, windowNumber: 0, context: nil,
                       subtype: 8, data1: (key << 16) | (state << 8) | (isRepeat ? 1 : 0), data2: -1)?
        .cgEvent?.post(tap: .cghidEventTap)
}


/// Gửi sự kiện chuột sạch: luôn xóa cờ phím bổ trợ (⌘ còn sót sẽ khiến Safari mở link ở tab mới) và đặt clickState.
func postMouse(_ type: CGEventType, at pos: CGPoint, button: CGMouseButton = .left, clickState: Int64 = 1) {
    guard let e = CGEvent(mouseEventSource: mouseSource, mouseType: type, mouseCursorPosition: pos, mouseButton: button) else { return }
    e.flags = []
    if type != .mouseMoved { e.setIntegerValueField(.mouseEventClickState, value: clickState) }
    e.post(tap: .cghidEventTap)
}

/// Nguồn sự kiện mặc định của hệ thống (nguồn "private" làm nhấn touchpad không còn click được).
let mouseSource: CGEventSource? = nil

/// Sau phím tắt có bổ trợ (⌘, ⌃…) gửi thêm sự kiện nhả bổ trợ để hệ thống không giữ nhầm trạng thái.
func releaseModifiers() {
    if let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
        e.type = .flagsChanged
        e.flags = []
        e.post(tap: .cghidEventTap)
    }
}


/// Gọi hàm riêng của Dock (CoreDockSendNotification) như phím Mission Control / Exposé thật; false nếu không tìm thấy hàm.
func sendDockNotification(_ name: String) -> Bool {
    typealias Fn = @convention(c) (CFString, Int32) -> Void
    _ = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_NOW)
    guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CoreDockSendNotification") else { return false }   // RTLD_DEFAULT
    unsafeBitCast(sym, to: Fn.self)(name as CFString, 0)
    return true
}

/// Zoom thông minh như chạm đúp hai ngón trên Magic Trackpad: Safari, Preview, Chrome… phóng to vừa khối nội dung
/// dưới con trỏ (đoạn văn, ảnh…), làm lại lần nữa thì về cũ.
///
/// Ở tầng CGEvent không có kiểu 32 (NSEventTypeSmartMagnify chỉ tồn tại trong AppKit — gửi kiểu 32 bị bỏ qua).
/// Trackpad thật gửi sự kiện cử chỉ (kiểu 29) có loại HID = 22 (kIOHIDEventTypeZoomToggle); AppKit dịch nó thành
/// NSEventTypeSmartMagnify (đã kiểm chứng: NSEvent(cgEvent:) của sự kiện này có type == .smartMagnify).
func postSmartMagnify() {
    guard let gesture = CGEventType(rawValue: 29), let e = CGEvent(source: nil) else { return }
    let pos = e.location                       // zoom quanh vị trí con trỏ
    e.type = gesture
    e.location = pos
    e.flags = []
    if let f = CGEventField(rawValue: 55) { e.setIntegerValueField(f, value: 29) }     // loại sự kiện CGS: gesture
    if let f = CGEventField(rawValue: 110) { e.setIntegerValueField(f, value: 22) }    // loại HID: zoom toggle
    e.post(tap: .cghidEventTap)
}
