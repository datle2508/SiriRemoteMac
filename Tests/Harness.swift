// Harness.swift
// Khung test tối giản (không cần Xcode project / SwiftPM): test(...) + expect(...), in kết quả, mã thoát ≠ 0 khi có lỗi.

import Foundation

var testsRun = 0
var testsFailed = 0
private var currentFailed = false

func group(_ name: String) { print("\n▸ \(name)") }

func test(_ name: String, _ body: () -> Void) {
    testsRun += 1
    currentFailed = false
    body()
    if currentFailed { testsFailed += 1 }
    print(currentFailed ? "  ✗ \(name)" : "  ✓ \(name)")
}

func expect(_ cond: Bool, _ msg: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) {
    guard !cond else { return }
    currentFailed = true
    print("    ↳ \(file):\(line) \(msg())")
}

func expectNear(_ a: Double, _ b: Double, tol: Double, _ msg: @autoclosure () -> String = "",
                file: StaticString = #fileID, line: UInt = #line) {
    expect(abs(a - b) <= tol, "\(a) ≉ \(b) (±\(tol)) \(msg())", file: file, line: line)
}

/// Báo một chỉ số đo (để thấy xu hướng khi tinh chỉnh), không ảnh hưởng kết quả.
func metric(_ name: String, _ value: Double, unit: String = "") {
    print(String(format: "      · %@: %.2f%@", name, value, unit))
}

/// Đồng hồ giả: test tự đặt thời gian.
final class FakeClock {
    var t: Double
    init(_ t: Double = 100) { self.t = t }
}

/// Bộ sinh số ngẫu nhiên có hạt giống (SplitMix64) → mỗi lần chạy test đều ra cùng dữ liệu.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    /// Phân phối chuẩn (Box–Muller).
    mutating func gaussian() -> Double {
        let u1 = max(Double.random(in: 0..<1, using: &self), 1e-12), u2 = Double.random(in: 0..<1, using: &self)
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}

/// Hệ số biến thiên (độ lệch chuẩn / trung bình): 0 = đều tuyệt đối.
func roughness(_ xs: [Double]) -> Double {
    guard xs.count > 1 else { return 0 }
    let m = xs.reduce(0, +) / Double(xs.count)
    let v = xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(xs.count)
    return m == 0 ? 0 : sqrt(v) / abs(m)
}
