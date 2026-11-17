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
    let timer = DispatchSource.makeTimerSource(flags: .strict, queue: DispatchQueue(label: "siriremote.navswipe", qos: .userInteractive))
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
    private var lastFrameTime = 0.0
    private var frameDt = 1.0 / 60
    // Click chính xác: nhớ vị trí con trỏ vài trăm ms gần nhất để lấy lại khi nhấn touchpad
    private var cursorHistory: [(t: Double, p: CGPoint)] = []
    private var pressTravel: Float = 0
    // Chạm rồi kéo
    private var lastTapEnd = -10.0
    private var tapDragging = false
    // Cuộn có quán tính
    private var scrollSamples: [(t: Double, x: Float, y: Float)] = []
    private var didScroll = false
    private var inertiaTimer: Timer?
    private var inertiaActive = false
    private var scrollStarted = false
    private var smoothX: Float = 0
    private var smoothY: Float = 0

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
        stopInertia()
        if scrollStarted { scrollStarted = false; postScroll(v: 0, h: 0, phase: 4) }
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
            maxFingers = active.count; lastCount = active.count; travel = 0
            scrollRemX = 0; scrollRemY = 0
            cursorDecided = false; bufX = 0; bufY = 0
            didScroll = false; scrollSamples.removeAll(); smoothX = 0; smoothY = 0
            stopInertia()                                   // chạm vào là dừng cuộn quán tính
            if tapClick, touchMode == .cursor, active.count == 1, timestamp - lastTapEnd < 0.3 {
                tapDragging = true                          // chạm rồi đặt ngón xuống ngay: giữ chuột để kéo
                cursorDecided = true
                mouseButtonDown = true
                postMouse(.leftMouseDown, at: currentPos(), clickState: 2)
            }
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
            finishScroll(endTime: ts)
            return
        }
        if fingers == 1 {
            let minDist: Float = touchMode == .cursor ? 0.3 : 0.2
            let maxTime = touchMode == .cursor ? 0.4 : 0.7
            let adx = abs(dx), ady = abs(dy)
            if dur < maxTime, max(adx, ady) >= minDist, max(adx, ady) >= 2 * min(adx, ady) {
                let key = adx > ady ? (dx > 0 ? "SWIPERIGHT" : "SWIPELEFT") : (dy > 0 ? "SWIPEUP" : "SWIPEDOWN")
                fire(key)
                return
            }
            if travel >= 0.04, touchMode == .cursor, !cursorDecided { moveCursor(bufX, bufY, dt: dur) }   // không phải vuốt: trả lại chuyển động đã giữ
            else if tapClick, dur < 0.25, travel < 0.04 {
                click()
                if touchMode == .cursor { lastTapEnd = ts }
            }
        } else if fingers == 2, dur < 0.25, travel < 0.06 {
            twoFingerTap(at: ts)
        }
    }

    // MARK: Hành động

    /// Chạm 2 ngón: nếu có gán "chạm đúp 2 ngón" thì chờ 0,3 s xem có lần chạm thứ hai không (đúp → zoom thông minh…);
    /// không có lần hai thì chạy hành động chạm đơn như bình thường.
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

    // Vị trí con trỏ: dùng lại vị trí vừa gửi nếu còn mới (tránh hỏi hệ thống ở từng khung hình)
    func notePosition(_ p: CGPoint) { lastPos = p; lastPosTime = ProcessInfo.processInfo.systemUptime }
    private var lastPos = CGPoint.zero
    private var lastPosTime = 0.0
    private func currentPos() -> CGPoint {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastPosTime < 0.05 { return lastPos }
        return CGEvent(source: nil)?.location ?? .zero
    }

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
        let now = ProcessInfo.processInfo.systemUptime
        cursorHistory.removeAll { now - $0.t > 0.5 }
        if let h = cursorHistory.last(where: { now - $0.t >= 0.12 }) { return h.p }
        return cursorHistory.first?.p
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
        let v = Double(hypotf(dx, dy)) / max(dt ?? frameDt, 0.004)          // đơn vị chuẩn hóa / giây
        let gain = 0.55 + 2.4 * (1 - exp(-v / 1.4))
        let k = touchSpeed * 800.0 * gain                                  // điểm ảnh trên một đơn vị chuẩn hóa
        var pos = currentPos()
        pos.x += Double(dx) * k
        pos.y -= Double(dy) * k                                            // trục y của cảm ứng hướng lên
        let b = screenBounds()
        if !b.isNull {
            pos.x = min(max(pos.x, b.minX), b.maxX - 1)
            pos.y = min(max(pos.y, b.minY), b.maxY - 1)
        }
        let type: CGEventType = mouseButtonDown ? .leftMouseDragged : .mouseMoved
        if let e = CGEvent(mouseEventSource: mouseSource, mouseType: type, mouseCursorPosition: pos, mouseButton: .left) {
            e.flags = []
            e.setDoubleValueField(.mouseEventDeltaX, value: Double(dx) * k)
            e.setDoubleValueField(.mouseEventDeltaY, value: -Double(dy) * k)
            e.post(tap: .cghidEventTap)
        }
        let now = ProcessInfo.processInfo.systemUptime
        lastPos = pos; lastPosTime = now
        cursorHistory.append((now, pos))
        cursorHistory.removeAll { now - $0.t > 0.5 }
    }

    private func scroll(_ dx: Float, _ dy: Float) {
        let sign: Float = naturalScroll ? -1 : 1
        let k = Float(scrollSpeed) * 1500
        // làm mượt nhẹ (lọc thông thấp) để cuộn không bị khựng khi khung cảm ứng đến không đều
        smoothX = smoothX * 0.35 + dx * k * -sign * 0.65
        smoothY = smoothY * 0.35 + dy * k * sign * 0.65
        let px = smoothX, py = smoothY
        didScroll = true
        scrollSamples.append((lastFrameTime, px, py))
        if scrollSamples.count > 8 { scrollSamples.removeFirst() }
        emitScroll(px, py, phase: scrollStarted ? 2 : 1)
        scrollStarted = true
    }

    /// Gửi sự kiện cuộn (điểm ảnh), cộng dồn phần lẻ.
    private func emitScroll(_ x: Float, _ y: Float, phase: Int64, momentum: Int64 = 0) {
        scrollRemX += x; scrollRemY += y
        let v = Int32(scrollRemY), h = Int32(scrollRemX)
        guard v != 0 || h != 0 else { return }
        scrollRemY -= Float(v); scrollRemX -= Float(h)
        postScroll(v: v, h: h, phase: phase, momentum: momentum)
    }

    /// Nhấc tay sau khi cuộn: gửi "ended", rồi (nếu bật) quán tính theo pha momentum của hệ thống.
    private func finishScroll(endTime: Double) {
        scrollStarted = false
        smoothX = 0; smoothY = 0
        postScroll(v: 0, h: 0, phase: 4)
        if scrollMomentum { startInertia(endTime: endTime) }
    }

    // MARK: Cuộn quán tính

    private func startInertia(endTime: Double) {
        let recent = scrollSamples.filter { endTime - $0.t < 0.1 }
        guard recent.count >= 2, let first = recent.first, let last = recent.last, endTime - last.t < 0.06 else { return }
        let span = Float(max(last.t - first.t, 0.016) + frameDt)
        var vx = max(min(recent.reduce(0) { $0 + $1.x } / span, 6000), -6000)       // điểm ảnh / giây
        var vy = max(min(recent.reduce(0) { $0 + $1.y } / span, 6000), -6000)
        guard abs(vx) > 150 || abs(vy) > 150 else { return }
        scrollRemX = 0; scrollRemY = 0
        var firstTick = true
        inertiaActive = true
        inertiaTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            vx *= 0.955; vy *= 0.955                                                // ma sát: giảm dần
            if abs(vx) < 30 && abs(vy) < 30 { self.stopInertia(); return }
            self.emitScroll(vx / 60, vy / 60, phase: 0, momentum: firstTick ? 1 : 2)
            firstTick = false
        }
    }

    private func stopInertia() {
        inertiaTimer?.invalidate()
        inertiaTimer = nil
        if inertiaActive { inertiaActive = false; postScroll(v: 0, h: 0, phase: 0, momentum: 3) }
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
