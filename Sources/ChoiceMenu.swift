// ChoiceMenu.swift
// Bảng chọn nổi kiểu Apple TV, dùng chung cho:
// - Menu nguồn (giữ Home): Ngủ / Tắt màn hình / Khóa / Màn hình chờ — thay vì cho Mac ngủ ngay (dễ lỡ tay).
// - Chế độ cảm ứng (giữ Siri): Con trỏ / Vuốt-chạm / Tắt — thấy trước rồi mới đổi.
//
// Điều khiển bằng remote: vuốt trái/phải (hoặc ←/→ của click ring, hoặc bấm Siri để xoay vòng) chuyển ô,
// bấm touchpad / Play-Pause để chọn, Menu / Back / Home để hủy. Bấm chuột cũng được. Tự đóng sau 10 giây.

import Cocoa
import QuartzCore

final class ChoiceMenu {
    /// Bảng đang mở (nếu có): Controller / TouchEngine chuyển nút và cử chỉ cho nó.
    private(set) static var active: ChoiceMenu?
    /// Khi chụp ảnh cho README: nền tối đặc (chụp riêng cửa sổ thì kính mờ không có gì phía sau để làm mờ → xám bạc).
    static var solidBackground = false

    struct Item {
        let title: String
        let symbol: String
        let hue: (NSColor, NSColor)           // cặp màu chuyển sắc (sáng → đậm)
        var note: String? = nil               // dòng nhỏ dưới tên, ví dụ "Đang dùng"
        let run: (() -> Void)?                // nil = Hủy
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
    static let cancelItem = Item(title: T("Hủy"), symbol: "xmark", hue: (rgb(0.72, 0.72, 0.76), rgb(0.45, 0.45, 0.50)), run: nil)

    // MARK: Các bảng

    /// Menu nguồn (giữ Home).
    static func showPower() {
        func act(_ spec: String) -> () -> Void { { Action.parse(spec)?.run() } }
        show(title: T("Bạn muốn làm gì?"), items: [
            Item(title: T("Ngủ"), symbol: "moon.zzz.fill", hue: (rgb(0.55, 0.47, 1.0), rgb(0.33, 0.22, 0.86)), run: act("sleep")),          // tím chàm: đêm
            Item(title: T("Tắt màn hình"), symbol: "display", hue: (rgb(0.35, 0.72, 1.0), rgb(0.10, 0.45, 0.95)), run: act("displaysleep")),   // xanh dương
            Item(title: T("Khóa"), symbol: "lock.fill", hue: (rgb(1.0, 0.72, 0.30), rgb(0.96, 0.48, 0.10)), run: act("lockscreen")),          // cam
            Item(title: T("Màn hình chờ"), symbol: "sparkles.tv", hue: (rgb(1.0, 0.50, 0.75), rgb(0.90, 0.22, 0.55)), run: act("screensaver")), // hồng
            cancelItem,
        ], focus: 0)
    }

    /// Chọn chế độ cảm ứng (giữ Siri). Tiêu điểm đặt sẵn ở chế độ hay đổi sang (Con trỏ ↔ Vuốt),
    /// nên giữ Siri rồi bấm touchpad nhanh như kiểu đổi qua lại cũ.
    static func showTouchMode() {
        let modes: [(TouchMode, String, String, (NSColor, NSColor))] = [
            (.cursor, T("Con trỏ"), "cursorarrow.motionlines", (rgb(0.30, 0.88, 0.90), rgb(0.05, 0.62, 0.72))),   // xanh ngọc
            (.swipe, T("Vuốt/chạm"), "hand.draw.fill", (rgb(0.45, 0.90, 0.45), rgb(0.15, 0.68, 0.30))),           // xanh lá
            (.off, T("Tắt"), "hand.raised.slash.fill", (rgb(1.0, 0.45, 0.42), rgb(0.86, 0.18, 0.20))),            // đỏ
        ]
        let target: TouchMode = touchMode == .cursor ? .swipe : .cursor
        var items = modes.map { m in
            Item(title: m.1, symbol: m.2, hue: m.3, note: m.0 == touchMode ? T("Đang dùng") : nil, run: { setTouchMode(m.0) })
        }
        items.append(cancelItem)
        show(title: T("Chế độ cảm ứng"), items: items, focus: modes.firstIndex { $0.0 == target } ?? 0)
    }

