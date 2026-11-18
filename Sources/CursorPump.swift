// CursorPump.swift
// Di chuyển con trỏ đều theo từng khung hình màn hình thay vì nhảy theo từng gói cảm ứng.
//
// Đo trên máy thật (Siri Remote đời 1): touchpad gửi đều mỗi 15 ms (66,7 Hz), Bluetooth gần như không trễ thêm.
// Nhưng màn hình 60 Hz vẽ mỗi 16,7 ms: cứ ~9 khung hình lại có một khung nhận 2 gói → con trỏ nhảy gấp đôi
// khoảng 7 lần mỗi giây ("đôi lúc khựng"). Ở đây đường đi của ngón (đã qua gia tốc) được ghi theo dấu thời gian
// lấy mẫu, rồi mỗi khung hình vẽ vị trí tại (bây giờ − ~20 ms) bằng nội suy → quãng mỗi khung đều nhau.
//
// Bơm cũng giữ vị trí con trỏ hiện tại và lịch sử 0,5 s (cho click / "giữ yên con trỏ khi nhấn").

import Cocoa

final class CursorPump {
    static let shared = CursorPump()

    private let q = DispatchQueue(label: "siriremote.cursorpump", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private let hz: Double

    private var active = false
    private var samples: [(t: Double, x: Double, y: Double)] = []   // đường đi cộng dồn (điểm ảnh)
    private var cumX = 0.0, cumY = 0.0
    private var renderedX = 0.0, renderedY = 0.0
    private var clockOffset: Double?
    private var pos = CGPoint.zero                  // vị trí con trỏ do bơm đặt
    private var bounds = CGRect.null                // vùng màn hình (để kẹp con trỏ)
    private var history: [(t: Double, p: CGPoint)] = []

    /// Vẽ trễ 20 ms (hơn một nhịp gói 15 ms là đủ để nội suy đều; giả lập trên nhịp thật: tăng thêm không mượt hơn).
    /// "Độ mượt" = 0 thì tắt (con trỏ theo gói như cũ); độ mạnh khử rung do bộ lọc One Euro trong TouchEngine đảm nhận.
    private var delay: Double { scrollSmooth < 0.05 ? 0 : 0.02 }

    private init() {
        let screens = Thread.isMainThread ? NSScreen.screens : DispatchQueue.main.sync { NSScreen.screens }
        hz = Double(max(screens.map { $0.maximumFramesPerSecond }.max() ?? 60, 60))
    }

    private func now() -> Double { ProcessInfo.processInfo.systemUptime }

    // MARK: Giao tiếp

    /// Ngón vừa đi thêm (dx, dy) điểm ảnh màn hình (đã qua gia tốc). ts: dấu thời gian lấy mẫu của touchpad.
    func feed(_ dx: Double, _ dy: Double, ts: Double, bounds b: CGRect) {
        let arrival = now()
        q.async { [self] in
            bounds = b
            if !active {
                active = true
                pos = CGEvent(source: nil)?.location ?? pos          // bắt đầu từ vị trí thật (có thể đã dùng chuột khác)
                samples.removeAll(); cumX = 0; cumY = 0; renderedX = 0; renderedY = 0; clockOffset = nil
            }
            let o = arrival - ts
            if let old = clockOffset, o < old {                     // gói tới nhanh hơn: dời đường đi cũ cho nhất quán
                let shift = o - old
                samples = samples.map { ($0.t + shift, $0.x, $0.y) }
                clockOffset = o
            } else if clockOffset == nil {
                clockOffset = o
            }
            var t = ts + clockOffset!
            if samples.isEmpty { samples.append((t - 0.015, 0, 0)) }
            t = max(t, samples.last!.t + 0.0005)
            cumX += dx; cumY += dy
            samples.append((t, cumX, cumY))
            if samples.count > 64 { samples.removeFirst(samples.count - 64) }
            ensureTimer()
        }
    }

    /// Vị trí con trỏ hiện tại (do bơm đặt nếu đang chạy, ngược lại hỏi hệ thống).
    func position() -> CGPoint {
        q.sync { active ? pos : (CGEvent(source: nil)?.location ?? pos) }
    }

    /// Vị trí con trỏ cách đây `ago` giây (nil nếu không có lịch sử gần đây).
    func position(ago: Double) -> CGPoint? {
        q.sync {
            let t = now()
            history.removeAll { t - $0.t > 0.5 }
            return history.last(where: { t - $0.t >= ago })?.p ?? history.first?.p
        }
    }

    /// Con trỏ vừa bị đặt lại (warp): bỏ phần đường đi chưa vẽ, tiếp tục từ vị trí mới.
    func warp(to p: CGPoint) {
        q.sync {
            pos = p
            renderedX = cumX; renderedY = cumY
            history.append((now(), p))
        }
    }

    // MARK: Bên trong (chỉ chạy trên q)

    private func ensureTimer() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: q)
        let ns = Int(1_000_000_000 / (hz * 2))      // gấp đôi tần số màn hình: không lệch pha với nhịp vẽ
        t.schedule(deadline: .now() + .nanoseconds(ns), repeating: .nanoseconds(ns), leeway: .microseconds(200))
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
    }

    private func interp(_ r: Double) -> (Double, Double) {
        guard let first = samples.first, let last = samples.last else { return (renderedX, renderedY) }
        if r <= first.t { return (first.x, first.y) }
        if r >= last.t { return (last.x, last.y) }
        var i = samples.count - 1
        while i > 0 && samples[i - 1].t > r { i -= 1 }
        let a = samples[i - 1], b = samples[i]
        let u = (r - a.t) / max(b.t - a.t, 1e-6)
        return (a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u)
    }

    private func tick() {
        let r = now() - delay
        let p = interp(r)
        let dx = p.0 - renderedX, dy = p.1 - renderedY
        renderedX = p.0; renderedY = p.1
        if abs(dx) >= 0.01 || abs(dy) >= 0.01 {
            var np = CGPoint(x: pos.x + dx, y: pos.y + dy)
            if !bounds.isNull {
                np.x = min(max(np.x, bounds.minX), bounds.maxX - 1)
                np.y = min(max(np.y, bounds.minY), bounds.maxY - 1)
            }
            pos = np
            let type: CGEventType = mouseButtonDown ? .leftMouseDragged : .mouseMoved
            if let e = CGEvent(mouseEventSource: mouseSource, mouseType: type, mouseCursorPosition: np, mouseButton: .left) {
                e.flags = []
                e.setDoubleValueField(.mouseEventDeltaX, value: dx)
                e.setDoubleValueField(.mouseEventDeltaY, value: dy)
                e.post(tap: .cghidEventTap)
            }
            let t = now()
            history.append((t, np))
            if history.count > 90 { history.removeFirst(history.count - 90) }
        }
        // Đã vẽ hết và không còn gói mới ~0,15 s: nghỉ (lần chạm sau đọc lại vị trí thật)
        if let last = samples.last, r > last.t + 0.15 {
            active = false
            timer?.cancel(); timer = nil
        }
    }
}
