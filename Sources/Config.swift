// Config.swift
// Tên nút, cấu hình mặc định, đọc/ghi ~/.siriremote.json.

import Cocoa

// MARK: - Cấu hình

/// Tên nút dùng trong file cấu hình → mã HID. Vẫn có thể dùng mã "PP:UUUU" trực tiếp.
let builtinButtonNames: [String: String] = [
    "menu": "01:0086", "home": "0C:0060", "siri": "0C:0004", "touchpad": "0C:0080",
    "playpause": "0C:00CD", "volup": "0C:00E9", "voldown": "0C:00EA",
    // Remote đời 2/3: mã theo chuẩn HID Consumer Control (chưa kiểm chứng trên máy thật;
    // nếu sai, dùng "Học nút mới…" trong cài đặt để tự ghi nhận mã đúng).
    "up": "0C:0042", "down": "0C:0043", "left": "0C:0044", "right": "0C:0045", "select": "0C:0041",
    "back": "0C:0224", "tv": "0C:0223", "mute": "0C:00E2", "power": "0C:0030",
]
/// Gồm nút có sẵn + nút tự học (khóa "custombuttons" trong file cấu hình).
var buttonNames = builtinButtonNames
var customButtons: [String: String] = [:]
var detectedProductID: Int = 0          // product ID của remote đang kết nối (0x266 = đời 1)

func registerCustomButtons(_ raw: [String: Any]) {
    customButtons = [:]
    buttonNames = builtinButtonNames
    for (k, v) in raw {
        let name = k.lowercased().trimmingCharacters(in: .whitespaces)
        let code = "\(v)".uppercased().trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, code.contains(":") else { continue }
        customButtons[name] = code
        buttonNames[name] = code
    }
}

/// Thêm "+hold" sau tên nút (ví dụ "home+hold") cho hành động khi giữ nút.
let defaultMap: [String: String] = [
    "menu": "media:previous",       // bài trước
    "home": "media:next",           // bài kế tiếp (bấm nhanh)
    "home+hold": "sleep",           // giữ nút đủ lâu để Mac sleep
    "siri": "app:Siri",             // mở Siri
    "siri+hold": "toggletouch",     // giữ Siri: đổi chế độ cảm ứng con trỏ ↔ vuốt/chạm
    "touchpad": "click",            // nhấn touchpad = click chuột trái
    "playpause": "media:playpause",
    "volup": "media:volumeup",
    "voldown": "media:volumedown",
    "remotemodel": "auto",          // auto | gen1 | gen23: quyết định các nút hiển thị trong cài đặt
    "twofingertap": "rightclick",   // chạm nhẹ hai ngón = click chuột phải
    "scrollmomentum": "1",          // 1 = cuộn tiếp (giảm dần) sau khi nhấc tay
    "clicksteady": "1",             // 1 = giữ yên con trỏ khi nhấn touchpad để click trúng đích
    "touchmode": "cursor",          // cảm ứng: cursor (con trỏ + cuộn + vuốt), swipe (chỉ vuốt/chạm), off
    "touchspeed": "1.5",            // tốc độ con trỏ (0.3 – 5)
    "scrollspeed": "1.0",           // tốc độ cuộn hai ngón (0.2 – 4)
    "navduration": "0.3",           // thời gian cú vuốt Back/Forward (giây, 0.15 – 1.0)
    "navdistance": "0.9",           // quãng vuốt = tỉ lệ chiều rộng cửa sổ (0.4 – 2.0)
    "navinvert": "0",               // 1 = đảo chiều hiệu ứng Back/Forward (nav:back / nav:forward)
    "naturalscroll": "1",           // 1 = cuộn tự nhiên (đảo chiều), 0 = ngược lại
    "tapclick": "0",                // 1 = chạm nhẹ để click
    "touchfamily": "160,145",       // mã họ thiết bị MultitouchSupport của remote (xem log khi bật "Ghi log")
    "doubletime": "0.3",            // số giây tối đa giữa 2 lần nhấn để tính là nhấn đúp (0.15 – 1.0)
    "holdtime": "0.8",              // số giây giữ nút để tính là "giữ" (0.2 – 3.0)
]

func normalizeKey(_ raw: String) -> String {
    var k = raw.trimmingCharacters(in: .whitespaces).lowercased()
    var suffix = ""
    for (low, up) in [("+hold", "+HOLD"), ("+double", "+DOUBLE")] where k.hasSuffix(low) {
        suffix = up
        k = String(k.dropLast(low.count))
        break
    }
    return (buttonNames[k] ?? k.uppercased()) + suffix
}

