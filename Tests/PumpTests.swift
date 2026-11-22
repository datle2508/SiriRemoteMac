// PumpTests.swift
// Test hành vi ScrollPump / CursorPump với đồng hồ giả: thứ tự pha cuộn, quãng đường, quán tính, kẹp màn hình…

import Cocoa

struct ScrollEvent { let v: Int32, h: Int32, phase: Int64, momentum: Int64 }

/// ScrollPump chạy bằng tay: đồng hồ giả + ghi lại mọi sự kiện gửi ra.
final class ScrollRig {
    let clock = FakeClock()
    private(set) var events: [ScrollEvent] = []
    let hz: Double
    lazy var pump = ScrollPump(hz: hz, clock: { [clock] in clock.t },
                               post: { [weak self] in self?.events.append(ScrollEvent(v: $0, h: $1, phase: $2, momentum: $3)) },
                               manualTicks: true)
    init(hz: Double = 60) { self.hz = hz }

    /// Chạy từng nhịp tới khi bơm nghỉ (hoặc hết `limit` giây).
    func runUntilIdle(limit: Double = 5) {
        let end = clock.t + limit
        while clock.t < end {
            clock.t += 1 / hz
            if !pump.step() { return }
        }
    }
    func flush() { _ = pump.step() }
}

func runPumpTests() {
    let savedSmooth = scrollSmooth
    scrollSmooth = 0.55
    defer { scrollSmooth = savedSmooth }

    group("ScrollPump: cú hất (vuốt gán cuộn, nút cuộn)")

    test("chuỗi pha giống trackpad: mayBegin → began → ended → quán tính 1, 2… 3") {
        let rig = ScrollRig()
        rig.pump.fling(0, -600); rig.pump.sync()
        rig.runUntilIdle()
        let e = rig.events
        expect(e.count > 10)
        expect(e[0].phase == 128 && e[0].v == 0)
        expect(e[1].phase == 1 && e[1].v < 0)
        expect(e[2].phase == 4 && e[2].v == 0)
        expect(e[3].momentum == 1, "quán tính đầu: \(e[3])")
        expect(e.dropFirst(4).dropLast().allSatisfy { $0.momentum == 2 })
        expect(e.last!.momentum == 3 && e.last!.v == 0)
    }

    test("tổng quãng ≈ quãng yêu cầu") {
        for want in [250.0, 600, 1300] {
            let rig = ScrollRig()
            rig.pump.fling(0, want); rig.pump.sync()
            rig.runUntilIdle()
            let got = Double(rig.events.reduce(0) { $0 + Int($1.v) })
            expectNear(got, want, tol: want * 0.06, "quãng \(want)")
        }
    }

    test("quán tính giảm theo e^(−3,1t) như trackpad thật") {
        let rig = ScrollRig()
        rig.pump.fling(0, 2000); rig.pump.sync()
        rig.runUntilIdle()
        let m = rig.events.filter { $0.momentum == 1 || $0.momentum == 2 }.map { Double($0.v) }
        let want = exp(-3.1 * 29 / 60)              // đo trên Magic Trackpad thật (scroll.log)
        expectNear(m[30] / m[1], want, tol: 0.03)
        // số nguyên + dồn phần lẻ: khung sau có thể lớn hơn khung trước tối đa 1 px
        expect(zip(m, m.dropFirst()).allSatisfy { $0 + 1 >= $1 }, "vận tốc phải giảm dần")
    }

    test("cuộn ngang đi theo trục h") {
        let rig = ScrollRig()
        rig.pump.fling(-400, 0); rig.pump.sync()
        rig.runUntilIdle()
        expect(rig.events.allSatisfy { $0.v == 0 })
        expect(rig.events.reduce(0) { $0 + Int($1.h) } < -350)
    }

    test("chạm lại khi đang trôi: gửi momentum end và dừng") {
        let rig = ScrollRig()
        rig.pump.fling(0, 1000); rig.pump.sync()
        for _ in 0..<5 { rig.clock.t += 1 / 60; rig.pump.step() }
        rig.pump.stop()
        rig.flush()
        expect(rig.events.last?.momentum == 3)
        expect(!rig.pump.step(), "bơm lẽ ra đã nghỉ")
    }

    group("ScrollPump: cuộn hai ngón")

    /// Ngón cuộn đều `perPacket` px mỗi gói 15 ms, `n` gói, rồi nhấc tay.
    func fingerScroll(_ rig: ScrollRig, perPacket: Double, n: Int, momentum: Bool) {
        let t0 = rig.clock.t
        for i in 0..<n {
            let arrival = t0 + Double(i) * 0.015 + 0.004
            while rig.clock.t + 1 / 60 <= arrival { rig.clock.t += 1 / 60; rig.pump.step() }
            let now = rig.clock.t
            rig.clock.t = arrival
            rig.pump.feed(0, perPacket, ts: Double(i) * 0.015)
            rig.clock.t = now
        }
        rig.pump.release(momentum: momentum)
        rig.runUntilIdle()
    }

    test("không quán tính: trang đi đúng bằng quãng ngón (không mất / thừa điểm ảnh)") {
        let rig = ScrollRig()
        fingerScroll(rig, perPacket: 7.3, n: 40, momentum: false)
        let total = rig.events.reduce(0) { $0 + Int($1.v) }
        expect(total == Int(7.3 * 40), "tổng \(total)")
        expect(rig.events.allSatisfy { $0.momentum == 0 })
        expect(rig.events.first?.phase == 1)
        expect(rig.events.last.map { $0.phase == 4 && $0.v == 0 } == true)
        expect(rig.events.dropFirst().dropLast().allSatisfy { $0.phase == 2 })
    }

    test("có quán tính: sau ended là chuỗi quán tính cùng chiều") {
        let rig = ScrollRig()
        fingerScroll(rig, perPacket: 12, n: 30, momentum: true)
        guard let end = rig.events.firstIndex(where: { $0.phase == 4 }) else { expect(false, "thiếu ended"); return }
        let tail = rig.events[(end + 1)...]
        expect(tail.first?.momentum == 1)
        expect(tail.last?.momentum == 3)
        expect(tail.allSatisfy { $0.v >= 0 })
        let glide = tail.reduce(0) { $0 + Int($1.v) }
        metric("quãng trôi", Double(glide), unit: " px")
        expect(glide > 50)
    }

    test("vuốt rất chậm rồi nhấc: không trôi") {
        let rig = ScrollRig()
        fingerScroll(rig, perPacket: 1, n: 30, momentum: true)                 // ~67 px/s < ngưỡng 120 px/s
        expect(rig.events.allSatisfy { $0.momentum == 0 })
    }

    test("đặt ngón lại khi đang trôi: kết thúc quán tính trước rồi mới bắt đầu lượt mới") {
        let rig = ScrollRig()
        rig.pump.fling(0, 800); rig.pump.sync()
        for _ in 0..<5 { rig.clock.t += 1 / 60; rig.pump.step() }
        rig.pump.feed(0, 5, ts: 50)
        rig.flush()
        let i = rig.events.lastIndex(where: { $0.momentum == 3 })
        expect(i != nil, "thiếu momentum end")
        expect(rig.events[(i! + 1)...].allSatisfy { $0.momentum == 0 })
    }

    group("CursorPump")

    final class CursorRig {
        let clock = FakeClock()
        var pos = CGPoint.zero
        lazy var pump = CursorPump(hz: 60, clock: { [clock] in clock.t }, post: { [weak self] p, _, _ in self?.pos = p },
                                   systemLocation: { CGPoint(x: 500, y: 500) }, manualTicks: true)
        func feed(_ dx: Double, _ dy: Double, ts: Double, bounds: CGRect = CGRect(x: 0, y: 0, width: 2000, height: 1000)) {
            pump.feed(dx, dy, ts: ts, bounds: bounds)
        }
        func runUntilIdle() { for _ in 0..<600 { clock.t += 1 / 120; if !pump.step() { return } } }
    }

    test("bắt đầu từ vị trí thật của con trỏ, đi đúng tổng quãng") {
        let rig = CursorRig()
        for i in 0..<20 { rig.clock.t += 0.015; rig.feed(3, -1.5, ts: Double(i) * 0.015) }
        rig.runUntilIdle()
        expectNear(rig.pos.x, 560, tol: 0.01)
        expectNear(rig.pos.y, 470, tol: 0.01)
    }

    test("kẹp trong vùng màn hình") {
        let rig = CursorRig()
        rig.feed(-5000, 9000, ts: 0)
        rig.runUntilIdle()
        expect(rig.pos == CGPoint(x: 0, y: 999), "\(rig.pos)")
    }

    test("nghỉ sau ~0,15 s không có gói mới; lần sau đọc lại vị trí thật") {
        let rig = CursorRig()
        rig.feed(10, 0, ts: 0)
        rig.runUntilIdle()
        expect(!rig.pump.step())
        expect(rig.pump.position() == CGPoint(x: 500, y: 500))   // đã nghỉ → hỏi hệ thống
    }

    test("position(ago:) trả vị trí trước khi nhấn (giữ yên con trỏ khi click)") {
        let rig = CursorRig()
        for i in 0..<40 {
            rig.clock.t += 0.0075
            if i % 2 == 0 { rig.feed(4, 0, ts: Double(i) * 0.0075) }
            rig.pump.step()
        }
        let now = rig.pump.position(), before = rig.pump.position(ago: 0.12)!
        expect(before.x < now.x - 20, "trước \(before.x), giờ \(now.x)")
    }

    test("warp: bỏ phần đường đi chưa vẽ, tiếp tục từ vị trí mới") {
        let rig = CursorRig()
        rig.feed(100, 0, ts: 0)                         // 100 px chưa kịp vẽ
        rig.pump.warp(to: CGPoint(x: 10, y: 10))
        rig.clock.t += 0.015
        rig.feed(5, 0, ts: 0.015)                       // ngón đi tiếp 5 px
        var xs: [CGFloat] = []
        for _ in 0..<120 { rig.clock.t += 1 / 120; guard rig.pump.step() else { break }; xs.append(rig.pos.x) }
        expectNear(Double(rig.pos.x), 15, tol: 0.01, "phải đi tiếp 5 px từ điểm warp")
        expect(xs.allSatisfy { $0 >= 10 }, "con trỏ giật lùi: min \(xs.min() ?? 0)")
    }
}
