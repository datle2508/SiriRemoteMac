// CursorPump.swift
// Di chuyển con trỏ đều theo từng khung hình màn hình thay vì nhảy theo từng gói cảm ứng.
//
// Đo trên máy thật (Siri Remote đời 1): touchpad gửi đều mỗi 15 ms (66,7 Hz), Bluetooth gần như không trễ thêm.
// Nhưng màn hình 60 Hz vẽ mỗi 16,7 ms: cứ ~9 khung hình lại có một khung nhận 2 gói → con trỏ nhảy gấp đôi
// khoảng 7 lần mỗi giây ("đôi lúc khựng"). Ở đây đường đi của ngón (đã qua gia tốc) được ghi theo dấu thời gian
// lấy mẫu (TouchPath), rồi mỗi khung hình vẽ vị trí tại (bây giờ − ~20 ms) bằng nội suy → quãng mỗi khung đều nhau.
//
// Bơm cũng giữ vị trí con trỏ hiện tại và lịch sử 0,5 s (cho click / "giữ yên con trỏ khi nhấn").

import Cocoa

final class CursorPump {
    static let shared = CursorPump(hz: displayRefreshRate())

    /// (vị trí mới, dx, dy)
    typealias Post = (_ p: CGPoint, _ dx: Double, _ dy: Double) -> Void

    private let q = DispatchQueue(label: "siriremote.cursorpump", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private let hz: Double
    private let clock: () -> Double
    private let post: Post
    private let systemLocation: () -> CGPoint
    private let manualTicks: Bool               // test: không tạo timer, tự gọi step()

    private var active = false
    private var path = TouchPath(lead: 0.015)
    private var renderedX = 0.0, renderedY = 0.0
    private var pos = CGPoint.zero                  // vị trí con trỏ do bơm đặt
    private var bounds = CGRect.null                // vùng màn hình (để kẹp con trỏ)
    private var history: [(t: Double, p: CGPoint)] = []

    /// Vẽ trễ 20 ms (hơn một nhịp gói 15 ms là đủ để nội suy đều; giả lập trên nhịp thật: tăng thêm không mượt hơn).
    /// "Độ mượt" = 0 thì tắt (con trỏ theo gói như cũ); độ mạnh khử rung do bộ lọc One Euro trong TouchEngine đảm nhận.
    static var delay: Double { scrollSmooth < 0.05 ? 0 : 0.02 }
    /// Thay độ trễ (công cụ phân tích dò tham số); nil = dùng mặc định ở trên.
    var delayOverride: Double?
    private var delay: Double { delayOverride ?? CursorPump.delay }

    init(hz: Double,
         clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
         post: @escaping Post = CursorPump.postMove,
         systemLocation: @escaping () -> CGPoint = { CGEvent(source: nil)?.location ?? .zero },
         manualTicks: Bool = false) {
        self.hz = hz; self.clock = clock; self.post = post
        self.systemLocation = systemLocation; self.manualTicks = manualTicks
    }

    static func postMove(_ p: CGPoint, _ dx: Double, _ dy: Double) {
        let type: CGEventType = mouseButtonDown ? .leftMouseDragged : .mouseMoved
        guard let e = CGEvent(mouseEventSource: mouseSource, mouseType: type, mouseCursorPosition: p, mouseButton: .left) else { return }
        e.flags = []
        e.setDoubleValueField(.mouseEventDeltaX, value: dx)
        e.setDoubleValueField(.mouseEventDeltaY, value: dy)
        e.post(tap: .cghidEventTap)
    }

    // MARK: Giao tiếp

    /// Ngón vừa đi thêm (dx, dy) điểm ảnh màn hình (đã qua gia tốc). ts: dấu thời gian lấy mẫu của touchpad.
    func feed(_ dx: Double, _ dy: Double, ts: Double, bounds b: CGRect) {
        let arrival = clock()
        q.async { [self] in
            bounds = b
            if !active {
                active = true
                pos = systemLocation()                      // bắt đầu từ vị trí thật (có thể đã dùng chuột khác)
                path.reset(); renderedX = 0; renderedY = 0
            }
            path.add(dx, dy, ts: ts, arrival: arrival)
            ensureTimer()
        }
    }

    /// Vị trí con trỏ hiện tại (do bơm đặt nếu đang chạy, ngược lại hỏi hệ thống).
    func position() -> CGPoint {
        q.sync { active ? pos : systemLocation() }
    }

    /// Vị trí con trỏ cách đây `ago` giây (nil nếu không có lịch sử gần đây).
    func position(ago: Double) -> CGPoint? {
        q.sync {
            let t = clock()
            history.removeAll { t - $0.t > 0.5 }
            return history.last(where: { t - $0.t >= ago })?.p ?? history.first?.p
        }
    }

    /// Con trỏ vừa bị đặt lại (warp): bỏ phần đường đi chưa vẽ, tiếp tục từ vị trí mới.
    func warp(to p: CGPoint) {
        q.sync {
            pos = p
            // Bắt đầu đường đi mới từ đây. (Chỉ đặt rendered = cuối đường đi thì nhịp sau nội suy ra vị trí CŨ hơn
            // → con trỏ giật lùi phần chưa vẽ rồi chạy tới lại.)
            path.reset(); renderedX = 0; renderedY = 0
            history.append((clock(), p))
        }
    }

    // MARK: Cho test (chỉ khi manualTicks)

    /// Chạy một nhịp nếu bơm đang hoạt động; false nếu bơm đã nghỉ.
    @discardableResult func step() -> Bool {
        q.sync {
            guard active else { return false }
            tick()
            return true
        }
    }

    // MARK: Bên trong (chỉ chạy trên q)

    private func ensureTimer() {
        guard !manualTicks, timer == nil else { return }
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: q)
        let ns = Int(1_000_000_000 / (hz * 2))      // gấp đôi tần số màn hình: không lệch pha với nhịp vẽ
        t.schedule(deadline: .now() + .nanoseconds(ns), repeating: .nanoseconds(ns), leeway: .microseconds(200))
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
    }

    private func tick() {
        let r = clock() - delay
        let p = path.position(at: r)
        let dx = p.x - renderedX, dy = p.y - renderedY
        renderedX = p.x; renderedY = p.y
        if abs(dx) >= 0.01 || abs(dy) >= 0.01 {
            var np = CGPoint(x: pos.x + dx, y: pos.y + dy)
            if !bounds.isNull {
                np.x = min(max(np.x, bounds.minX), bounds.maxX - 1)
                np.y = min(max(np.y, bounds.minY), bounds.maxY - 1)
            }
            pos = np
            post(np, dx, dy)
            history.append((clock(), np))
            if history.count > 90 { history.removeFirst(history.count - 90) }
        }
        // Đã vẽ hết và không còn gói mới ~0,15 s: nghỉ (lần chạm sau đọc lại vị trí thật)
        if path.last.map({ r > $0.t + 0.15 }) ?? true {
            active = false
            timer?.cancel(); timer = nil
        }
    }
}