    private static func show(title: String, items: [Item], focus: Int) {
        if let a = active { a.dismiss() }
        let m = ChoiceMenu(title: title, items: items, focus: focus)
        active = m
        m.present()
    }

    // MARK: Một bảng

    private let titleText: String
    private let items: [Item]
    private let glow = CAGradientLayer()          // vệt sáng màu phía sau ô đang chọn
    private var tileCenters: [CGPoint] = []
    private var panel: NSPanel?
    var windowNumber: Int? { panel?.windowNumber }
    private var tiles: [Tile] = []
    private var focus: Int
    private var touchAccum: Float = 0
    private var idleTimer: Timer?

    private init(title: String, items: [Item], focus: Int) {
        titleText = title
        self.items = items
        self.focus = focus
    }

    private func present() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen = screen else { return }

        let tileW: CGFloat = 132, tileH: CGFloat = 156, gap: CGFloat = 18, pad: CGFloat = 34
        let w = CGFloat(items.count) * tileW + CGFloat(items.count - 1) * gap + pad * 2
        let h = tileH + 92
        let frame = NSRect(x: screen.frame.midX - w / 2, y: screen.frame.midY - h / 2, width: w, height: h)

        let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .popUpMenu
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.isReleasedWhenClosed = false

        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .darkAqua)
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 28
        blur.layer?.masksToBounds = true
        p.contentView = blur
        if ChoiceMenu.solidBackground {
            let bg = NSView(frame: blur.bounds)
            bg.wantsLayer = true
            bg.layer?.backgroundColor = CGColor(srgbRed: 0.13, green: 0.13, blue: 0.15, alpha: 1)
            blur.addSubview(bg)
        }

        let title = NSTextField(labelWithString: titleText)
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = NSColor(white: 1, alpha: 0.75)
        title.alignment = .center
        title.frame = NSRect(x: 0, y: h - 46, width: w, height: 22)
        blur.addSubview(title)

        let hint = NSTextField(labelWithString: T("Vuốt để chọn · bấm touchpad để xác nhận · Menu để hủy"))
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = NSColor(white: 1, alpha: 0.45)
        hint.alignment = .center
        hint.frame = NSRect(x: 0, y: 14, width: w, height: 16)
        blur.addSubview(hint)

        // Vệt sáng màu (gradient tròn) nằm sau các ô, trượt theo ô đang chọn
        let glowHost = NSView(frame: NSRect(origin: .zero, size: frame.size))
        glowHost.wantsLayer = true
        glow.type = .radial
        glow.startPoint = CGPoint(x: 0.5, y: 0.5); glow.endPoint = CGPoint(x: 1, y: 1)
        glow.bounds = CGRect(x: 0, y: 0, width: 300, height: 300)
        glowHost.layer?.addSublayer(glow)
        blur.addSubview(glowHost)
        tileCenters = (0..<items.count).map { CGPoint(x: pad + CGFloat($0) * (tileW + gap) + tileW / 2, y: 40 + tileH - 55) }

        tiles = items.enumerated().map { i, item in
            let t = Tile(title: item.title, symbol: item.symbol, hue: item.hue, note: item.note)
            t.frame = NSRect(x: pad + CGFloat(i) * (tileW + gap), y: 40, width: tileW, height: tileH)
            t.onHover = { [weak self] in self?.setFocus(i) }
            t.onClick = { [weak self] in self?.setFocus(i); self?.confirm() }
            blur.addSubview(t)
            return t
        }
        touchAccum = 0
        for (i, t) in tiles.enumerated() { t.setFocused(i == focus, animated: false) }
        moveGlow(animated: false)

