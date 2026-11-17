// Touch.swift
// Cảm ứng touchpad qua MultitouchSupport: con trỏ, cuộn, vuốt, chạm.

import Cocoa

var navInvert = false

/// Giả lập cú vuốt hai ngón ngang của trackpad (chuỗi sự kiện cuộn có pha) để Safari/Chrome chạy
/// hiệu ứng Back/Forward như Magic Trackpad. Hướng: ngón tay sang phải = Back.
func navSwipe(back: Bool) {
    let dir: Double = (back ? 1 : -1) * (navInvert ? -1 : 1)
    func post(_ delta: Int32, _ phase: Int64) {
        guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                              wheel1: 0, wheel2: delta, wheel3: 0) else { return }
        if let f = CGEventField(rawValue: 88) { e.setIntegerValueField(f, value: 1) }       // isContinuous
        if let f = CGEventField(rawValue: 99) { e.setIntegerValueField(f, value: phase) }   // scrollPhase
        e.post(tap: .cghidEventTap)
    }
    post(0, 1)                                    // began
    var i = 0
    let frames = 18
    Timer.scheduledTimer(withTimeInterval: 0.012, repeats: true) { t in
        i += 1
        let progress = Double(i) / Double(frames)
        let delta = Int32((dir * 45 * (1.2 - progress)).rounded())     // chậm dần như ngón tay thật
        post(delta, 2)                            // changed
        if i >= frames { t.invalidate(); post(0, 4) }                  // ended
    }
}

/// Đổi qua lại giữa chế độ con trỏ và chế độ vuốt/chạm; lưu vào file cấu hình.
func toggleTouchMode() {
    var c = ConfigFile.load()
    let next = touchMode == .cursor ? "swipe" : "cursor"
    c.global["touchmode"] = next
    c.save()
    controller.reloadMap()
    NSSound(named: NSSound.Name(next == "cursor" ? "Pop" : "Tink"))?.play()
    appDelegate.flash(next == "cursor" ? "Con trỏ" : "Vuốt/chạm")
    appDelegate.refresh()
}
// MARK: - Cảm ứng (MultitouchSupport, framework riêng của Apple)

struct MTPoint { var x: Float; var y: Float }
struct MTVector { var pos: MTPoint; var vel: MTPoint }
struct MTTouch {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32
    var fingerId: Int32
    var handId: Int32
    var normalized: MTVector
    var size: Float
    var pressure: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absoluteVector: MTVector
    var unknown1: Int32
    var unknown2: Int32
    var density: Float
}

struct TouchPoint { var id: Int32; var x: Float; var y: Float; var state: Int32 }

typealias MTContactCB = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Void
typealias MTFnList = @convention(c) () -> UnsafeRawPointer?
typealias MTFnReg = @convention(c) (UnsafeMutableRawPointer, MTContactCB) -> Void
typealias MTFnUnreg = @convention(c) (UnsafeMutableRawPointer, MTContactCB) -> Void
typealias MTFnStart = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
typealias MTFnStop = @convention(c) (UnsafeMutableRawPointer) -> Void
typealias MTFnFamily = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<Int32>) -> Int32

/// Chạy trên luồng riêng của MultitouchSupport: chỉ sao chép dữ liệu rồi chuyển sang luồng chính.
func touchCallbackFn(_ dev: UnsafeMutableRawPointer?, _ raw: UnsafeMutableRawPointer?, _ n: Int32, _ ts: Double, _ frame: Int32) {
    var list: [TouchPoint] = []
    if let raw = raw, n > 0 {
        let t = raw.assumingMemoryBound(to: MTTouch.self)
        for i in 0..<Int(n) {
            list.append(TouchPoint(id: t[i].identifier, x: t[i].normalized.pos.x, y: t[i].normalized.pos.y, state: t[i].state))
        }
    }
    DispatchQueue.main.async { touchEngine.process(list, timestamp: ts) }
}
let touchCallback: MTContactCB = touchCallbackFn

final class TouchEngine {
    private var lib: UnsafeMutableRawPointer?
    private var deviceList: CFArray?
    private var devices: [UnsafeMutableRawPointer] = []
    private var runningMode: TouchMode = .off
    private var runningFamilies: Set<Int32> = []

    // Trạng thái cử chỉ
    private var inSession = false
    private var startTime = 0.0
    private var lastCentroid = (x: Float(0), y: Float(0))
    private var startCentroid = (x: Float(0), y: Float(0))
    private var lastCount = 0
    private var maxFingers = 0
    private var travel: Float = 0
    private var scrollRemX: Float = 0
    private var scrollRemY: Float = 0
    private var cursorDecided = false       // false: đang giữ con trỏ đứng yên, chờ xem có phải cú vuốt không
    private var bufX: Float = 0
    private var bufY: Float = 0

