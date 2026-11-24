// TouchAnalyzer: đọc bản ghi của TouchRecorder, phân tích cách vuốt, phát lại qua bộ xử lý của app
// (lọc One Euro → gia tốc → CursorPump) và dò tham số ít khựng nhất.
//
// Build + chạy:  tools/analyze.sh touch.csv

import Foundation

// MARK: - Đọc bản ghi

struct Touch { let id: Int32; let x: Double; let y: Double; let state: Int32; var size = 1.0 }
struct Frame { let arrival: Double; let ts: Double; var touches: [Touch] }

func load(_ path: String) -> [Frame] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { print("Không đọc được \(path)"); exit(1) }
    var frames: [Frame] = []
    for line in text.split(separator: "\n").dropFirst() {
        let f = line.split(separator: ",")
        guard f.count >= 7, let arr = Double(f[0]), let ts = Double(f[1]), let id = Int32(f[3]) else { continue }
        if frames.last?.ts != ts { frames.append(Frame(arrival: arr, ts: ts, touches: [])) }
        if id >= 0, let x = Double(f[4]), let y = Double(f[5]), let st = Int32(f[6]) {
            frames[frames.count - 1].touches.append(Touch(id: id, x: x, y: y, state: st, size: f.count > 7 ? Double(f[7]) ?? 1 : 1))
        }
    }
    return frames
}

// MARK: - Tách lượt chạm (giống TouchEngine.process)

struct Sample { let ts: Double; let arrival: Double; let x: Double; let y: Double; let n: Int; var size = 1.0 }
struct Session {
    var samples: [Sample] = []
    var maxFingers: Int { samples.map(\.n).max() ?? 0 }
    var dur: Double { (samples.last?.ts ?? 0) - (samples.first?.ts ?? 0) }
    var dx: Double { (samples.last?.x ?? 0) - (samples.first?.x ?? 0) }
    var dy: Double { (samples.last?.y ?? 0) - (samples.first?.y ?? 0) }
    var travel: Double { zip(samples, samples.dropFirst()).reduce(0) { $1.0.n == $1.1.n ? $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) : $0 } }
}

func sessions(_ frames: [Frame]) -> [Session] {
    var out: [Session] = [], cur: Session?
    for f in frames {
        let act = f.touches.filter { $0.state == 3 || $0.state == 4 }
        if act.isEmpty { if let c = cur, c.samples.count > 1 { out.append(c) }; cur = nil; continue }
        let n = Double(act.count)
        let s = Sample(ts: f.ts, arrival: f.arrival, x: act.reduce(0) { $0 + $1.x } / n, y: act.reduce(0) { $0 + $1.y } / n, n: act.count, size: act.reduce(0) { $0 + $1.size } / n)
        if cur == nil { cur = Session() }
        cur!.samples.append(s)
    }
    if let c = cur, c.samples.count > 1 { out.append(c) }
    return out
}

let swipeMinDist = GestureRules.cursor.swipeDist

enum Kind: String { case swipe = "vuốt", nearSwipe = "vuốt hụt", cursor = "rê con trỏ", tap = "chạm", scroll = "cuộn 2 ngón", other = "khác" }

func classify(_ s: Session) -> Kind {
    if s.maxFingers >= 2 { return s.travel >= 0.03 ? .scroll : .other }
    let adx = abs(s.dx), ady = abs(s.dy), far = max(adx, ady)
    let dominant = far >= 2 * min(adx, ady)
    if s.dur < 0.4, far >= swipeMinDist, dominant { return .swipe }
    if s.dur < 0.25, s.travel < 0.04 { return .tap }
    // gần như vuốt nhưng trượt ngưỡng (chậm hơn 0,4 s / ngắn hơn 0,3 / hơi chéo): app hiểu thành rê con trỏ
    if dominant, far >= 0.15, s.dur < 0.6, far / max(s.dur, 0.03) >= 0.6 { return .nearSwipe }
    return s.travel >= 0.04 ? .cursor : .other
}

// MARK: - Thống kê

func pct(_ xs: [Double], _ p: Double) -> Double {
    guard !xs.isEmpty else { return .nan }
    let s = xs.sorted(); return s[min(Int(Double(s.count - 1) * p + 0.5), s.count - 1)]
}
func f(_ x: Double, _ d: Int = 2) -> String { String(format: "%.\(d)f", x) }

