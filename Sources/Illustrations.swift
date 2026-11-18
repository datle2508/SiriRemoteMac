// Illustrations.swift
// Hình minh hoạ + animation cho cửa sổ cài đặt (vẽ bằng Core Animation, không cần file ảnh):
// - RemoteIllustrationView: Siri Remote đời 1 / đời 2-3, sáng nút khi rê chuột hoặc khi bấm nút thật.
// - GestureDemoView: touchpad mini lặp lại cử chỉ vuốt / chạm.
// - TouchModeTile: thẻ chọn chế độ cảm ứng có hình động.
// - StatusPill: nhãn trạng thái dạng viên thuốc, chấm xanh "thở".

import Cocoa
import QuartzCore

/// Gọi trên main thread mỗi khi remote bấm nút (tên nút, ví dụ "menu") hoặc chạy cử chỉ ("swipeleft"...).
var remoteEventObserver: ((String) -> Void)?

func notifyRemoteEvent(_ name: String) {
    guard remoteEventObserver != nil else { return }
    DispatchQueue.main.async { remoteEventObserver?(name) }
}

var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

extension CGColor {
    static func hex(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: a)
    }
}

private func accentCG(_ alpha: CGFloat = 1) -> CGColor {
    var c = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
    c = c.withAlphaComponent(alpha)
    return c.cgColor
}

/// Ảnh SF Symbol tô một màu, dùng làm contents cho CALayer.
private var layerSymbolCache: [String: Any] = [:]

func symbolLayerContents(_ name: String, size: CGFloat, color: NSColor, weight: NSFont.Weight = .semibold) -> Any? {
    let key = "\(name)|\(size)|\(weight.rawValue)|\(color.usingColorSpace(.sRGB)?.description ?? color.description)"
    if let c = layerSymbolCache[key] { return c }
    let made = makeSymbolContents(name, size: size, color: color, weight: weight)
    layerSymbolCache[key] = made
    return made
}

private func makeSymbolContents(_ name: String, size: CGFloat, color: NSColor, weight: NSFont.Weight) -> Any? {
    guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))) else { return nil }
    return img.layerContents(forContentsScale: 2)
}

private func symbolLayer(_ name: String, size: CGFloat, color: NSColor, frame: CGRect) -> CALayer {
    let l = CALayer()
    l.frame = frame
    l.contentsGravity = .center
    l.contentsScale = 2
    l.contents = symbolLayerContents(name, size: size, color: color)
    return l
}

// MARK: - Siri Remote

final class RemoteIllustrationView: NSView {

    enum Model { case gen1, gen23 }

    var model: Model = .gen1 { didSet { if oldValue != model { needsRebuild = true; needsLayout = true } } }
    /// Rê chuột lên một nút trên hình: báo tên nút (nil khi rời khỏi).
    var onHover: ((String?) -> Void)?

    private var parts: [String: CAShapeLayer] = [:]
    private var touchSurface: CAShapeLayer?
    private var needsRebuild = true
    private var highlighted: String?
    private var hoverName: String?

