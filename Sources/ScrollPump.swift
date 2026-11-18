// ScrollPump.swift
// "Bơm cuộn": xuất sự kiện cuộn đều đặn theo tần số màn hình (60/120 Hz) trên một luồng riêng ưu tiên cao.
//
// Vì sao: khung cảm ứng từ remote đến qua Bluetooth với nhịp không đều (dồn cục), và luồng chính có thể bận.
// Nếu mỗi khung cảm ứng bắn ngay một sự kiện cuộn thì Safari cuộn giật theo nhịp đó.
//
// Cách làm (giống làm mượt chuyển động trong game):
// - Ghi lại đường đi của ngón theo DẤU THỜI GIAN LẤY MẪU của touchpad (không theo lúc gói Bluetooth tới).
// - Mỗi khung hình, "vẽ" vị trí ngón tại thời điểm (bây giờ − 45 ms) bằng nội suy tuyến tính → ngón đi đều thì trang đi đều.
// - Nhấc tay: quán tính v(t) = v0·e^(−3,1t) như đuôi trackpad thật (đo bằng ScrollSniffer, xem scroll.log).

import Cocoa

final class ScrollPump {
    static let shared = ScrollPump()

    private enum Mode { case idle, finger, momentum }

    private let q = DispatchQueue(label: "siriremote.scrollpump", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private let hz: Double
    private var mode = Mode.idle
    private var velX = 0.0, velY = 0.0          // vận tốc quán tính (điểm ảnh / giây)
    private var carryX = 0.0, carryY = 0.0      // phần lẻ dưới 1 điểm ảnh
    private var began = false                   // đã gửi pha "bắt đầu" của lượt cuộn ngón tay
    private var momentumFirst = true
    private var lastTick = 0.0

    // Đường đi của ngón: (thời điểm theo đồng hồ máy, vị trí cộng dồn)
    private var samples: [(t: Double, x: Double, y: Double)] = []
    private var cumX = 0.0, cumY = 0.0
    private var renderedX = 0.0, renderedY = 0.0
    private var clockOffset: Double?            // đồng hồ máy − đồng hồ touchpad (lấy gói tới sớm nhất)
    private var releasing = false
    private var releaseMomentum = true

    /// Vẽ trễ để luôn có dữ liệu hai phía mà nội suy: theo tuỳ chọn "Độ mượt khi cuộn" (0 → 0 ms, 1 → 80 ms).
    private static var delay: Double { min(max(scrollSmooth, 0), 1) * 0.08 }
    private static let friction = 3.1           // quán tính: v(t) = v0·e^(−3,1t) (~0,95 mỗi khung 60 Hz như trackpad thật)
    private static let maxSpeed = 9000.0

    private init() {
        let screens = Thread.isMainThread ? NSScreen.screens : DispatchQueue.main.sync { NSScreen.screens }
        hz = Double(max(screens.map { $0.maximumFramesPerSecond }.max() ?? 60, 60))
    }

    // MARK: Giao tiếp (gọi từ bất kỳ luồng nào)

    /// Ngón tay vừa đi thêm (dx, dy) điểm ảnh (y dương = cuộn lên, x dương = sang trái).
    /// ts: dấu thời gian lấy mẫu của touchpad (giây); nil thì dùng lúc gọi.
    func feed(_ dx: Double, _ dy: Double, ts: Double? = nil) {
        let arrival = now()
        q.async { [self] in
            if mode == .momentum { endMomentum() }
            if mode != .finger {
                mode = .finger; began = false; releasing = false
                samples.removeAll(); cumX = 0; cumY = 0; renderedX = 0; renderedY = 0
                carryX = 0; carryY = 0; clockOffset = nil
            }
            var t = arrival
            if let ts = ts {
                let o = arrival - ts
                if let old = clockOffset, o < old {
                    // gói này tới nhanh hơn: đồng hồ quy đổi sớm hơn → dời cả đường đi cũ theo cho nhất quán
                    let shift = o - old
                    samples = samples.map { ($0.t + shift, $0.x, $0.y) }
                    clockOffset = o
                } else if clockOffset == nil {
                    clockOffset = o
                }
                t = ts + clockOffset!
            }
            if samples.isEmpty {                                            // điểm xuất phát
                samples.append((t - 1 / 60, 0, 0))
            }
            t = max(t, samples.last!.t + 0.0005)
            cumX += dx; cumY += dy
            samples.append((t, cumX, cumY))
            if samples.count > 64 { samples.removeFirst(samples.count - 64) }
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
                if began { postScroll(v: 0, h: 0, phase: 4) }
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
            if mode == .finger, began { postScroll(v: 0, h: 0, phase: 4) }
            carryX = 0; carryY = 0
            let vx = dx * ScrollPump.friction, vy = dy * ScrollPump.friction
            // "chạm" ngắn đúng bằng vận tốc đầu (để Safari nhận đây là cú cuộn trackpad), rồi quán tính
            let dt = 1 / hz
            postScroll(v: 0, h: 0, phase: 128)
            emitRaw(vx * dt, vy * dt, phase: 1)
            postScroll(v: 0, h: 0, phase: 4)
            velX = vx; velY = vy
            mode = .momentum
            momentumFirst = true
            ensureTimer()
        }
    }

    // MARK: Bên trong (chỉ chạy trên q)

    private func now() -> Double { ProcessInfo.processInfo.systemUptime }

    private func ensureTimer() {
        guard timer == nil else { return }
        lastTick = now()
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: q)
        let ns = Int(1_000_000_000 / hz)
        t.schedule(deadline: .now() + .nanoseconds(ns), repeating: .nanoseconds(ns), leeway: .microseconds(200))
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
    }

