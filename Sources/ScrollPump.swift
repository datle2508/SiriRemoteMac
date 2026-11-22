// ScrollPump.swift
// "Bơm cuộn": xuất sự kiện cuộn đều đặn theo tần số màn hình (60/120 Hz) trên một luồng riêng ưu tiên cao.
//
// Vì sao: khung cảm ứng từ remote đến qua Bluetooth với nhịp không đều (dồn cục), và luồng chính có thể bận.
// Nếu mỗi khung cảm ứng bắn ngay một sự kiện cuộn thì Safari cuộn giật theo nhịp đó.
//
// Cách làm (giống làm mượt chuyển động trong game):
// - Ghi lại đường đi của ngón theo DẤU THỜI GIAN LẤY MẪU của touchpad (TouchPath).
// - Mỗi khung hình, "vẽ" vị trí ngón tại thời điểm (bây giờ − trễ) bằng nội suy tuyến tính → ngón đi đều thì trang đi đều.
// - Nhấc tay: quán tính v(t) = v0·e^(−3,1t) như đuôi trackpad thật (đo bằng ScrollSniffer, xem scroll.log).

import Cocoa

final class ScrollPump {
    static let shared = ScrollPump(hz: displayRefreshRate())

    /// (cuộn dọc, cuộn ngang, pha, pha quán tính)
    typealias Post = (_ v: Int32, _ h: Int32, _ phase: Int64, _ momentum: Int64) -> Void

    private enum Mode { case idle, finger, momentum }

    private let q = DispatchQueue(label: "siriremote.scrollpump", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private let hz: Double
    private let clock: () -> Double
    private let post: Post
    private let manualTicks: Bool               // test: không tạo timer, tự gọi step()
    private var manualRunning = false
    private var mode = Mode.idle
    private var velX = 0.0, velY = 0.0          // vận tốc quán tính (điểm ảnh / giây)
    private var carryX = 0.0, carryY = 0.0      // phần lẻ dưới 1 điểm ảnh
    private var began = false                   // đã gửi pha "bắt đầu" của lượt cuộn ngón tay
    private var momentumFirst = true
    private var lastTick = 0.0

    private var path = TouchPath(lead: 1.0 / 60)
    private var renderedX = 0.0, renderedY = 0.0
    private var releasing = false
    private var releaseMomentum = true

    /// Vẽ trễ để luôn có dữ liệu hai phía mà nội suy: theo tuỳ chọn "Độ mượt" (0 → 0 ms, 1 → 80 ms).
    static var delay: Double { min(max(scrollSmooth, 0), 1) * 0.08 }
    static let friction = 3.1                   // quán tính: v(t) = v0·e^(−3,1t) (~0,95 mỗi khung 60 Hz như trackpad thật)
    static let maxSpeed = 9000.0
    static let stopSpeed = 50.0                 // quán tính dừng dưới 50 px/s (trackpad thật dừng ở ~1 px/khung)

    init(hz: Double,
         clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
         post: @escaping Post = { postScroll(v: $0, h: $1, phase: $2, momentum: $3) },
         manualTicks: Bool = false) {
        self.hz = hz; self.clock = clock; self.post = post; self.manualTicks = manualTicks
    }

    // MARK: Giao tiếp (gọi từ bất kỳ luồng nào)

    /// Ngón tay vừa đi thêm (dx, dy) điểm ảnh (y dương = cuộn lên, x dương = sang trái).
    /// ts: dấu thời gian lấy mẫu của touchpad (giây); nil thì dùng lúc gọi.
    func feed(_ dx: Double, _ dy: Double, ts: Double? = nil) {
        let arrival = clock()
        q.async { [self] in
            if mode == .momentum { endMomentum() }
            if mode != .finger {
                mode = .finger; began = false; releasing = false
                path.reset(); renderedX = 0; renderedY = 0
                carryX = 0; carryY = 0
            }
            path.add(dx, dy, ts: ts, arrival: arrival)
            ensureTimer()
        }
    }

    /// Nhấc tay: vẽ nốt phần đường đi còn lại, gửi "ended", rồi quán tính nếu được bật và đang đủ nhanh.
    func release(momentum: Bool) {
        q.async { [self] in
            guard mode == .finger else { return }
            releasing = true
            releaseMomentum = momentum
        }
    }

    /// Chạm lại touchpad: dừng mọi chuyển động đang chạy.
    func stop() {
        q.async { [self] in
            switch mode {
            case .momentum: endMomentum()
            case .finger:
                if began { send(phase: 4) }
                mode = .idle
            case .idle: break
            }
        }
    }

    /// Cuộn một quãng như cú hất hai ngón: một đường vận tốc liền mạch v(t) = v0·e^(−3,1t).
    /// Tổng quãng ≈ (dx, dy).
    func fling(_ dx: Double, _ dy: Double) {
        q.async { [self] in
            if mode == .momentum { endMomentum() }
            if mode == .finger, began { send(phase: 4) }
            carryX = 0; carryY = 0
            let vx = dx * ScrollPump.friction, vy = dy * ScrollPump.friction
            // "chạm" ngắn đúng bằng vận tốc đầu (để Safari nhận đây là cú cuộn trackpad), rồi quán tính
            let dt = 1 / hz
            send(phase: 128)
            emitRaw(vx * dt, vy * dt, phase: 1)
            send(phase: 4)
            velX = vx; velY = vy
            mode = .momentum
            momentumFirst = true
            ensureTimer()
        }
    }

    // MARK: Cho test (chỉ khi manualTicks)

    /// Chờ các lệnh đã gửi (feed, fling…) chạy xong.
    func sync() { q.sync {} }

    /// Chạy một nhịp nếu bơm đang hoạt động; false nếu bơm đã nghỉ.
    @discardableResult func step() -> Bool {
        q.sync {
            guard manualRunning else { return false }
            tick()
            return true
        }
    }

    // MARK: Bên trong (chỉ chạy trên q)

    private func send(v: Int32 = 0, h: Int32 = 0, phase: Int64, momentum: Int64 = 0) {
        post(v, h, phase, momentum)
    }

    private func ensureTimer() {
        if manualTicks {
            if !manualRunning { manualRunning = true; lastTick = clock() }
            return
        }
        guard timer == nil else { return }
        lastTick = clock()
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: q)
        let ns = Int(1_000_000_000 / hz)
        t.schedule(deadline: .now() + .nanoseconds(ns), repeating: .nanoseconds(ns), leeway: .microseconds(200))
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
    }