    /// Tên nút trong cấu hình có thể trỏ tới cùng một nút vật lý khác tên ở đời 2/3.
    private func resolve(_ name: String) -> String {
        if model == .gen23 {
            switch name {
            case "menu": return "back"
            case "home": return "tv"
            default: return name
            }
        }
        return name
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 410) }

    override func layout() {
        super.layout()
        if needsRebuild || layer?.sublayers?.isEmpty != false { rebuild() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsRebuild = true; needsLayout = true
    }

    /// Đổi toạ độ "từ trên xuống" sang toạ độ layer (gốc ở dưới).
    private func r(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat, in hgt: CGFloat) -> CGRect {
        CGRect(x: x, y: hgt - top - h, width: w, height: h)
    }

    private func rebuild() {
        needsRebuild = false
        guard let root = layer else { return }
        root.sublayers?.forEach { $0.removeFromSuperlayer() }
        parts = [:]

        let W: CGFloat = 104, H: CGFloat = 360
        let ox = (bounds.width - W) / 2, oy = max(0, (bounds.height - H) / 2)
        let body = CALayer()
        body.frame = CGRect(x: ox, y: oy, width: W, height: H)
        body.cornerRadius = model == .gen1 ? 22 : 26
        body.masksToBounds = false
        body.shadowColor = .black; body.shadowOpacity = 0.35; body.shadowRadius = 14; body.shadowOffset = CGSize(width: 0, height: -6)
        root.addSublayer(body)

        let shell = CAGradientLayer()
        shell.frame = body.bounds
        shell.cornerRadius = body.cornerRadius
        shell.masksToBounds = true
        if model == .gen1 {
            shell.colors = [CGColor.hex(0x3A3A3E), CGColor.hex(0x1C1C1F)]
        } else {
            shell.colors = [CGColor.hex(0xE9E9EC), CGColor.hex(0xB9BBC0)]
        }
        shell.startPoint = CGPoint(x: 0, y: 1); shell.endPoint = CGPoint(x: 1, y: 0)
        shell.borderWidth = 1
        shell.borderColor = model == .gen1 ? CGColor.hex(0x55555A) : CGColor.hex(0xFFFFFF, 0.7)
        body.addSublayer(shell)

        let iconColor: NSColor = .white
        let btnFill = CGColor.hex(0x111113)

        func add(_ name: String, _ rect: CGRect, path: CGPath, fill: CGColor = CGColor.hex(0x111113), symbol: String? = nil, symSize: CGFloat = 13) {
            let s = CAShapeLayer()
            s.frame = rect
            s.path = path
            s.fillColor = fill
            s.strokeColor = CGColor.hex(0xFFFFFF, model == .gen1 ? 0.08 : 0.0)
            s.lineWidth = 1
            s.shadowColor = accentCG()
            s.shadowOpacity = 0
            s.shadowRadius = 9
            s.shadowOffset = .zero
            if let sym = symbol {
                s.addSublayer(symbolLayer(sym, size: symSize, color: iconColor, frame: s.bounds))
            }
            shell.addSublayer(s)
            parts[name] = s
        }
        func circle(_ name: String, cx: CGFloat, top: CGFloat, d: CGFloat, _ sym: String, symSize: CGFloat = 12) {
            let rect = r(cx - d / 2, top, d, d, in: H)
            add(name, rect, path: CGPath(ellipseIn: CGRect(origin: .zero, size: rect.size), transform: nil), symbol: sym, symSize: symSize)
        }

        if model == .gen1 {
            // Touchpad kính tràn viền phía trên
            let padRect = r(0, 0, W, 128, in: H)
            let pad = CAShapeLayer()
            pad.frame = padRect
            pad.path = CGPath(rect: CGRect(origin: .zero, size: padRect.size), transform: nil)
            pad.fillColor = CGColor.hex(0x0B0B0D)
            pad.shadowColor = accentCG(); pad.shadowOpacity = 0; pad.shadowRadius = 9; pad.shadowOffset = .zero
            let gloss = CAGradientLayer()
            gloss.frame = pad.bounds
            gloss.colors = [CGColor.hex(0xFFFFFF, 0.10), CGColor.hex(0xFFFFFF, 0.0)]
            gloss.startPoint = CGPoint(x: 0, y: 1); gloss.endPoint = CGPoint(x: 0.7, y: 0.3)
            pad.addSublayer(gloss)
            shell.addSublayer(pad)
            let edge = CALayer()
            edge.frame = r(0, 128, W, 1, in: H)
            edge.backgroundColor = CGColor.hex(0x000000, 0.6)
            shell.addSublayer(edge)
            parts["touchpad"] = pad
            touchSurface = pad

            let lx: CGFloat = 30, rx: CGFloat = W - 30, d: CGFloat = 34
            circle("menu", cx: lx, top: 148, d: d, "chevron.backward", symSize: 13)
            circle("home", cx: rx, top: 148, d: d, "tv", symSize: 12)
            circle("siri", cx: lx, top: 196, d: d, "mic.fill", symSize: 13)
            circle("playpause", cx: lx, top: 244, d: d, "playpause.fill", symSize: 12)
            // Nút âm lượng dạng viên dài, chia hai nửa
            let pillTop: CGFloat = 196, pillH: CGFloat = 82
            let up = r(rx - d / 2, pillTop, d, pillH / 2, in: H)
            let dn = r(rx - d / 2, pillTop + pillH / 2, d, pillH / 2, in: H)
            add("volup", up, path: halfPill(size: up.size, top: true), fill: btnFill, symbol: "plus", symSize: 11)
            add("voldown", dn, path: halfPill(size: dn.size, top: false), fill: btnFill, symbol: "minus", symSize: 11)
        } else {
            // Đời 2/3: vỏ nhôm bạc, clickpad tròn đen, nút nguồn trên cùng, Siri ở cạnh phải
            circle("power", cx: W - 24, top: 14, d: 18, "power", symSize: 8)
            let ringD: CGFloat = 84, cx = W / 2, ringTop: CGFloat = 40
            let ringRect = r(cx - ringD / 2, ringTop, ringD, ringD, in: H)
            let ring = CAShapeLayer()
            ring.frame = ringRect
            ring.path = CGPath(ellipseIn: CGRect(origin: .zero, size: ringRect.size), transform: nil)
            ring.fillColor = CGColor.hex(0x18181A)
            ring.shadowColor = accentCG(); ring.shadowOpacity = 0; ring.shadowRadius = 9; ring.shadowOffset = .zero
            shell.addSublayer(ring)
            parts["touchpad"] = ring
            touchSurface = ring
            // 4 cung click ring (vùng nhấn) — trong suốt, chỉ hiện khi sáng
            let c = CGPoint(x: ringD / 2, y: ringD / 2)
            for (name, angle) in [("up", CGFloat.pi / 2), ("down", -CGFloat.pi / 2), ("left", CGFloat.pi), ("right", 0)] as [(String, CGFloat)] {
                let p = CGMutablePath()
                p.addArc(center: c, radius: ringD / 2 - 2, startAngle: angle - 0.55, endAngle: angle + 0.55, clockwise: false)
                p.addArc(center: c, radius: ringD / 2 - 15, startAngle: angle + 0.55, endAngle: angle - 0.55, clockwise: true)
                p.closeSubpath()
                let s = CAShapeLayer()
                s.frame = ring.bounds
                s.path = p
                s.fillColor = CGColor.hex(0xFFFFFF, 0.06)
                s.shadowColor = accentCG(); s.shadowOpacity = 0; s.shadowRadius = 8; s.shadowOffset = .zero
                let dot = CALayer()
                let dp = CGPoint(x: c.x + cos(angle) * (ringD / 2 - 8.5), y: c.y + sin(angle) * (ringD / 2 - 8.5))
                dot.frame = CGRect(x: dp.x - 1.5, y: dp.y - 1.5, width: 3, height: 3)
                dot.cornerRadius = 1.5
                dot.backgroundColor = CGColor.hex(0xFFFFFF, 0.55)
                s.addSublayer(dot)
                ring.addSublayer(s)
                parts[name] = s
            }
            let inner: CGFloat = 46
            let sel = CAShapeLayer()
            sel.frame = CGRect(x: (ringD - inner) / 2, y: (ringD - inner) / 2, width: inner, height: inner)
            sel.path = CGPath(ellipseIn: sel.bounds, transform: nil)
            sel.fillColor = CGColor.hex(0x232326)
            sel.strokeColor = CGColor.hex(0xFFFFFF, 0.08)
            sel.shadowColor = accentCG(); sel.shadowOpacity = 0; sel.shadowRadius = 8; sel.shadowOffset = .zero
            ring.addSublayer(sel)
            parts["select"] = sel

            let lx: CGFloat = 30, rx: CGFloat = W - 30, d: CGFloat = 32
            circle("back", cx: lx, top: 146, d: d, "chevron.backward", symSize: 12)
            circle("tv", cx: rx, top: 146, d: d, "tv", symSize: 11)
            circle("playpause", cx: lx, top: 190, d: d, "playpause.fill", symSize: 11)
            circle("mute", cx: lx, top: 234, d: d, "speaker.slash.fill", symSize: 11)
            let pillTop: CGFloat = 190, pillH: CGFloat = 76
            let up = r(rx - d / 2, pillTop, d, pillH / 2, in: H)
            let dn = r(rx - d / 2, pillTop + pillH / 2, d, pillH / 2, in: H)
            add("volup", up, path: halfPill(size: up.size, top: true), fill: btnFill, symbol: "plus", symSize: 10)
            add("voldown", dn, path: halfPill(size: dn.size, top: false), fill: btnFill, symbol: "minus", symSize: 10)
            // Nút Siri ở cạnh phải thân remote
            let side = r(W - 3, 120, 4, 34, in: H)
            add("siri", side, path: CGPath(roundedRect: CGRect(origin: .zero, size: side.size), cornerWidth: 2, cornerHeight: 2, transform: nil),
                fill: CGColor.hex(0x8E8E93))
        }
        // Logo nhỏ ở đáy
        let logo = symbolLayer("applelogo", size: 13, color: model == .gen1 ? NSColor(white: 1, alpha: 0.35) : NSColor(white: 0, alpha: 0.3),
                               frame: r(0, H - 44, W, 20, in: H))
        shell.addSublayer(logo)

        if let h = highlighted { applyHighlight(h, on: true, animated: false) }
    }

    private func halfPill(size: CGSize, top: Bool) -> CGPath {
        let w = size.width, h = size.height, rad = w / 2
        let p = CGMutablePath()
        if top {           // bo tròn phía trên (y lớn), phẳng phía dưới
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: 0, y: h - rad))
            p.addArc(center: CGPoint(x: rad, y: h - rad), radius: rad, startAngle: .pi, endAngle: 0, clockwise: true)
            p.addLine(to: CGPoint(x: w, y: 0))
        } else {
            p.move(to: CGPoint(x: 0, y: h))
            p.addLine(to: CGPoint(x: 0, y: rad))
            p.addArc(center: CGPoint(x: rad, y: rad), radius: rad, startAngle: .pi, endAngle: 0, clockwise: false)
            p.addLine(to: CGPoint(x: w, y: h))
        }
        p.closeSubpath()
        return p
    }

    // MARK: Sáng nút

    /// Làm sáng (viền + quầng màu nhấn) một nút; nil để bỏ sáng.
    func highlight(_ name: String?) {
        let n = name.map(resolve)
        guard n != highlighted else { return }
        if let old = highlighted { applyHighlight(old, on: false, animated: true) }
        highlighted = n
        if let n = n { applyHighlight(n, on: true, animated: true) }
    }

    private func applyHighlight(_ name: String, on: Bool, animated: Bool) {
        guard let s = parts[name] else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.22 : 0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        s.shadowOpacity = on ? 1 : 0
        s.strokeColor = on ? accentCG() : CGColor.hex(0xFFFFFF, model == .gen1 ? 0.08 : 0)
        s.lineWidth = on ? 2 : 1
        CATransaction.commit()
    }

    /// Hiệu ứng khi bấm nút thật: nút nảy nhẹ + gợn sóng lan ra.
    func pulse(_ rawName: String) {
        if let dir = ["swipeleft": CGVector(dx: -1, dy: 0), "swiperight": CGVector(dx: 1, dy: 0),
                      "swipeup": CGVector(dx: 0, dy: 1), "swipedown": CGVector(dx: 0, dy: -1)][rawName] {
            swipeTrail(dir); return
        }
        if rawName == "twofingertap" || rawName == "twofingerdoubletap" { tapDots(rawName == "twofingertap" ? 1 : 2); return }
        if rawName == "doubletap" { tapDots(2, fingers: 1); return }
        let name = resolve(rawName)
        guard let s = parts[name], let host = s.superlayer else { return }
        let ripple = CAShapeLayer()
        ripple.frame = s.frame
        ripple.path = s.path
        ripple.fillColor = nil
        ripple.strokeColor = accentCG()
        ripple.lineWidth = 2.5
        host.addSublayer(ripple)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1; scale.toValue = 1.55
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1; fade.toValue = 0
        let g = CAAnimationGroup()
        g.animations = [scale, fade]
        g.duration = 0.6
        g.timingFunction = CAMediaTimingFunction(name: .easeOut)
        g.isRemovedOnCompletion = false; g.fillMode = .forwards
        CATransaction.begin()
        CATransaction.setCompletionBlock { ripple.removeFromSuperlayer() }
        ripple.add(g, forKey: "ripple")
        CATransaction.commit()

        let press = CAKeyframeAnimation(keyPath: "transform.scale")
        press.values = [1, 0.86, 1.04, 1]
        press.keyTimes = [0, 0.3, 0.7, 1]
        press.duration = 0.32
        s.add(press, forKey: "press")

        let glow = CAKeyframeAnimation(keyPath: "shadowOpacity")
        glow.values = [s.shadowOpacity, 1, s.shadowOpacity]
        glow.duration = 0.5
        s.add(glow, forKey: "glow")
    }

    private func swipeTrail(_ dir: CGVector) {
        guard let pad = touchSurface else { return }
        let b = pad.bounds
        let c = CGPoint(x: b.midX, y: b.midY)
        let len = min(b.width, b.height) * 0.32
        let from = CGPoint(x: c.x - dir.dx * len, y: c.y - dir.dy * len)
        let to = CGPoint(x: c.x + dir.dx * len, y: c.y + dir.dy * len)
        let dot = fingerDot(at: from)
        pad.addSublayer(dot)
        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = NSValue(point: from); move.toValue = NSValue(point: to)
        move.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0, 0.2, 1)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]; fade.keyTimes = [0, 0.15, 0.7, 1]
        let g = CAAnimationGroup(); g.animations = [move, fade]; g.duration = 0.55
        g.isRemovedOnCompletion = false; g.fillMode = .forwards
        CATransaction.begin()
        CATransaction.setCompletionBlock { dot.removeFromSuperlayer() }
        dot.add(g, forKey: "swipe")
        CATransaction.commit()
    }

    private func tapDots(_ count: Int, fingers: Int = 2) {
        guard let pad = touchSurface else { return }
        let b = pad.bounds
        for (i, x) in (fingers == 1 ? [b.midX] : [b.midX - 10, b.midX + 10]).enumerated() {
            let dot = fingerDot(at: CGPoint(x: x, y: b.midY))
            dot.opacity = 0
            pad.addSublayer(dot)
            let a = CAKeyframeAnimation(keyPath: "opacity")
            a.values = count == 1 ? [0, 1, 0] : [0, 1, 0, 1, 0]
            a.duration = count == 1 ? 0.4 : 0.7
            a.beginTime = CACurrentMediaTime() + Double(i) * 0.02
            CATransaction.begin()
            CATransaction.setCompletionBlock { dot.removeFromSuperlayer() }
            dot.add(a, forKey: "tap")
            CATransaction.commit()
        }
    }

    private func fingerDot(at p: CGPoint) -> CALayer {
        let d = CALayer()
        d.bounds = CGRect(x: 0, y: 0, width: 16, height: 16)
        d.position = p
        d.cornerRadius = 8
        d.backgroundColor = accentCG(0.9)
        d.shadowColor = accentCG(); d.shadowOpacity = 1; d.shadowRadius = 8; d.shadowOffset = .zero
        return d
    }

    // MARK: Rê chuột

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    private func part(at p: NSPoint) -> String? {
        guard let root = layer else { return nil }
        // Ưu tiên phần nhỏ (nút trong clickpad) trước vùng touchpad lớn
        let order = parts.keys.filter { $0 != "touchpad" } + ["touchpad"]
        for name in order {
            guard let s = parts[name], let path = s.path else { continue }
            let local = s.convert(p, from: root)
            if path.contains(local) || (name != "touchpad" && path.boundingBox.insetBy(dx: -3, dy: -3).contains(local)) { return name }
        }
        return nil
    }

    override func mouseMoved(with event: NSEvent) {
        let n = part(at: convert(event.locationInWindow, from: nil))
        if n != hoverName { hoverName = n; onHover?(n) }
    }

    override func mouseExited(with event: NSEvent) {
        if hoverName != nil { hoverName = nil; onHover?(nil) }
    }
}

