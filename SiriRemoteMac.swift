// SiriRemoteMac.swift
// Ứng dụng thanh menu: dùng Apple TV Siri Remote (đời 1, ghép Bluetooth) để điều khiển Mac.
//
// Build:  swiftc -O SiriRemoteMac.swift -o SiriRemoteMac
// Chạy:   ./SiriRemoteMac
// Quyền:  System Settings → Privacy & Security → Accessibility + Input Monitoring
// Cấu hình nút: ~/.siriremote.json (xem README.md). Nút có mã "PP:UUUU" (hex): usage page : usage.

import Cocoa
import IOKit.hid
import ServiceManagement
import UniformTypeIdentifiers

// MARK: - Hành động

enum Action {
    case key(CGKeyCode, CGEventFlags)
    case media(Int)
    case app(String)
    case click
    case scroll(Int32)          // +1 lên, -1 xuống
    case command(String, [String])

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
        if spec == "sleep" { return .command("/usr/bin/pmset", ["sleepnow"]) }
        if spec == "displaysleep" { return .command("/usr/bin/pmset", ["displaysleepnow"]) }
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
        case "scroll": return arg == "up" ? .scroll(1) : arg == "down" ? .scroll(-1) : nil
        default: return nil
        }
    }

    func run() {
        if debugLog { log("RUN \(self) accessibility=\(AXIsProcessTrusted())") }
        switch self {
        case .key(let code, let flags):
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { continue }
                e.flags = flags
                e.post(tap: .cghidEventTap)
            }
        case .media(let key):
            for state in [0xA, 0xB] {       // nhấn, thả
                NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                   modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                                   timestamp: 0, windowNumber: 0, context: nil,
                                   subtype: 8, data1: (key << 16) | (state << 8), data2: -1)?
                    .cgEvent?.post(tap: .cghidEventTap)
            }
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
        case .click, .scroll:
            break   // xử lý riêng vì cần biết lúc nhấn và lúc thả
        }
    }
}

// MARK: - Cấu hình

/// Tên nút dùng trong file cấu hình → mã HID. Vẫn có thể dùng mã "PP:UUUU" trực tiếp.
let buttonNames: [String: String] = [
    "menu": "01:0086", "home": "0C:0060", "siri": "0C:0004", "touchpad": "0C:0080",
    "playpause": "0C:00CD", "volup": "0C:00E9", "voldown": "0C:00EA",
]

/// Thêm "+hold" sau tên nút (ví dụ "home+hold") cho hành động khi giữ nút.
let defaultMap: [String: String] = [
    "menu": "media:previous",       // bài trước
    "home": "media:next",           // bài kế tiếp (bấm nhanh)
    "home+hold": "sleep",           // giữ nút đủ lâu để Mac sleep
    "siri": "app:Siri",             // mở Siri
    "touchpad": "click",            // nhấn touchpad = click chuột trái
    "playpause": "media:playpause",
    "volup": "media:volumeup",
    "voldown": "media:volumedown",
    "doubletime": "0.3",            // số giây tối đa giữa 2 lần nhấn để tính là nhấn đúp (0.15 – 1.0)
    "holdtime": "0.8",              // số giây giữ nút để tính là "giữ" (0.2 – 3.0)
]

func normalizeKey(_ raw: String) -> String {
    var k = raw.trimmingCharacters(in: .whitespaces).lowercased()
    var suffix = ""
    for (low, up) in [("+hold", "+HOLD"), ("+double", "+DOUBLE")] where k.hasSuffix(low) {
        suffix = up
        k = String(k.dropLast(low.count))
        break
    }
    return (buttonNames[k] ?? k.uppercased()) + suffix
}

/// Các nút hệ thống tự xử lý khi KHÔNG chiếm quyền remote (tránh chạy trùng).
let systemHandledKeys: Set<String> = ["0C:00CD", "0C:00E9", "0C:00EA"]

let configPath = NSHomeDirectory() + "/.siriremote.json"
let logPath = NSHomeDirectory() + "/Library/Logs/SiriRemoteMac.log"
var debugLog = false
var holdDelaySeconds: TimeInterval = 0.8   // đổi bằng khóa "holdtime" trong file cấu hình
var doubleDelaySeconds: TimeInterval = 0.3 // khoảng cách tối đa giữa hai lần nhấn đúp, khóa "doubletime"

