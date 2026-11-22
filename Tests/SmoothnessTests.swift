// SmoothnessTests.swift
// Phát lại cử chỉ rê / cuộn giống remote thật rồi đo độ "khựng" trên từng khung hình màn hình 60 Hz.
//
// Dữ liệu tổng hợp theo đúng số đo trên Siri Remote đời 1 (máy của tác giả):
// - gói cảm ứng đều mỗi 15 ms (66,7 Hz), tới trễ 4 ms + 0–3 ms rung Bluetooth;
// - toạ độ mỗi gói lệch ~15–21 % so với chuyển động trung bình.
// Độ khựng = hệ số biến thiên quãng đi mỗi khung hình (0 % = đều tuyệt đối).
// Ngưỡng được đặt có dư so với kết quả hiện tại: sửa code mà mượt kém đi rõ rệt thì test đỏ.

import Cocoa

struct Packet { let ts: Double; let arrival: Double; let x: Double }

/// Một nét rê thẳng `duration` giây với tốc độ `speed` (đơn vị chuẩn hoá / giây).
func makeStroke(duration: Double, speed: Double, noise: Double, seed: UInt64) -> [Packet] {
    var rng = SeededRNG(seed: seed)
    let step = speed * 0.015
    let sigma = noise * step / sqrt(2)                 // lệch vị trí σ → lệch mỗi bước ≈ σ·√2
    return (0..<Int(duration / 0.015)).map { i in
        let ts = Double(i) * 0.015
        return Packet(ts: ts, arrival: 10 + ts + 0.004 + Double.random(in: 0...0.003, using: &rng),
                      x: speed * ts + rng.gaussian() * sigma)
    }
}

/// Lọc toạ độ như TouchEngine (One Euro theo "Độ mượt").
func filteredDeltas(_ pk: [Packet], smooth: Double) -> [Double] {
    guard let prm = OneEuro.params(smooth: smooth) else { return zip(pk, pk.dropFirst()).map { $1.x - $0.x } }
    var f = OneEuro(minCutoff: prm.minCutoff, beta: prm.beta)
    var last = f.filter(pk[0].x, 0, dt: 0.015).0
    return pk.dropFirst().map { p in
        let v = f.filter(p.x, 0, dt: 0.015).0
        defer { last = v }
        return v - last
    }
}

/// Quãng con trỏ đi mỗi khung hình 60 Hz trong đoạn ổn định (bỏ 0,25 s đầu và cuối).
func frameSteps(_ positions: [(t: Double, x: Double)], from: Double, to: Double) -> [Double] {
    let p = positions.filter { $0.t >= from && $0.t <= to }
    return zip(p, p.dropFirst()).map { $1.x - $0.x }
}

/// Cách cũ: con trỏ nhảy ngay khi gói tới.
func simulateDirect(_ pk: [Packet], deltas: [Double], gain: Double) -> [(t: Double, x: Double)] {
    var out: [(Double, Double)] = []
    var t = pk[0].arrival, x = 0.0, i = 1
    while t < pk.last!.arrival + 0.1 {
        while i < pk.count && pk[i].arrival <= t { x += deltas[i - 1] * gain; i += 1 }
        out.append((t, x))
        t += 1 / 60
    }
    return out
}

/// Qua CursorPump (đồng hồ giả, nhịp bơm 120 Hz, lấy mẫu vị trí ở mỗi khung hình 60 Hz).
func simulateCursorPump(_ pk: [Packet], deltas: [Double], gain: Double) -> [(t: Double, x: Double)] {
    let clock = FakeClock(pk[0].arrival)
    var x = 0.0
    let pump = CursorPump(hz: 60, clock: { clock.t }, post: { p, _, _ in x = Double(p.x) },
                          systemLocation: { .zero }, manualTicks: true)
    var out: [(Double, Double)] = []
    var i = 1, tick = 0
    var t = pk[0].arrival + 0.0021                       // lệch pha bất kỳ giữa màn hình và touchpad
    while t < pk.last!.arrival + 0.1 {
        while i < pk.count && pk[i].arrival <= t {
            clock.t = pk[i].arrival
            pump.feed(deltas[i - 1] * gain, 0, ts: pk[i].ts, bounds: .null)
            i += 1
        }
        clock.t = t
        pump.step()
        if tick % 2 == 0 { out.append((t, x)) }
        tick += 1
        t += 1 / 120
    }
    return out
}