// MARK: - Touchpad mini minh hoạ cử chỉ

/// Lúc nghỉ: sơ đồ tĩnh (ray mờ + mũi tên chỉ hướng, chấm ở điểm đầu).
/// Rê chuột vào hàng: chạy lặp, từ tốn. Cử chỉ chạy thật: chạy một lần + nháy viền.
final class GestureDemoView: NSView {
    let gesture: String
    private let pad = CALayer()
    private let track = CAShapeLayer()       // ray mờ
    private let fill = CAShapeLayer()        // ray sáng dần theo chấm
    private let head = CALayer()             // mũi tên ở cuối ray
    private let dots: [CALayer]
    private var looping = false

    private var dir: CGVector? {
        ["swipeleft": CGVector(dx: -1, dy: 0), "swiperight": CGVector(dx: 1, dy: 0),
         "swipeup": CGVector(dx: 0, dy: 1), "swipedown": CGVector(dx: 0, dy: -1)][gesture]
    }
    private var taps: Int { gesture.hasSuffix("doubletap") ? 2 : 1 }
    private var fingers: Int { gesture.hasPrefix("twofinger") ? 2 : 1 }

    init(gesture: String, size: NSSize = NSSize(width: 54, height: 38)) {
        self.gesture = gesture
        dots = (0..<2).map { _ in CALayer() }
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size.width).isActive = true
        heightAnchor.constraint(equalToConstant: size.height).isActive = true
        pad.frame = bounds
        pad.cornerRadius = 8
        pad.borderWidth = 1
        layer?.addSublayer(pad)
        for l in [track, fill] {
            l.frame = pad.bounds
            l.fillColor = nil
            l.lineWidth = 3
            l.lineCap = .round
            pad.addSublayer(l)
        }
        fill.strokeEnd = 0
        head.contentsGravity = .center
        head.contentsScale = 2
        pad.addSublayer(head)
        for d in dots {
            d.bounds = CGRect(x: 0, y: 0, width: 9, height: 9)
            d.cornerRadius = 4.5
            pad.addSublayer(d)
        }
        layoutDiagram()
        applyColors()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private var ends: (CGPoint, CGPoint)? {
        guard let d = dir else { return nil }
        let b = pad.bounds, c = CGPoint(x: b.midX, y: b.midY)
        let hx = b.width * 0.30, hy = b.height * 0.28
        return (CGPoint(x: c.x - d.dx * hx, y: c.y - d.dy * hy), CGPoint(x: c.x + d.dx * hx, y: c.y + d.dy * hy))
    }

