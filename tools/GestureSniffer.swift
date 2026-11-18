// GestureSniffer.swift
// Ghi lại MỌI trường của các sự kiện cử chỉ (gesture, magnify, smart magnify…) đi qua hệ thống,
// để sao chép đúng cú "chạm đúp hai ngón = zoom thông minh" của trackpad thật.
//
// Build:  swiftc -O tools/GestureSniffer.swift -o gesturesniffer
// Chạy:   ./gesturesniffer | tee gesture.log      (cần quyền Input Monitoring / Accessibility)

import Cocoa

// Mọi loại sự kiện trừ di chuột / cuộn (quá nhiều, không liên quan)
var mask: CGEventMask = 0
for t in 0..<64 where ![5, 6, 7, 22, 27].contains(t) { mask |= CGEventMask(1) << CGEventMask(t) }
var lastMs = 0.0

guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask,
    callback: { _, type, event, _ in
        let ms = Double(event.timestamp) / 1_000_000
        var parts: [String] = []
        for f in 0..<256 {
            guard let field = CGEventField(rawValue: UInt32(f)) else { continue }
            let i = event.getIntegerValueField(field)
            let d = event.getDoubleValueField(field)
            if i != 0 || d != 0 {
                parts.append("\(f)=\(i)" + (Double(i) != d ? "/" + String(format: "%.4f", d) : ""))
            }
        }
        let ns = NSEvent(cgEvent: event).map { " ns=\($0.type.rawValue)" } ?? ""
        let loc = event.location
        print(String(format: "+%.1fms type=%d%@ flags=%llx loc=(%.0f,%.0f) ", ms - lastMs, type.rawValue, ns,
                     event.flags.rawValue, loc.x, loc.y) + parts.joined(separator: " "))
        lastMs = ms
        fflush(stdout)
        return Unmanaged.passUnretained(event)
    }, userInfo: nil) else {
    print("Không tạo được event tap: cấp quyền Input Monitoring / Accessibility rồi chạy lại.")
    exit(1)
}

let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
print("Đang ghi. Trong Safari, CHẠM ĐÚP HAI NGÓN trên trackpad thật (zoom thông minh) 2 lần, rồi Ctrl+C.")
CFRunLoopRun()
