// TouchRecorder.swift
// Ghi lại MỌI khung cảm ứng của touchpad Siri Remote (dấu thời gian lấy mẫu, lúc tới, toạ độ từng ngón)
// để phân tích cách vuốt thật và phát lại qua bộ xử lý của app khi tinh chỉnh độ mượt.
//
// Build:  swiftc -O tools/TouchRecorder.swift -o touchrecorder
// Chạy:   ./touchrecorder 120 touch.csv        (ghi 120 giây; app SiriRemoteMac vẫn chạy bình thường)
//         ./touchrecorder 0 touch.csv guided   (có hướng dẫn bằng giọng nói từng thao tác; ghi nhãn vào touch.csv.phases)
//
// Mỗi dòng CSV: arrival,ts,frame,id,x,y,state,size   (một dòng cho mỗi ngón; khung không có ngón: id = -1)

import Foundation

struct MTPoint { var x: Float; var y: Float }
struct MTVector { var pos: MTPoint; var vel: MTPoint }
struct MTTouch {
    var frame: Int32; var timestamp: Double; var identifier: Int32; var state: Int32
    var fingerId: Int32; var handId: Int32; var normalized: MTVector; var size: Float
    var pressure: Int32; var angle: Float; var majorAxis: Float; var minorAxis: Float
    var absoluteVector: MTVector; var unknown1: Int32; var unknown2: Int32; var density: Float
}
typealias MTContactCB = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Void

let args = CommandLine.arguments
let guided = args.count > 3 && args[3] == "guided"
let outPath = args.count > 2 ? args[2] : "touch.csv"

/// Các bước ghi có hướng dẫn: (nhãn, số giây, câu đọc lên)
let phases: [(String, Double, String)] = [
    ("tap", 20, "Chạm nhẹ một ngón, mười lần, chậm rãi. Không bấm lún."),
    ("swipeup", 16, "Vuốt lên, mười lần."),
    ("swipedown", 16, "Vuốt xuống, mười lần."),
    ("swipeleft", 14, "Vuốt sang trái, tám lần."),
    ("swiperight", 14, "Vuốt sang phải, tám lần."),
    ("precise", 25, "Rê con trỏ thật chậm và chính xác, đưa tới từng biểu tượng trên thanh Dock rồi nhấc tay."),
    ("fast", 16, "Rê con trỏ nhanh qua lại khắp màn hình."),
    ("twotap", 14, "Chạm nhẹ hai ngón cùng lúc, sáu lần."),
]
let duration = guided ? phases.reduce(12) { $0 + $1.1 + 1 } : (args.count > 1 ? Double(args[1]) ?? 120 : 120)

func speak(_ text: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    p.arguments = ["-v", "Linh", text]
    try? p.run()
}
FileManager.default.createFile(atPath: outPath, contents: Data("arrival,ts,frame,id,x,y,state,size\n".utf8))
let out = FileHandle(forWritingAtPath: outPath)!
out.seekToEndOfFile()
let lock = NSLock()
var buffer = ""
var frames = 0, touchFrames = 0

let callback: MTContactCB = { _, raw, n, ts, frame in
    let arrival = ProcessInfo.processInfo.systemUptime
    var s = ""
    if let raw = raw, n > 0 {
        let t = raw.assumingMemoryBound(to: MTTouch.self)
        for i in 0..<Int(n) {
            s += String(format: "%.6f,%.6f,%d,%d,%.5f,%.5f,%d,%.3f\n", arrival, ts, frame, t[i].identifier,
                        t[i].normalized.pos.x, t[i].normalized.pos.y, t[i].state, t[i].size)
        }
    } else {
        s = String(format: "%.6f,%.6f,%d,-1,0,0,0,0\n", arrival, ts, frame)
    }
    lock.lock(); buffer += s; frames += 1; if n > 0 { touchFrames += 1 }; lock.unlock()
}

guard let h = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW),
      let sList = dlsym(h, "MTDeviceCreateList"), let sReg = dlsym(h, "MTRegisterContactFrameCallback"),
      let sStart = dlsym(h, "MTDeviceStart"), let sFam = dlsym(h, "MTDeviceGetFamilyID") else {
    print("Không nạp được MultitouchSupport"); exit(1)
}
typealias FnList = @convention(c) () -> UnsafeRawPointer?
typealias FnReg = @convention(c) (UnsafeMutableRawPointer, MTContactCB) -> Void
typealias FnStart = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
typealias FnFam = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<Int32>) -> Int32

guard let rawList = unsafeBitCast(sList, to: FnList.self)() else { print("Không có thiết bị cảm ứng"); exit(1) }
let list = Unmanaged<CFArray>.fromOpaque(rawList).takeRetainedValue()
var used = 0
for i in 0..<CFArrayGetCount(list) {
    guard let p = CFArrayGetValueAtIndex(list, i) else { continue }
    let dev = UnsafeMutableRawPointer(mutating: p)
    var fam: Int32 = -1
    _ = unsafeBitCast(sFam, to: FnFam.self)(dev, &fam)
    guard fam == 160 || fam == 145 else { continue }       // chỉ touchpad của Siri Remote
    unsafeBitCast(sReg, to: FnReg.self)(dev, callback)
    unsafeBitCast(sStart, to: FnStart.self)(dev, 0)
    used += 1
}
guard used > 0 else { print("Không thấy Siri Remote (bấm một nút trên remote để nó kết nối rồi chạy lại)"); exit(1) }

print("Đang ghi \(Int(duration)) giây vào \(outPath)…"); fflush(stdout)
let timer = DispatchSource.makeTimerSource(queue: .main)
timer.schedule(deadline: .now() + 1, repeating: 1)
let start = Date()
if guided {
    speak("Chuẩn bị. Đặt con trỏ vào chỗ trống trên màn hình.")
    var lines = "label,start,end\n"
    var at = 10.0                               // 10 giây chuẩn bị
    for (label, secs, text) in phases {
        let t0 = ProcessInfo.processInfo.systemUptime + at
        lines += String(format: "%@,%.3f,%.3f\n", label, t0, t0 + secs)
        DispatchQueue.main.asyncAfter(deadline: .now() + at) { print("▶ \(text)"); fflush(stdout); speak(text) }
        at += secs + 1
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + at - 0.5) { speak("Xong. Cảm ơn bạn.") }
    try? lines.write(toFile: outPath + ".phases", atomically: true, encoding: .utf8)
}
timer.setEventHandler {
    lock.lock(); let s = buffer; buffer = ""; let f = frames, tf = touchFrames; lock.unlock()
    out.write(Data(s.utf8))
    let el = Date().timeIntervalSince(start)
    if Int(el) % 15 == 0 { print("  \(Int(el)) s: \(f) khung, \(tf) có ngón"); fflush(stdout) }
    if el >= duration {
        out.closeFile()
        print("Xong: \(f) khung, \(tf) có ngón → \(outPath)")
        exit(0)
    }
}
timer.resume()
dispatchMain()