    private func layoutDiagram() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let b = pad.bounds
        if let (from, to) = ends, let d = dir {
            let p = CGMutablePath(); p.move(to: from); p.addLine(to: to)
            track.path = p; fill.path = p
            head.frame = CGRect(x: to.x - 6 + d.dx * 5, y: to.y - 6 + d.dy * 5, width: 12, height: 12)
            dots[0].position = from
            dots[0].opacity = 1
            dots[1].isHidden = true
        } else {
            for (i, d) in dots.enumerated() {
                d.position = CGPoint(x: fingers == 1 ? b.midX : b.midX + (i == 0 ? -7 : 7), y: b.midY)
                d.opacity = 0.55
                d.isHidden = fingers == 1 && i == 1
            }
        }
        CATransaction.commit()
    }

    private func applyColors() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        pad.backgroundColor = CGColor.hex(0x232327)
        pad.borderColor = CGColor.hex(0xFFFFFF, 0.12)
        track.strokeColor = CGColor.hex(0xFFFFFF, 0.13)
        fill.strokeColor = accentCG(0.55)
        for d in dots { d.backgroundColor = accentCG() }
        if let d = dir {
            let sym = d.dx < 0 ? "chevron.left" : d.dx > 0 ? "chevron.right" : d.dy > 0 ? "chevron.up" : "chevron.down"
            head.contents = symbolLayerContents(sym, size: 8, color: NSColor(white: 1, alpha: 0.35), weight: .heavy)
        }
        CATransaction.commit()
    }

    /// Một lượt animation (dùng cho cả lặp lẫn chạy một lần).
    private func cycle(duration: CFTimeInterval, repeating: Bool) {
        let rep: Float = repeating ? .infinity : 1
        let ease = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.2, 1)
        if let (from, to) = ends {
            // chạy trong 55% đầu, nghỉ phần còn lại
            let move = CAKeyframeAnimation(keyPath: "position")
            move.values = [NSValue(point: from), NSValue(point: to), NSValue(point: to), NSValue(point: from)]
            move.keyTimes = [0, 0.55, 0.8, 1]
            move.timingFunctions = [ease, CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .linear)]
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1, 1, 0, 0, 1]; fade.keyTimes = [0, 0.55, 0.75, 0.85, 1]
            let g = CAAnimationGroup(); g.animations = [move, fade]
            g.duration = duration; g.repeatCount = rep
            dots[0].add(g, forKey: "anim")

            let stroke = CAKeyframeAnimation(keyPath: "strokeEnd")
            stroke.values = [0, 1, 1, 0]; stroke.keyTimes = [0, 0.55, 0.8, 1]
            stroke.timingFunctions = [ease, CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeIn)]
            stroke.duration = duration; stroke.repeatCount = rep
            fill.add(stroke, forKey: "anim")
        } else {
            for d in dots {
                let fade = CAKeyframeAnimation(keyPath: "opacity")
                let scale = CAKeyframeAnimation(keyPath: "transform.scale")
                if taps == 1 {
                    fade.values = [0.55, 1, 0.55, 0.55]; fade.keyTimes = [0, 0.15, 0.45, 1]
                    scale.values = [1, 0.7, 1, 1]; scale.keyTimes = fade.keyTimes
                } else {
                    fade.values = [0.55, 1, 0.55, 1, 0.55, 0.55]; fade.keyTimes = [0, 0.12, 0.27, 0.39, 0.55, 1]
                    scale.values = [1, 0.7, 1, 0.7, 1, 1]; scale.keyTimes = fade.keyTimes
                }
                let g = CAAnimationGroup(); g.animations = [fade, scale]
                g.duration = duration; g.repeatCount = rep
                d.add(g, forKey: "anim")
            }
        }
    }

    private func stopAnim() {
        for l in [dots[0], dots[1], fill] { l.removeAnimation(forKey: "anim") }
    }

    /// Rê chuột vào hàng: chạy lặp; rời đi: về sơ đồ tĩnh.
    func setLooping(_ on: Bool) {
        guard on != looping, !reduceMotion else { return }
        looping = on
        stopAnim()
        if on { cycle(duration: 1.6, repeating: true) }
    }

    /// Cử chỉ vừa chạy thật: chạy một lượt + nháy viền.
    func flash() {
        if !looping && !reduceMotion { stopAnim(); cycle(duration: 1.2, repeating: false) }
        let a = CAKeyframeAnimation(keyPath: "borderColor")
        a.values = [accentCG(), accentCG(), CGColor.hex(0xFFFFFF, 0.12)]
        a.keyTimes = [0, 0.4, 1]
        a.duration = 0.8
        let w = CAKeyframeAnimation(keyPath: "borderWidth")
        w.values = [2, 2, 1]; w.keyTimes = [0, 0.4, 1]; w.duration = 0.8
        pad.add(a, forKey: "flash"); pad.add(w, forKey: "flashw")
    }
}


