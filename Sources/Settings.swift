// Settings.swift
// Cửa sổ cài đặt: chọn T("Áp dụng cho") (mặc định hoặc một app) → tab Nút bấm / Cảm ứng / Nâng cao.
// Mọi thay đổi được lưu ngay vào ~/.siriremote.json.

import Cocoa
import UniformTypeIdentifiers

final class SettingsWindow: NSObject, NSWindowDelegate, NSMenuDelegate {

    // MARK: Dữ liệu hiển thị

    private static let baseRows: [(String, String)] = [
        ("touchpad", "Touchpad"), ("menu", "Menu"), ("home", "Home"), ("siri", "Siri"),
        ("playpause", "Play/Pause"), ("volup", "Vol +"), ("voldown", "Vol −"),
    ]
    private static let gen23Rows: [(String, String)] = [
        ("select", T("Click ring: giữa")), ("up", "Click ring ↑"), ("down", "Click ring ↓"),
        ("left", "Click ring ←"), ("right", "Click ring →"), ("back", "Back"), ("tv", "TV"),
        ("mute", "Mute"), ("power", "Power"),
    ]
    private static let gestureRows: [(String, String)] = [
        ("swipeleft", T("Vuốt trái")), ("swiperight", T("Vuốt phải")), ("swipeup", T("Vuốt lên")),
        ("swipedown", T("Vuốt xuống")), ("twofingertap", T("Chạm 2 ngón")), ("twofingerdoubletap", T("Chạm đúp 2 ngón")),
        ("doubletap", T("Chạm đúp 1 ngón")),
    ]
    private static let actionGroups: [(String, [(String, String)])] = [
        ("Media", [("media:playpause", T("Phát / Dừng")), ("media:next", T("Bài kế tiếp")), ("media:previous", T("Bài trước")),
                   ("media:fast", T("Tua tới")), ("media:rewind", T("Tua lui")), ("media:volumeup", T("Tăng âm lượng")),
                   ("media:volumedown", T("Giảm âm lượng")), ("media:mute", T("Tắt tiếng"))]),
        (T("Phím"), [("key:left", T("Phím ←")), ("key:right", T("Phím →")), ("key:up", T("Phím ↑")), ("key:down", T("Phím ↓")),
                  ("key:space", "Space"), ("key:return", "Enter"), ("key:escape", "Esc"),
                  ("key:pageup", "Page Up"), ("key:pagedown", "Page Down"),
                  ("key:cmd+[", "Back (cmd+[)"), ("key:cmd+]", "Forward (cmd+])"),
                  ("nav:back", T("Back (thử nghiệm: hiệu ứng vuốt)")), ("nav:forward", T("Forward (thử nghiệm: hiệu ứng vuốt)"))]),
        (T("Chuột"), [("click", T("Click chuột")), ("rightclick", T("Click phải")), ("scroll:up", T("Cuộn lên")), ("scroll:down", T("Cuộn xuống")),
                     ("scroll:left", T("Cuộn ngang ←")), ("scroll:right", T("Cuộn ngang →"))]),
        (T("Zoom"), [("zoomtoggle", T("Zoom nhanh (phóng to ↔ về cũ)")), ("smartzoom", T("Zoom thông minh (như Magic Trackpad)")), ("zoomin", T("Phóng to (⌘+)")),
                      ("zoomout", T("Thu nhỏ (⌘−)")), ("zoomreset", T("Kích thước thật (⌘0)"))]),
        (T("Hệ thống"), [("mission", "Mission Control"), ("expose", T("Exposé (cửa sổ của app)")), ("screensaver", T("Màn hình chờ")),
                      ("showdesktop", T("Hiện màn hình nền")), ("lockscreen", T("Khóa màn hình")), ("sleep", T("Cho Mac ngủ")), ("displaysleep", T("Tắt màn hình")),
                      ("toggletouch", T("Đổi chế độ cảm ứng (con trỏ ↔ vuốt)")),
                      ("powermenu", T("Menu nguồn (như Apple TV)")), ("touchmenu", T("Chọn chế độ cảm ứng (bảng chọn)"))]),
    ]
    /// Biểu tượng SF Symbols cho từng hành động / hàng (nếu hệ thống không có thì bỏ qua, không lỗi).
    private static let icons: [String: String] = [
        "media:playpause": "playpause.fill", "media:next": "forward.fill", "media:previous": "backward.fill",
        "media:fast": "goforward.10", "media:rewind": "gobackward.10", "media:volumeup": "speaker.wave.3.fill",
        "media:volumedown": "speaker.wave.1.fill", "media:mute": "speaker.slash.fill",
        "key:left": "arrow.left", "key:right": "arrow.right", "key:up": "arrow.up", "key:down": "arrow.down",
        "key:space": "space", "key:return": "return", "key:escape": "escape",
        "key:pageup": "arrow.up.to.line", "key:pagedown": "arrow.down.to.line",
        "key:cmd+[": "chevron.backward", "key:cmd+]": "chevron.forward", "nav:back": "hand.draw", "nav:forward": "hand.draw",
        "click": "cursorarrow.click", "rightclick": "cursorarrow.click.2", "scroll:up": "arrow.up.circle", "scroll:down": "arrow.down.circle",
        "scroll:left": "arrow.left.circle", "scroll:right": "arrow.right.circle",
        "mission": "rectangle.3.group", "expose": "macwindow.on.rectangle", "screensaver": "photo.tv", "lockscreen": "lock.fill", "showdesktop": "menubar.dock.rectangle",
        "sleep": "moon.zzz.fill", "displaysleep": "display", "toggletouch": "arrow.left.arrow.right", "powermenu": "power", "touchmenu": "hand.point.up.left.fill",
        "@app": "square.grid.2x2", "@key": "keyboard", "none": "nosign",
        // hàng nút / cử chỉ
        "touchpad": "hand.point.up.left.fill", "menu": "chevron.backward.circle", "home": "tv", "siri": "mic.fill",
        "playpause": "playpause.fill", "volup": "speaker.wave.3.fill", "voldown": "speaker.wave.1.fill",
        "select": "circle.circle", "up": "arrow.up.circle", "down": "arrow.down.circle", "left": "arrow.left.circle",
        "right": "arrow.right.circle", "back": "chevron.backward", "tv": "tv", "mute": "speaker.slash.fill", "power": "power",
        "swipeleft": "arrow.left", "swiperight": "arrow.right", "swipeup": "arrow.up", "swipedown": "arrow.down",
        "twofingertap": "hand.tap", "twofingerdoubletap": "hand.tap.fill", "doubletap": "hand.tap",
        "smartzoom": "plus.magnifyingglass", "zoomtoggle": "plus.magnifyingglass", "zoomin": "plus.magnifyingglass", "zoomout": "minus.magnifyingglass", "zoomreset": "1.magnifyingglass",
    ]
    private static let allPresets: [(String, String)] = SettingsWindow.actionGroups.flatMap { $0.1 }

