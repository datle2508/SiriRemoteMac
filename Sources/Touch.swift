// Touch.swift
// Cảm ứng touchpad qua MultitouchSupport: con trỏ, cuộn, vuốt, chạm.

import Cocoa

var navInvert = false
var navDuration = 0.25       // giây
var navDistance = 0.9        // tỉ lệ chiều rộng cửa sổ

/// Khung của cửa sổ phía trước (của app đang ở trên cùng), theo tọa độ màn hình của CGEvent.
func frontWindowFrame() -> CGRect? {
    guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
          let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
    else { return nil }
    for w in list {
        guard (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
              (w[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
              let b = w[kCGWindowBounds as String] as? NSDictionary,
              let r = CGRect(dictionaryRepresentation: b as CFDictionary), r.width > 100, r.height > 100 else { continue }
        return r
    }
    return nil
}

/// Giả lập cú vuốt hai ngón ngang của trackpad (chuỗi sự kiện cuộn có pha: 1 = bắt đầu, 2 = đang vuốt, 4 = kết thúc)
/// để Safari/Chrome chạy hiệu ứng Back/Forward. Hướng: ngón tay sang phải = Back.
/// Sự kiện cuộn đi tới cửa sổ dưới con trỏ, nên nếu con trỏ đang ở ngoài cửa sổ phía trước thì đưa nó vào giữa cửa sổ.
func navSwipe(back: Bool) {
    let dir: Double = (back ? 1 : -1) * (navInvert ? -1 : 1)
    if let r = frontWindowFrame() {
        let cur = CGEvent(source: nil)?.location ?? .zero
        if !r.contains(cur) { CGWarpMouseCursorPosition(CGPoint(x: r.midX, y: r.midY)) }
    }
    let width = frontWindowFrame()?.width ?? CGDisplayBounds(CGMainDisplayID()).width
    let total = max(width * navDistance, 600)          // tổng quãng (gồm cả quán tính)

    // Dựng sẵn toàn bộ chuỗi sự kiện giống trackpad thật (đã đo bằng ScrollSniffer):
    // mayBegin(128) → began(1) → changed(2) tăng dần mượt → ended(4) → momentum(1,2,2,…) giảm dần → momentum end(3), 60 sự kiện/giây.
    struct Frame { var delta: Double; var phase: Int64; var momentum: Int64 }
    var frames: [Frame] = [Frame(delta: 0, phase: 128, momentum: 0)]
    let n = max(Int((navDuration * 60).rounded()), 6)           // số khung của giai đoạn vuốt
    let decay = 0.93                                             // quán tính: mỗi khung còn 93%
    // peak sao cho: tổng vuốt (ramp ~ nửa đỉnh) + tổng quán tính (peak/(1-decay)) = total
    let peak = total / (Double(n) * 0.5 + 1.0 / (1 - decay))
    for k in 1...n {
        let t = Double(k) / Double(n)
        let v = peak * (t * t * (3 - 2 * t) * 0.85 + 0.15 * t)   // tăng mượt, đạt đỉnh lúc nhấc tay
        frames.append(Frame(delta: v, phase: k == 1 ? 1 : 2, momentum: 0))
    }
    frames.append(Frame(delta: 0, phase: 4, momentum: 0))
    var v = peak * decay
    var first = true
    while v >= 1 {
        frames.append(Frame(delta: v, phase: 0, momentum: first ? 1 : 2))
        first = false
        v *= decay
    }
    frames.append(Frame(delta: 0, phase: 0, momentum: 3))

    var carry = 0.0
    func post(_ f: Frame) {
        carry += f.delta * dir
        let d = Int32(carry.rounded())
        carry -= Double(d)
        postScroll(v: 0, h: d, phase: f.phase, momentum: f.momentum)
    }

    navTimer?.cancel()
    var idx = 0
    let timer = DispatchSource.makeTimerSource(flags: .strict, queue: navQueue)
    timer.schedule(deadline: .now(), repeating: .microseconds(16667), leeway: .microseconds(300))
    timer.setEventHandler {
        // mỗi nhịp gửi đúng 1 khung (không dồn); nếu trễ quá 2 khung thì gộp delta để không mất quãng
        guard idx < frames.count else { timer.cancel(); return }
        post(frames[idx])
        idx += 1
        if idx >= frames.count { timer.cancel() }
    }
    navTimer = timer
    timer.resume()
}

private var navTimer: DispatchSourceTimer?
private let navQueue = DispatchQueue(label: "siriremote.navswipe", qos: .userInteractive)
/// Cuộn mượt một quãng (điểm ảnh) như cú hất nhanh hai ngón trên trackpad, thay cho một bước nhảy cứng.
func smoothScroll(v: Double, h: Double) { ScrollPump.shared.fling(h, v) }

/// Gửi một sự kiện cuộn "như trackpad": liên tục (pixel) kèm pha cuộn (1 bắt đầu, 2 đang cuộn, 4 nhấc tay, 128 mayBegin)
/// hoặc pha quán tính (1 bắt đầu, 2 tiếp tục, 3 kết thúc). Cấu trúc theo bản ghi ScrollSniffer của trackpad thật.
func postScroll(v: Int32, h: Int32, phase: Int64, momentum: Int64 = 0) {
    guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                          wheel1: v, wheel2: h, wheel3: 0) else { return }
    func setI(_ id: UInt32, _ val: Int64) { if let f = CGEventField(rawValue: id) { e.setIntegerValueField(f, value: val) } }
    func setD(_ id: UInt32, _ val: Double) { if let f = CGEventField(rawValue: id) { e.setDoubleValueField(f, value: val) } }
    setI(88, 1)                                                  // isContinuous
    if momentum == 0 { setI(99, phase) } else { setI(123, momentum); setI(173, momentum) }
    if phase != 0 || momentum != 0 { setI(100, 1) }              // scrollCount
    setI(137, 1)
    if h != 0 { setD(175, -Double(h) / 10.0); setD(177, -Double(h) * 0.75) }
    e.post(tap: .cghidEventTap)
}

/// Đổi qua lại giữa chế độ con trỏ và chế độ vuốt/chạm; lưu vào file cấu hình.
func toggleTouchMode() {
    var c = ConfigFile.load()
    let next = touchMode == .cursor ? "swipe" : "cursor"
    c.global["touchmode"] = next
    c.save()
    controller.reloadMap()
    NSSound(named: NSSound.Name(next == "cursor" ? "Pop" : "Tink"))?.play()
    appDelegate.flash(next == "cursor" ? T("Con trỏ") : T("Vuốt/chạm"))
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

/// Bộ lọc One Euro (Casiez 2012) cho toạ độ ngón: đi chậm lọc mạnh (khử rung), đi nhanh lọc nhẹ (ít trễ).
/// Đo trên Siri Remote đời 1: khi rê, mỗi gói lệch ~15–21 % so với chuyển động trung bình → con trỏ đi không đều.
struct OneEuro {
    var minCutoff: Double, beta: Double
    private var x = 0.0, y = 0.0, dx = 0.0, dy = 0.0, primed = false
    init(minCutoff: Double, beta: Double) { self.minCutoff = minCutoff; self.beta = beta }
    mutating func reset(_ px: Double, _ py: Double) { x = px; y = py; dx = 0; dy = 0; primed = true }
    private static func alpha(_ cutoff: Double, _ dt: Double) -> Double { let r = 2 * .pi * cutoff * dt; return r / (r + 1) }
    mutating func filter(_ px: Double, _ py: Double, dt: Double) -> (Double, Double) {
        guard primed else { reset(px, py); return (px, py) }
        let ad = OneEuro.alpha(1.0, dt)
        dx += ad * ((px - x) / dt - dx); dy += ad * ((py - y) / dt - dy)
        let a = OneEuro.alpha(minCutoff + beta * hypot(dx, dy), dt)
        x += a * (px - x); y += a * (py - y)
        return (x, y)
    }
}

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
    private var cursorDecided = false       // false: đang giữ con trỏ đứng yên, chờ xem có phải cú vuốt không
    private var bufX: Float = 0
    private var bufY: Float = 0
    private var lastFrameTime = 0.0
    // Toạ độ đã lọc (cho con trỏ / cuộn); nhận dạng vuốt / chạm vẫn dùng toạ độ gốc
    private var euro = OneEuro(minCutoff: 4, beta: 4)
    private var lastFiltered = (x: 0.0, y: 0.0)
    private var cursorSpeed = 0.0                   // tốc độ ngón đã làm mượt (~50 ms), dùng cho gia tốc

    /// Độ mạnh bộ lọc theo "Độ mượt": 0 → không lọc; 55 % → (≈3,8 Hz, β≈3,4); 100 % → (2 Hz, β=1).
    /// (Dò trên bản ghi thật: 55 % giảm độ giật con trỏ 19 % → ~10 %, trễ thêm ~15 ms.)
    private func filtered(_ c: (x: Float, y: Float), reset: Bool) -> (x: Double, y: Double) {
        let s = min(max(scrollSmooth, 0), 1)
        let p = (x: Double(c.x), y: Double(c.y))
        if s < 0.05 { return p }
        euro.minCutoff = 6 - 4 * s
        euro.beta = 15 * pow(1.0 / 15, s)
        if reset { euro.reset(p.x, p.y); return p }
        let f = euro.filter(p.x, p.y, dt: max(frameDt, 0.004))
        return (f.0, f.1)
    }
    private var frameDt = 1.0 / 60
    private var pressTravel: Float = 0
    // Chạm rồi kéo
    private var lastTapEnd = -10.0
    private var tapDragging = false
    // Cuộn có quán tính
    private var didScroll = false

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
        ScrollPump.shared.stop()
        if tapDragging { tapDragging = false; mouseButtonDown = false; postMouse(.leftMouseUp, at: currentPos(), clickState: 2) }
        inSession = false
        lastCount = 0
    }

    // MARK: Xử lý khung hình

    func process(_ pts: [TouchPoint], timestamp: Double) {
        guard isRunning else { return }
        frameDt = min(max(timestamp - lastFrameTime, 0.004), 0.05)
        lastFrameTime = timestamp
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
            lastFiltered = filtered(c, reset: true); cursorSpeed = 0
            maxFingers = active.count; lastCount = active.count; travel = 0
            cursorDecided = false; bufX = 0; bufY = 0
            didScroll = false
            pressedInSession = mouseButtonDown
            scrollAxis = .undecided; axisBufX = 0; axisBufY = 0; scrollVel = 0
            ScrollPump.shared.stop()                        // chạm vào là dừng cuộn quán tính
            if tapClick, touchMode == .cursor, active.count == 1, timestamp - lastTapEnd < 0.3 {
                tapDragging = true                          // chạm rồi đặt ngón xuống ngay: giữ chuột để kéo
                cursorDecided = true
                mouseButtonDown = true
                postMouse(.leftMouseDown, at: currentPos(), clickState: 2)
            }
            return
        }
        maxFingers = max(maxFingers, active.count)
        if mouseButtonDown { pressedInSession = true }
        if active.count != lastCount {      // tránh nhảy khi đổi số ngón
            lastCentroid = c; lastCount = active.count
            lastFiltered = filtered(c, reset: true)
            if active.count > 1 { cursorDecided = true; bufX = 0; bufY = 0 }
            return
        }
        let dx = c.x - lastCentroid.x, dy = c.y - lastCentroid.y
        travel += hypotf(dx, dy)
        lastCentroid = c
        let f = filtered(c, reset: false)                   // chuyển động đã khử rung cho con trỏ / cuộn
        let fdx = Float(f.x - lastFiltered.x), fdy = Float(f.y - lastFiltered.y)
        lastFiltered = f
        guard touchMode == .cursor else { return }
        if active.count == 1 { steer(fdx, fdy, c, timestamp) } else { cursorDecided = true; scroll(fdx, fdy) }
    }

    /// Một ngón: nếu chuyển động trông như cú vuốt đã gán hành động thì giữ con trỏ đứng yên,
    /// ngược lại (di chuyển chậm, hướng chéo, hướng chưa gán, hoặc quá 0,3 s) mới cho con trỏ chạy.
    private func steer(_ dx: Float, _ dy: Float, _ c: (x: Float, y: Float), _ ts: Double) {
        if cursorDecided { moveCursor(dx, dy); return }
        bufX += dx; bufY += dy
        let ddx = c.x - startCentroid.x, ddy = c.y - startCentroid.y
        let adx = abs(ddx), ady = abs(ddy)
        let far = max(adx, ady)
        let elapsed = ts - startTime
        var decide = mouseButtonDown || elapsed >= 0.45             // quá lâu: chắc chắn không phải cú vuốt
        // Cú vuốt phải đi ≥ 0,3 trong ≤ 0,4 s (~0,75/s). Sau 0,1 s mà còn chậm hơn 0,6/s thì là rê con trỏ:
        // nhả ngay thay vì giữ con trỏ đứng yên tới 0,45 s (gây cảm giác khựng khi rê dọc/ngang).
        if elapsed >= 0.1, Double(hypotf(ddx, ddy)) / elapsed < 0.6 { decide = true }
        if !decide {
            let dominant = far >= 2 * min(adx, ady)
            let key = adx > ady ? (ddx > 0 ? "SWIPERIGHT" : "SWIPELEFT") : (ddy > 0 ? "SWIPEUP" : "SWIPEDOWN")
            if far >= 0.06, dominant, controller.action(for: key) == nil { decide = true }   // hướng chưa gán cử chỉ
            else if far >= 0.12, !dominant { decide = true }                                  // đi chéo rõ ràng
        }
        guard decide else { return }
        cursorDecided = true
        moveCursor(bufX, bufY, dt: ts - startTime)
        bufX = 0; bufY = 0
    }

    private func endSession(_ ts: Double) {
        inSession = false
        lastCount = 0
        let dur = ts - startTime
        let dx = lastCentroid.x - startCentroid.x, dy = lastCentroid.y - startCentroid.y
        let fingers = maxFingers
        if debugLog { log("TOUCH kết thúc: ngón=\(fingers) dx=\(dx) dy=\(dy) thời gian=\(dur) quãng=\(travel)") }
        if tapDragging {                                    // nhả chuột sau khi kéo
            tapDragging = false; mouseButtonDown = false
            postMouse(.leftMouseUp, at: currentPos(), clickState: 2)
            lastTapEnd = -10
            return
        }
        if didScroll {                                      // vừa cuộn hai ngón: tiếp tục cuộn giảm dần
            didScroll = false
            finishScroll()
            return
        }
        if fingers == 1 {
            let minDist: Float = touchMode == .cursor ? 0.3 : 0.2
            let maxTime = touchMode == .cursor ? 0.4 : 0.7
            let adx = abs(dx), ady = abs(dy)
            if dur < maxTime, max(adx, ady) >= minDist, max(adx, ady) >= 2 * min(adx, ady) {
                let key = adx > ady ? (dx > 0 ? "SWIPERIGHT" : "SWIPELEFT") : (dy > 0 ? "SWIPEUP" : "SWIPEDOWN")
                // tốc độ vuốt (đơn vị chuẩn hoá / giây): vuốt nhanh thì cuộn xa hơn, như trackpad
                fire(key, speed: Double(max(adx, ady)) / max(dur, 0.03))
                return
            }
            if travel >= 0.04, touchMode == .cursor, !cursorDecided { moveCursor(bufX, bufY, dt: dur) }   // không phải vuốt: trả lại chuyển động đã giữ
            else if dur < 0.25, travel < 0.04, !pressedInSession {
                oneFingerTap(at: ts)
            }
        } else if fingers == 2, dur < 0.25, travel < 0.06 {
            twoFingerTap(at: ts)
        }
    }

    // MARK: Hành động

    /// Chạm 2 ngón: nếu có gán "chạm đúp 2 ngón" thì chờ 0,3 s xem có lần chạm thứ hai không (đúp → zoom thông minh…);
    /// không có lần hai thì chạy hành động chạm đơn như bình thường.
    private var pendingTap: DispatchWorkItem?
    private var lastOneTap = -10.0
    private var pressedInSession = false        // đã bấm lún touchpad trong lượt chạm này (không tính là chạm nhẹ)

    /// Chạm nhẹ một ngón. Nếu có gán "chạm đúp 1 ngón" thì chờ 0,3 s xem có lần chạm thứ hai:
    /// có → chạy hành động chạm đúp (không click); không → click như bình thường (nếu bật Chạm nhẹ để click).
    /// Khi đã gán chạm đúp, "chạm rồi giữ để kéo" tạm tắt để hai lần chạm không thành kéo thả.
    private func oneFingerTap(at ts: Double) {
        guard controller.action(for: "DOUBLETAP") != nil else {
            if tapClick {
                click()
                if touchMode == .cursor { lastTapEnd = ts }
            }
            return
        }
        if let p = pendingTap, ts - lastOneTap < 0.4 {
            p.cancel(); pendingTap = nil
            fire("DOUBLETAP")
            return
        }
        lastOneTap = ts
        let work = DispatchWorkItem { [weak self] in
            self?.pendingTap = nil
            if tapClick { self?.click() }
        }
        pendingTap = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private var pendingTwoTap: DispatchWorkItem?
    private var lastTwoTap = -10.0

    private func twoFingerTap(at ts: Double) {
        guard controller.action(for: "TWOFINGERDOUBLETAP") != nil else { fire("TWOFINGERTAP"); return }
        if let p = pendingTwoTap, ts - lastTwoTap < 0.4 {
            p.cancel(); pendingTwoTap = nil
            fire("TWOFINGERDOUBLETAP")
            return
        }
        lastTwoTap = ts
        let work = DispatchWorkItem { [weak self] in
            self?.pendingTwoTap = nil
            self?.fire("TWOFINGERTAP")
        }
        pendingTwoTap = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func fire(_ key: String, speed: Double? = nil) {
        notifyRemoteEvent(key.lowercased())
        if debugLog { log("CỬ CHỈ \(key) → \(controller.action(for: key).map { "\($0)" } ?? "không gán")") }
        guard let a = controller.action(for: key) else { return }
        // Vuốt gán cuộn: theo "Cuộn tự nhiên" giống cuộn hai ngón (bật = nội dung đi theo ngón tay,
        // vuốt lên → trang cuộn xuống). Nút bấm trên remote không bị ảnh hưởng.
        let flip = key.hasPrefix("SWIPE") && naturalScroll
        switch a {
        case .click: click()
        case .scroll(let dir) where key.hasPrefix("SWIPE"):
            smoothScroll(v: Double(flip ? -dir : dir) * swipeScrollDistance(speed), h: 0)
        case .hscroll(let dir) where key.hasPrefix("SWIPE"):
            smoothScroll(v: 0, h: Double(flip ? -dir : dir) * swipeScrollDistance(speed))
        default: a.run()
        }
    }

    /// Quãng cuộn (điểm ảnh) của một cú vuốt: vuốt chậm ~250 px, vuốt vừa ~500 px, hất mạnh tới ~1300 px.
    private func swipeScrollDistance(_ speed: Double?) -> Double {
        let v = speed ?? 2
        let factor = min(max(0.5 + (v - 1) * 0.5, 0.5), 2.6)
        return 500 * scrollSpeed * factor
    }

    // Vị trí con trỏ do CursorPump giữ (bơm di chuyển con trỏ đều theo khung hình, xem CursorPump.swift)
    func notePosition(_ p: CGPoint) { CursorPump.shared.warp(to: p) }
    private func currentPos() -> CGPoint { CursorPump.shared.position() }

    private func click() {
        let pos = currentPos()
        postMouse(.leftMouseDown, at: pos)
        postMouse(.leftMouseUp, at: pos)
    }

    /// Gọi khi touchpad vừa bị nhấn: trả về vị trí con trỏ khoảng 0,12 s trước đó (trước khi ngón tay lăn đi
    /// do lực nhấn) để click trúng đích; nil nếu không cần.
    func beginPress() -> CGPoint? {
        pressTravel = 0
        guard clickSteady, touchMode == .cursor, !tapDragging else { return nil }
        return CursorPump.shared.position(ago: 0.12)
    }

    private var cachedBounds: CGRect?
    private func screenBounds() -> CGRect {
        if let b = cachedBounds { return b }
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        CGGetActiveDisplayList(16, &ids, &count)
        var r = CGRect.null
        for i in 0..<Int(count) { r = r.union(CGDisplayBounds(ids[i])) }
        cachedBounds = r
        return r
    }
    func invalidateScreens() { cachedBounds = nil }

    /// dt: thời gian (giây) mà dx, dy đã diễn ra; mặc định là một khung hình.
    private func moveCursor(_ dx: Float, _ dy: Float, dt: Double? = nil) {
        if mouseButtonDown, !tapDragging, clickSteady {     // đang nhấn touchpad: bỏ qua rung nhẹ, chỉ kéo khi thật sự di chuyển
            pressTravel += hypotf(dx, dy)
            if pressTravel < 0.05 { return }
        }
        // Đường cong tăng tốc kiểu trackpad: chậm = chính xác, nhanh = đi xa
        let span = max(dt ?? frameDt, 0.004)
        let inst = Double(hypotf(dx, dy)) / span                          // đơn vị chuẩn hóa / giây
        // tốc độ làm mượt ~50 ms: gia tốc không nhảy theo độ lệch của từng gói
        cursorSpeed = cursorSpeed == 0 ? inst : cursorSpeed + (inst - cursorSpeed) * (1 - exp(-span / 0.05))
        let v = cursorSpeed
        let gain = 0.55 + 2.4 * (1 - exp(-v / 1.4))
        let k = touchSpeed * 800.0 * gain                                  // điểm ảnh trên một đơn vị chuẩn hóa
        // trục y của cảm ứng hướng lên, của màn hình hướng xuống
        CursorPump.shared.feed(Double(dx) * k, -Double(dy) * k, ts: lastFrameTime, bounds: screenBounds())
    }

    // Cuộn kiểu Magic Trackpad: khoá trục + gia tốc, rồi nạp vào ScrollPump (xuất đều theo tần số màn hình).
    private enum ScrollAxis { case undecided, vertical, horizontal, free }
    private var scrollAxis = ScrollAxis.undecided
    private var axisBufX: Float = 0, axisBufY: Float = 0
    private var scrollVel: Double = 0                 // tốc độ ngón (đơn vị chuẩn hoá / giây), làm mượt

    private func scroll(_ dx: Float, _ dy: Float) {
        var dx = dx, dy = dy
        // 1) Khoá trục như trackpad thật: đi gần thẳng dọc/ngang thì bỏ hẳn phần lệch của trục kia
        //    (tránh trang trôi ngang và vô tình kích hoạt vuốt Back/Forward khi đang cuộn dọc).
        if scrollAxis == .undecided {
            axisBufX += dx; axisBufY += dy
            let ax = abs(axisBufX), ay = abs(axisBufY)
            // chờ đủ quãng để biết hướng; chưa đủ thì CHƯA tính là cuộn (để chạm 2 ngón / chạm đúp 2 ngón vẫn nhận được)
            guard hypotf(ax, ay) >= 0.02 else { return }
            scrollAxis = ay >= ax * 1.6 ? .vertical : ax >= ay * 1.6 ? .horizontal : .free
            dx = axisBufX; dy = axisBufY
        }
        switch scrollAxis {
        case .vertical: dx = 0
        case .horizontal: dy = 0
        default: break
        }
        didScroll = true
        // 2) Gia tốc: chậm = chính xác (≈ 1:1), hất nhanh = đi xa (tới ~3,5 lần)
        let dist = Double(hypotf(dx, dy))
        let inst = dist / max(frameDt, 0.004)
        scrollVel += (inst - scrollVel) * 0.35
        let gain = 0.75 + 2.75 * (1 - exp(-scrollVel / 1.6))
        let sign: Double = naturalScroll ? -1 : 1
        let k = scrollSpeed * 1100 * gain
        ScrollPump.shared.feed(Double(dx) * k * -sign, Double(dy) * k * sign, ts: lastFrameTime)   // dấu thời gian lấy mẫu của touchpad
    }

    /// Nhấc tay sau khi cuộn: "ended" rồi (nếu bật) quán tính.
    private func finishScroll() {
        ScrollPump.shared.release(momentum: scrollMomentum)
    }
}

extension TouchMode {
    var title: String {
        switch self {
        case .cursor: return T("Con trỏ")
        case .swipe: return T("Vuốt/chạm")
        case .off: return T("Tắt")
        }
    }
}