    private func stopTimer() { timer?.cancel(); timer = nil; manualRunning = false }

    private func finishFinger() {
        let last = path.last.map { ($0.x, $0.y) } ?? (renderedX, renderedY)
        emit(last.0 - renderedX, last.1 - renderedY, phase: began ? 2 : 1, momentum: 0)
        renderedX = last.0; renderedY = last.1
        if began { send(phase: 4) }
        began = false
        releasing = false
        (velX, velY) = path.velocity(window: 0.06)          // độ dốc đường đi trong ~60 ms cuối
        velX = min(max(velX, -ScrollPump.maxSpeed), ScrollPump.maxSpeed)
        velY = min(max(velY, -ScrollPump.maxSpeed), ScrollPump.maxSpeed)
        if releaseMomentum && hypot(velX, velY) > 120 {
            mode = .momentum
            momentumFirst = true
            carryX = 0; carryY = 0
        } else {
            mode = .idle
        }
    }

    private func endMomentum() {
        if !momentumFirst { send(phase: 0, momentum: 3) }
        mode = .idle
        velX = 0; velY = 0
    }

    private func tick() {
        let t = clock()
        let dt = min(max(t - lastTick, 0.002), 0.05)
        lastTick = t
        switch mode {
        case .idle:
            stopTimer()
        case .finger:
            let r = t - ScrollPump.delay
            if releasing, let last = path.last, r >= last.t { finishFinger(); return }
            let p = path.position(at: r)
            emit(p.x - renderedX, p.y - renderedY, phase: began ? 2 : 1, momentum: 0)
            renderedX = p.x; renderedY = p.y
        case .momentum:
            let f = exp(-ScrollPump.friction * dt)
            velX *= f; velY *= f
            if hypot(velX, velY) < ScrollPump.stopSpeed { endMomentum(); stopTimer(); return }
            emit(velX * dt, velY * dt, phase: 0, momentum: momentumFirst ? 1 : 2)
        }
    }

    /// Gửi phần nguyên của quãng (cộng dồn phần lẻ). Pha "bắt đầu"/quán tính đầu chỉ tính khi thật sự gửi.
    private func emit(_ x: Double, _ y: Double, phase: Int64, momentum: Int64) {
        carryX += x; carryY += y
        let h = Int32(carryX.rounded(.towardZero)), v = Int32(carryY.rounded(.towardZero))
        guard h != 0 || v != 0 else { return }
        carryX -= Double(h); carryY -= Double(v)
        send(v: v, h: h, phase: phase, momentum: momentum)
        if mode == .finger { began = true }
        if momentum != 0 { momentumFirst = false }
    }

    private func emitRaw(_ x: Double, _ y: Double, phase: Int64) {
        carryX += x; carryY += y
        let h = Int32(carryX.rounded(.towardZero)), v = Int32(carryY.rounded(.towardZero))
        carryX -= Double(h); carryY -= Double(v)
        send(v: v, h: h, phase: phase)
    }
}
