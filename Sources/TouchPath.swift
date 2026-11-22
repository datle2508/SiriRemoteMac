// TouchPath.swift
// Đường đi của ngón theo thời gian, dùng chung cho ScrollPump và CursorPump.
//
// Mỗi gói cảm ứng mang dấu thời gian LẤY MẪU của touchpad. Quy đổi sang đồng hồ máy bằng độ lệch nhỏ nhất từng thấy
// (gói tới nhanh nhất ≈ ít trễ Bluetooth nhất), rồi nội suy tuyến tính vị trí ở bất kỳ thời điểm nào.
// Code thuần (không gửi sự kiện, không đọc đồng hồ) để test được.

import Cocoa

struct TouchPath {
    private(set) var samples: [(t: Double, x: Double, y: Double)] = []
    private(set) var cumX = 0.0, cumY = 0.0           // vị trí cộng dồn (điểm ảnh)
    private var clockOffset: Double?                  // đồng hồ máy − đồng hồ touchpad
    /// Điểm xuất phát được đặt sớm hơn mẫu đầu một khoảng này (để đoạn đầu cũng nội suy được).
    let lead: Double

    init(lead: Double) { self.lead = lead }

    var last: (t: Double, x: Double, y: Double)? { samples.last }

    mutating func reset() {
        samples.removeAll(); cumX = 0; cumY = 0; clockOffset = nil
    }

    /// Ngón vừa đi thêm (dx, dy). ts: dấu thời gian lấy mẫu của touchpad (nil → dùng lúc tới); arrival: lúc gói tới.
    mutating func add(_ dx: Double, _ dy: Double, ts: Double?, arrival: Double) {
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
        if samples.isEmpty { samples.append((t - lead, 0, 0)) }
        t = max(t, samples.last!.t + 0.0005)
        cumX += dx; cumY += dy
        samples.append((t, cumX, cumY))
        if samples.count > 64 { samples.removeFirst(samples.count - 64) }
    }

    /// Vị trí tại thời điểm r (nội suy tuyến tính giữa hai mẫu kề nhau; ngoài khoảng thì giữ đầu mút).
    func position(at r: Double) -> (x: Double, y: Double) {
        guard let first = samples.first, let last = samples.last else { return (cumX, cumY) }
        if r <= first.t { return (first.x, first.y) }
        if r >= last.t { return (last.x, last.y) }
        var i = samples.count - 1
        while i > 0 && samples[i - 1].t > r { i -= 1 }
        let a = samples[i - 1], b = samples[i]
        let u = (r - a.t) / max(b.t - a.t, 1e-6)
        return (a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u)
    }

    /// Vận tốc (điểm ảnh / giây): độ dốc đường đi trong khoảng `window` giây cuối. (0, 0) nếu quá ít dữ liệu.
    func velocity(window: Double) -> (x: Double, y: Double) {
        guard let last = samples.last else { return (0, 0) }
        let s = samples.last(where: { last.t - $0.t >= window }) ?? samples.first!
        let span = last.t - s.t
        guard span >= 0.012 else { return (0, 0) }
        return ((last.x - s.x) / span, (last.y - s.y) / span)
    }
}

/// Tần số làm tươi cao nhất trong các màn hình (tối thiểu 60 Hz).
func displayRefreshRate() -> Double {
    let screens = Thread.isMainThread ? NSScreen.screens : DispatchQueue.main.sync { NSScreen.screens }
    return Double(max(screens.map { $0.maximumFramesPerSecond }.max() ?? 60, 60))
}
