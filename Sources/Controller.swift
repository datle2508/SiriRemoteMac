// Controller.swift
// Đọc nút bấm từ remote (IOKit HID), giữ / nhấn đúp / tua.

import Cocoa
import IOKit.hid

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
    /// Khi khác nil: nút remote kế tiếp được bấm sẽ được gửi vào đây (không chạy hành động) để "học" mã nút.
    var learnHandler: ((String) -> Void)?

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

    func reloadMap() { map = loadMap(); touchEngine.start(force: false) }

    /// Hành động của nút: ưu tiên cấu hình riêng của app đang ở trên cùng, nếu không có thì dùng cấu hình mặc định.
    func action(for key: String) -> Action? {
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
        detectedProductID = (IOHIDDeviceGetProperty(d, kIOHIDProductIDKey as CFString) as? Int) ?? 0
        if debugLog { log("REMOTE \(name) productID=0x\(String(detectedProductID, radix: 16))") }
        IOHIDDeviceRegisterInputValueCallback(d, onValue, nil)
        IOHIDDeviceScheduleWithRunLoop(d, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        remotes.append(d)
        DispatchQueue.main.async { appDelegate.refresh() }
        // Thiết bị cảm ứng xuất hiện chậm hơn nút bấm một chút: thử nạp lại vài lần.
        for delay in [1.0, 3.0, 6.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { touchEngine.start(force: false) }
        }
    }

    func removed(_ d: IOHIDDevice) {
        guard let i = remotes.firstIndex(where: { $0 === d }) else { return }
        remotes.remove(at: i)
        mouseButtonDown = false
        touchEngine.stop()
        setScroll(0)
        stopSeek()
        DispatchQueue.main.async { appDelegate.refresh() }
    }

    func handle(_ value: IOHIDValue) {
        let el = IOHIDValueGetElement(value)
        let key = String(format: "%02X:%04X", IOHIDElementGetUsagePage(el), IOHIDElementGetUsage(el))
        let down = IOHIDValueGetIntegerValue(value) != 0
        if let h = learnHandler {
            if down { learnHandler = nil; DispatchQueue.main.async { h(key) } }
            return
        }
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

    private func startSeek(_ key: Int) {
        stopSeek()
        seekKey = key
        if debugLog { log("SEEK start \(key) accessibility=\(AXIsProcessTrusted())") }
        postMediaKey(key, down: true, isRepeat: false)
        seekTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.postMediaKey(key, down: true, isRepeat: true)
        }
    }

    private func stopSeek() {
        seekTimer?.invalidate(); seekTimer = nil
        if let k = seekKey { postMediaKey(k, down: false, isRepeat: false); seekKey = nil }
    }

    func mouse(down: Bool) {
        mouseButtonDown = down
        var pos = CGEvent(source: nil)?.location ?? .zero
        if down, let anchor = touchEngine.beginPress() {     // lấy lại vị trí trước khi ngón tay lăn đi lúc nhấn
            CGWarpMouseCursorPosition(anchor)
            pos = anchor
        }
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
let touchEngine = TouchEngine()

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