        panel = p
        p.alphaValue = 0
        p.orderFrontRegardless()
        // Hiện ra: mờ → rõ, phóng nhẹ từ 0,94
        if !reduceMotion, let l = blur.layer {
            // phóng quanh tâm (layer do AppKit quản lý có gốc ở góc, không đổi anchorPoint)
            let cx = frame.width / 2, cy = frame.height / 2
            var t = CATransform3DMakeTranslation(cx, cy, 0)
            t = CATransform3DScale(t, 0.94, 0.94, 1)
            t = CATransform3DTranslate(t, -cx, -cy, 0)
            let s = CABasicAnimation(keyPath: "transform")
            s.fromValue = NSValue(caTransform3D: t); s.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            s.duration = 0.28
            s.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            l.add(s, forKey: "pop")
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            p.animator().alphaValue = 1
        }
        NSSound(named: "Pop")?.play()
        restartIdleTimer()
    }

    func dismiss() {
        guard let p = panel else { return }
        panel = nil
        tiles = []
        idleTimer?.invalidate(); idleTimer = nil
        if ChoiceMenu.active === self { ChoiceMenu.active = nil }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16
            p.animator().alphaValue = 0
        }, completionHandler: { p.orderOut(nil) })
    }

    // MARK: Điều khiển

    private func restartIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in self?.dismiss() }
    }

    private func setFocus(_ i: Int) {
        let n = max(0, min(items.count - 1, i))
        guard n != focus else { return }
        tiles[safe: focus]?.setFocused(false, animated: true)
        focus = n
        tiles[safe: focus]?.setFocused(true, animated: true)
        moveGlow(animated: true)
        NSSound(named: "Tink")?.play()
        restartIdleTimer()
    }

    func move(_ step: Int) { setFocus(focus + step) }

    private func moveGlow(animated: Bool) {
        guard tileCenters.indices.contains(focus) else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated && !reduceMotion ? 0.35 : 0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1))
        glow.position = tileCenters[focus]
        glow.colors = [items[focus].hue.0.withAlphaComponent(0.42).cgColor, items[focus].hue.1.withAlphaComponent(0).cgColor]
        CATransaction.commit()
    }

    func confirm() {
        let run = items[focus].run
        tiles[safe: focus]?.press()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.dismiss()
            // chờ bảng mờ đi rồi mới chạy (khóa / ngủ ngay khi bảng còn trên màn hình trông giật)
            if let run = run { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: run) }
        }
    }

    /// Nút remote khi bảng đang mở. Trả về false nếu để nút chạy bình thường (âm lượng).
    func button(_ name: String) -> Bool {
        switch name {
        case "volup", "voldown", "mute": return false
        case "touchpad", "select", "playpause": confirm()
        case "menu", "back", "home", "tv": dismiss()
        case "left": move(-1)
        case "right": move(1)
        case "siri": setFocus(focus + 1 < items.count ? focus + 1 : 0)   // xoay vòng (dùng được cả khi cảm ứng đang tắt)
        default: break
        }
        return true
    }

    /// Ngón rê ngang trên touchpad: mỗi ~18 % bề ngang = một ô (như tiêu điểm của tvOS).
    func touchMove(_ dx: Float) {
        touchAccum += dx
        while touchAccum >= 0.18 { touchAccum -= 0.18; move(1) }
        while touchAccum <= -0.18 { touchAccum += 0.18; move(-1) }
    }

    func touchEnded() { touchAccum = 0 }
}