// MARK: - Phát lại một lượt rê con trỏ

/// Thời điểm (giây từ lúc chạm) mà TouchEngine.steer thả con trỏ (cả 4 hướng vuốt đều được gán như cấu hình hiện tại).
func steerDecision(_ s: Session, holdMax: Double = GestureRules.holdMax,
                   slowSpeed: Double = GestureRules.slowSpeed(priority: swipePriority),
                   minTime: Double = GestureRules.holdMinTime) -> Double? {
    let s0 = s.samples[0]
    for p in s.samples.dropFirst() where p.n == 1 {
        let el = p.ts - s0.ts
        let ddx = p.x - s0.x, ddy = p.y - s0.y, adx = abs(ddx), ady = abs(ddy), far = max(adx, ady)
        if el >= holdMax { return el }
        if el >= minTime, hypot(ddx, ddy) / el < slowSpeed { return el }
        if far >= 0.12, far < 2 * min(adx, ady) { return el }
    }
    return nil
}

struct Replay { var jank: Double; var bigJumps: Int; var frames: Int }

/// Độ khựng: trung bình |quãng khung k − trung bình 5 khung quanh nó| / trung bình đó, trên các khung đang chạy.
func jank(_ pos: [(Double, Double)]) -> (Double, Int, Int) {
    let st = zip(pos, pos.dropFirst()).map { hypot($1.0 - $0.0, $1.1 - $0.1) }
    var sum = 0.0, n = 0, big = 0
    if st.count < 5 { return (0, 0, 0) }
    for k in 2..<(st.count - 2) {
        let m = (st[k - 2] + st[k - 1] + st[k] + st[k + 1] + st[k + 2]) / 5
        guard m > 0.5 else { continue }
        let d = abs(st[k] - m) / m
        sum += d; n += 1
        if st[k] > 2.5 * m && st[k] > 6 { big += 1 }        // khung nhảy vọt rõ rệt
    }
    return (n > 0 ? sum / Double(n) : 0, big, n)
}

enum Mode { case direct, pump(smooth: Double, delay: Double) }