// MARK: - Thẻ chọn chế độ cảm ứng

final class TouchModeTile: NSView {
    let modeID: String
    var onSelect: ((String) -> Void)?
    var isSelected = false { didSet { updateState(animated: true) } }

    private let stage = CALayer()
    private let badge = CALayer()
    private var hovering = false

    init(mode: String, title: String, detail: String, symbol: String) {
        modeID = mode
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1.5

        let stageHost = NSView()
        stageHost.wantsLayer = true
        stageHost.translatesAutoresizingMaskIntoConstraints = false
        stageHost.heightAnchor.constraint(equalToConstant: 84).isActive = true
        stageHost.layer?.addSublayer(stage)

        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold)) ?? NSImage())
        icon.contentTintColor = .controlAccentColor
        let t = NSTextField(labelWithString: title)
        t.font = .systemFont(ofSize: 13, weight: .semibold)
        let titleRow = NSStackView(views: [icon, t]); titleRow.spacing = 6
        let d = NSTextField(wrappingLabelWithString: detail)
        d.font = .systemFont(ofSize: 11); d.textColor = .secondaryLabelColor
        d.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let v = NSStackView(views: [stageHost, titleRow, d])
        v.orientation = .vertical; v.alignment = .leading; v.spacing = 6
        v.translatesAutoresizingMaskIntoConstraints = false
        addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            v.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            v.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            v.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10),
            stageHost.widthAnchor.constraint(equalTo: v.widthAnchor),
        ])
        badge.contentsGravity = .center
        badge.contentsScale = 2
        layer?.addSublayer(badge)
        self.stageHost = stageHost
        updateState(animated: false)
    }
    required init?(coder: NSCoder) { fatalError() }

    private weak var stageHost: NSView?
    private var builtFor: CGSize = .zero

    override func layout() {
        super.layout()
        if let h = stageHost, h.bounds.size != builtFor, h.bounds.width > 0 {
            builtFor = h.bounds.size
            CATransaction.begin(); CATransaction.setDisableActions(true)
            stage.frame = h.bounds
            buildStage()
            CATransaction.commit()
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        badge.frame = CGRect(x: bounds.width - 30, y: bounds.height - 30, width: 22, height: 22)
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateState(animated: false)
        builtFor = .zero; needsLayout = true
    }

    private func buildStage() {
        stage.sublayers?.forEach { $0.removeFromSuperlayer() }
        let b = stage.bounds
        stage.cornerRadius = 9
        stage.backgroundColor = CGColor.hex(0x7F7F86, 0.12)

        // Touchpad mini
        let padW: CGFloat = 62, padH: CGFloat = 62
        let pad = CALayer()
        let padX = modeID == "cursor" ? b.midX - padW - 10 : b.midX - padW / 2
        pad.frame = CGRect(x: padX, y: (b.height - padH) / 2, width: padW, height: padH)
        pad.cornerRadius = 12
        pad.backgroundColor = CGColor.hex(0x1C1C1F)
        pad.borderWidth = 1; pad.borderColor = CGColor.hex(0xFFFFFF, 0.12)
        stage.addSublayer(pad)

        func dot() -> CALayer {
            let d = CALayer()
            d.bounds = CGRect(x: 0, y: 0, width: 11, height: 11)
            d.cornerRadius = 5.5
            d.backgroundColor = accentCG()
            d.shadowColor = accentCG(); d.shadowOpacity = 0.9; d.shadowRadius = 5; d.shadowOffset = .zero
            return d
        }

        switch modeID {
        case "cursor":
            // Ngón tay vẽ hình số 8 trên touchpad; con trỏ trên "màn hình" chạy theo
            let screen = CALayer()
            screen.frame = CGRect(x: b.midX + 8, y: (b.height - 54) / 2 + 4, width: 78, height: 50)
            screen.cornerRadius = 5
            screen.backgroundColor = CGColor.hex(0x7F7F86, 0.25)
            screen.borderWidth = 1; screen.borderColor = CGColor.hex(0x7F7F86, 0.45)
            stage.addSublayer(screen)
            let stand = CALayer()
            stand.frame = CGRect(x: screen.frame.midX - 10, y: screen.frame.minY - 6, width: 20, height: 3)
            stand.cornerRadius = 1.5
            stand.backgroundColor = CGColor.hex(0x7F7F86, 0.45)
            stage.addSublayer(stand)

            let f = dot()
            pad.addSublayer(f)
            let cursor = CALayer()
            cursor.bounds = CGRect(x: 0, y: 0, width: 14, height: 18)
            cursor.anchorPoint = CGPoint(x: 0.25, y: 0.85)
            cursor.contentsGravity = .resizeAspect
            cursor.contentsScale = 2
            cursor.contents = symbolLayerContents("cursorarrow", size: 13, color: isDark ? .white : .black, weight: .bold)
            screen.addSublayer(cursor)

            func eight(in r: CGRect) -> CGPath {
                let p = CGMutablePath()
                let steps = 60
                for i in 0...steps {
                    let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
                    let pt = CGPoint(x: r.midX + sin(t) * r.width / 2, y: r.midY + sin(2 * t) * r.height / 2)
                    i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                }
                return p
            }
            f.position = CGPoint(x: pad.bounds.midX, y: pad.bounds.midY)
            cursor.position = CGPoint(x: screen.bounds.midX, y: screen.bounds.midY)
            if !reduceMotion {
                for (l, rect) in [(f, pad.bounds.insetBy(dx: 16, dy: 18)), (cursor, screen.bounds.insetBy(dx: 18, dy: 12))] {
                    let a = CAKeyframeAnimation(keyPath: "position")
                    a.path = eight(in: rect)
                    a.duration = 3.2; a.repeatCount = .infinity
                    a.calculationMode = .paced
                    l.add(a, forKey: "loop")
                }
            }
        case "swipe":
            let trail = CAGradientLayer()
            trail.bounds = CGRect(x: 0, y: 0, width: 34, height: 9)
            trail.cornerRadius = 4.5
            trail.colors = [accentCG(0), accentCG(0.6)]
            trail.startPoint = CGPoint(x: 0, y: 0.5); trail.endPoint = CGPoint(x: 1, y: 0.5)
            trail.anchorPoint = CGPoint(x: 1, y: 0.5)
            pad.addSublayer(trail)
            let f = dot()
            pad.addSublayer(f)
            let y = pad.bounds.midY
            let from = CGPoint(x: 14, y: y), to = CGPoint(x: pad.bounds.width - 14, y: y)
            f.position = to; trail.position = to
            if !reduceMotion {
                for l in [f, trail] as [CALayer] {
                    let move = CAKeyframeAnimation(keyPath: "position")
                    move.values = [NSValue(point: from), NSValue(point: from), NSValue(point: to), NSValue(point: to)]
                    move.keyTimes = [0, 0.2, 0.45, 1]
                    move.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(controlPoints: 0.5, 0, 0.2, 1),
                                            CAMediaTimingFunction(name: .linear)]
                    let fade = CAKeyframeAnimation(keyPath: "opacity")
                    fade.values = [0, 1, 1, 0, 0]; fade.keyTimes = [0, 0.15, 0.42, 0.6, 1]
                    let g = CAAnimationGroup(); g.animations = [move, fade]
                    g.duration = 1.8; g.repeatCount = .infinity
                    l.add(g, forKey: "loop")
                }
            }
            // Mũi tên mờ gợi ý hướng vuốt
            for (i, sym) in ["chevron.left", "chevron.right"].enumerated() {
                let a = CALayer()
                a.frame = CGRect(x: i == 0 ? pad.frame.minX - 22 : pad.frame.maxX + 6, y: b.midY - 8, width: 16, height: 16)
                a.contentsGravity = .center; a.contentsScale = 2
                a.contents = symbolLayerContents(sym, size: 12, color: .secondaryLabelColor, weight: .bold)
                a.opacity = 0.6
                stage.addSublayer(a)
            }
        default:
            pad.opacity = 0.45
            let no = CALayer()
            no.frame = pad.frame
            no.contentsGravity = .center; no.contentsScale = 2
            no.contents = symbolLayerContents("nosign", size: 28, color: .systemRed, weight: .medium)
            stage.addSublayer(no)
            if !reduceMotion {
                let a = CABasicAnimation(keyPath: "opacity")
                a.fromValue = 0.35; a.toValue = 1
                a.duration = 1.4; a.autoreverses = true; a.repeatCount = .infinity
                a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                no.add(a, forKey: "breathe")
            }
        }
    }

    private var isDark: Bool { effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

    private func updateState(animated: Bool) {
        guard let l = layer else { return }
        var bg: CGColor = .clear, border: CGColor = .clear
        effectiveAppearance.performAsCurrentDrawingAppearance {
            bg = isSelected ? accentCG(0.10) : (hovering ? NSColor.labelColor.withAlphaComponent(0.05).cgColor : NSColor.labelColor.withAlphaComponent(0.02).cgColor)
            border = isSelected ? accentCG() : (hovering ? NSColor.labelColor.withAlphaComponent(0.25).cgColor : NSColor.separatorColor.cgColor)
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animated ? 0.2 : 0
            ctx.allowsImplicitAnimation = animated
            l.backgroundColor = bg
            l.borderColor = border
        }
        CATransaction.begin(); CATransaction.setDisableActions(!animated)
        badge.contents = symbolLayerContents("checkmark.circle.fill", size: 16, color: .controlAccentColor)
        badge.opacity = isSelected ? 1 : 0
        CATransaction.commit()
        if isSelected && animated && !reduceMotion {
            let pop = CAKeyframeAnimation(keyPath: "transform.scale")
            pop.values = [0.4, 1.2, 1]; pop.keyTimes = [0, 0.6, 1]; pop.duration = 0.32
            badge.add(pop, forKey: "pop")
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; updateState(animated: true) }
    override func mouseExited(with event: NSEvent) { hovering = false; updateState(animated: true) }
    override func mouseDown(with event: NSEvent) {
        if !isSelected { onSelect?(modeID) }
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

// MARK: - Nhãn trạng thái

final class StatusPill: NSView {
    private let dot = CALayer()
    private let halo = CALayer()
    private let label = NSTextField(labelWithString: "")
    private var state: (Bool, String)?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 11
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        layer?.addSublayer(halo)
        layer?.addSublayer(dot)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 22),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let c = CGPoint(x: 12, y: bounds.midY)
        dot.bounds = CGRect(x: 0, y: 0, width: 7, height: 7); dot.cornerRadius = 3.5; dot.position = c
        halo.bounds = CGRect(x: 0, y: 0, width: 7, height: 7); halo.cornerRadius = 3.5; halo.position = c
        CATransaction.commit()
    }

    func set(ok: Bool, text: String) {
        if let s = state, s.0 == ok, s.1 == text { return }
        let changed = state != nil
        state = (ok, text)
        label.stringValue = text
        let color: NSColor = ok ? .systemGreen : .systemOrange
        label.textColor = ok ? .labelColor : .systemOrange
        CATransaction.begin(); CATransaction.setAnimationDuration(0.3)
        dot.backgroundColor = color.cgColor
        halo.backgroundColor = color.cgColor
        layer?.backgroundColor = color.withAlphaComponent(0.13).cgColor
        CATransaction.commit()
        halo.removeAllAnimations()
        if !reduceMotion {
            // Quầng sáng lan ra định kỳ: chậm khi ổn, nhanh hơn khi cần chú ý
            let scale = CABasicAnimation(keyPath: "transform.scale"); scale.fromValue = 1; scale.toValue = 2.8
            let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 0.6; fade.toValue = 0
            let g = CAAnimationGroup(); g.animations = [scale, fade]
            g.duration = ok ? 2.2 : 1.2; g.repeatCount = .infinity
            g.timingFunction = CAMediaTimingFunction(name: .easeOut)
            halo.add(g, forKey: "halo")
            if changed {
                let pop = CAKeyframeAnimation(keyPath: "transform.scale")
                pop.values = [1, 1.06, 1]; pop.duration = 0.3
                layer?.add(pop, forKey: "pop")
            }
        } else {
            halo.opacity = 0
        }
    }
}

// MARK: - Hàng có thể sáng khi rê chuột

/// Bọc nhãn của một hàng (nút / cử chỉ): nền bo góc sáng dần khi được chọn.
final class HoverRow: NSView {
    let name: String
    var onHover: ((String?) -> Void)?
    var isLit = false { didSet { if oldValue != isLit { updateBG() } } }

    init(name: String, content: NSView) {
        self.name = name
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    private func updateBG() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.allowsImplicitAnimation = true
            layer?.backgroundColor = isLit ? accentCG(0.16) : .clear
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { onHover?(name) }
    override func mouseExited(with event: NSEvent) { onHover?(nil) }
}

// MARK: - Animation dùng chung

extension NSView {
    /// Các view con lần lượt hiện ra (mờ → rõ, trượt lên nhẹ).
    func staggerIn(_ views: [NSView], step: CFTimeInterval = 0.045) {
        guard !reduceMotion else { return }
        let now = CACurrentMediaTime()
        for (i, v) in views.enumerated() {
            v.wantsLayer = true
            guard let l = v.layer else { continue }
            let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 0; fade.toValue = 1
            let move = CABasicAnimation(keyPath: "transform.translation.y"); move.fromValue = -10; move.toValue = 0
            let g = CAAnimationGroup(); g.animations = [fade, move]
            g.duration = 0.35
            g.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            g.beginTime = now + Double(i) * step
            g.fillMode = .backwards
            l.add(g, forKey: "staggerIn")
        }
    }
}
