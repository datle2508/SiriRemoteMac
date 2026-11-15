// Sniffer.swift - chỉ NGHE các gói HID của Siri Remote, không chiếm quyền, không ghi gì vào remote.
// Build: swiftc -O tools/Sniffer.swift -o sniffer
// Chạy:  ./sniffer | tee ~/sniffer.log
// Cần quyền Input Monitoring cho Terminal.

import Foundation
import IOKit.hid

final class Tag { let label: String; init(_ l: String) { label = l } }

var lastSig: [String: String] = [:]
var repeats: [String: Int] = [:]
let t0 = Date()

func out(_ s: String) {
    print(String(format: "%8.3f ", Date().timeIntervalSince(t0)) + s)
    fflush(stdout)
}

func onReport(_ ctx: UnsafeMutableRawPointer?, _ r: IOReturn, _ s: UnsafeMutableRawPointer?,
              _ type: IOHIDReportType, _ id: UInt32,
              _ report: UnsafeMutablePointer<UInt8>, _ len: CFIndex) {
    guard let ctx = ctx else { return }
    let label = Unmanaged<Tag>.fromOpaque(ctx).takeUnretainedValue().label
    let hex = (0..<len).map { String(format: "%02X", report[$0]) }.joined(separator: " ")
    let sig = "\(id):\(hex)"
    if lastSig[label] == sig { repeats[label, default: 0] += 1; return }
    if let n = repeats[label], n > 0 { out("[\(label)] (lặp \(n) lần)"); repeats[label] = 0 }
    lastSig[label] = sig
    out("[\(label)] id=\(id) len=\(len): \(hex)")
}

func onAdded(_ ctx: UnsafeMutableRawPointer?, _ r: IOReturn, _ s: UnsafeMutableRawPointer?, _ d: IOHIDDevice) {
    let name = (IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) as? String) ?? ""
    guard name.lowercased().contains("remote") else { return }
    let page = (IOHIDDeviceGetProperty(d, kIOHIDPrimaryUsagePageKey as CFString) as? Int) ?? 0
    let usage = (IOHIDDeviceGetProperty(d, kIOHIDPrimaryUsageKey as CFString) as? Int) ?? 0
    let label = String(format: "%04X:%04X", page, usage)
    let res = IOHIDDeviceOpen(d, IOOptionBits(kIOHIDOptionsTypeNone))
    out("Mở \(label) -> \(String(format: "0x%08X", UInt32(bitPattern: res))) " +
        (res == kIOReturnSuccess ? "OK" : "(lỗi; 0xE00002C5 = đang bị app khác chiếm quyền)"))
    guard res == kIOReturnSuccess else { return }
    let maxIn = max((IOHIDDeviceGetProperty(d, kIOHIDMaxInputReportSizeKey as CFString) as? Int) ?? 64, 64) + 8
    let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: maxIn)
    let tag = Unmanaged.passRetained(Tag(label)).toOpaque()
    IOHIDDeviceRegisterInputReportCallback(d, buf, maxIn, onReport, tag)
    IOHIDDeviceScheduleWithRunLoop(d, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
}

let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(m, [kIOHIDVendorIDKey as String: 0x004C] as CFDictionary)
IOHIDManagerRegisterDeviceMatchingCallback(m, onAdded, nil)
IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
out("Đang nghe... vuốt 1 ngón, cuộn 2 ngón, nhấn touchpad. Ctrl+C để dừng.")
CFRunLoopRun()