/// hold: mô phỏng việc giữ con trỏ chờ phân biệt vuốt (rồi thả cả đoạn một lúc) như app hiện tại;
/// holdRelease: thay vì thả một lúc, rải phần đã giữ ra theo thời gian (đề xuất).
func replayCursor(_ s: Session, mode: Mode, touchSpeed: Double, hold: Bool, holdMax: Double = GestureRules.holdMax,
                  slowSpeed: Double = GestureRules.slowSpeed(priority: swipePriority), minTime: Double = GestureRules.holdMinTime, spread: Bool = false, glideN: Int = 7) -> (Double, Int, Int) {
    let smp = s.samples.filter { $0.n == 1 }
    guard smp.count > 6 else { return (0, 0, 0) }
    let decideAt = hold ? (steerDecision(s, holdMax: holdMax, slowSpeed: slowSpeed, minTime: minTime) ?? .infinity) : 0
    var euro: OneEuro? = nil
    if case .pump(let sm, _) = mode, let p = OneEuro.params(smooth: sm) { euro = OneEuro(minCutoff: p.minCutoff, beta: p.beta) }
    _ = euro?.filter(smp[0].x, smp[0].y, dt: 0.015)
    var last = (smp[0].x, smp[0].y)
    var cursorSpeed = 0.0
    var bufX = 0.0, bufY = 0.0, decided = !hold
    var catchX = 0.0, catchY = 0.0, catchI = glideN
    let wsum = Double(glideN * (glideN + 1) / 2)
    func addCatch() {
        guard catchI < glideN, !moves.isEmpty else { return }
        let w = Double(glideN - catchI) / wsum
        let m = moves.removeLast()
        moves.append((m.0, m.1, m.2 + catchX * w, m.3 + catchY * w))
        catchI += 1
    }
    // các bước con trỏ: (lúc tới, ts, dx px, dy px)
    var moves: [(Double, Double, Double, Double)] = []
    for i in 1..<smp.count {
        let p = smp[i], dt = max(p.ts - smp[i - 1].ts, 0.004)
        let fp = euro.map { e -> (Double, Double) in var e = e; let r = e.filter(p.x, p.y, dt: dt); euro = e; return r } ?? (p.x, p.y)
        let dx = fp.0 - last.0, dy = fp.1 - last.1
        last = fp
        func emit(_ dx: Double, _ dy: Double, span: Double) {
            let inst = hypot(dx, dy) / max(span, 0.004)
            cursorSpeed = cursorSpeed == 0 ? inst : cursorSpeed + (inst - cursorSpeed) * (1 - exp(-max(span, 0.004) / 0.05))
            let k = touchSpeed * 800 * (0.55 + 2.4 * (1 - exp(-cursorSpeed / 1.4)))
            moves.append((p.arrival, p.ts, dx * k, -dy * k))
        }
        if decided { emit(dx, dy, span: dt); addCatch(); continue }
        bufX += dx; bufY += dy
        if p.ts - smp[0].ts >= decideAt {
            decided = true
            emit(bufX, bufY, span: p.ts - smp[0].ts)
            if spread {
                // đề xuất: phần đã giữ không nhảy một lần mà đuổi theo trong `glideN` gói kế tiếp (nhiều trước, ít sau)
                let m = moves.removeLast()
                catchX = m.2; catchY = m.3; catchI = 0
                moves.append((m.0, m.1, 0, 0))
                addCatch()
            }
            bufX = 0; bufY = 0
        }
    }
    guard !moves.isEmpty else { return (0, 0, 0) }

    var pos: [(Double, Double)] = []
    let t0 = smp[0].arrival
    let end = smp.last!.arrival + 0.12
    switch mode {
    case .direct:
        var x = 0.0, y = 0.0, i = 0, t = t0 + 0.0021
        while t < end {
            while i < moves.count && moves[i].0 <= t { x += moves[i].2; y += moves[i].3; i += 1 }
            pos.append((x, y)); t += 1 / 60
        }
    case .pump(_, let delay):
        let clock = FakeClockA(t0)
        var x = 0.0, y = 0.0
        let pump = CursorPump(hz: 60, clock: { clock.t }, post: { p, _, _ in x = Double(p.x); y = Double(p.y) },
                              systemLocation: { .zero }, manualTicks: true)
        pump.delayOverride = delay
        var i = 0, tick = 0, t = t0 + 0.0021
        while t < end {
            while i < moves.count && moves[i].0 <= t {
                clock.t = moves[i].0
                pump.feed(moves[i].2, moves[i].3, ts: moves[i].1, bounds: .null)
                i += 1
            }
            clock.t = t
            pump.step()
            if tick % 2 == 0 { pos.append((x, y)) }
            tick += 1; t += 1 / 120
        }
    }
    return jank(pos)
}

final class FakeClockA { var t: Double; init(_ t: Double) { self.t = t } }

/// Trễ của bộ lọc One Euro khi ngón đi đều `speed` (đơn vị/giây), tính bằng giây.
func filterLag(smooth: Double, speed: Double) -> Double {
    guard let p = OneEuro.params(smooth: smooth) else { return 0 }
    var e = OneEuro(minCutoff: p.minCutoff, beta: p.beta)
    var x = 0.0, y = 0.0
    for i in 0..<80 { x = Double(i) * speed * 0.015; y = e.filter(x, 0, dt: 0.015).0 }
    return (x - y) / speed
}

// MARK: - Chạy

_ = loadMap()                    // đọc cấu hình thật (thanh trượt Nhận vuốt…) như app
let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "touch.csv"
let touchSpeedCfg = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2]) ?? 0.77 : 0.77
let smoothCfg = CommandLine.arguments.count > 3 ? Double(CommandLine.arguments[3]) ?? 0.76 : 0.76
let frames = load(path)
let ss = sessions(frames)
print("Bản ghi: \(frames.count) khung, \(ss.count) lượt chạm  (touchspeed \(touchSpeedCfg), độ mượt \(smoothCfg))")

// Nhịp gói
let inSession = frames.filter { !$0.touches.isEmpty }
let intervals = zip(inSession, inSession.dropFirst()).map { $1.ts - $0.ts }.filter { $0 < 0.05 }
let offs = inSession.map { $0.arrival - $0.ts }
let minOff = offs.min() ?? 0
let jit = offs.map { ($0 - minOff) * 1000 }
print("\n▸ Nhịp touchpad")
print("  khoảng cách gói: trung vị \(f(pct(intervals, 0.5) * 1000)) ms (p5 \(f(pct(intervals, 0.05) * 1000)), p95 \(f(pct(intervals, 0.95) * 1000)))")
print("  trễ Bluetooth thêm: trung vị \(f(pct(jit, 0.5))) ms, p95 \(f(pct(jit, 0.95))) ms, max \(f(jit.max() ?? 0))")