    private func stopTimer() { timer?.cancel(); timer = nil }

    /// Vị trí ngón tại thời điểm r (nội suy tuyến tính giữa hai mẫu kề nhau; ngoài khoảng thì giữ đầu mút).
    private func position(at r: Double) -> (Double, Double) {
        guard let first = samples.first, let last = samples.last else { return (0, 0) }
        if r <= first.t { return (first.x, first.y) }
        if r >= last.t { return (last.x, last.y) }
        var i = samples.count - 1
        while i > 0 && samples[i - 1].t > r { i -= 1 }
        let a = samples[i - 1], b = samples[i]
        let u = (r - a.t) / max(b.t - a.t, 1e-6)
        return (a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u)
    }

    /// Vận tốc lúc nhấc tay: độ dốc đường đi trong ~60 ms cuối (theo thời gian lấy mẫu).
    private func releaseVelocity() -> (Double, Double) {
        guard let last = samples.last else { return (0, 0) }
        let s = samples.last(where: { last.t - $0.t >= 0.06 }) ?? samples.first!
        let span = last.t - s.t
        guard span >= 0.012 else { return (0, 0) }
        return ((last.x - s.x) / span, (last.y - s.y) / span)
    }

    private func finishFinger() {
        let last = samples.last.map { ($0.x, $0.y) } ?? (renderedX, renderedY)
        emit(last.0 - renderedX, last.1 - renderedY, phase: began ? 2 : 1, momentum: 0)
        renderedX = last.0; renderedY = last.1
        if began { postScroll(v: 0, h: 0, phase: 4) }
        began = false
        releasing = false
        (velX, velY) = releaseVelocity()
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
        if !momentumFirst { postScroll(v: 0, h: 0, phase: 0, momentum: 3) }
        mode = .idle
        velX = 0; velY = 0
    }

    private func tick() {
        let t = now()
        let dt = min(max(t - lastTick, 0.002), 0.05)
        lastTick = t
        switch mode {
        case .idle:
            stopTimer()
        case .finger:
            let r = t - ScrollPump.delay
            if releasing, let last = samples.last, r >= last.t { finishFinger(); return }
            let p = position(at: r)
            emit(p.0 - renderedX, p.1 - renderedY, phase: began ? 2 : 1, momentum: 0)
            renderedX = p.0; renderedY = p.1
        case .momentum:
            let f = exp(-ScrollPump.friction * dt)
            velX *= f; velY *= f
            if hypot(velX, velY) < 50 { endMomentum(); stopTimer(); return }     // trackpad thật dừng ở ~1 px/khung
            emit(velX * dt, velY * dt, phase: 0, momentum: momentumFirst ? 1 : 2)
        }
    }

    /// Gửi phần nguyên của quãng (cộng dồn phần lẻ). Pha "bắt đầu"/quán tính đầu chỉ tính khi thật sự gửi.
    private func emit(_ x: Double, _ y: Double, phase: Int64, momentum: Int64) {
        carryX += x; carryY += y
        let h = Int32(carryX.rounded(.towardZero)), v = Int32(carryY.rounded(.towardZero))
        guard h != 0 || v != 0 else { return }
        carryX -= Double(h); carryY -= Double(v)
        postScroll(v: v, h: h, phase: phase, momentum: momentum)
        if mode == .finger { began = true }
        if momentum != 0 { momentumFirst = false }
    }

    private func emitRaw(_ x: Double, _ y: Double, phase: Int64) {
        carryX += x; carryY += y
        let h = Int32(carryX.rounded(.towardZero)), v = Int32(carryY.rounded(.towardZero))
        carryX -= Double(h); carryY -= Double(v)
        postScroll(v: v, h: h, phase: phase)
    }
}