/// Các nút hệ thống tự xử lý khi KHÔNG chiếm quyền remote (tránh chạy trùng).
let systemHandledKeys: Set<String> = ["0C:00CD", "0C:00E9", "0C:00EA", "0C:00E2"]

let configPath = NSHomeDirectory() + "/.siriremote.json"
let logPath = NSHomeDirectory() + "/Library/Logs/SiriRemoteMac.log"
var debugLog = false
var holdDelaySeconds: TimeInterval = 0.8   // đổi bằng khóa "holdtime" trong file cấu hình
var doubleDelaySeconds: TimeInterval = 0.3 // khoảng cách tối đa giữa hai lần nhấn đúp, khóa "doubletime"

enum TouchMode: String { case off, cursor, swipe }

/// Cấu hình riêng mặc định cho một số app (chỉ thêm một lần, sau đó bạn tự do sửa/xóa).
let seedApps: [String: [String: String]] = [
    "com.apple.Safari": ["menu": "key:cmd+[", "home": "key:cmd+]"],     // Menu = Back, Home = Forward
]

func migrateConfig() {
    var c = ConfigFile.load()
    var changed = false
    for (bid, specs) in seedApps where !c.seeded.contains(bid) {
        if c.apps[bid] == nil { c.apps[bid] = specs }
        c.seeded.append(bid)
        changed = true
    }
    // Một lần: hiệu ứng vuốt (nav:back/forward) chưa chạy ổn trên Safari → trả về phím cmd+[ / cmd+]
    let revert = "com.apple.Safari:keys"
    if !c.seeded.contains(revert) {
        if c.apps["com.apple.Safari"]?["menu"] == "nav:back" && c.apps["com.apple.Safari"]?["home"] == "nav:forward" {
            c.apps["com.apple.Safari"]?["menu"] = "key:cmd+["
            c.apps["com.apple.Safari"]?["home"] = "key:cmd+]"
        }
        c.seeded.append(revert)
        changed = true
    }
    if changed || !FileManager.default.fileExists(atPath: configPath) { c.save() }
}

var touchMode: TouchMode = .cursor
var touchSpeed = 1.5
var scrollSpeed = 1.0
var naturalScroll = true
var tapClick = false
var scrollMomentum = true
var clickSteady = true
var touchFamilies: Set<Int32> = [160, 145]   // 160: Siri Remote đời 1 (đo trên máy thật), 145: đời 3
var mouseButtonDown = false      // Controller đặt khi nút touchpad đang được nhấn (để kéo thả bằng cảm ứng)

func log(_ s: String) {
    guard let data = "\(Date()) \(s)\n".data(using: .utf8) else { return }
    if let h = FileHandle(forWritingAtPath: logPath) {
        h.seekToEndOfFile(); h.write(data); h.closeFile()
    } else {
        FileManager.default.createFile(atPath: logPath, contents: data)
    }
}

/// Cấu hình riêng cho từng app (khóa = bundle id, ví dụ "com.apple.Safari"), nằm trong khóa "apps" của file cấu hình.
var appOverrides: [String: [String: Action]] = [:]
var appDisabled: [String: Set<String>] = [:]     // nút bị tắt ("none") riêng trong app đó

/// Các khóa là tùy chọn (không phải nút bấm / cử chỉ).
let settingKeys: Set<String> = ["holdtime", "doubletime", "remotemodel", "navinvert", "touchmode",
                                "touchspeed", "scrollspeed", "naturalscroll", "tapclick", "touchfamily",
                                "scrollmomentum", "clicksteady", "navduration", "navdistance"]

