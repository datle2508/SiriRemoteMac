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

func loadMap() -> [String: Action] {
    var specs: [String: String] = [:]
    for (k, v) in defaultMap { specs[normalizeKey(k)] = v }
    if let data = FileManager.default.contents(atPath: configPath) {
        if let user = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (k, v) in user { specs[normalizeKey(k)] = "\(v)" }
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
        let tap = map[key]
        let hold = map[key + "+HOLD"]
        let dbl = map[key + "+DOUBLE"]
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
        for m in [statusLine, .separator(), loginItem, seizeItem, debugItem, .separator(),
                  entry("Mở file cấu hình nút", #selector(openConfig)),
                  entry("Nạp lại cấu hình", #selector(reload)),
                  entry("Mở file log", #selector(openLog)), .separator(),
                  entry("Thoát", #selector(quit), key: "q")] {
            menu.addItem(m)
        }
        item.menu = menu

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
