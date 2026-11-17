// ScrollSniffer.swift
// Ghi lại MỌI trường của các sự kiện cuộn (scrollWheel) đi qua hệ thống, để so sánh cú vuốt thật của trackpad
// với cú vuốt giả lập của SiriRemoteMac (hành động nav:back / nav:forward).
//
// Build:  swiftc -O tools/ScrollSniffer.swift -o scrollsniffer
// Chạy:   ./scrollsniffer | tee scroll.log      (Terminal cần quyền Input Monitoring / Accessibility)

import Cocoa

let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
var lastMs = 0.0

guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask,
    callback: { _, _, event, _ in
        let ms = Double(event.timestamp) / 1_000_000
        var parts: [String] = []
        for f in 0..<200 {
            guard let field = CGEventField(rawValue: UInt32(f)) else { continue }
            let i = event.getIntegerValueField(field)
            let d = event.getDoubleValueField(field)
            if i != 0 || d != 0 {
                parts.append("\(f)=\(i)" + (Double(i) != d ? "/" + String(format: "%.3f", d) : ""))
            }
        }
        let loc = event.location
        print(String(format: "+%.1fms flags=%llx loc=(%.0f,%.0f) ", ms - lastMs, event.flags.rawValue, loc.x, loc.y) + parts.joined(separator: " "))
        lastMs = ms
        fflush(stdout)
        return Unmanaged.passUnretained(event)
    }, userInfo: nil) else {
    print("Không tạo được event tap: cấp quyền Input Monitoring / Accessibility cho Terminal rồi chạy lại.")
    exit(1)
}

let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
print("Đang ghi. (1) Vuốt 2 ngón sang phải trên TRACKPAD THẬT trong Safari để Back, chờ 2 giây; (2) bấm nút Menu trên remote (nav:back); (3) Ctrl+C.")
CFRunLoopRun()