// Phân loại
var byKind: [Kind: [Session]] = [:]
for s in ss { byKind[classify(s), default: []].append(s) }
print("\n▸ Các lượt chạm")
for k in [Kind.cursor, .swipe, .nearSwipe, .scroll, .tap, .other] {
    print("  \(k.rawValue): \(byKind[k]?.count ?? 0)")
}

let swipes = byKind[.swipe] ?? []
if !swipes.isEmpty {
    let sp = swipes.map { max(abs($0.dx), abs($0.dy)) / max($0.dur, 0.03) }
    print("\n▸ Cú vuốt của bạn (\(swipes.count))")
    print("  thời gian: trung vị \(f(pct(swipes.map(\.dur), 0.5) * 1000, 0)) ms (p10 \(f(pct(swipes.map(\.dur), 0.1) * 1000, 0)) – p90 \(f(pct(swipes.map(\.dur), 0.9) * 1000, 0)))")
    print("  quãng: trung vị \(f(pct(swipes.map { max(abs($0.dx), abs($0.dy)) }, 0.5))) (ngưỡng \(swipeMinDist))")
    print("  tốc độ: p10 \(f(pct(sp, 0.1))) · trung vị \(f(pct(sp, 0.5))) · p90 \(f(pct(sp, 0.9))) đơn vị/s")
}
let near = byKind[.nearSwipe] ?? []
if !near.isEmpty {
    print("\n▸ Vuốt hụt (\(near.count)): trông như vuốt nhưng trượt ngưỡng → app hiểu là rê con trỏ")
    for s in near.prefix(8) {
        let far = max(abs(s.dx), abs(s.dy))
        print("  thời gian \(f(s.dur * 1000, 0)) ms, quãng \(f(far)), chéo \(f(min(abs(s.dx), abs(s.dy)) / max(far, 1e-6) * 100, 0)) %")
    }
}

// Giữ con trỏ khi chờ phân biệt vuốt
let cursors = (byKind[.cursor] ?? []) + near
if !cursors.isEmpty {
    var holds: [Double] = [], heldPx: [Double] = []
    for s in cursors {
        guard let t = steerDecision(s) else { continue }
        holds.append(t)
        let p = s.samples.first(where: { $0.ts - s.samples[0].ts >= t }) ?? s.samples.last!
        heldPx.append(hypot(p.x - s.samples[0].x, p.y - s.samples[0].y) * touchSpeedCfg * 800 * 2)
    }
    let long = holds.filter { $0 >= 0.2 }.count
    print("\n▸ Con trỏ bị giữ đứng yên lúc bắt đầu rê (chờ xem có phải vuốt)")
    print("  thời gian giữ: trung vị \(f(pct(holds, 0.5) * 1000, 0)) ms, p90 \(f(pct(holds, 0.9) * 1000, 0)) ms; ≥ 200 ms: \(long)/\(holds.count) lượt")
    print("  rồi nhảy một lần: trung vị ~\(f(pct(heldPx, 0.5), 0)) px, p90 ~\(f(pct(heldPx, 0.9), 0)) px")
}