/// Đặt chế độ cảm ứng, lưu vào file cấu hình, báo bằng tiếng + chữ cạnh biểu tượng thanh menu.
func setTouchMode(_ mode: TouchMode) {
    var c = ConfigFile.load()
    c.global["touchmode"] = mode.rawValue
    c.save()
    controller.reloadMap()
    appDelegate.touchModeChanged(mode)
    NSSound(named: NSSound.Name(mode == .cursor ? "Pop" : "Tink"))?.play()
    appDelegate.flash(mode.title)
    appDelegate.refresh()
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: - Ô lựa chọn

private final class Tile: NSView {
    var onHover: (() -> Void)?
    var onClick: (() -> Void)?
    private let disc = CALayer()                  // đĩa (giữ bóng / quầng sáng)
    private let fill = CAGradientLayer()          // nền chuyển sắc khi được chọn
    private let icon = CALayer()
    private let label = NSTextField(labelWithString: "")
    private let symbol: String
    private let hue: (NSColor, NSColor)
    private var focused = false

    private let noteLabel = NSTextField(labelWithString: "")

    init(title: String, symbol: String, hue: (NSColor, NSColor), note: String?) {
        self.symbol = symbol
        self.hue = hue
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(disc)
        fill.colors = [hue.0.cgColor, hue.1.cgColor]
        fill.startPoint = CGPoint(x: 0.2, y: 1); fill.endPoint = CGPoint(x: 0.8, y: 0)
        fill.masksToBounds = true
        disc.addSublayer(fill)
        disc.addSublayer(icon)
        label.stringValue = title
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.alignment = .center
        addSubview(label)
        if let note = note {                       // ví dụ "Đang dùng": chữ nhỏ cùng màu dưới tên
            noteLabel.stringValue = note
            noteLabel.font = .systemFont(ofSize: 10, weight: .semibold)
            noteLabel.textColor = hue.0
            noteLabel.alignment = .center
            addSubview(noteLabel)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let d: CGFloat = 86
        disc.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        disc.position = CGPoint(x: bounds.midX, y: bounds.height - 12 - d / 2)
        disc.cornerRadius = d / 2
        fill.frame = disc.bounds
        fill.cornerRadius = d / 2
        icon.frame = disc.bounds
        icon.contentsGravity = .center
        icon.contentsScale = 2
        label.frame = NSRect(x: 0, y: 18, width: bounds.width, height: 20)
        noteLabel.frame = NSRect(x: 0, y: 2, width: bounds.width, height: 14)
        CATransaction.commit()
        apply(animated: false)
    }

    func setFocused(_ f: Bool, animated: Bool) {
        focused = f
        apply(animated: animated)
    }

    private func apply(animated: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated && !reduceMotion ? 0.22 : 0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1))
        // Tiêu điểm kiểu tvOS: đĩa chuyển sắc rực + quầng sáng cùng màu, phóng to; còn lại đĩa nhuộm nhẹ, biểu tượng màu
        disc.backgroundColor = hue.1.withAlphaComponent(0.22).cgColor
        disc.borderWidth = 1
        disc.borderColor = hue.0.withAlphaComponent(focused ? 0 : 0.35).cgColor
        fill.opacity = focused ? 1 : 0
        disc.transform = CATransform3DMakeScale(focused ? 1.12 : 1, focused ? 1.12 : 1, 1)
        disc.shadowColor = hue.1.cgColor
        disc.shadowOpacity = focused ? 0.85 : 0
        disc.shadowRadius = 18
        disc.shadowOffset = .zero
        icon.contents = symbolLayerContents(symbol, size: 30, color: focused ? .white : hue.0, weight: .semibold)
        CATransaction.commit()
        label.textColor = focused ? .white : NSColor(white: 1, alpha: 0.6)
    }

    /// Nhấn chọn: đĩa lún xuống rồi nảy lại.
    func press() {
        guard !reduceMotion else { return }
        let a = CAKeyframeAnimation(keyPath: "transform.scale")
        a.values = [1.12, 0.96, 1.12]
        a.keyTimes = [0, 0.4, 1]
        a.duration = 0.2
        disc.add(a, forKey: "press")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