    /// Mẫu cấu hình nhanh: áp dụng cho mặc định hoặc cho app đang chọn.
    private static let templates: [(String, [String: String])] = [
        (T("Nghe nhạc"), ["touchpad": "media:playpause", "menu": "media:previous", "home": "media:next",
                       "swipeleft": "media:previous", "swiperight": "media:next",
                       "swipeup": "media:volumeup", "swipedown": "media:volumedown"]),
        (T("Xem YouTube"), ["touchpad": "key:k", "playpause": "key:k", "touchpad+double": "key:shift+n",
                         "swipeleft": "key:j", "swiperight": "key:l", "swipeup": "key:up", "swipedown": "key:down",
                         "home": "key:f", "menu": "key:escape"]),
        (T("Lướt TikTok"), ["touchpad": "key:space", "swipeup": "key:down", "swipedown": "key:up",
                         "home": "key:m", "menu": "key:escape"]),
        (T("Duyệt web"), ["menu": "key:cmd+[", "home": "key:cmd+]", "swipeup": "scroll:down", "swipedown": "scroll:up",
                      "twofingerdoubletap": "zoomtoggle"]),
        (T("Thuyết trình"), ["touchpad": "key:right", "menu": "key:left", "home": "key:escape",
                          "swipeleft": "key:right", "swiperight": "key:left"]),
    ]

    // MARK: Trạng thái

    private let window: NSWindow
    private var cfg = ConfigFile.load()
    private var current: String?            // nil = cấu hình mặc định; ngược lại = bundle id của app
    private var centered = false

    private let profilePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let templatePopup = NSPopUpButton(frame: .zero, pullsDown: true)
    private let removeButton = NSButton(title: T("Xóa app này"), target: nil, action: nil)
    private let permButton = NSButton(title: T("Cấp quyền…"), target: nil, action: nil)
    private let buttonsHost = NSStackView()
    private let touchHost = NSStackView()
    private let advancedHost = NSStackView()
    private var pages: [NSScrollView] = []
    private var statusTimer: Timer?
    var onClose: (() -> Void)?
    private let segment = NSSegmentedControl()
    private let pageHost = NSView()
    private var currentPage = 0

    // Hình minh hoạ
    private let permPill = StatusPill(), remotePill = StatusPill(), touchPill = StatusPill()
    private var remoteView: RemoteIllustrationView?
    private var rowViews: [String: [HoverRow]] = [:]
    private var gestureDemos: [String: GestureDemoView] = [:]
    private var modeTiles: [TouchModeTile] = []
    private var valueLabels: [String: NSTextField] = [:]
    private weak var touchDevicePill: StatusPill?
    private weak var touchTechView: NSView?
    private var showTouchTech = false

    /// "gen1" hoặc "gen23": theo lựa chọn trong tab Nâng cao, hoặc tự nhận từ product ID khi để "auto".
    private var effectiveModel: String {
        let m = cfg.global["remotemodel"] ?? "auto"
        if m != "auto" { return m }
        return detectedProductID == 0 || detectedProductID == 0x266 ? "gen1" : "gen23"
    }

    private var buttonRows: [(String, String)] {
        var r = SettingsWindow.baseRows
        if effectiveModel == "gen23" { r += SettingsWindow.gen23Rows }
        for name in cfg.custom.keys.sorted() where !r.contains(where: { $0.0 == name }) { r.append((name, TF("Nút “%@”", name))) }
        return r
    }