/// Qua ScrollPump (nhịp 60 Hz), vị trí = tổng điểm ảnh đã cuộn.
func simulateScrollPump(_ pk: [Packet], deltas: [Double], gain: Double) -> [(t: Double, x: Double)] {
    let clock = FakeClock(pk[0].arrival)
    var y = 0.0
    let pump = ScrollPump(hz: 60, clock: { clock.t }, post: { v, _, _, _ in y += Double(v) }, manualTicks: true)
    var out: [(Double, Double)] = []
    var i = 1
    var t = pk[0].arrival + 0.0021
    while t < pk.last!.arrival + 0.1 {
        while i < pk.count && pk[i].arrival <= t {
            clock.t = pk[i].arrival
            pump.feed(0, deltas[i - 1] * gain, ts: pk[i].ts)
            i += 1
        }
        clock.t = t
        pump.step()
        out.append((t, y))
        t += 1 / 60
    }
    return out
}

func runSmoothnessTests() {
    let savedSmooth = scrollSmooth
    scrollSmooth = 0.55
    defer { scrollSmooth = savedSmooth }

    let pk = makeStroke(duration: 2, speed: 0.8, noise: 0.18, seed: 42)
    let from = pk[0].arrival + 0.25, to = pk.last!.arrival - 0.25
    let raw = zip(pk, pk.dropFirst()).map { $1.x - $0.x }
    let filtered = filteredDeltas(pk, smooth: 0.55)

    group("Độ mượt con trỏ (phát lại nét rê 2 s, 66,7 Hz → màn hình 60 Hz)")

    let direct = roughness(frameSteps(simulateDirect(pk, deltas: raw, gain: 1500), from: from, to: to))
    let pumpOnly = roughness(frameSteps(simulateCursorPump(pk, deltas: raw, gain: 1500), from: from, to: to))
    let full = roughness(frameSteps(simulateCursorPump(pk, deltas: filtered, gain: 1500), from: from, to: to))

    test("cách cũ (con trỏ nhảy theo gói) khựng rõ — mốc so sánh") {
        metric("độ khựng", direct * 100, unit: " %")
        expect(direct > 0.25)
    }
    test("chỉ bơm khung hình: hết nhịp nhảy đôi") {
        metric("độ khựng", pumpOnly * 100, unit: " %")
        expect(pumpOnly < direct * 0.8)
    }
    test("bơm + lọc One Euro (độ mượt 55 %): mượt hơn cách cũ ≥ 2,5 lần") {
        metric("độ khựng", full * 100, unit: " %")
        expect(full < 0.12, "độ khựng \(full * 100) %")
        expect(full < direct / 2.5)
    }

    test("không rung toạ độ: bơm cho quãng mỗi khung gần như bằng nhau") {
        let clean = makeStroke(duration: 2, speed: 0.8, noise: 0, seed: 7)
        let d = zip(clean, clean.dropFirst()).map { $1.x - $0.x }
        let r = roughness(frameSteps(simulateCursorPump(clean, deltas: d, gain: 1500), from: from, to: to))
        let rd = roughness(frameSteps(simulateDirect(clean, deltas: d, gain: 1500), from: from, to: to))
        metric("bơm / cách cũ", r * 100, unit: " %")
        metric("cách cũ", rd * 100, unit: " %")
        expect(r < 0.05 && rd > 0.2)
    }

    group("Độ mượt cuộn hai ngón")

    let scrollDirect = roughness(frameSteps(simulateDirect(pk, deltas: raw, gain: 1100), from: from, to: to))
    let scrollFull = roughness(frameSteps(simulateScrollPump(pk, deltas: filtered, gain: 1100), from: from, to: to))

    test("cuộn qua bơm + lọc mượt hơn cách cũ ≥ 3 lần") {
        metric("cách cũ", scrollDirect * 100, unit: " %")
        metric("bơm + lọc", scrollFull * 100, unit: " %")
        expect(scrollFull < 0.12, "độ khựng \(scrollFull * 100) %")
        expect(scrollFull < scrollDirect / 3)
    }

    test("nhiều nét rê khác nhau (tốc độ, hạt giống): bơm luôn mượt hơn") {
        for (speed, seed) in [(0.3, UInt64(1)), (0.8, 2), (1.6, 3), (2.5, 4)] {
            let s = makeStroke(duration: 1.5, speed: speed, noise: 0.18, seed: seed)
            let a = s[0].arrival + 0.25, b = s.last!.arrival - 0.25
            let r = zip(s, s.dropFirst()).map { $1.x - $0.x }
            let old = roughness(frameSteps(simulateDirect(s, deltas: r, gain: 1500), from: a, to: b))
            let new = roughness(frameSteps(simulateCursorPump(s, deltas: filteredDeltas(s, smooth: 0.55), gain: 1500),
                                           from: a, to: b))
            expect(new < old / 2, "tốc độ \(speed): \(new) vs \(old)")
        }
    }
}