/// Đọc file cấu hình (qua ConfigFile) → bản đồ nút → hành động; cập nhật các tùy chọn toàn cục.
func loadMap() -> [String: Action] {
    let cfg = ConfigFile.load()
    var specs = cfg.global
    func take(_ k: String) -> String? { specs.removeValue(forKey: k) }
    func flag(_ v: String) -> Bool { v == "1" || v.lowercased() == "true" }
    func number(_ k: String, _ range: ClosedRange<Double>) -> Double? {
        guard let v = take(k) else { return nil }
        guard let d = Double(v) else { log("\(k) không hợp lệ: \(v)"); return nil }
        return min(max(d, range.lowerBound), range.upperBound)
    }

    if let t = number("doubletime", 0.15...1.0) { doubleDelaySeconds = t }
    if let t = number("holdtime", 0.2...3.0) { holdDelaySeconds = t }
    if let t = number("touchspeed", 0.3...5.0) { touchSpeed = t }
    if let t = number("scrollspeed", 0.2...4.0) { scrollSpeed = t }
    if let t = number("navduration", 0.15...1.0) { navDuration = t }
    if let t = number("navdistance", 0.4...2.0) { navDistance = t }
    if let v = take("touchmode") { touchMode = TouchMode(rawValue: v.lowercased()) ?? .cursor }
    if let v = take("navinvert") { navInvert = flag(v) }
    if let v = take("naturalscroll") { naturalScroll = !(v == "0" || v.lowercased() == "false") }
    if let v = take("tapclick") { tapClick = flag(v) }
    if let v = take("scrollmomentum") { scrollMomentum = !(v == "0" || v.lowercased() == "false") }
    if let v = take("clicksteady") { clickSteady = !(v == "0" || v.lowercased() == "false") }
    if let v = take("touchfamily") {   // danh sách cách nhau bằng dấu phẩy; luôn gồm 160 và 145
        touchFamilies = Set(v.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Int32($0) }).union([160, 145])
    }
    _ = take("remotemodel")

    var map: [String: Action] = [:]
    for (k, v) in specs {
        if v.isEmpty || v == "none" { continue }   // "none": tắt hành động mặc định của nút này
        if let a = Action.parse(v) { map[normalizeKey(k)] = a } else { log("Hành động không hợp lệ: \(k) → \(v)") }
    }

    appOverrides = [:]; appDisabled = [:]
    for (bid, d) in cfg.apps {
        for (k, spec) in d where !settingKeys.contains(k) {
            let key = normalizeKey(k)
            if spec.isEmpty || spec == "none" { appDisabled[bid, default: []].insert(key) }
            else if let a = Action.parse(spec) { appOverrides[bid, default: [:]][key] = a }
            else { log("Hành động không hợp lệ trong \(bid): \(k) → \(spec)") }
        }
    }
    return map
}

// MARK: - Tệp cấu hình (dùng cho giao diện)

func canonicalKey(_ raw: String) -> String {
    let n = normalizeKey(raw)
    var base = n, suffix = ""
    for sfx in ["+HOLD", "+DOUBLE"] where n.hasSuffix(sfx) {
        base = String(n.dropLast(sfx.count)); suffix = sfx.lowercased(); break
    }
    if let name = buttonNames.first(where: { $0.value == base })?.key { return name + suffix }
    return raw.trimmingCharacters(in: .whitespaces).lowercased()
}

struct ConfigFile {
    var global: [String: String] = [:]
    var apps: [String: [String: String]] = [:]
    var custom: [String: String] = [:]
    var seeded: [String] = []

    static func load() -> ConfigFile {
        var c = ConfigFile()
        let fileData = FileManager.default.contents(atPath: configPath)
        let parsed = fileData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        if fileData != nil && parsed == nil { log("File cấu hình sai định dạng, dùng mặc định") }
        registerCustomButtons((parsed?["custombuttons"] as? [String: Any]) ?? [:])
        for (k, v) in defaultMap { c.global[canonicalKey(k)] = v }
        if let obj = parsed {
            for (k, v) in obj {
                if k == "seededapps" {
                    c.seeded = (v as? [String]) ?? []
                } else if k == "custombuttons" {
                    for (n, code) in (v as? [String: Any]) ?? [:] { c.custom[n.lowercased()] = "\(code)".uppercased() }
                } else if k == "apps" {
                    for (bid, d) in (v as? [String: Any]) ?? [:] {
                        var m: [String: String] = [:]
                        for (kk, vv) in (d as? [String: Any]) ?? [:] { m[canonicalKey(kk)] = "\(vv)" }
                        c.apps[bid] = m
                    }
                } else {
                    c.global[canonicalKey(k)] = "\(v)"
                }
            }
        }
        return c
    }

    func save() {
        var dict: [String: Any] = global
        if !apps.isEmpty { dict["apps"] = apps }
        if !custom.isEmpty { dict["custombuttons"] = custom }
        if !seeded.isEmpty { dict["seededapps"] = seeded }
        guard let d = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? d.write(to: URL(fileURLWithPath: configPath), options: .atomic)
    }
}