// Độ khựng khi phát lại
func avgJank(_ fn: (Session) -> (Double, Int, Int)) -> (Double, Int) {
    var s = 0.0, n = 0, big = 0
    for c in cursors { let r = fn(c); s += r.0 * Double(r.2); n += r.2; big += r.1 }
    return (n > 0 ? s / Double(n) : 0, big)
}
if !cursors.isEmpty {
    let cursorSp = cursors.flatMap { s in zip(s.samples, s.samples.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) / max($1.ts - $0.ts, 0.004) } }
    let typical = max(pct(cursorSp.filter { $0 > 0.05 }, 0.5), 0.1)
    print("\n▸ Phát lại \(cursors.count) lượt rê qua bộ xử lý (tốc độ rê điển hình \(f(typical)) đơn vị/s)")
    let old = avgJank { replayCursor($0, mode: .direct, touchSpeed: touchSpeedCfg, hold: true) }
    let prev = avgJank { replayCursor($0, mode: .pump(smooth: smoothCfg, delay: 0.02), touchSpeed: touchSpeedCfg, hold: true) }
    print("  bản trước (bơm, thả phần giữ một lần): khựng \(f(prev.0 * 100, 1)) %, khung nhảy vọt \(prev.1)")
    let cur = avgJank { replayCursor($0, mode: .pump(smooth: smoothCfg, delay: 0.02), touchSpeed: touchSpeedCfg, hold: true, spread: true, glideN: 8) }
    let noHold = avgJank { replayCursor($0, mode: .pump(smooth: smoothCfg, delay: 0.02), touchSpeed: touchSpeedCfg, hold: false) }
    print("  không bơm, không lọc (cách cũ):   khựng \(f(old.0 * 100, 1)) %, khung nhảy vọt \(old.1)")
    print("  hiện tại (đuổi theo 8 gói):        khựng \(f(cur.0 * 100, 1)) %, khung nhảy vọt \(cur.1)")
    print("  hiện tại, bỏ giữ con trỏ:          khựng \(f(noHold.0 * 100, 1)) %, khung nhảy vọt \(noHold.1)")
    for n in [3, 5, 7, 10, 14] {
        let g = avgJank { replayCursor($0, mode: .pump(smooth: smoothCfg, delay: 0.02), touchSpeed: touchSpeedCfg, hold: true, spread: true, glideN: n) }
        print("    đuổi theo trong \(n) gói (\(n * 15) ms): khựng \(f(g.0 * 100, 1)) %, khung nhảy vọt \(g.1)")
    }

    print("\n▸ Dò tham số (độ mượt × trễ bơm), giữ cách phân biệt vuốt hiện tại")
    print("  độ mượt  trễ   khựng   nhảy  trễ tổng")
    var rows: [(Double, Double, Double, Int, Double)] = []
    for sm in stride(from: 0.3, through: 1.0001, by: 0.1) {
        for d in [0.010, 0.015, 0.020, 0.025, 0.030] {
            let r = avgJank { replayCursor($0, mode: .pump(smooth: sm, delay: d), touchSpeed: touchSpeedCfg, hold: true, spread: true) }
            let lag = d + filterLag(smooth: sm, speed: typical)
            rows.append((sm, d, r.0, r.1, lag))
        }
    }
    let curLag = 0.02 + filterLag(smooth: smoothCfg, speed: typical)
    for r in rows.sorted(by: { $0.2 < $1.2 }).prefix(10) {
        print("  \(f(r.0))     \(f(r.1 * 1000, 0)) ms  \(f(r.2 * 100, 1)) %   \(r.3)    \(f(r.4 * 1000, 0)) ms")
    }
    if let best = rows.filter({ $0.4 <= curLag + 0.004 }).min(by: { $0.2 < $1.2 }) {
        print("  → tốt nhất mà không trễ hơn hiện tại (\(f(curLag * 1000, 0)) ms): độ mượt \(f(best.0)), trễ bơm \(f(best.1 * 1000, 0)) ms, khựng \(f(best.2 * 100, 1)) %")
    }
}