func log(_ s: String) {
    guard let data = "\(Date()) \(s)\n".data(using: .utf8) else { return }
    if let h = FileHandle(forWritingAtPath: logPath) {
        h.seekToEndOfFile(); h.write(data); h.closeFile()
    } else {
        FileManager.default.createFile(atPath: logPath, contents: data)
    }
}

/// Cấu hình riêng cho từng app (khóa = bundle id, ví dụ "com.apple.Safari"), nằm trong khóa "apps" của file cấu hình.
var appOverrides: [String: [String: Action]] = [:]
var appDisabled: [String: Set<String>] = [:]     // nút bị tắt ("none") riêng trong app đó

func loadMap() -> [String: Action] {
    appOverrides = [:]; appDisabled = [:]
    var specs: [String: String] = [:]
    for (k, v) in defaultMap { specs[normalizeKey(k)] = v }
    if let data = FileManager.default.contents(atPath: configPath) {
        if let user = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (k, v) in user {
                if k == "apps" {
                    for (bid, d) in (v as? [String: Any]) ?? [:] {
                        for (kk, vv) in (d as? [String: Any]) ?? [:] {
                            let key = normalizeKey(kk), spec = "\(vv)"
                            if key == "HOLDTIME" || key == "DOUBLETIME" { continue }
                            if spec.isEmpty || spec == "none" { appDisabled[bid, default: []].insert(key); continue }
                            if let a = Action.parse(spec) { appOverrides[bid, default: [:]][key] = a }
                            else { log("Hành động không hợp lệ trong \(bid): \(kk) → \(spec)") }
                        }
                    }
                    continue
                }
                specs[normalizeKey(k)] = "\(v)"
            }
        } else {
            log("File cấu hình sai định dạng, dùng mặc định")
        }
    } else if let d = try? JSONSerialization.data(withJSONObject: defaultMap, options: [.prettyPrinted, .sortedKeys]) {
        FileManager.default.createFile(atPath: configPath, contents: d)
    }
    if let d = specs.removeValue(forKey: "DOUBLETIME") {
        if let t = Double(d) { doubleDelaySeconds = min(max(t, 0.15), 1.0) } else { log("doubletime không hợp lệ: \(d)") }
    }
    if let h = specs.removeValue(forKey: "HOLDTIME") {
        if let t = Double(h) { holdDelaySeconds = min(max(t, 0.2), 3.0) } else { log("holdtime không hợp lệ: \(h)") }
    }
    var map: [String: Action] = [:]
    for (k, v) in specs {
        if v.isEmpty || v == "none" { continue }   // "none": tắt hành động mặc định của nút này
        if let a = Action.parse(v) { map[k] = a } else { log("Hành động không hợp lệ: \(k) → \(v)") }
    }
    return map
}

// MARK: - Bộ điều khiển

final class Controller {
    private var manager: IOHIDManager?
    private var remotes: [IOHIDDevice] = []
    private var scrollTimer: Timer?
    private var holdTimers: [String: Timer] = [:]
    private var holdFired: Set<String> = []
    private var doubleTimers: [String: Timer] = [:]
    private(set) var map = loadMap()
    var seize = false           // bật nếu muốn gán lại Play/Pause, Vol (tránh macOS xử lý trùng)

    var isConnected: Bool { !remotes.isEmpty }