    // MARK: Khởi tạo

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 780),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = "SiriRemoteMac"
        window.subtitle = T("Cài đặt")
        window.isReleasedWhenClosed = false
        window.delegate = self

        // Hàng 1: áp dụng cho + mẫu
        profilePopup.target = self; profilePopup.action = #selector(profileChanged(_:))
        profilePopup.widthAnchor.constraint(equalToConstant: 210).isActive = true
        let addButton = NSButton(title: T("Thêm app"), target: self, action: #selector(addApp(_:)))
        addButton.image = symbol("plus"); addButton.imagePosition = .imageLeading
        removeButton.title = T("Xóa"); removeButton.image = symbol("trash"); removeButton.imagePosition = .imageLeading
        removeButton.target = self; removeButton.action = #selector(removeApp)
        templatePopup.addItem(withTitle: T("Mẫu có sẵn"))
        templatePopup.item(at: 0)?.image = symbol("wand.and.stars")
        for (i, t) in SettingsWindow.templates.enumerated() {
            let mi = NSMenuItem(title: t.0, action: #selector(applyTemplate(_:)), keyEquivalent: "")
            mi.target = self
            mi.tag = i
            templatePopup.menu?.addItem(mi)
        }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row1 = hstack([iconLabel("app.dashed", T("Áp dụng cho")), profilePopup, addButton, removeButton, spacer, templatePopup])

        // Đầu trang: biểu tượng app + tên + các nhãn trạng thái
        permButton.title = T("Cấp quyền…")
        permButton.target = self; permButton.action = #selector(openAccessibility)
        permButton.bezelColor = .systemOrange
        let appIcon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        appIcon.imageScaling = .scaleProportionallyUpOrDown
        appIcon.widthAnchor.constraint(equalToConstant: 44).isActive = true
        appIcon.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let appTitle = NSTextField(labelWithString: "SiriRemoteMac")
        appTitle.font = .systemFont(ofSize: 18, weight: .bold)
        let pills = hstack([permPill, remotePill, touchPill, permButton], spacing: 6)
        let titleCol = vstack([appTitle, pills], spacing: 4)
        let row2 = hstack([appIcon, titleCol], spacing: 12)

        // Thanh chuyển trang
        segment.segmentCount = 3
        for (i, (title, sym)) in [(T("Nút bấm"), "av.remote"), (T("Cảm ứng"), "hand.point.up.left"), (T("Nâng cao"), "slider.horizontal.3")].enumerated() {
            segment.setLabel(title, forSegment: i)
            segment.setImage(symbol(sym), forSegment: i)
            segment.setWidth(130, forSegment: i)
        }
        segment.segmentStyle = .rounded
        segment.trackingMode = .selectOne
        segment.selectedSegment = 0
        segment.target = self; segment.action = #selector(pageChanged(_:))

        // Các trang (mỗi trang một khung cuộn, chỉ hiện một trang)
        pageHost.wantsLayer = true
        for h in [buttonsHost, touchHost, advancedHost] {
            let sv = makePage(h)
            sv.translatesAutoresizingMaskIntoConstraints = false
            pageHost.addSubview(sv)
            NSLayoutConstraint.activate([
                sv.topAnchor.constraint(equalTo: pageHost.topAnchor), sv.bottomAnchor.constraint(equalTo: pageHost.bottomAnchor),
                sv.leadingAnchor.constraint(equalTo: pageHost.leadingAnchor), sv.trailingAnchor.constraint(equalTo: pageHost.trailingAnchor),
            ])
            pages.append(sv)
        }
        showPage(0, animated: false)
        pageHost.setContentHuggingPriority(.defaultLow, for: .vertical)
        pageHost.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let footer = note(T("Mọi thay đổi được lưu ngay. “↩ Mặc định” nghĩa là dùng cấu hình chung; cấu hình riêng áp dụng cho app đang ở trên cùng."))

        let segRow = NSView()
        segment.translatesAutoresizingMaskIntoConstraints = false
        segRow.addSubview(segment)
        NSLayoutConstraint.activate([
            segment.centerXAnchor.constraint(equalTo: segRow.centerXAnchor),
            segment.topAnchor.constraint(equalTo: segRow.topAnchor),
            segment.bottomAnchor.constraint(equalTo: segRow.bottomAnchor),
        ])
        let root = NSStackView(views: [row2, row1, segRow, pageHost, footer])
        root.setCustomSpacing(16, after: row2)
        root.orientation = .vertical; root.alignment = .leading; root.spacing = 12; root.distribution = .fill
        root.translatesAutoresizingMaskIntoConstraints = false
        for v in [row1, row2, segRow, pageHost, footer] { v.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true }
        let container = NSView()
        container.addSubview(root)
        window.contentView = container
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
        ])
    }

    func show() {
        cfg = ConfigFile.load()
        if let c = current, cfg.apps[c] == nil { current = nil }
        reload()
        if !centered { window.center(); centered = true }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // Trạng thái quyền / remote / cảm ứng có thể đổi bất cứ lúc nào: cập nhật định kỳ khi cửa sổ đang mở
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.updateStatus() }
        // Nút / cử chỉ thật trên remote → sáng trên hình minh hoạ
        remoteEventObserver = { [weak self] name in self?.remoteEvent(name) }
        window.contentView?.staggerIn([currentHost])
    }

    private var currentHost: NSStackView { [buttonsHost, touchHost, advancedHost][currentPage] }

    private func remoteEvent(_ name: String) {
        remoteView?.pulse(name)
        gestureDemos[name]?.flash()
        for row in rowViews[name] ?? [] { flashRow(row) }
    }

    private func flashRow(_ row: HoverRow) {
        row.isLit = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak row, weak self] in
            guard let row = row else { return }
            row.isLit = self?.hoverName == row.name
        }
    }

    private var hoverName: String?

    /// Rê chuột lên hàng hoặc lên nút trên hình: sáng cả hai.
    private func setHover(_ name: String?) {
        hoverName = name
        remoteView?.highlight(name)
        for (n, rows) in rowViews { for r in rows { r.isLit = n == name } }
        for (n, demo) in gestureDemos { demo.setLooping(n == name) }
    }

    func windowWillClose(_ notification: Notification) {
        remoteEventObserver = nil
        statusTimer?.invalidate()
        statusTimer = nil
        onClose?()                      // AppDelegate giải phóng cửa sổ để không giữ RAM khi không dùng
    }

    deinit {
        window.delegate = nil
        statusTimer?.invalidate()
    }

    @objc private func pageChanged(_ sender: NSSegmentedControl) { showPage(sender.selectedSegment, animated: true) }

    /// Đổi trang: trượt sang trái / phải theo thứ tự tab, các thẻ hiện ra lần lượt.
    private func showPage(_ i: Int, animated: Bool) {
        let old = currentPage
        currentPage = i
        if animated, i != old, !reduceMotion, let l = pageHost.layer {
            let t = CATransition()
            t.type = .push
            t.subtype = i > old ? .fromRight : .fromLeft
            t.duration = 0.32
            t.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.9, 0.3, 1)
            l.add(t, forKey: "page")
        }
        for (n, p) in pages.enumerated() { p.isHidden = n != i }
        if animated { pages[i].contentView.scroll(to: .zero) }
    }

    // MARK: Hàm dựng giao diện dùng chung

    /// Ảnh SF Symbol dùng chung (bộ nhớ đệm): hàng nghìn mục menu chỉ giữ vài chục ảnh thay vì mỗi mục một ảnh.
    private static var symbolCache: [String: NSImage] = [:]

    private func symbol(_ name: String?, size: CGFloat = 13) -> NSImage? {
        guard let name = name else { return nil }
        let key = "\(name)|\(size)"
        if let img = SettingsWindow.symbolCache[key] { return img }
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .regular))
        SettingsWindow.symbolCache[key] = img
        return img
    }

    /// Nhãn có biểu tượng đứng trước.
    private func iconLabel(_ sym: String?, _ text: String) -> NSView {
        let l = NSTextField(labelWithString: text)
        guard let img = symbol(sym) else { return l }
        let iv = NSImageView(image: img)
        iv.contentTintColor = .secondaryLabelColor
        iv.widthAnchor.constraint(equalToConstant: 20).isActive = true
        return hstack([iv, l], spacing: 6)
    }

    private func hstack(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal; s.spacing = spacing; s.alignment = .centerY
        return s
    }

    private func vstack(_ views: [NSView], spacing: CGFloat = 6) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .vertical; s.spacing = spacing; s.alignment = .leading
        return s
    }

    private func note(_ text: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.textColor = .secondaryLabelColor; l.font = .systemFont(ofSize: 11); l.preferredMaxLayoutWidth = 640
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }

    private func caption(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 11, weight: .medium)
        l.textColor = .secondaryLabelColor
        return l
    }

    /// Thẻ có tiêu đề + biểu tượng, nền nhẹ, bo góc; nội dung xếp dọc.
    private func card(_ title: String, _ sym: String, _ views: [NSView]) -> NSView {
        let box = NSBox()
        box.boxType = .custom; box.titlePosition = .noTitle
        box.cornerRadius = 10; box.borderWidth = 1
        box.borderColor = .separatorColor; box.fillColor = .controlBackgroundColor
        box.contentViewMargins = .zero
        let stack = vstack([cardTitle(sym, title)] + views, spacing: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.contentView?.addSubview(stack)
        if let cv = box.contentView {
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: cv.topAnchor, constant: 12),
                stack.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -12),
                stack.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 14),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: cv.trailingAnchor, constant: -14),
            ])
        }
        return box
    }

    /// Tiêu đề thẻ: biểu tượng trong ô vuông bo góc màu nhấn + chữ đậm.
    private func cardTitle(_ sym: String, _ title: String) -> NSView {
        let l = NSTextField(labelWithString: title)
        l.font = .systemFont(ofSize: 13, weight: .semibold)
        let chip = NSView()
        chip.wantsLayer = true
        chip.layer?.cornerRadius = 6
        chip.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
        chip.translatesAutoresizingMaskIntoConstraints = false
        chip.widthAnchor.constraint(equalToConstant: 24).isActive = true
        chip.heightAnchor.constraint(equalToConstant: 24).isActive = true
        if let img = symbol(sym, size: 12) {
            let iv = NSImageView(image: img)
            iv.contentTintColor = .controlAccentColor
            iv.translatesAutoresizingMaskIntoConstraints = false
            chip.addSubview(iv)
            iv.centerXAnchor.constraint(equalTo: chip.centerXAnchor).isActive = true
            iv.centerYAnchor.constraint(equalTo: chip.centerYAnchor).isActive = true
        }
        return hstack([chip, l], spacing: 8)
    }

    /// Thêm thẻ vào trang, rộng bằng trang.
    private func add(_ v: NSView, to host: NSStackView) {
        host.addArrangedSubview(v)
        v.widthAnchor.constraint(equalTo: host.widthAnchor).isActive = true
    }

    private final class FlippedView: NSView { override var isFlipped: Bool { true } }

    private func makePage(_ host: NSStackView) -> NSScrollView {
        host.orientation = .vertical; host.alignment = .leading; host.spacing = 12
        host.translatesAutoresizingMaskIntoConstraints = false
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(host)
        let sv = NSScrollView()
        sv.drawsBackground = false; sv.borderType = .noBorder
        sv.hasVerticalScroller = true; sv.autohidesScrollers = true
        sv.documentView = doc
        let clip = sv.contentView
        NSLayoutConstraint.activate([
            doc.topAnchor.constraint(equalTo: clip.topAnchor),
            doc.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            host.topAnchor.constraint(equalTo: doc.topAnchor, constant: 4),
            host.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -12),
            host.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 2),
            host.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -10),
        ])
        return sv
    }

    private func idPopup(_ items: [(String, String)], selected: String, action: Selector) -> NSPopUpButton {
        let p = NSPopUpButton(frame: .zero, pullsDown: false)
        for (id, title) in items {
            let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            mi.representedObject = id
            p.menu?.addItem(mi)
        }
        if let i = p.itemArray.firstIndex(where: { ($0.representedObject as? String) == selected }) { p.selectItem(at: i) }
        p.target = self; p.action = action
        return p
    }

    private func textField(_ id: String, _ fallback: String, width: CGFloat) -> NSTextField {
        let f = NSTextField(string: cfg.global[id] ?? fallback)
        f.identifier = NSUserInterfaceItemIdentifier(id)
        f.target = self; f.action = #selector(fieldChanged(_:))
        (f.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = true
        f.widthAnchor.constraint(equalToConstant: width).isActive = true
        return f
    }

    private func checkbox(_ id: String, _ title: String, _ def: String) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: self, action: #selector(checkChanged(_:)))
        b.identifier = NSUserInterfaceItemIdentifier(id)
        b.state = (cfg.global[id] ?? def) == "1" ? .on : .off
        return b
    }

    private func slider(_ id: String, _ lo: Double, _ hi: Double, _ def: Double) -> NSSlider {
        let s = NSSlider(value: Double(cfg.global[id] ?? "") ?? def, minValue: lo, maxValue: hi,
                         target: self, action: #selector(sliderChanged(_:)))
        s.identifier = NSUserInterfaceItemIdentifier(id)
        s.isContinuous = true
        s.widthAnchor.constraint(equalToConstant: 260).isActive = true
        return s
    }

    private func appName(_ bid: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bid
    }

    private func label(for spec: String?) -> String {
        guard let spec = spec, spec != "none", !spec.isEmpty else { return T("Không làm gì") }
        if let p = SettingsWindow.allPresets.first(where: { $0.0 == spec }) { return p.1 }
        if spec.hasPrefix("app:") { return T("Mở ") + String(spec.dropFirst(4)) }
        if spec.hasPrefix("key:") { return T("Phím ") + String(spec.dropFirst(4)) }
        return spec
    }

    // MARK: Dựng nội dung

    private func reload() {
        profilePopup.removeAllItems()
        let def = NSMenuItem(title: T("Mặc định (mọi app)"), action: nil, keyEquivalent: "")
        def.representedObject = ""
        def.image = symbol("globe", size: 12)
        profilePopup.menu?.addItem(def)
        for bid in cfg.apps.keys.sorted(by: { appName($0).localizedCaseInsensitiveCompare(appName($1)) == .orderedAscending }) {
            let mi = NSMenuItem(title: appName(bid), action: nil, keyEquivalent: "")
            mi.representedObject = bid
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 16, height: 16)
                mi.image = icon
            }
            profilePopup.menu?.addItem(mi)
        }
        if let i = profilePopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == (current ?? "") }) {
            profilePopup.selectItem(at: i)
        }
        removeButton.isEnabled = current != nil
        rebuild()
        if window.isVisible { window.contentView?.staggerIn(currentHost.arrangedSubviews) }
    }

    private func rebuild() {
        for h in [buttonsHost, touchHost, advancedHost] {
            for v in h.arrangedSubviews { h.removeArrangedSubview(v); v.removeFromSuperview() }
        }
        rowViews = [:]; gestureDemos = [:]; modeTiles = []; valueLabels = [:]; remoteView = nil
        updateStatus()
        buildButtonsTab()
        buildTouchTab()
        buildAdvancedTab()
    }

    func updateStatus() {
        let trusted = AXIsProcessTrusted()
        permPill.set(ok: trusted, text: trusted ? T("Đã cấp quyền") : T("Thiếu quyền Accessibility"))
        remotePill.set(ok: controller.isConnected, text: controller.isConnected ? T("Remote đã kết nối") : T("Remote chưa kết nối"))
        touchPill.set(ok: touchMode != .off, text: T("Cảm ứng: ") + touchMode.title)
        if permButton.isHidden != trusted {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25; ctx.allowsImplicitAnimation = true
                permButton.isHidden = trusted
                permButton.superview?.layoutSubtreeIfNeeded()
            }
        }
        updateTouchDeviceStatus()
        for t in modeTiles { t.isSelected = t.modeID == (cfg.global["touchmode"] ?? "cursor") }
    }

    private func rowLabel(_ name: String, _ text: String, gesture: Bool) -> NSView {
        let content: NSView
        if gesture {
            let demo = GestureDemoView(gesture: name)
            gestureDemos[name] = demo
            content = hstack([demo, NSTextField(labelWithString: text)], spacing: 8)
        } else {
            content = iconLabel(SettingsWindow.icons[name], text)
        }
        let row = HoverRow(name: name, content: content)
        row.onHover = { [weak self] n in self?.setHover(n) }
        rowViews[name, default: []].append(row)
        return row
    }

    private func makeGrid(columns: [(String, String)], rows: [(String, String)], popupWidth: CGFloat = 155,
                          gesture: Bool = false) -> NSGridView {
        var data: [[NSView]] = [[NSView()] + columns.map { caption($0.0) as NSView }]
        for (name, text) in rows {
            data.append([rowLabel(name, text, gesture: gesture)] + columns.map { makePopup(name + $0.1, width: popupWidth) as NSView })
        }
        let g = NSGridView(views: data)
        g.columnSpacing = 12; g.rowSpacing = 6
        g.column(at: 0).width = gesture ? 200 : 160
        g.yPlacement = .center
        return g
    }

    private func buildButtonsTab() {
        let remote = RemoteIllustrationView()
        remote.model = effectiveModel == "gen23" ? .gen23 : .gen1
        remote.onHover = { [weak self] n in self?.setHover(n) }
        remote.translatesAutoresizingMaskIntoConstraints = false
        remote.widthAnchor.constraint(equalToConstant: 150).isActive = true
        remote.heightAnchor.constraint(equalToConstant: 410).isActive = true
        remoteView = remote
        let hint = note(T("Rê chuột lên nút trên hình hoặc bấm nút thật trên remote để thấy hàng tương ứng."))
        hint.preferredMaxLayoutWidth = 150
        hint.alignment = .center
        let left = vstack([remote, hint], spacing: 4)
        left.alignment = .centerX
        left.widthAnchor.constraint(equalToConstant: 150).isActive = true
        let grid = makeGrid(columns: [(T("Bấm"), ""), (T("Giữ"), "+hold"), (T("Nhấn đúp"), "+double")], rows: buttonRows, popupWidth: 150)
        // Bảng giữ chiều cao tự nhiên, nằm sát trên (không bị kéo giãn theo chiều cao hình remote)
        grid.setContentHuggingPriority(.required, for: .vertical)
        grid.setContentCompressionResistancePriority(.required, for: .vertical)
        let gridCol = NSStackView(views: [grid])
        gridCol.orientation = .vertical; gridCol.alignment = .leading
        gridCol.setHuggingPriority(.defaultLow, for: .vertical)
        let content = NSStackView(views: [left, gridCol])
        content.orientation = .horizontal; content.alignment = .top; content.spacing = 18
        add(card(T("Phím trên remote"), "av.remote", [content]), to: buttonsHost)
    }

    /// Chữ hiện cạnh thanh trượt: độ mượt hiện theo phần trăm, còn lại là số.
    private func valueText(_ id: String, _ v: Double) -> String {
        id == "scrollsmooth" ? "\(Int((v * 100).rounded()))%" : String(format: "%.2f", v)
    }

    private func sliderRow(_ title: String, _ id: String, _ lo: Double, _ hi: Double, _ def: Double) -> NSView {
        let t = NSTextField(labelWithString: title)
        t.widthAnchor.constraint(equalToConstant: 120).isActive = true
        let s = slider(id, lo, hi, def)
        let v = NSTextField(labelWithString: valueText(id, s.doubleValue))
        v.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        v.textColor = .secondaryLabelColor
        v.widthAnchor.constraint(equalToConstant: 40).isActive = true
        valueLabels[id] = v
        return hstack([t, s, v], spacing: 10)
    }

    private func buildTouchTab() {
        if current == nil {
            let modes: [(String, String, String, String)] = [
                ("cursor", T("Con trỏ"), "cursorarrow.motionlines", T("Một ngón di chuyển con trỏ, hai ngón cuộn, vuốt nhanh chạy cử chỉ bên dưới.")),
                ("swipe", T("Vuốt / chạm"), "hand.draw", T("Không di chuyển con trỏ; chỉ nhận cử chỉ vuốt và chạm bên dưới.")),
                ("off", T("Tắt"), "nosign", T("Bỏ qua touchpad.")),
            ]
            let cur = cfg.global["touchmode"] ?? "cursor"
            let tiles: [TouchModeTile] = modes.map { (id, title, sym, desc) in
                let t = TouchModeTile(mode: id, title: title, detail: desc, symbol: sym)
                t.isSelected = id == cur
                t.onSelect = { [weak self] m in self?.selectTouchMode(m) }
                return t
            }
            modeTiles = tiles
            let tileRow = NSStackView(views: tiles)
            tileRow.orientation = .horizontal; tileRow.distribution = .fillEqually; tileRow.spacing = 10; tileRow.alignment = .top
            for t in tiles { t.heightAnchor.constraint(equalToConstant: 168).isActive = true }
            let modeCard = card(T("Chế độ cảm ứng"), "hand.point.up.left", [tileRow, note(T("Mẹo: giữ nút Siri để đổi nhanh giữa các chế độ."))])
            tileRow.widthAnchor.constraint(equalTo: modeCard.widthAnchor, constant: -28).isActive = true
            add(modeCard, to: touchHost)

            add(card(T("Độ nhạy"), "dial.medium", [
                sliderRow(T("Tốc độ con trỏ"), "touchspeed", 0.3, 4, 1.5),
                sliderRow(T("Tốc độ cuộn"), "scrollspeed", 0.2, 3, 1.0),
                sliderRow(T("Độ mượt"), "scrollsmooth", 0, 1, 0.55),
                note(T("Độ mượt (con trỏ và cuộn): cao = khử rung mạnh hơn, đi đều hơn nhưng chạy sau ngón một chút; thấp = bám sát ngón; 0% = tắt làm mượt.")),
            ]), to: touchHost)

            add(card(T("Cảm giác như Magic Trackpad"), "wand.and.stars", [
                checkbox("naturalscroll", T("Cuộn tự nhiên (đảo chiều, áp dụng cả cho vuốt gán Cuộn)"), "1"),
                checkbox("scrollmomentum", T("Cuộn có quán tính (tiếp tục cuộn sau khi nhấc tay)"), "1"),
                checkbox("tapclick", T("Chạm nhẹ để click (chạm rồi đặt ngón xuống = kéo thả)"), "0"),
                checkbox("clicksteady", T("Giữ yên con trỏ khi nhấn touchpad để click"), "1"),
            ]), to: touchHost)
        }
        add(card(T("Cử chỉ"), "hand.draw", [makeGrid(columns: [(T("Hành động"), "")], rows: SettingsWindow.gestureRows, popupWidth: 260, gesture: true)]), to: touchHost)
    }

    private func buildAdvancedTab() {
        guard current == nil else {
            add(card(T("Nâng cao"), "slider.horizontal.3", [note(T("Cài đặt nâng cao áp dụng chung cho mọi app. Chọn “Mặc định (mọi app)” ở ô Áp dụng cho để chỉnh."))]), to: advancedHost)
            return
        }
        let langs: [(String, String)] = [("auto", T("Tự động (theo hệ thống)")), ("vi", "Tiếng Việt"), ("en", "English")]
        add(card(T("Ngôn ngữ"), "globe", [
            idPopup(langs, selected: cfg.global["language"] ?? "auto", action: #selector(languageChanged(_:))),
            note(T("Đổi ngôn ngữ có hiệu lực sau khi mở lại app.")),
        ]), to: advancedHost)
        let models: [(String, String)] = [("auto", T("Tự nhận (khuyên dùng)")), ("gen1", T("Đời 1 (A1513 / A1844)")),
                                          ("gen23", T("Đời 2 / 3 (A2540 / A2854, USB-C)"))]
        let detected = detectedProductID == 0 ? T("chưa thấy remote") : "product ID 0x" + String(detectedProductID, radix: 16)
        add(card(T("Đời remote"), "av.remote", [
            hstack([idPopup(models, selected: cfg.global["remotemodel"] ?? "auto", action: #selector(modelChanged(_:))),
                    NSTextField(labelWithString: TF("đang nhận: %@", detected))], spacing: 10),
            note(T("Đời 2/3 hiện thêm các nút click ring, Back, TV, Mute, Power ở tab Nút bấm (mã nút theo chuẩn HID, chưa kiểm chứng trên máy thật).")),
        ]), to: advancedHost)

        add(card(T("Thời gian"), "timer", [
            hstack([NSTextField(labelWithString: T("Giữ nút (giây)")), textField("holdtime", "0.8", width: 56),
                    NSTextField(labelWithString: T("      Nhấn đúp (giây)")), textField("doubletime", "0.3", width: 56)], spacing: 8),
        ]), to: advancedHost)

        // Touchpad của remote: trạng thái dễ hiểu; mã thiết bị (family) giấu trong "Tuỳ chọn kỹ thuật"
        let pill = StatusPill()
        touchDevicePill = pill
        let tech = vstack([
            hstack([NSTextField(labelWithString: T("Mã thiết bị cảm ứng")), textField("touchfamily", "160,145", width: 140)], spacing: 8),
            note(T("Đời 1 = 160, đời 3 = 145 (luôn được thử). Với đời khác: bật “Ghi log nút bấm” (menu → Nâng cao), nối lại remote, xem dòng `family` trong log và thêm vào đây, cách nhau bằng dấu phẩy.")),
        ], spacing: 6)
        tech.isHidden = !showTouchTech
        let disclose = NSButton(title: "", target: self, action: #selector(toggleTouchTech(_:)))
        disclose.bezelStyle = .disclosure
        disclose.setButtonType(.pushOnPushOff)
        disclose.state = showTouchTech ? .on : .off
        let discloseLabel = NSTextField(labelWithString: T("Tuỳ chọn kỹ thuật"))
        discloseLabel.textColor = .secondaryLabelColor
        touchTechView = tech
        add(card(T("Touchpad của remote"), "hand.point.up.left", [
            pill,
            note(T("Thường không cần chỉnh gì: app tự nhận touchpad của Siri Remote đời 1 và đời 3.")),
            hstack([disclose, discloseLabel], spacing: 4),
            tech,
        ]), to: advancedHost)
        updateTouchDeviceStatus()

        var learnViews: [NSView] = [
            NSButton(title: T("Học nút mới…"), target: self, action: #selector(learnButton)),
            note(T("Dùng khi một nút chưa có trong danh sách: bấm “Học nút mới…”, bấm nút đó trên remote rồi đặt tên. Nút sẽ xuất hiện ở tab Nút bấm.")),
        ]
        for name in cfg.custom.keys.sorted() {
            let del = NSButton(title: T("Xóa"), target: self, action: #selector(removeCustom(_:)))
            del.identifier = NSUserInterfaceItemIdentifier(name)
            learnViews.append(hstack([NSTextField(labelWithString: "\(name)  →  \(cfg.custom[name] ?? "")"), del], spacing: 10))
        }
        add(card(T("Nút tự học"), "plus.viewfinder", learnViews), to: advancedHost)

        add(card(T("Hiệu ứng Back/Forward (nav:back, nav:forward)"), "hand.draw", [
            sliderRow(T("Thời gian"), "navduration", 0.15, 1.0, 0.25),
            sliderRow(T("Quãng vuốt"), "navdistance", 0.4, 6.0, 0.9),
            checkbox("navinvert", T("Đảo chiều"), "0"),
            note(T("Nếu thấy giật/lag: giảm Thời gian và Quãng vuốt; nếu không đổi trang: tăng Quãng vuốt.")),
        ]), to: advancedHost)
    }

    private func updateTouchDeviceStatus() {
        guard let pill = touchDevicePill else { return }
        if touchMode == .off {
            pill.set(ok: false, text: T("Cảm ứng đang tắt — bật lại ở tab Cảm ứng"))
        } else if touchEngine.isRunning {
            pill.set(ok: true, text: T("Đang nhận cảm ứng từ remote"))
        } else if !controller.isConnected {
            pill.set(ok: false, text: T("Chưa thấy remote — hãy kết nối qua Bluetooth"))
        } else {
            pill.set(ok: false, text: T("Remote đã kết nối nhưng chưa nhận được touchpad — thử tắt/bật remote"))
        }
    }

    @objc private func toggleTouchTech(_ sender: NSButton) {
        showTouchTech = sender.state == .on
        guard let v = touchTechView else { return }
        if showTouchTech && !reduceMotion {
            v.isHidden = false
            v.superview?.staggerIn([v])
        } else {
            v.isHidden = !showTouchTech
        }
    }

    // MARK: Ô chọn hành động

    /// Menu của ô chọn hành động, dựng đầy đủ khi người dùng mở ra lần đầu (xem menuNeedsUpdate).
    private final class ActionMenu: NSMenu {
        var key = ""
        var built = false
        weak var popup: NSPopUpButton?
    }

    /// Hành động hiện tại của một khóa trong hồ sơ đang chọn (nil = dùng mặc định).
    private func currentSpec(_ key: String) -> String? {
        current == nil ? (cfg.global[key] ?? "none") : cfg.apps[current!]?[key]
    }

    private func actionItem(_ title: String, _ rep: String?) -> NSMenuItem {   // rep = nil: tiêu đề nhóm
        let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        mi.representedObject = rep
        mi.isEnabled = rep != nil
        if let rep = rep {
            mi.image = symbol(rep == "@inherit" ? "arrow.uturn.backward" : SettingsWindow.icons[rep], size: 12)
        }
        return mi
    }

    /// Ô chọn hành động. Ban đầu chỉ chứa đúng mục đang chọn; danh sách đầy đủ (~45 mục) dựng khi mở ra.
    /// (Trên macOS mới mỗi mục menu tốn khá nhiều bộ nhớ: dựng sẵn cho ~55 ô chọn từng chiếm ~100 MB.)
    private func makePopup(_ key: String, width: CGFloat = 155) -> NSPopUpButton {
        let p = NSPopUpButton(frame: .zero, pullsDown: false)
        let menu = ActionMenu()
        menu.key = key
        menu.popup = p
        menu.delegate = self
        menu.autoenablesItems = false
        p.menu = menu
        p.identifier = NSUserInterfaceItemIdentifier(key)
        p.target = self; p.action = #selector(actionChanged(_:))
        p.widthAnchor.constraint(equalToConstant: width).isActive = true

        let cur = currentSpec(key)
        let title: String
        if let cur = cur {
            title = SettingsWindow.allPresets.first(where: { $0.0 == cur })?.1 ?? (cur == "none" ? T("Không làm gì") : label(for: cur))
        } else {
            title = T("↩ Mặc định: ") + label(for: cfg.global[key])
        }
        menu.addItem(actionItem(title, cur ?? "@inherit"))
        p.selectItem(at: 0)
        return p
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let m = menu as? ActionMenu, !m.built, let p = m.popup else { return }
        m.built = true
        m.removeAllItems()
        let key = m.key
        if current != nil { m.addItem(actionItem(T("↩ Mặc định: ") + label(for: cfg.global[key]), "@inherit")) }
        m.addItem(actionItem(T("Không làm gì"), "none"))
        for (group, items) in SettingsWindow.actionGroups {
            m.addItem(.separator())
            m.addItem(actionItem(group.uppercased(), nil))
            for (spec, title) in items { m.addItem(actionItem(title, spec)) }
        }
        m.addItem(.separator())
        m.addItem(actionItem(T("Mở ứng dụng…"), "@app"))
        m.addItem(actionItem(T("Phím tắt…"), "@key"))

        let cur = currentSpec(key) ?? "@inherit"
        if let i = p.itemArray.firstIndex(where: { ($0.representedObject as? String) == cur }) {
            p.selectItem(at: i)
        } else {                                        // phím tắt / mở app riêng: thêm mục cho nó
            let mi = actionItem(label(for: cur), cur)
            m.insertItem(mi, at: current != nil ? 1 : 0)
            p.select(mi)
        }
    }

    // MARK: Thao tác

    private func commit(rebuild doRebuild: Bool = true) {
        cfg.save()
        controller.reloadMap()
        if doRebuild { rebuild() }
    }

    @objc private func profileChanged(_ sender: NSPopUpButton) {
        let rep = (sender.selectedItem?.representedObject as? String) ?? ""
        current = rep.isEmpty ? nil : rep
        reload()
    }

    @objc private func actionChanged(_ sender: NSPopUpButton) {
        guard let key = sender.identifier?.rawValue,
              let rep = sender.selectedItem?.representedObject as? String else { return }
        var value: String? = rep
        switch rep {
        case "@inherit": value = nil
        case "@app":
            guard let name = chooseApp()?.deletingPathExtension().lastPathComponent else { rebuild(); return }
            value = "app:" + name
        case "@key":
            guard let k = promptKey() else { rebuild(); return }
            value = "key:" + k
        default: break
        }
        if let bid = current {
            if let v = value { cfg.apps[bid, default: [:]][key] = v } else { cfg.apps[bid]?[key] = nil }
        } else if let v = value {
            if v == "none" && defaultMap[key] == nil { cfg.global[key] = nil } else { cfg.global[key] = v }
        }
        // Ô chọn đã tự hiện lựa chọn mới: chỉ dựng lại khi cần thêm mục riêng (mở app… / phím tắt…)
        commit(rebuild: rep.hasPrefix("@") && rep != "@inherit")
    }

    @objc private func applyTemplate(_ sender: NSMenuItem) {
        guard SettingsWindow.templates.indices.contains(sender.tag) else { return }
        let (name, specs) = SettingsWindow.templates[sender.tag]
        let target = current.map { appName($0) } ?? T("mặc định (mọi app)")
        let a = NSAlert()
        a.messageText = TF("Áp dụng mẫu “%@” cho %@?", T(name), target)
        a.informativeText = T("Các nút và cử chỉ có trong mẫu sẽ được thay; những nút khác giữ nguyên.")
        a.addButton(withTitle: T("Áp dụng")); a.addButton(withTitle: T("Hủy"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        for (k, v) in specs {
            if let bid = current { cfg.apps[bid, default: [:]][k] = v } else { cfg.global[k] = v }
        }
        commit()
    }

    /// Chọn chế độ bằng thẻ: chỉ đổi trạng thái thẻ (có animation), không dựng lại cả trang.
    private func selectTouchMode(_ id: String) {
        cfg.global["touchmode"] = id
        for t in modeTiles { t.isSelected = t.modeID == id }
        commit(rebuild: false)
        updateStatus()
        appDelegate.refresh()
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        guard let id = sender.selectedItem?.representedObject as? String else { return }
        cfg.global["language"] = id
        cfg.save()
        let a = NSAlert()
        a.messageText = T("Cần mở lại app để đổi ngôn ngữ")
        a.addButton(withTitle: T("Mở lại ngay")); a.addButton(withTitle: T("Để sau"))
        if a.runModal() == .alertFirstButtonReturn {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", "sleep 0.6; open -n \"\(Bundle.main.bundlePath)\""]
            try? p.run()
            controller.stop()
            NSApp.terminate(nil)
        }
    }

    @objc private func modelChanged(_ sender: NSPopUpButton) {
        guard let id = sender.selectedItem?.representedObject as? String else { return }
        cfg.global["remotemodel"] = id
        commit()
    }

    @objc private func checkChanged(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        cfg.global[id] = sender.state == .on ? "1" : "0"
        commit(rebuild: false)
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        guard let id = sender.identifier?.rawValue else { return }
        cfg.global[id] = String(format: "%.2f", sender.doubleValue)
        valueLabels[id]?.stringValue = valueText(id, sender.doubleValue)
        // Kéo liên tục: chỉ ghi file khi thả chuột cho đỡ tốn
        if NSApp.currentEvent?.type == .leftMouseDragged { return }
        commit(rebuild: false)
    }

    @objc private func fieldChanged(_ sender: NSTextField) {
        guard let id = sender.identifier?.rawValue else { return }
        if id == "touchfamily" {
            cfg.global[id] = sender.stringValue
        } else {
            let range = id == "holdtime" ? 0.2...3.0 : 0.15...1.0
            guard let v = Double(sender.stringValue.replacingOccurrences(of: ",", with: ".")) else { commit(); return }
            cfg.global[id] = String(format: "%.2f", min(max(v, range.lowerBound), range.upperBound))
            sender.stringValue = cfg.global[id] ?? sender.stringValue
        }
        commit(rebuild: false)
    }

    @objc private func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Thêm / xóa app

    @objc private func addApp(_ sender: NSButton) {
        let menu = NSMenu()
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != nil
                && $0.bundleIdentifier != Bundle.main.bundleIdentifier && cfg.apps[$0.bundleIdentifier!] == nil
        }.sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        for a in running {
            let mi = NSMenuItem(title: a.localizedName ?? a.bundleIdentifier!, action: #selector(addRunning(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = a.bundleIdentifier
            if let icon = a.icon?.copy() as? NSImage { icon.size = NSSize(width: 16, height: 16); mi.image = icon }
            menu.addItem(mi)
        }
        if !running.isEmpty { menu.addItem(.separator()) }
        let disk = NSMenuItem(title: T("Chọn từ thư mục Applications…"), action: #selector(addFromDisk), keyEquivalent: "")
        disk.target = self
        menu.addItem(disk)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    @objc private func addRunning(_ sender: NSMenuItem) {
        if let bid = sender.representedObject as? String { addProfile(bid) }
    }

    @objc private func addFromDisk() {
        guard let url = chooseApp(), let bid = Bundle(url: url)?.bundleIdentifier else { return }
        addProfile(bid)
    }

    private func addProfile(_ bid: String) {
        if cfg.apps[bid] == nil { cfg.apps[bid] = [:] }
        current = bid
        cfg.save()
        controller.reloadMap()
        reload()
    }

    @objc private func removeApp() {
        guard let bid = current else { return }
        let a = NSAlert()
        a.messageText = TF("Xóa cấu hình riêng của %@?", appName(bid))
        a.addButton(withTitle: T("Xóa")); a.addButton(withTitle: T("Hủy"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        cfg.apps[bid] = nil
        current = nil
        cfg.save()
        controller.reloadMap()
        reload()
    }

    private func chooseApp() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func promptKey() -> String? {
        let a = NSAlert()
        a.messageText = T("Nhập phím tắt")
        a.informativeText = T("Ví dụ: cmd+w, cmd+shift+4, ctrl+right, space. Phím bổ trợ: cmd, ctrl, alt, shift.")
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        a.accessoryView = f
        a.addButton(withTitle: "OK"); a.addButton(withTitle: T("Hủy"))
        a.window.initialFirstResponder = f
        guard a.runModal() == .alertFirstButtonReturn else { return nil }
        let text = f.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { return nil }
        guard Action.parse("key:" + text) != nil else {
            let e = NSAlert()
            e.messageText = TF("Phím không hợp lệ: %@", text)
            e.runModal()
            return nil
        }
        return text
    }

    // MARK: Nút tự học

    @objc private func learnButton() {
        let a = NSAlert()
        a.messageText = T("Bấm một nút trên remote…")
        a.informativeText = T("Nút đầu tiên bạn bấm sẽ được ghi nhận (không chạy hành động).")
        a.addButton(withTitle: T("Hủy"))
        controller.learnHandler = { [weak self] key in
            guard let self = self else { return }
            self.window.endSheet(a.window)
            self.finishLearn(key)
        }
        a.beginSheetModal(for: window) { _ in controller.learnHandler = nil }
    }

    private func finishLearn(_ key: String) {
        if let existing = buttonNames.first(where: { $0.value == key })?.key {
            let e = NSAlert()
            e.messageText = TF("Nút này đã có tên: %@", existing)
            e.informativeText = TF("Mã nút: %@", key)
            e.runModal()
            return
        }
        let a = NSAlert()
        a.messageText = TF("Đặt tên cho nút (mã %@)", key)
        a.informativeText = T("Chữ thường, không dấu, không khoảng trắng. Ví dụ: ring_up")
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        a.accessoryView = f
        a.addButton(withTitle: T("Lưu")); a.addButton(withTitle: T("Hủy"))
        a.window.initialFirstResponder = f
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let name = f.stringValue.lowercased().trimmingCharacters(in: .whitespaces)
        let ok = !name.isEmpty && !name.contains(where: { " +:".contains($0) }) && buttonNames[name] == nil
        guard ok else {
            let e = NSAlert()
            e.messageText = TF("Tên không hợp lệ hoặc đã tồn tại: %@", name)
            e.runModal()
            return
        }
        cfg.custom[name] = key
        commit()
    }

    @objc private func removeCustom(_ sender: NSButton) {
        guard let name = sender.identifier?.rawValue else { return }
        cfg.custom[name] = nil
        for k in [name, name + "+hold", name + "+double"] {
            cfg.global[k] = nil
            for bid in cfg.apps.keys { cfg.apps[bid]?[k] = nil }
        }
        commit()
    }
}