// MARK: - Dò cách phân biệt vuốt / rê theo dữ liệu của bạn
do {
    let sw = (byKind[.swipe] ?? [])
    let cur = byKind[.cursor] ?? []
    print("\n▸ Dò ngưỡng phân biệt vuốt / rê (giữ con trỏ ngắn nhất mà không cú vuốt nào làm con trỏ chạy)")
    print("  giữ tối đa  chậm hơn  sau     vuốt lọt  giữ trung vị  p90    khựng  nhảy")
    var rows: [(Double, Double, Double, Int, Double, Double, Double, Int)] = []
    for hm in [0.2, 0.25, 0.3, 0.35, 0.45] {
        for sl in [0.6, 0.8, 1.0, 1.2, 1.4] {
            for mt in [0.06, 0.1, 0.135, 0.15] {
                let leak = sw.filter { s in (steerDecision(s, holdMax: hm, slowSpeed: sl, minTime: mt) ?? .infinity) < s.dur - 0.001 }.count
                let holds = cur.compactMap { steerDecision($0, holdMax: hm, slowSpeed: sl, minTime: mt) }
                let j = avgJank { replayCursor($0, mode: .pump(smooth: smoothCfg, delay: 0.02), touchSpeed: touchSpeedCfg, hold: true, holdMax: hm, slowSpeed: sl, minTime: mt) }
                rows.append((hm, sl, mt, leak, pct(holds, 0.5), pct(holds, 0.9), j.0, j.1))
            }
        }
    }
    let ok = rows.filter { $0.3 <= 4 }.sorted { ($0.4, $0.6) < ($1.4, $1.6) }
    for r in ok.prefix(14) {
        print("  \(f(r.0)) s      \(f(r.1)) /s   \(f(r.2 * 1000, 0)) ms   \(r.3)         \(f(r.4 * 1000, 0)) ms        \(f(r.5 * 1000, 0)) ms  \(f(r.6 * 100, 1)) %  \(r.7)")
    }
    let oldRow = rows.first { $0.0 == 0.45 && $0.1 == 0.6 && $0.2 == 0.1 }!
    print("  bản trước: 0.45 s, 0.60 /s, 100 ms → vuốt lọt \(oldRow.3)/\(sw.count), giữ trung vị \(f(oldRow.4 * 1000, 0)) ms")
    let curRow = rows.first { $0.0 == 0.45 && $0.1 == 0.6 && $0.2 == 0.135 }!
    print("  hiện tại: 0.45 s, 0.60 /s, 135 ms → vuốt lọt \(curRow.3), giữ trung vị \(f(curRow.4 * 1000, 0)) ms, khựng \(f(curRow.6 * 100, 1)) %, nhảy \(curRow.7)")
    // tốc độ sớm của cú vuốt
    for t in [0.045, 0.06, 0.075, 0.09] {
        let sv = sw.compactMap { s -> Double? in
            guard let p = s.samples.first(where: { $0.ts - s.samples[0].ts >= t - 0.001 }) else { return nil }
            return hypot(p.x - s.samples[0].x, p.y - s.samples[0].y) / (p.ts - s.samples[0].ts) }
        let cv = cur.compactMap { s -> Double? in
            guard let p = s.samples.first(where: { $0.ts - s.samples[0].ts >= t - 0.001 }) else { return nil }
            return hypot(p.x - s.samples[0].x, p.y - s.samples[0].y) / (p.ts - s.samples[0].ts) }
        print("  tốc độ sau \(f(t * 1000, 0)) ms — vuốt: min \(f(sv.min() ?? 0)) p10 \(f(pct(sv, 0.1)));  rê: trung vị \(f(pct(cv, 0.5))) p90 \(f(pct(cv, 0.9)))")
    }
    let durs = sw.map(\.dur)
    print("  vuốt dài nhất: \(f((durs.max() ?? 0) * 1000, 0)) ms; quãng ngắn nhất \(f(sw.map { max(abs($0.dx), abs($0.dy)) }.min() ?? 0))")
}

// MARK: - Độ chính xác (chỉ khi có file nhãn .phases từ bản ghi có hướng dẫn)

typealias Rules = GestureRules      // luật của app (Sources/GestureRules.swift), không chép lại ở đây

/// Cách TouchEngine.endSession hiểu một lượt chạm (chế độ con trỏ, cả 4 hướng vuốt đã gán).
func appSees(_ s: Session, _ r: Rules) -> String {
    let dur = s.dur + 0.015                          // app tính tới khung nhấc tay
    let end = r.classifyEnd(fingers: s.maxFingers, dur: dur, dx: s.dx, dy: s.dy, travel: s.travel,
                            recent: s.samples.map { ($0.ts, $0.x, $0.y) })
    switch end {
    case .swipe(let key): return key.lowercased()
    case .tap: return "tap"
    case .twoFingerTap: return "twotap"
    case .none: return s.maxFingers >= 2 ? (s.travel >= 0.02 ? "scroll" : "none") : (s.travel >= 0.04 ? "cursor" : "none")
    }
}

func expected(_ label: String) -> Set<String> {
    switch label {
    case "precise", "fast": return ["cursor", "none"]
    default: return [label]
    }
}

