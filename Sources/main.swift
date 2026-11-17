// main.swift
// SiriRemoteMac: ứng dụng thanh menu dùng Apple TV Siri Remote để điều khiển Mac.
//
// Build:  ./build_app.sh   (hoặc: swiftc -O Sources/*.swift -o SiriRemoteMac)
// Quyền:  System Settings → Privacy & Security → Accessibility + Input Monitoring
// Cấu hình: ~/.siriremote.json hoặc menu 🎛 → Cài đặt… (xem README.md)

import Cocoa

let app = NSApplication.shared
app.delegate = appDelegate
app.setActivationPolicy(.accessory)
app.run()
