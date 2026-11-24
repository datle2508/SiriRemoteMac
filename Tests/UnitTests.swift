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

    group("File cấu hình")

    test("file hỏng (gõ tay sai cú pháp): cất bản cũ sang .broken trước khi ghi đè") {
        let dir = NSTemporaryDirectory() + "siriremote-test-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = dir + "/cfg.json"
        let broken = "{ \"home\": \"media:next\", \"apps\": "
        try? broken.write(toFile: path, atomically: true, encoding: .utf8)
        var c = ConfigFile.load(from: path)
        expect(c.unreadable)
        c.global["touchmode"] = "swipe"
        c.save(to: path)
        expect((try? String(contentsOfFile: path + ".broken", encoding: .utf8)) == broken, "bản cũ phải còn nguyên")
        let again = ConfigFile.load(from: path)
        expect(!again.unreadable && again.global["touchmode"] == "swipe")
    }

    test("file đúng: ghi rồi đọc lại giữ nguyên, không tạo .broken") {
        let dir = NSTemporaryDirectory() + "siriremote-test-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = dir + "/cfg.json"
        var c = ConfigFile.load(from: path)                 // chưa có file: mặc định, không phải "hỏng"
        expect(!c.unreadable)
        c.apps["com.apple.Safari"] = ["menu": "key:cmd+["]
        c.save(to: path)
        let back = ConfigFile.load(from: path)
        expect(back.apps["com.apple.Safari"]?["menu"] == "key:cmd+[")
        expect(!FileManager.default.fileExists(atPath: path + ".broken"))
    }

    group("Bản dịch tiếng Anh")

    test("bảng chuỗi tiếng Anh nạp được (khoá trùng làm app sập khi giao diện là English)") {
        expect(englishStrings["Thoát"] == "Quit")
    }

    group("Nhận dạng cử chỉ lúc nhấc tay (GestureRules)")

    /// Lượt một ngón đi đều từ (0,0) tới (dx, dy) trong dur giây, mẫu mỗi 15 ms.
    func line(_ dx: Double, _ dy: Double, _ dur: Double) -> [(t: Double, x: Double, y: Double)] {
        let n = max(Int(dur / 0.015), 1)
        return (0...n).map { i in let u = Double(i) / Double(n); return (u * dur, dx * u, dy * u) }
    }
    func end(_ dx: Double, _ dy: Double, _ dur: Double, fingers: Int = 1,
             _ r: GestureRules = .cursor) -> TouchEnd {
        r.classifyEnd(fingers: fingers, dur: dur, dx: dx, dy: dy, travel: hypot(dx, dy), recent: line(dx, dy, dur))
    }

    test("vuốt nhanh, thẳng: nhận đúng hướng") {
        expect(end(0.3, 0.02, 0.2) == .swipe("SWIPERIGHT"))
        expect(end(-0.3, 0, 0.2) == .swipe("SWIPELEFT"))
        expect(end(0, 0.25, 0.15) == .swipe("SWIPEUP"))
        expect(end(0.05, -0.4, 0.25) == .swipe("SWIPEDOWN"))
    }

    test("không phải vuốt: ngắn, chậm, hay chéo") {
        expect(end(0.2, 0, 0.2) == .none, "ngắn hơn 0,22")
        expect(end(0.4, 0, 0.45) == .none, "lâu hơn 0,4 s")
        expect(end(0.3, 0.2, 0.2) == .none, "chéo")
    }

    test("rê nhanh rồi dừng trước khi nhấc: không phải vuốt") {
        // 0,35 s: đi nhanh 0,3 trong 0,25 s rồi gần như đứng yên 0,1 s
        var r = line(0.3, 0, 0.25)
        for i in 1...7 { r.append((0.25 + Double(i) * 0.015, 0.3 + Double(i) * 0.001, 0)) }
        let e = GestureRules.cursor.classifyEnd(fingers: 1, dur: 0.355, dx: 0.307, dy: 0, travel: 0.307, recent: r)
        expect(e == .none, "\(e)")
        expect(end(0.6, 0, 0.35) == .swipe("SWIPERIGHT"), "vẫn nhanh (≥ 1,5/s) tới lúc nhấc thì là vuốt")
    }

    test("chạm một ngón / hai ngón") {
        expect(end(0.01, 0.01, 0.1) == .tap)
        expect(end(0.01, 0, 0.3) == .none, "giữ lâu không phải chạm")
        expect(end(0.02, 0, 0.25, fingers: 2) == .twoFingerTap)
        expect(end(0.02, 0, 0.35, fingers: 2) == .none)
        expect(end(0.02, 0, 0.1, fingers: 3) == .none)
    }

    test("chế độ vuốt/chạm: nhận vuốt dài hơn, chậm hơn") {
        expect(end(0.21, 0, 0.2, .swipe) == .swipe("SWIPERIGHT"))
        expect(end(0.21, 0, 0.2) == .none)
        expect(end(0.8, 0, 0.5, .swipe) == .swipe("SWIPERIGHT"))
        expect(end(0.8, 0, 0.5) == .none)
    }

    test("thanh trượt Nhận vuốt: 100 % → 0,6/s, 0 % → 1,4/s, kẹp ngoài 0…1") {
        expectNear(GestureRules.slowSpeed(priority: 1), 0.6, tol: 1e-9)
        expectNear(GestureRules.slowSpeed(priority: 0), 1.4, tol: 1e-9)
        expectNear(GestureRules.slowSpeed(priority: 5), 0.6, tol: 1e-9)
    }

    test("mặc định: mọi hành động trong defaultMap đều đọc được") {
        for (k, v) in defaultMap where !settingKeys.contains(k) {
            expect(Action.parse(v) != nil, "\(k): \(v)")
        }
    }
}