    func start() {
        stop()
        map = loadMap()
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        // Chỉ giao diện nút bấm (Consumer Control) của thiết bị Apple; lọc tiếp theo tên "remote".
        let match: [String: Any] = [kIOHIDVendorIDKey as String: 0x004C,
                                    kIOHIDPrimaryUsagePageKey as String: 0x0C,
                                    kIOHIDPrimaryUsageKey as String: 0x01]
        IOHIDManagerSetDeviceMatching(m, match as CFDictionary)
        IOHIDManagerRegisterDeviceMatchingCallback(m, onDeviceAdded, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(m, onDeviceRemoved, nil)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = m
    }

    func stop() {
        holdTimers.values.forEach { $0.invalidate() }; holdTimers.removeAll(); holdFired.removeAll()
        stopSeek()
        doubleTimers.values.forEach { $0.invalidate() }; doubleTimers.removeAll()
        scrollTimer?.invalidate(); scrollTimer = nil
        for d in remotes { close(d) }
        remotes.removeAll()
        if let m = manager {
            IOHIDManagerUnscheduleFromRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
    }

    func reloadMap() { map = loadMap() }

    /// Hành động của nút: ưu tiên cấu hình riêng của app đang ở trên cùng, nếu không có thì dùng cấu hình mặc định.
    private func action(for key: String) -> Action? {
        if let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            if appDisabled[bid]?.contains(key) == true { return nil }
            if let a = appOverrides[bid]?[key] { return a }
        }
        return map[key]
    }

    private func close(_ d: IOHIDDevice) {
        IOHIDDeviceUnscheduleFromRunLoop(d, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(d, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func added(_ d: IOHIDDevice) {
        let name = (IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) as? String) ?? ""
        guard name.lowercased().contains("remote") else { return }
        let r = IOHIDDeviceOpen(d, IOOptionBits(seize ? kIOHIDOptionsTypeSeizeDevice : kIOHIDOptionsTypeNone))
        guard r == kIOReturnSuccess else { log("Không mở được remote (\(r))"); return }
        IOHIDDeviceRegisterInputValueCallback(d, onValue, nil)
        IOHIDDeviceScheduleWithRunLoop(d, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        remotes.append(d)
        DispatchQueue.main.async { appDelegate.refresh() }
    }

    func removed(_ d: IOHIDDevice) {
        guard let i = remotes.firstIndex(where: { $0 === d }) else { return }
        remotes.remove(at: i)
        setScroll(0)
        stopSeek()
        DispatchQueue.main.async { appDelegate.refresh() }
    }

    func handle(_ value: IOHIDValue) {
        let el = IOHIDValueGetElement(value)
        let key = String(format: "%02X:%04X", IOHIDElementGetUsagePage(el), IOHIDElementGetUsage(el))
        let down = IOHIDValueGetIntegerValue(value) != 0
        if debugLog { log("BUTTON \(key) (\(buttonNames.first { $0.value == key }?.key ?? "?")) \(down ? "down" : "up")") }
        let tap = action(for: key)
        let hold = action(for: key + "+HOLD")
        let dbl = action(for: key + "+DOUBLE")
        guard tap != nil || hold != nil || dbl != nil, seize || !systemHandledKeys.contains(key) else { return }

        // Nút có hành động "giữ" hoặc "nhấn đúp": bấm nhanh được xử lý khi THẢ nút.
        if hold != nil || dbl != nil {
            if down {
                holdFired.remove(key)
                if let hold = hold {
                    holdTimers[key]?.invalidate()
                    holdTimers[key] = Timer.scheduledTimer(withTimeInterval: holdDelaySeconds, repeats: false) { [weak self] _ in
                        self?.holdTimers[key] = nil
                        self?.holdFired.insert(key)
                        if case .media(let k) = hold, k == 19 || k == 20 { self?.startSeek(k) } else { hold.run() }
                    }
                }
            } else {
                holdTimers[key]?.invalidate(); holdTimers[key] = nil
                if holdFired.remove(key) != nil { stopSeek(); return }
                shortPress(key, tap: tap, double: dbl)
            }
            return
        }

        guard let action = tap else { return }
        switch action {
        case .click: mouse(down: down)
        case .scroll(let dir): setScroll(down ? dir : 0)
        default: if down { action.run() }
        }
    }

    /// Bấm nhanh: nếu có hành động nhấn đúp thì chờ một khoảng ngắn xem có lần nhấn thứ hai không.
    private func shortPress(_ key: String, tap: Action?, double dbl: Action?) {
        guard let dbl = dbl else { tap?.run(); return }
        if let t = doubleTimers[key] {
            t.invalidate(); doubleTimers[key] = nil
            dbl.run()
            return
        }
        doubleTimers[key] = Timer.scheduledTimer(withTimeInterval: doubleDelaySeconds, repeats: false) { [weak self] _ in
            self?.doubleTimers[key] = nil
            tap?.run()
        }
    }

    // Tua: giữ phím media FAST/REWIND xuống (kèm tín hiệu lặp) cho tới khi thả nút remote.
    private var seekTimer: Timer?
    private var seekKey: Int?

    private func postMediaRaw(_ key: Int, down: Bool, isRepeat: Bool) {
        let state = down ? 0xA : 0xB
        let data1 = (key << 16) | (state << 8) | (isRepeat ? 1 : 0)
        NSEvent.otherEvent(with: .systemDefined, location: .zero,
                           modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                           timestamp: 0, windowNumber: 0, context: nil,
                           subtype: 8, data1: data1, data2: -1)?.cgEvent?.post(tap: .cghidEventTap)
    }

    private func startSeek(_ key: Int) {
        stopSeek()
        seekKey = key
        if debugLog { log("SEEK start \(key) accessibility=\(AXIsProcessTrusted())") }
        postMediaRaw(key, down: true, isRepeat: false)
        seekTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.postMediaRaw(key, down: true, isRepeat: true)
        }
    }

    private func stopSeek() {
        seekTimer?.invalidate(); seekTimer = nil
        if let k = seekKey { postMediaRaw(k, down: false, isRepeat: false); seekKey = nil }
    }

    private func mouse(down: Bool) {
        let pos = CGEvent(source: nil)?.location ?? .zero
        CGEvent(mouseEventSource: nil, mouseType: down ? .leftMouseDown : .leftMouseUp,
                mouseCursorPosition: pos, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    /// dir: +1 lên, -1 xuống, 0 dừng.
    private func setScroll(_ dir: Int32) {
        scrollTimer?.invalidate(); scrollTimer = nil
        guard dir != 0 else { return }
        let step = dir * 25     // pixel mỗi nhịp; tăng số này để cuộn nhanh hơn
        let fire = {
            CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                    wheel1: step, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
        }
        fire()
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in fire() }
    }
}

let controller = Controller()

// Callback kiểu C: chỉ chuyển tiếp sang controller.
func onDeviceAdded(_ c: UnsafeMutableRawPointer?, _ r: IOReturn, _ s: UnsafeMutableRawPointer?, _ d: IOHIDDevice) {
    controller.added(d)
}
func onDeviceRemoved(_ c: UnsafeMutableRawPointer?, _ r: IOReturn, _ s: UnsafeMutableRawPointer?, _ d: IOHIDDevice) {
    controller.removed(d)
}
func onValue(_ c: UnsafeMutableRawPointer?, _ r: IOReturn, _ s: UnsafeMutableRawPointer?, _ v: IOHIDValue) {
    controller.handle(v)
}

// MARK: - Tệp cấu hình (dùng cho giao diện)

func canonicalKey(_ raw: String) -> String {
    let n = normalizeKey(raw)
    var base = n, suffix = ""
    for sfx in ["+HOLD", "+DOUBLE"] where n.hasSuffix(sfx) {
        base = String(n.dropLast(sfx.count)); suffix = sfx.lowercased(); break
    }
    if let name = buttonNames.first(where: { $0.value == base })?.key { return name + suffix }
    return raw.trimmingCharacters(in: .whitespaces).lowercased()
}

struct ConfigFile {
    var global: [String: String] = [:]
    var apps: [String: [String: String]] = [:]

    static func load() -> ConfigFile {
        var c = ConfigFile()
        for (k, v) in defaultMap { c.global[canonicalKey(k)] = v }
        if let data = FileManager.default.contents(atPath: configPath),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (k, v) in obj {
                if k == "apps" {
                    for (bid, d) in (v as? [String: Any]) ?? [:] {
                        var m: [String: String] = [:]
                        for (kk, vv) in (d as? [String: Any]) ?? [:] { m[canonicalKey(kk)] = "\(vv)" }
                        c.apps[bid] = m
                    }
                } else {
                    c.global[canonicalKey(k)] = "\(v)"
                }
            }
        }
        return c
    }

    func save() {
        var dict: [String: Any] = global
        if !apps.isEmpty { dict["apps"] = apps }
        guard let d = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? d.write(to: URL(fileURLWithPath: configPath), options: .atomic)
    }
}

// MARK: - Cửa sổ cài đặt

final class SettingsWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private var cfg = ConfigFile.load()
    private var current: String?            // nil = cấu hình mặc định; ngược lại = bundle id của app
    private let profilePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let removeButton = NSButton(title: "Xóa app này", target: nil, action: nil)
    private let gridHost = NSStackView()
    private var centered = false

    private let rows: [(String, String)] = [
        ("touchpad", "Touchpad"), ("menu", "Menu"), ("home", "Home"), ("siri", "Siri"),
        ("playpause", "Play/Pause"), ("volup", "Vol +"), ("voldown", "Vol −"),
    ]
    private let presets: [(String, String)] = [
        ("media:playpause", "Phát / Dừng"), ("media:next", "Bài kế tiếp"), ("media:previous", "Bài trước"),
        ("media:fast", "Tua tới"), ("media:rewind", "Tua lui"),
        ("media:volumeup", "Tăng âm lượng"), ("media:volumedown", "Giảm âm lượng"), ("media:mute", "Tắt tiếng"),
        ("click", "Click chuột"), ("scroll:up", "Cuộn lên"), ("scroll:down", "Cuộn xuống"),
        ("key:left", "Phím ←"), ("key:right", "Phím →"), ("key:up", "Phím ↑"), ("key:down", "Phím ↓"),
        ("key:space", "Phím Space"), ("key:return", "Phím Enter"), ("key:escape", "Phím Esc"),
        ("key:pageup", "Page Up"), ("key:pagedown", "Page Down"),
        ("sleep", "Cho Mac ngủ"), ("displaysleep", "Tắt màn hình"),
    ]

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = "SiriRemoteMac – Cài đặt nút"
        window.isReleasedWhenClosed = false
        window.delegate = self

        let container = NSView()
        window.contentView = container

        let profileLabel = NSTextField(labelWithString: "Áp dụng cho:")
        profilePopup.target = self; profilePopup.action = #selector(profileChanged(_:))
        profilePopup.widthAnchor.constraint(equalToConstant: 230).isActive = true
        let addButton = NSButton(title: "＋ Thêm app", target: self, action: #selector(addApp(_:)))
        removeButton.target = self; removeButton.action = #selector(removeApp)
        let top = NSStackView(views: [profileLabel, profilePopup, addButton, removeButton])
        top.orientation = .horizontal; top.spacing = 10

        gridHost.orientation = .vertical; gridHost.alignment = .leading; gridHost.spacing = 14

        let footer = NSTextField(wrappingLabelWithString:
            "Thay đổi được lưu tự động vào ~/.siriremote.json. Mỗi app có thể ghi đè cấu hình mặc định; nút nào để “Giống mặc định” sẽ dùng cấu hình chung. Cấu hình áp dụng theo app đang ở trên cùng.")
        footer.textColor = .secondaryLabelColor
        footer.font = .systemFont(ofSize: 11)
        footer.preferredMaxLayoutWidth = 600

        let root = NSStackView(views: [top, gridHost, footer])
        root.orientation = .vertical; root.alignment = .leading; root.spacing = 18
        root.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20),
        ])
    }

    func show() {
        cfg = ConfigFile.load()
        if let c = current, cfg.apps[c] == nil { current = nil }
        reload()
        if !centered { window.center(); centered = true }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: Dựng giao diện

    private func appName(_ bid: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bid
    }

    private func label(for spec: String?) -> String {
        guard let spec = spec, spec != "none", !spec.isEmpty else { return "Không làm gì" }
        if let p = presets.first(where: { $0.0 == spec }) { return p.1 }
        if spec.hasPrefix("app:") { return "Mở " + String(spec.dropFirst(4)) }
        if spec.hasPrefix("key:") { return "Phím " + String(spec.dropFirst(4)) }
        return spec
    }

    private func reload() {
        profilePopup.removeAllItems()
        let def = NSMenuItem(title: "Mặc định (mọi app)", action: nil, keyEquivalent: "")
        def.representedObject = ""
        profilePopup.menu?.addItem(def)
        for bid in cfg.apps.keys.sorted(by: { appName($0).localizedCaseInsensitiveCompare(appName($1)) == .orderedAscending }) {
            let mi = NSMenuItem(title: appName(bid), action: nil, keyEquivalent: "")
            mi.representedObject = bid
            profilePopup.menu?.addItem(mi)
        }
        if let i = profilePopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == (current ?? "") }) {
            profilePopup.selectItem(at: i)
        }
        removeButton.isEnabled = current != nil
        rebuildGrid()
    }

    private func rebuildGrid() {
        for v in gridHost.arrangedSubviews { gridHost.removeArrangedSubview(v); v.removeFromSuperview() }

        func header(_ t: String) -> NSTextField {
            let f = NSTextField(labelWithString: t); f.font = .boldSystemFont(ofSize: 12); return f
        }
        var gridRows: [[NSView]] = [[header("Nút"), header("Bấm"), header("Giữ"), header("Nhấn đúp")]]
        for (name, title) in rows {
            gridRows.append([NSTextField(labelWithString: title),
                             makePopup(name), makePopup(name + "+hold"), makePopup(name + "+double")])
        }
        let grid = NSGridView(views: gridRows)
        grid.columnSpacing = 12; grid.rowSpacing = 8
        gridHost.addArrangedSubview(grid)

        if current == nil {
            func field(_ id: String, _ fallback: String) -> NSTextField {
                let f = NSTextField(string: cfg.global[id] ?? fallback)
                f.identifier = NSUserInterfaceItemIdentifier(id)
                f.target = self; f.action = #selector(timeChanged(_:))
                (f.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = true
                f.widthAnchor.constraint(equalToConstant: 56).isActive = true
                return f
            }
            let t = NSStackView(views: [
                NSTextField(labelWithString: "Thời gian giữ nút (giây):"), field("holdtime", "0.8"),
                NSTextField(labelWithString: "   Khoảng cách nhấn đúp (giây):"), field("doubletime", "0.3"),
            ])
            t.orientation = .horizontal; t.spacing = 6
            gridHost.addArrangedSubview(t)
        }
    }

    private func makePopup(_ key: String) -> NSPopUpButton {
        let p = NSPopUpButton(frame: .zero, pullsDown: false)
        p.identifier = NSUserInterfaceItemIdentifier(key)
        p.target = self; p.action = #selector(actionChanged(_:))
        p.widthAnchor.constraint(equalToConstant: 160).isActive = true

        func add(_ title: String, _ rep: String) {
            let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            mi.representedObject = rep
            p.menu?.addItem(mi)
        }
        if current != nil { add("Giống mặc định: " + label(for: cfg.global[key]), "@inherit") }
        add("Không làm gì", "none")
        p.menu?.addItem(.separator())
        for (spec, title) in presets { add(title, spec) }
        p.menu?.addItem(.separator())
        add("Mở ứng dụng…", "@app")
        add("Phím tắt…", "@key")

        let cur: String? = current == nil ? (cfg.global[key] ?? "none") : cfg.apps[current!]?[key]
        if let cur = cur {
            if let i = p.itemArray.firstIndex(where: { ($0.representedObject as? String) == cur }) {
                p.selectItem(at: i)
            } else {
                let mi = NSMenuItem(title: label(for: cur), action: nil, keyEquivalent: "")
                mi.representedObject = cur
                p.menu?.insertItem(mi, at: current != nil ? 1 : 0)
                p.select(mi)
            }
        } else {
            p.selectItem(at: 0)     // “Giống mặc định”
        }
        return p
    }

    // MARK: Thao tác

    @objc private func profileChanged(_ sender: NSPopUpButton) {
        let rep = (sender.selectedItem?.representedObject as? String) ?? ""
        current = rep.isEmpty ? nil : rep
        reload()
    }

    @objc private func actionChanged(_ sender: NSPopUpButton) {
        guard let key = sender.identifier?.rawValue,
              let rep = sender.selectedItem?.representedObject as? String else { return }
        var value: String? = rep
        switch rep {
        case "@inherit": value = nil
        case "@app":
            guard let name = pickApp() else { rebuildGrid(); return }
            value = "app:" + name
        case "@key":
            guard let k = promptKey() else { rebuildGrid(); return }
            value = "key:" + k
        default: break
        }
        if let bid = current {
            if let v = value { cfg.apps[bid, default: [:]][key] = v } else { cfg.apps[bid]?[key] = nil }
        } else if let v = value {
            if v == "none" && defaultMap[key] == nil { cfg.global[key] = nil } else { cfg.global[key] = v }
        }
        commit()
    }

    @objc private func timeChanged(_ sender: NSTextField) {
        guard let id = sender.identifier?.rawValue else { return }
        let text = sender.stringValue.replacingOccurrences(of: ",", with: ".")
        let range = id == "holdtime" ? 0.2...3.0 : 0.15...1.0
        if let v = Double(text) {
            cfg.global[id] = String(format: "%.2f", min(max(v, range.lowerBound), range.upperBound))
        }
        commit()
    }

    private func commit() {
        cfg.save()
        controller.reloadMap()
        rebuildGrid()
    }

    @objc private func addApp(_ sender: NSButton) {
        let menu = NSMenu()
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != nil
                && $0.bundleIdentifier != Bundle.main.bundleIdentifier && cfg.apps[$0.bundleIdentifier!] == nil
        }.sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        for a in running {
            let mi = NSMenuItem(title: a.localizedName ?? a.bundleIdentifier!, action: #selector(addRunning(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = a.bundleIdentifier
            if let icon = a.icon?.copy() as? NSImage { icon.size = NSSize(width: 16, height: 16); mi.image = icon }
            menu.addItem(mi)
        }
        if !running.isEmpty { menu.addItem(.separator()) }
        let disk = NSMenuItem(title: "Chọn từ thư mục Applications…", action: #selector(addFromDisk), keyEquivalent: "")
        disk.target = self
        menu.addItem(disk)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    @objc private func addRunning(_ sender: NSMenuItem) {
        if let bid = sender.representedObject as? String { addProfile(bid) }
    }

    @objc private func addFromDisk() {
        guard let url = chooseApp(), let bid = Bundle(url: url)?.bundleIdentifier else { return }
        addProfile(bid)
    }

    private func addProfile(_ bid: String) {
        if cfg.apps[bid] == nil { cfg.apps[bid] = [:] }
        current = bid
        cfg.save()
        controller.reloadMap()
        reload()
    }

    @objc private func removeApp() {
        guard let bid = current else { return }
        let a = NSAlert()
        a.messageText = "Xóa cấu hình riêng của \(appName(bid))?"
        a.addButton(withTitle: "Xóa"); a.addButton(withTitle: "Hủy")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        cfg.apps[bid] = nil
        current = nil
        cfg.save()
        controller.reloadMap()
        reload()
    }

    private func chooseApp() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func pickApp() -> String? {
        chooseApp()?.deletingPathExtension().lastPathComponent
    }

    private func promptKey() -> String? {
        let a = NSAlert()
        a.messageText = "Nhập phím tắt"
        a.informativeText = "Ví dụ: cmd+w, cmd+shift+4, ctrl+right, space. Phím bổ trợ: cmd, ctrl, alt, shift."
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        a.accessoryView = f
        a.addButton(withTitle: "OK"); a.addButton(withTitle: "Hủy")
        a.window.initialFirstResponder = f
        guard a.runModal() == .alertFirstButtonReturn else { return nil }
        let text = f.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { return nil }
        guard Action.parse("key:" + text) != nil else {
            let e = NSAlert()
            e.messageText = "Phím không hợp lệ: \(text)"
            e.runModal()
            return nil
        }
        return text
    }
}

// MARK: - Thanh menu

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private let statusLine = NSMenuItem()
    private let seizeItem = NSMenuItem()
    private let debugItem = NSMenuItem()
    private let loginItem = NSMenuItem()

    private func entry(_ title: String, _ sel: Selector, key: String = "") -> NSMenuItem {
        let m = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        m.target = self
        return m
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = AppDelegate.makeMenuIcon()
        item.button?.imagePosition = .imageOnly

        seizeItem.title = "Chiếm quyền remote (chỉ bật khi gán lại Vol/Play)"; seizeItem.action = #selector(toggleSeize)
        debugItem.title = "Ghi log nút bấm (dò mã nút)"; debugItem.action = #selector(toggleDebug)
        seizeItem.target = self; debugItem.target = self
        loginItem.title = "Khởi động cùng macOS"; loginItem.action = #selector(toggleLogin); loginItem.target = self

        let menu = NSMenu()
        for m in [statusLine, .separator(),
                  entry("Cài đặt nút…", #selector(openSettings), key: ","), .separator(),
                  loginItem, seizeItem, debugItem, .separator(),
                  entry("Mở file cấu hình nút", #selector(openConfig)),
                  entry("Nạp lại cấu hình", #selector(reload)),
                  entry("Mở file log", #selector(openLog)), .separator(),
                  entry("Thoát", #selector(quit), key: "q")] {
            menu.addItem(m)
        }
        item.menu = menu

        // Menu chính tối thiểu để Cmd+C / Cmd+V hoạt động trong ô nhập của cửa sổ cài đặt.
        let mainMenu = NSMenu(), editHost = NSMenuItem(), edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editHost.submenu = edit
        mainMenu.addItem(editHost)
        NSApp.mainMenu = mainMenu

        if !AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) {
            log("Chưa có quyền Accessibility")
        }
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)

        controller.start()
        refresh()
    }

    /// Biểu tượng thanh menu (template, đơn sắc), cùng bố cục với icon app:
    /// touchpad phẳng tràn viền ở trên; bên dưới cột trái 3 nút tròn, cột phải 1 nút tròn + 1 nút dài.
    private static func makeMenuIcon() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let body = NSBezierPath(roundedRect: NSRect(x: 4.5, y: 0.5, width: 9, height: 17), xRadius: 2.4, yRadius: 2.4)
            body.lineWidth = 1.2
            body.stroke()
            NSGraphicsContext.saveGraphicsState()
            body.addClip()
            NSRect(x: 4.5, y: 11.4, width: 9, height: 6.6).fill()        // touchpad phẳng, tràn viền
            NSGraphicsContext.restoreGraphicsState()
            func dot(_ x: CGFloat, _ y: CGFloat) {
                NSBezierPath(ovalIn: NSRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6)).fill()
            }
            for y in [9.3, 6.3, 3.3] as [CGFloat] { dot(6.7, y) }          // cột trái: 3 nút tròn
            dot(11.3, 9.3)                                                  // cột phải: nút tròn trên cùng
            NSBezierPath(roundedRect: NSRect(x: 10.5, y: 2.5, width: 1.6, height: 4.6),
                         xRadius: 0.8, yRadius: 0.8).fill()                  // cột phải: nút dài
            return true
        }
        img.isTemplate = true
        return img
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        item.button?.appearsDisabled = !controller.isConnected
        statusLine.title = !trusted ? "⚠ Thiếu quyền Accessibility (nút sẽ không có tác dụng)"
            : controller.isConnected ? "Remote: đã kết nối" : "Remote: chưa thấy (ghép qua Bluetooth)"
        seizeItem.state = controller.seize ? .on : .off
        debugItem.state = debugLog ? .on : .off
        let inApp = Bundle.main.bundlePath.hasSuffix(".app")
        loginItem.isEnabled = inApp      // chỉ bật được khi chạy từ SiriRemoteMac.app
        loginItem.state = (inApp && SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    @objc private func toggleSeize() { controller.seize.toggle(); controller.start(); refresh() }
    @objc private func toggleDebug() { debugLog.toggle(); refresh() }
    @objc private func toggleLogin() {
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled { try svc.unregister() } else { try svc.register() }
        } catch {
            log("Không đổi được khởi động cùng macOS: \(error.localizedDescription)")
            let a = NSAlert()
            a.messageText = "Không bật được khởi động cùng macOS"
            a.informativeText = "Hãy chép SiriRemoteMac.app vào thư mục Applications rồi mở từ đó, hoặc thêm thủ công trong System Settings → General → Login Items.\n\n\(error.localizedDescription)"
            a.runModal()
        }
        refresh()
    }
    private var settingsWindow: SettingsWindow?
    @objc private func openSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindow() }
        settingsWindow?.show()
    }
    @objc private func quit() { controller.stop(); NSApp.terminate(nil) }
    @objc private func reload() { controller.reloadMap() }
    @objc private func openConfig() { NSWorkspace.shared.open(URL(fileURLWithPath: configPath)) }
    @objc private func openLog() { NSWorkspace.shared.open(URL(fileURLWithPath: logPath)) }
}

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.setActivationPolicy(.accessory)
app.run()