    var isRunning: Bool { !devices.isEmpty }

    /// force = false: bỏ qua nếu đang chạy đúng cấu hình.
    func start(force: Bool) {
        if !force && isRunning && runningMode == touchMode && runningFamilies == touchFamilies { return }
        stop()
        guard touchMode != .off else { return }
        if lib == nil { lib = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW) }
        guard let h = lib else { log("Không nạp được MultitouchSupport"); return }
        guard let sList = dlsym(h, "MTDeviceCreateList"), let sReg = dlsym(h, "MTRegisterContactFrameCallback"),
              let sStart = dlsym(h, "MTDeviceStart") else { log("MultitouchSupport thiếu hàm cần dùng"); return }
        let fam: MTFnFamily? = dlsym(h, "MTDeviceGetFamilyID").map { unsafeBitCast($0, to: MTFnFamily.self) }
        guard let raw = unsafeBitCast(sList, to: MTFnList.self)() else { return }
        let arr = Unmanaged<CFArray>.fromOpaque(raw).takeRetainedValue()
        deviceList = arr
        var found: [UnsafeMutableRawPointer] = []
        for i in 0..<CFArrayGetCount(arr) {
            guard let p = CFArrayGetValueAtIndex(arr, i) else { continue }
            let dev = UnsafeMutableRawPointer(mutating: p)
            var f: Int32 = -1
            _ = fam?(dev, &f)
            if debugLog { log("MT thiết bị #\(i) family=\(f)\(touchFamilies.contains(f) ? " ← dùng" : "")") }
            if touchFamilies.contains(f) { found.append(dev) }
        }
        let reg = unsafeBitCast(sReg, to: MTFnReg.self)
        let startFn = unsafeBitCast(sStart, to: MTFnStart.self)
        for dev in found { reg(dev, touchCallback); startFn(dev, 0) }
        devices = found
        runningMode = touchMode
        runningFamilies = touchFamilies
        if debugLog { log("Cảm ứng: bắt đầu với \(found.count) thiết bị, chế độ \(touchMode.rawValue)") }
    }

    func stop() {
        if let h = lib {
            let unreg = dlsym(h, "MTUnregisterContactFrameCallback").map { unsafeBitCast($0, to: MTFnUnreg.self) }
            let stopFn = dlsym(h, "MTDeviceStop").map { unsafeBitCast($0, to: MTFnStop.self) }
            for dev in devices { unreg?(dev, touchCallback); stopFn?(dev) }
        }
        devices.removeAll()
        deviceList = nil
        runningMode = .off
        inSession = false
        lastCount = 0
    }

    // MARK: Xử lý khung hình

    func process(_ pts: [TouchPoint], timestamp: Double) {
        guard isRunning else { return }
        let active = pts.filter { $0.state == 3 || $0.state == 4 }
        if active.isEmpty {
            if inSession { endSession(timestamp) }
            return
        }
        let n = Float(active.count)
        let c = (x: active.reduce(0) { $0 + $1.x } / n, y: active.reduce(0) { $0 + $1.y } / n)
        if !inSession {
            inSession = true
            startTime = timestamp; startCentroid = c; lastCentroid = c
            maxFingers = active.count; lastCount = active.count; travel = 0
            scrollRemX = 0; scrollRemY = 0
            cursorDecided = false; bufX = 0; bufY = 0
            return
        }
        maxFingers = max(maxFingers, active.count)
        if active.count != lastCount {      // tránh nhảy khi đổi số ngón
            lastCentroid = c; lastCount = active.count
            if active.count > 1 { cursorDecided = true; bufX = 0; bufY = 0 }
            return
        }
        let dx = c.x - lastCentroid.x, dy = c.y - lastCentroid.y
        travel += hypotf(dx, dy)
        lastCentroid = c
        guard touchMode == .cursor else { return }
        if active.count == 1 { steer(dx, dy, c, timestamp) } else { cursorDecided = true; scroll(dx, dy) }
    }

    /// Một ngón: nếu chuyển động trông như cú vuốt đã gán hành động thì giữ con trỏ đứng yên,
    /// ngược lại (di chuyển chậm, hướng chéo, hướng chưa gán, hoặc quá 0,3 s) mới cho con trỏ chạy.
    private func steer(_ dx: Float, _ dy: Float, _ c: (x: Float, y: Float), _ ts: Double) {
        if cursorDecided { moveCursor(dx, dy); return }
        bufX += dx; bufY += dy
        let ddx = c.x - startCentroid.x, ddy = c.y - startCentroid.y
        let adx = abs(ddx), ady = abs(ddy)
        let far = max(adx, ady)
        var decide = mouseButtonDown || ts - startTime >= 0.45      // quá lâu: chắc chắn không phải cú vuốt
        if !decide {
            let dominant = far >= 2 * min(adx, ady)
            let key = adx > ady ? (ddx > 0 ? "SWIPERIGHT" : "SWIPELEFT") : (ddy > 0 ? "SWIPEUP" : "SWIPEDOWN")
            if far >= 0.06, dominant, controller.action(for: key) == nil { decide = true }   // hướng chưa gán cử chỉ
            else if far >= 0.12, !dominant { decide = true }                                  // đi chéo rõ ràng
        }
        guard decide else { return }
        cursorDecided = true
        moveCursor(bufX, bufY)
        bufX = 0; bufY = 0
    }

    private func endSession(_ ts: Double) {
        inSession = false
        lastCount = 0
        let dur = ts - startTime
        let dx = lastCentroid.x - startCentroid.x, dy = lastCentroid.y - startCentroid.y
        let fingers = maxFingers
        if debugLog { log("TOUCH kết thúc: ngón=\(fingers) dx=\(dx) dy=\(dy) thời gian=\(dur) quãng=\(travel)") }
        if fingers == 1 {
            let minDist: Float = touchMode == .cursor ? 0.3 : 0.2
            let maxTime = touchMode == .cursor ? 0.4 : 0.7
            let adx = abs(dx), ady = abs(dy)
            if dur < maxTime, max(adx, ady) >= minDist, max(adx, ady) >= 2 * min(adx, ady) {
                let key = adx > ady ? (dx > 0 ? "SWIPERIGHT" : "SWIPELEFT") : (dy > 0 ? "SWIPEUP" : "SWIPEDOWN")
                fire(key)
                return
            }
            if travel >= 0.04, touchMode == .cursor, !cursorDecided { moveCursor(bufX, bufY) }   // không phải vuốt: trả lại chuyển động đã giữ
            else if tapClick, dur < 0.25, travel < 0.04 { click() }
        } else if fingers == 2, dur < 0.25, travel < 0.06 {
            fire("TWOFINGERTAP")
        }
    }

    // MARK: Hành động

    private func fire(_ key: String) {
        guard let a = controller.action(for: key) else { return }
        switch a {
        case .click: click()
        case .scroll(let dir):
            CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                    wheel1: dir * 300, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
        default: a.run()
        }
    }

    private func click() {
        let pos = CGEvent(source: nil)?.location ?? .zero
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: pos, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
    }

    private func screenBounds() -> CGRect {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        CGGetActiveDisplayList(16, &ids, &count)
        var r = CGRect.null
        for i in 0..<Int(count) { r = r.union(CGDisplayBounds(ids[i])) }
        return r
    }

    private func moveCursor(_ dx: Float, _ dy: Float) {
        let d = Double(hypotf(dx, dy))
        let k = touchSpeed * (1.0 + min(d * 20.0, 2.0)) * 1400.0     // điểm ảnh trên một đơn vị chuẩn hóa
        var pos = CGEvent(source: nil)?.location ?? .zero
        pos.x += Double(dx) * k
        pos.y -= Double(dy) * k                                     // trục y của cảm ứng hướng lên
        let b = screenBounds()
        if !b.isNull {
            pos.x = min(max(pos.x, b.minX), b.maxX - 1)
            pos.y = min(max(pos.y, b.minY), b.maxY - 1)
        }
        let type: CGEventType = mouseButtonDown ? .leftMouseDragged : .mouseMoved
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: pos, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    private func scroll(_ dx: Float, _ dy: Float) {
        let sign: Float = naturalScroll ? -1 : 1
        let k = Float(scrollSpeed) * 1500
        scrollRemY += dy * k * sign
        scrollRemX += dx * k * -sign
        let v = Int32(scrollRemY), h = Int32(scrollRemX)
        guard v != 0 || h != 0 else { return }
        scrollRemY -= Float(v); scrollRemX -= Float(h)
        CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                wheel1: v, wheel2: h, wheel3: 0)?.post(tap: .cghidEventTap)
    }
}


extension TouchMode {
    var title: String {
        switch self {
        case .cursor: return "Con trỏ"
        case .swipe: return "Vuốt/chạm"
        case .off: return "Tắt"
        }
    }
}
