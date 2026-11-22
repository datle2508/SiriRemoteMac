// UnitTests.swift
// Test các phần tính toán thuần: bộ lọc One Euro, TouchPath, đọc hành động, tên nút.

import Cocoa

/// Mô tả gọn một Action để so sánh (Action không Equatable vì chứa CGEventFlags).
func describe(_ a: Action?) -> String {
    guard let a = a else { return "nil" }
    switch a {
    case .key(let c, let f): return "key(\(c),\(f.rawValue))"
    case .media(let m): return "media(\(m))"
    case .app(let s): return "app(\(s))"
    case .click: return "click"
    case .scroll(let d): return "scroll(\(d))"
    case .hscroll(let d): return "hscroll(\(d))"
    case .command(let p, let args): return "command(\(p) \(args.joined(separator: " ")))"
    case .nav(let b): return "nav(\(b))"
    case .rightClick: return "rightclick"
    case .zoomToggle: return "zoomtoggle"
    case .smartZoom: return "smartzoom"
    case .dock(let n): return "dock(\(n))"
    case .toggleTouch: return "toggletouch"
    case .powerMenu: return "powermenu"
    case .touchMenu: return "touchmenu"
    }
}

func runUnitTests() {
    group("OneEuro (khử rung toạ độ ngón)")

    test("mẫu đầu tiên đi thẳng qua") {
        var f = OneEuro(minCutoff: 4, beta: 4)
        let p = f.filter(0.3, 0.7, dt: 0.015)
        expect(p.0 == 0.3 && p.1 == 0.7)
    }

    test("ngón đứng yên: rung nhỏ bị khử phần lớn") {
        let prm = OneEuro.params(smooth: 0.55)!
        var f = OneEuro(minCutoff: prm.minCutoff, beta: prm.beta)
        var rng = SeededRNG(seed: 1)
        var raw: [Double] = [], out: [Double] = []
        for _ in 0..<200 {
            let x = 0.5 + rng.gaussian() * 0.002
            raw.append(x); out.append(f.filter(x, 0.5, dt: 0.015).0)
        }
        let sdRaw = roughness(raw) * 0.5, sdOut = roughness(Array(out.dropFirst(20))) * 0.5
        metric("độ rung còn lại", sdOut / sdRaw * 100, unit: " %")
        expect(sdOut < sdRaw * 0.5, "rung chỉ giảm còn \(sdOut / sdRaw)")
    }

    test("đi nhanh: bám sát, trễ nhỏ") {
        let prm = OneEuro.params(smooth: 0.55)!
        var f = OneEuro(minCutoff: prm.minCutoff, beta: prm.beta)
        var x = 0.0, y = 0.0
        for i in 0..<60 { x = Double(i) * 0.03; y = f.filter(x, 0, dt: 0.015).0 }   // 2 đơn vị/giây
        let lag = (x - y) / 2.0                                                          // giây
        metric("trễ", lag * 1000, unit: " ms")
        expect(lag < 0.03, "trễ \(lag * 1000) ms")
    }

    test("độ mượt dưới 5 % thì tắt lọc; tăng độ mượt thì lọc mạnh hơn") {
        expect(OneEuro.params(smooth: 0) == nil)
        expect(OneEuro.params(smooth: 0.04) == nil)
        let a = OneEuro.params(smooth: 0.3)!, b = OneEuro.params(smooth: 0.9)!
        expect(b.minCutoff < a.minCutoff && b.beta < a.beta)
    }

    group("TouchPath (đường đi theo thời gian)")

    test("nội suy giữa hai mẫu, giữ đầu mút ngoài khoảng") {
        var p = TouchPath(lead: 0.01)
        p.add(10, 0, ts: 1.00, arrival: 5.00)
        p.add(10, 0, ts: 1.02, arrival: 5.02)
        expectNear(p.position(at: 4.95).x, 0, tol: 1e-9)          // trước điểm xuất phát
        expectNear(p.position(at: 5.01).x, 15, tol: 1e-6)         // giữa hai mẫu
        expectNear(p.position(at: 9.00).x, 20, tol: 1e-9)         // sau mẫu cuối
    }

    test("gói tới nhanh hơn: dời đường đi cũ, giữ khoảng cách giữa các mẫu") {
        var p = TouchPath(lead: 0.01)
        p.add(10, 0, ts: 1.00, arrival: 5.010)                     // trễ 10 ms
        p.add(10, 0, ts: 1.015, arrival: 5.017)                    // trễ 2 ms → đồng hồ dịch 8 ms
        let ts = p.samples.map(\.t)
        expectNear(ts[2] - ts[1], 0.015, tol: 1e-9)
        expectNear(ts[2], 5.017, tol: 1e-9)
    }

    test("thời gian luôn tăng dù gói đến sai thứ tự") {
        var p = TouchPath(lead: 0.01)
        p.add(1, 0, ts: 1.03, arrival: 5.0)
        p.add(1, 0, ts: 1.01, arrival: 5.001)
        let ts = p.samples.map(\.t)
        expect(zip(ts, ts.dropFirst()).allSatisfy { $0 < $1 })
    }

    test("vận tốc lúc nhấc tay = độ dốc ~60 ms cuối") {
        var p = TouchPath(lead: 0.015)
        for i in 0..<20 { p.add(15, -3, ts: Double(i) * 0.015, arrival: 10 + Double(i) * 0.015) }
        let v = p.velocity(window: 0.06)
        expectNear(v.x, 1000, tol: 1)
        expectNear(v.y, -200, tol: 1)
    }

    test("giữ tối đa 64 mẫu") {
        var p = TouchPath(lead: 0.015)
        for i in 0..<200 { p.add(1, 0, ts: Double(i) * 0.015, arrival: Double(i) * 0.015) }
        expect(p.samples.count == 64)
        expect(p.cumX == 200)
    }

    group("Action.parse (cấu hình hành động)")

    test("các hành động có tên") {
        let cases: [(String, String)] = [
            ("click", "click"), ("rightclick", "rightclick"), ("powermenu", "powermenu"), ("touchmenu", "touchmenu"),
            ("toggletouch", "toggletouch"), ("smartzoom", "smartzoom"), ("zoomtoggle", "zoomtoggle"),
            ("nav:back", "nav(true)"), ("nav:forward", "nav(false)"),
            ("sleep", "command(/usr/bin/pmset sleepnow)"),
            ("mission", "dock(com.apple.expose.awake)"),
        ]
        for (spec, want) in cases { expect(describe(Action.parse(spec)) == want, "\(spec) → \(describe(Action.parse(spec)))") }
    }

    test("phím tắt có phím bổ trợ") {
        let cmdSpace = CGEventFlags.maskCommand.rawValue
        expect(describe(Action.parse("key:cmd+space")) == "key(49,\(cmdSpace))")
        expect(describe(Action.parse("key:CMD+Shift+Left")) ==
               "key(123,\(CGEventFlags.maskCommand.union(.maskShift).rawValue))")
        expect(describe(Action.parse("zoomin")) == "key(24,\(cmdSpace))")
    }

    test("cuộn dọc / ngang, media, mở app") {
        expect(describe(Action.parse("scroll:up")) == "scroll(1)")
        expect(describe(Action.parse("scroll:down")) == "scroll(-1)")
        expect(describe(Action.parse("scroll:left")) == "hscroll(1)")
        expect(describe(Action.parse("scroll:right")) == "hscroll(-1)")
        expect(describe(Action.parse("media:PlayPause")) == "media(16)")
        expect(describe(Action.parse("app:Visual Studio Code")) == "app(Visual Studio Code)")
    }

    test("cấu hình sai trả về nil") {
        for bad in ["", "key:", "key:cmd+nosuchkey", "scroll:sideways", "media:nope", "whatever", "foo:bar"] {
            expect(Action.parse(bad) == nil, "'\(bad)' lẽ ra phải nil, được \(describe(Action.parse(bad)))")
        }
    }

    group("Tên nút ↔ mã HID")

    test("tên nút, +hold, +double → mã HID") {
        expect(normalizeKey("home") == "0C:0060")
        expect(normalizeKey(" Home+Hold ") == "0C:0060+HOLD")
        expect(normalizeKey("menu+double") == "01:0086+DOUBLE")
        expect(normalizeKey("swipeup") == "SWIPEUP")
    }

    test("mã HID → tên nút (canonicalKey là nghịch đảo)") {
        for name in ["home", "siri+hold", "playpause+double", "volup"] {
            expect(canonicalKey(normalizeKey(name)) == name, "\(name) → \(canonicalKey(normalizeKey(name)))")
        }
        expect(canonicalKey("SwipeUp") == "swipeup")
    }

    test("mặc định: mọi hành động trong defaultMap đều đọc được") {
        for (k, v) in defaultMap where !settingKeys.contains(k) {
            expect(Action.parse(v) != nil, "\(k): \(v)")
        }
    }
}