let phasePath = path + ".phases"
if let ptext = try? String(contentsOfFile: phasePath, encoding: .utf8) {
    var phaseList: [(String, Double, Double)] = []
    for l in ptext.split(separator: "\n").dropFirst() {
        let c = l.split(separator: ",")
        if c.count == 3, let a = Double(c[1]), let b = Double(c[2]) { phaseList.append((String(c[0]), a, b)) }
    }
    // gán nhãn theo lúc bắt đầu chạm (bỏ 1 giây đầu: còn đang nghe hướng dẫn)
    var labeled: [(String, Session)] = []
    for s in ss {
        let t = s.samples[0].arrival
        if let p = phaseList.first(where: { t >= $0.1 + 1.0 && t <= $0.2 + 0.8 }) { labeled.append((p.0, s)) }
    }
    func score(_ r: Rules) -> (ok: Int, total: Int, falseClicks: Int) {
        var ok = 0, fc = 0
        for (lab, s) in labeled {
            let seen = appSees(s, r)
            if expected(lab).contains(seen) { ok += 1 }
            if (lab == "precise" || lab == "fast"), seen == "tap" || seen.hasPrefix("swipe") { fc += 1 }
        }
        return (ok, labeled.count, fc)
    }

    print("\n▸ Độ chính xác theo thao tác bạn ĐỊNH làm (\(labeled.count) lượt có nhãn)")
    let cur = Rules()
    var old = Rules(); old.twoDur = 0.25; old.endSpeedRule = false
    let so = score(old)
    print("  (quy tắc cũ: \(so.ok)/\(so.total) đúng, rê bị hiểu nhầm \(so.falseClicks))")
    for lab in phaseList.map(\.0) {
        let items = labeled.filter { $0.0 == lab }
        let ok = items.filter { expected(lab).contains(appSees($0.1, cur)) }.count
        var wrong: [String: Int] = [:]
        for (_, s) in items where !expected(lab).contains(appSees(s, cur)) { wrong[appSees(s, cur), default: 0] += 1 }
        let w = wrong.map { "\($0.key)×\($0.value)" }.sorted().joined(separator: ", ")
        print("  \(lab.padding(toLength: 11, withPad: " ", startingAt: 0)) \(ok)/\(items.count)" + (w.isEmpty ? "" : "   nhầm thành: \(w)"))
    }
    let base = score(cur)
    print("  tổng: \(base.ok)/\(base.total) đúng; rê con trỏ bị hiểu thành chạm/vuốt: \(base.falseClicks)")

    print("\n▸ Đặc điểm từng nhóm")
    for lab in ["tap", "twotap"] {
        let it = labeled.filter { $0.0 == lab }.map(\.1)
        guard !it.isEmpty else { continue }
        print("  \(lab): thời gian p50 \(f(pct(it.map { $0.dur + 0.015 }, 0.5) * 1000, 0)) / p90 \(f(pct(it.map { $0.dur + 0.015 }, 0.9) * 1000, 0)) / max \(f((it.map { $0.dur + 0.015 }.max() ?? 0) * 1000, 0)) ms; xê dịch p50 \(f(pct(it.map(\.travel), 0.5), 3)) / p90 \(f(pct(it.map(\.travel), 0.9), 3)) / max \(f(it.map(\.travel).max() ?? 0, 3))")
    }
    let sw = labeled.filter { $0.0.hasPrefix("swipe") }.map(\.1)
    if !sw.isEmpty {
        print("  vuốt: thời gian p90 \(f(pct(sw.map { $0.dur + 0.015 }, 0.9) * 1000, 0)) / max \(f((sw.map { $0.dur + 0.015 }.max() ?? 0) * 1000, 0)) ms; quãng min \(f(sw.map { max(abs($0.dx), abs($0.dy)) }.min() ?? 0)); chéo max \(f((sw.map { min(abs($0.dx), abs($0.dy)) / max(abs($0.dx), abs($0.dy), 1e-6) }.max() ?? 0) * 100, 0)) %")
    }
    let pre = labeled.filter { $0.0 == "precise" }.map(\.1)
    let shortCur = labeled.filter { ($0.0 == "precise" || $0.0 == "fast") && $0.1.maxFingers == 1 }.map(\.1)
    if !shortCur.isEmpty {
        print("  rê ngắn nhất: thời gian \(f((shortCur.map { $0.dur + 0.015 }.min() ?? 0) * 1000, 0)) ms, xê dịch min \(f(shortCur.map(\.travel).min() ?? 0, 3))")
    }

    // Trôi khi nhấc tay: quãng ngón đi trong 30 ms cuối so với tốc độ trước đó (rê chính xác)
    if !pre.isEmpty {
        var lift: [Double] = [], liftPx: [Double] = [], still: [Double] = []
        for s in pre where s.samples.count > 12 && s.maxFingers == 1 {
            let n = s.samples.count
            let a = s.samples[n - 3], b = s.samples[n - 1], c = s.samples[n - 9]
            let vEnd = hypot(b.x - a.x, b.y - a.y) / max(b.ts - a.ts, 0.004)
            let vBefore = hypot(a.x - c.x, a.y - c.y) / max(a.ts - c.ts, 0.004)
            lift.append(vEnd / max(vBefore, 0.02))
            liftPx.append(hypot(b.x - a.x, b.y - a.y) * touchSpeedCfg * 800 * 0.6)
            // rung khi gần như đứng yên: các đoạn tốc độ < 0,08/s
            for (p, q) in zip(s.samples, s.samples.dropFirst()) {
                let v = hypot(q.x - p.x, q.y - p.y) / max(q.ts - p.ts, 0.004)
                if v < 0.08 { still.append(hypot(q.x - p.x, q.y - p.y)) }
            }
        }
        print("\n▸ Con trỏ khi rê chính xác (\(pre.count) lượt)")
        print("  30 ms cuối trước khi nhấc tay: tốc độ gấp p50 \(f(pct(lift, 0.5))) / p90 \(f(pct(lift, 0.9))) lần đoạn trước; con trỏ trôi p50 \(f(pct(liftPx, 0.5), 1)) / p90 \(f(pct(liftPx, 0.9), 1)) px")
        // mô phỏng giữ khung "ngón đang nhấc" (vùng chạm < 70 % đỉnh) như app hiện tại
        var dropped: [Double] = []
        for s in pre where s.samples.count > 12 && s.maxFingers == 1 {
            let raw = s.samples.map(\.size)
            var peak = raw[0], held = 0.0, k = 0
            for i in 1..<s.samples.count {
                peak = max(peak * 0.97, raw[i])
                let d = hypot(s.samples[i].x - s.samples[i - 1].x, s.samples[i].y - s.samples[i - 1].y)
                if raw[i] < 0.7 * peak { held += d; k += 1 } else { held = 0 }
            }
            dropped.append(held * touchSpeedCfg * 800 * 0.6)
            _ = k
        }
        print("  giữ khung ngón đang nhấc → bỏ được p50 \(f(pct(dropped, 0.5), 1)) / p90 \(f(pct(dropped, 0.9), 1)) px trôi")
        print("  rung khi gần như đứng yên: p50 \(f(pct(still, 0.5) * 1000, 2)) / p90 \(f(pct(still, 0.9) * 1000, 2)) ×10⁻³ đơn vị mỗi gói")
    }

    // Dò ngưỡng
    print("\n▸ Dò ngưỡng nhận diện")
    var best = (cur, base)
    for td in [0.2, 0.25, 0.3, 0.35, 0.4] {
        for tt in [0.03, 0.04, 0.05, 0.06, 0.08] {
            for sd in [0.15, 0.18, 0.22, 0.26] {
                for st in [0.35, 0.4, 0.45, 0.5] {
                    for dom in [1.5, 2.0, 2.5] {
                        for (wd, wt) in [(0.25, 0.06), (0.3, 0.06), (0.35, 0.1)] {
                            let r = Rules(tapDur: td, tapTravel: tt, swipeDist: sd, swipeTime: st, swipeDominance: dom, twoDur: wd, twoTravel: wt)
                            let sc = score(r)
                            if (sc.ok - sc.falseClicks * 2, -abs(td - 0.25) - abs(sd - 0.22)) > (best.1.ok - best.1.falseClicks * 2, -abs(best.0.tapDur - 0.25) - abs(best.0.swipeDist - 0.22)) { best = (r, sc) }
                        }
                    }
                }
            }
        }
    }
    let b = best.0
    print("  tốt nhất: \(best.1.ok)/\(best.1.total) đúng (rê bị hiểu nhầm: \(best.1.falseClicks))")
    print("    chạm: < \(f(b.tapDur * 1000, 0)) ms, xê dịch < \(b.tapTravel)   (hiện tại < 250 ms, < 0.04)")
    print("    vuốt: quãng ≥ \(b.swipeDist), < \(f(b.swipeTime * 1000, 0)) ms, thẳng gấp \(b.swipeDominance) lần   (hiện tại 0.22, 400 ms, 2.0)")
    print("    chạm 2 ngón: < \(f(b.twoDur * 1000, 0)) ms, xê dịch < \(b.twoTravel)   (hiện tại < 300 ms, < 0.06)")
}
