// GestureRules.swift
// Luật nhận dạng cử chỉ lúc nhấc tay (vuốt / chạm / chạm 2 ngón) và luật giữ con trỏ chờ phân biệt vuốt.
// Dùng chung cho TouchEngine và công cụ phân tích (tools/TouchAnalyzer): đổi ngưỡng ở đây là đổi cả hai.
// Code thuần (không đọc thiết bị, không gửi sự kiện) để test được.

import Foundation

enum TouchEnd: Equatable { case swipe(String), tap, twoFingerTap, none }

struct GestureRules {
    var tapDur = 0.25, tapTravel = 0.04
    // 0,22: trên bản ghi thật, 16 % cú vuốt nhanh (105–210 ms) chỉ dài 0,24–0,28 → trước đây (0,30) bị hiểu là rê;
    // không lượt rê nào dài 0,18–0,30 trong < 0,4 s mà đi thẳng
    var swipeDist = 0.22, swipeTime = 0.4, swipeDominance = 2.0
    var twoDur = 0.3, twoTravel = 0.06              // đo: chạm 2 ngón của bạn kéo dài 255–285 ms
    var endSpeedRule = true                         // ≥ 0,3 s mà chậm lại < 1,5/s trước khi nhấc → không phải vuốt

    static let cursor = GestureRules()
    static let swipe = GestureRules(swipeDist: 0.2, swipeTime: 0.7)

    // Giữ con trỏ (TouchEngine.steer): quá 0,45 s chắc chắn không phải vuốt; sau 0,135 s mà còn chậm thì là rê.
    // 0,135 s (không phải 0,1): cú vuốt của bạn thường đặt ngón nghỉ ~0,1 s rồi mới hất; bản ghi có nhãn: 0,1 s làm
    // 1/36 cú vuốt bị thả con trỏ giữa chừng, 0,135 s thì 0/36 (con trỏ chờ thêm ~45 ms khi rê chậm).
    static let holdMax = 0.45, holdMinTime = 0.135

    /// Ngưỡng "chậm" (đơn vị chuẩn hoá / giây) theo thanh trượt Nhận vuốt: 100 % → 0,6/s (bản ghi tự nhiên: lọt
    /// 1/42 cú vuốt, con trỏ chờ ~375 ms); 0 % → 1,4/s (lọt 4/42 — con trỏ nhích rồi về chỗ cũ —, chờ ~135 ms).
    static func slowSpeed(priority: Double) -> Double { 1.4 - 0.8 * min(max(priority, 0), 1) }

    /// Lượt chạm kết thúc: fingers = số ngón nhiều nhất, dur tính tới khung nhấc tay, (dx, dy) từ lúc chạm,
    /// travel = tổng quãng đi, recent = vài toạ độ cuối (cho luật chậm lại trước khi nhấc).
    func classifyEnd(fingers: Int, dur: Double, dx: Double, dy: Double, travel: Double,
                     recent: [(t: Double, x: Double, y: Double)]) -> TouchEnd {
        if fingers == 2 { return dur < twoDur && travel < twoTravel ? .twoFingerTap : .none }
        guard fingers == 1 else { return .none }
        let adx = abs(dx), ady = abs(dy), far = max(adx, ady)
        if dur < swipeTime, far >= swipeDist, far >= swipeDominance * min(adx, ady),
           !(endSpeedRule && GestureRules.slowedBeforeLift(dur: dur, recent: recent)) {
            return .swipe(adx > ady ? (dx > 0 ? "SWIPERIGHT" : "SWIPELEFT") : (dy > 0 ? "SWIPEUP" : "SWIPEDOWN"))
        }
        return dur < tapDur && travel < tapTravel ? .tap : .none
    }

    /// Lượt kéo dài (≥ 0,3 s) mà ngón đã chậm lại trước khi nhấc (< 1,5 đơn vị/s, bỏ khung cuối): là rê nhanh rồi dừng,
    /// không phải cú vuốt. Đo trên bản ghi có nhãn: mọi cú vuốt rời mặt ở ≥ 1,8/s; rê nhanh bị nhầm thì 1,0–1,4/s.
    static func slowedBeforeLift(dur: Double, recent: [(t: Double, x: Double, y: Double)]) -> Bool {
        guard dur >= 0.3, recent.count >= 5 else { return false }
        let a = recent[recent.count - 5], b = recent[recent.count - 2]
        return hypot(b.x - a.x, b.y - a.y) / max(b.t - a.t, 0.004) < 1.5
    }
}
