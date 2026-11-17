// Settings.swift
// Cửa sổ cài đặt: chọn "Áp dụng cho" (mặc định hoặc một app) → tab Nút bấm / Cảm ứng / Nâng cao.
// Mọi thay đổi được lưu ngay vào ~/.siriremote.json.

import Cocoa
import UniformTypeIdentifiers

final class SettingsWindow: NSObject, NSWindowDelegate {

    // MARK: Dữ liệu hiển thị

    private static let baseRows: [(String, String)] = [
        ("touchpad", "Touchpad"), ("menu", "Menu"), ("home", "Home"), ("siri", "Siri"),
        ("playpause", "Play/Pause"), ("volup", "Vol +"), ("voldown", "Vol −"),
    ]
    private static let gen23Rows: [(String, String)] = [
        ("select", "Click ring: giữa"), ("up", "Click ring ↑"), ("down", "Click ring ↓"),
        ("left", "Click ring ←"), ("right", "Click ring →"), ("back", "Back"), ("tv", "TV"),
        ("mute", "Mute"), ("power", "Power"),
    ]
    private static let gestureRows: [(String, String)] = [
        ("swipeleft", "Vuốt trái"), ("swiperight", "Vuốt phải"), ("swipeup", "Vuốt lên"),
        ("swipedown", "Vuốt xuống"), ("twofingertap", "Chạm 2 ngón"),
    ]
    private static let actionGroups: [(String, [(String, String)])] = [
        ("Media", [("media:playpause", "Phát / Dừng"), ("media:next", "Bài kế tiếp"), ("media:previous", "Bài trước"),
                   ("media:fast", "Tua tới"), ("media:rewind", "Tua lui"), ("media:volumeup", "Tăng âm lượng"),
                   ("media:volumedown", "Giảm âm lượng"), ("media:mute", "Tắt tiếng")]),
        ("Phím", [("key:left", "Phím ←"), ("key:right", "Phím →"), ("key:up", "Phím ↑"), ("key:down", "Phím ↓"),
                  ("key:space", "Space"), ("key:return", "Enter"), ("key:escape", "Esc"),
                  ("key:pageup", "Page Up"), ("key:pagedown", "Page Down"),
                  ("key:cmd+[", "Back (cmd+[)"), ("key:cmd+]", "Forward (cmd+])"),
                  ("nav:back", "Back (thử nghiệm: hiệu ứng vuốt)"), ("nav:forward", "Forward (thử nghiệm: hiệu ứng vuốt)")]),
        ("Chuột", [("click", "Click chuột"), ("rightclick", "Click phải"), ("scroll:up", "Cuộn lên"), ("scroll:down", "Cuộn xuống")]),
        ("Hệ thống", [("sleep", "Cho Mac ngủ"), ("displaysleep", "Tắt màn hình"),
                      ("toggletouch", "Đổi chế độ cảm ứng (con trỏ ↔ vuốt)")]),
    ]
    private static let allPresets: [(String, String)] = SettingsWindow.actionGroups.flatMap { $0.1 }

    /// Mẫu cấu hình nhanh: áp dụng cho mặc định hoặc cho app đang chọn.
    private static let templates: [(String, [String: String])] = [
        ("Nghe nhạc", ["touchpad": "media:playpause", "menu": "media:previous", "home": "media:next",
                       "swipeleft": "media:previous", "swiperight": "media:next",
                       "swipeup": "media:volumeup", "swipedown": "media:volumedown"]),
        ("Xem YouTube", ["touchpad": "key:k", "playpause": "key:k", "touchpad+double": "key:shift+n",
                         "swipeleft": "key:j", "swiperight": "key:l", "swipeup": "key:up", "swipedown": "key:down",
                         "home": "key:f", "menu": "key:escape"]),
        ("Lướt TikTok", ["touchpad": "key:space", "swipeup": "key:down", "swipedown": "key:up",
                         "home": "key:m", "menu": "key:escape"]),
        ("Duyệt web", ["menu": "key:cmd+[", "home": "key:cmd+]", "swipeup": "scroll:down", "swipedown": "scroll:up"]),
        ("Thuyết trình", ["touchpad": "key:right", "menu": "key:left", "home": "key:escape",
                          "swipeleft": "key:right", "swiperight": "key:left"]),
    ]

    // MARK: Trạng thái

    private let window: NSWindow
    private var cfg = ConfigFile.load()
    private var current: String?            // nil = cấu hình mặc định; ngược lại = bundle id của app
    private var centered = false

    private let profilePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let templatePopup = NSPopUpButton(frame: .zero, pullsDown: true)
    private let removeButton = NSButton(title: "Xóa app này", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let permButton = NSButton(title: "Cấp quyền…", target: nil, action: nil)
    private let buttonsHost = NSStackView()
    private let touchHost = NSStackView()
    private let advancedHost = NSStackView()

    /// "gen1" hoặc "gen23": theo lựa chọn trong tab Nâng cao, hoặc tự nhận từ product ID khi để "auto".
    private var effectiveModel: String {
        let m = cfg.global["remotemodel"] ?? "auto"
        if m != "auto" { return m }
        return detectedProductID == 0 || detectedProductID == 0x266 ? "gen1" : "gen23"
    }

    private var buttonRows: [(String, String)] {
        var r = SettingsWindow.baseRows
        if effectiveModel == "gen23" { r += SettingsWindow.gen23Rows }
        for name in cfg.custom.keys.sorted() where !r.contains(where: { $0.0 == name }) { r.append((name, "Nút “\(name)”")) }
        return r
    }

    // MARK: Khởi tạo

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 660),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = "SiriRemoteMac – Cài đặt"
        window.isReleasedWhenClosed = false
        window.delegate = self

        // Hàng 1: chọn đối tượng áp dụng + mẫu
        profilePopup.target = self; profilePopup.action = #selector(profileChanged(_:))
        profilePopup.widthAnchor.constraint(equalToConstant: 200).isActive = true
        let addButton = NSButton(title: "＋ Thêm app", target: self, action: #selector(addApp(_:)))
        removeButton.target = self; removeButton.action = #selector(removeApp)
        templatePopup.addItem(withTitle: "Mẫu có sẵn")
        for (i, t) in SettingsWindow.templates.enumerated() {
            let mi = NSMenuItem(title: t.0, action: #selector(applyTemplate(_:)), keyEquivalent: "")
            mi.target = self
            mi.tag = i
            templatePopup.menu?.addItem(mi)
        }
        let row1 = hstack([NSTextField(labelWithString: "Áp dụng cho:"), profilePopup, addButton, removeButton, templatePopup])

        // Hàng 2: trạng thái
        permButton.target = self; permButton.action = #selector(openAccessibility)
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        let row2 = hstack([statusLabel, permButton])

        // Tab
        let tabs = NSTabView()
        tabs.addTabViewItem(makeTab("Nút bấm", host: buttonsHost, scrolls: true))
        tabs.addTabViewItem(makeTab("Cảm ứng", host: touchHost, scrolls: false))
        tabs.addTabViewItem(makeTab("Nâng cao", host: advancedHost, scrolls: true))
        tabs.translatesAutoresizingMaskIntoConstraints = false
        tabs.widthAnchor.constraint(equalToConstant: 600).isActive = true
        tabs.heightAnchor.constraint(equalToConstant: 500).isActive = true

        let footer = note("Mọi thay đổi được lưu ngay. “↩ Mặc định” nghĩa là dùng cấu hình chung. Cấu hình áp dụng theo app đang ở trên cùng.")

        let root = NSStackView(views: [row1, row2, tabs, footer])
        root.orientation = .vertical; root.alignment = .leading; root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(root)
        window.contentView = container
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20),
        ])
    }

    func show() {
        cfg = ConfigFile.load()
        if let c = current, cfg.apps[c] == nil { current = nil }
        reload()
        if !centered { window.center(); centered = true }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: Hàm dựng giao diện dùng chung

    private func hstack(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal; s.spacing = spacing; s.alignment = .centerY
        return s
    }

    private func vstack(_ views: [NSView], spacing: CGFloat = 4) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .vertical; s.spacing = spacing; s.alignment = .leading
        return s
    }

    private func note(_ text: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.textColor = .secondaryLabelColor; l.font = .systemFont(ofSize: 11); l.preferredMaxLayoutWidth = 540
        return l
    }

    private func heading(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .boldSystemFont(ofSize: 12)
        return l
    }

    private func makeTab(_ title: String, host: NSStackView, scrolls: Bool) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: title)
        item.label = title
        host.orientation = .vertical; host.alignment = .leading; host.spacing = 14
        host.translatesAutoresizingMaskIntoConstraints = false
        let container: NSView
        let anchor: NSView
        if scrolls {
            let sv = NSScrollView()
            sv.hasVerticalScroller = true
            sv.drawsBackground = false
            sv.documentView = host
            container = sv
            anchor = sv.contentView
        } else {
            container = NSView()
            container.addSubview(host)
            anchor = container
        }
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: anchor.topAnchor, constant: 14),
            host.leadingAnchor.constraint(equalTo: anchor.leadingAnchor, constant: 14),
        ])
        item.view = container
        return item
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
        s.widthAnchor.constraint(equalToConstant: 220).isActive = true
        return s
    }

    private func appName(_ bid: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bid
    }

    private func label(for spec: String?) -> String {
        guard let spec = spec, spec != "none", !spec.isEmpty else { return "Không làm gì" }
        if let p = SettingsWindow.allPresets.first(where: { $0.0 == spec }) { return p.1 }
        if spec.hasPrefix("app:") { return "Mở " + String(spec.dropFirst(4)) }
        if spec.hasPrefix("key:") { return "Phím " + String(spec.dropFirst(4)) }
        return spec
    }

    // MARK: Dựng nội dung

    private func reload() {
        profilePopup.removeAllItems()
        let def = NSMenuItem(title: "Mặc định (mọi app)", action: nil, keyEquivalent: "")
        def.representedObject = ""
        profilePopup.menu?.addItem(def)
        for bid in cfg.apps.keys.sorted(by: { appName($0).localizedCaseInsensitiveCompare(appName($1)) == .orderedAscending }) {
            let mi = NSMenuItem(title: appName(bid), action: nil, keyEquivalent: "")
            mi.representedObject = bid
            profilePopup.menu?.addItem(mi)
        }
        if let i = profilePopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == (current ?? "") }) {
            profilePopup.selectItem(at: i)
        }
        removeButton.isEnabled = current != nil
        rebuild()
    }

    private func rebuild() {
        for h in [buttonsHost, touchHost, advancedHost] {
            for v in h.arrangedSubviews { h.removeArrangedSubview(v); v.removeFromSuperview() }
        }
        updateStatus()
        buildButtonsTab()
        buildTouchTab()
        buildAdvancedTab()
    }

    private func updateStatus() {
        let trusted = AXIsProcessTrusted()
        let remote = controller.isConnected ? "Remote: đã kết nối" : "Remote: chưa kết nối"
        statusLabel.stringValue = (trusted ? "" : "⚠ Thiếu quyền Accessibility · ") + remote + " · Cảm ứng: " + touchMode.title
        permButton.isHidden = trusted
    }

    private func makeGrid(title: String, columns: [(String, String)], rows: [(String, String)]) -> NSGridView {
        var head: [NSView] = [heading(title)]
        for c in columns { head.append(heading(c.0)) }
        var data: [[NSView]] = [head]
        for (name, text) in rows {
            var line: [NSView] = [NSTextField(labelWithString: text)]
            for c in columns { line.append(makePopup(name + c.1)) }
            data.append(line)
        }
        let g = NSGridView(views: data)
        g.columnSpacing = 12; g.rowSpacing = 8
        g.column(at: 0).width = 110
        return g
    }

    private func buildButtonsTab() {
        buttonsHost.addArrangedSubview(makeGrid(title: "Nút",
                                                columns: [("Bấm", ""), ("Giữ", "+hold"), ("Nhấn đúp", "+double")],
                                                rows: buttonRows))
    }

    private func buildTouchTab() {
        if current == nil {
            let modes: [(String, String, String)] = [
                ("cursor", "Con trỏ", "Một ngón di chuyển con trỏ, hai ngón cuộn, vuốt nhanh chạy cử chỉ bên dưới."),
                ("swipe", "Vuốt / chạm", "Không di chuyển con trỏ; chỉ nhận cử chỉ vuốt và chạm bên dưới."),
                ("off", "Tắt", "Bỏ qua touchpad."),
            ]
            let cur = cfg.global["touchmode"] ?? "cursor"
            touchHost.addArrangedSubview(heading("Chế độ cảm ứng (giữ nút Siri để đổi nhanh)"))
            for (id, title, desc) in modes {
                let b = NSButton(radioButtonWithTitle: title, target: self, action: #selector(touchModeChanged(_:)))
                b.identifier = NSUserInterfaceItemIdentifier(id)
                b.state = id == cur ? .on : .off
                let indent = NSView()
                indent.widthAnchor.constraint(equalToConstant: 18).isActive = true
                touchHost.addArrangedSubview(vstack([b, hstack([indent, note(desc)])], spacing: 2))
            }
            touchHost.addArrangedSubview(hstack([NSTextField(labelWithString: "Tốc độ con trỏ:"), slider("touchspeed", 0.3, 4, 1.5)]))
            touchHost.addArrangedSubview(hstack([NSTextField(labelWithString: "Tốc độ cuộn:"), slider("scrollspeed", 0.2, 3, 1.0)]))
            touchHost.addArrangedSubview(vstack([checkbox("naturalscroll", "Cuộn tự nhiên (đảo chiều)", "1"),
                                                 checkbox("tapclick", "Chạm nhẹ để click (chạm rồi đặt ngón xuống kéo = kéo thả)", "0"),
                                                 checkbox("scrollmomentum", "Cuộn có quán tính (tiếp tục cuộn sau khi nhấc tay)", "1"),
                                                 checkbox("clicksteady", "Giữ yên con trỏ khi nhấn touchpad để click", "1")]))
        }
        touchHost.addArrangedSubview(makeGrid(title: "Cử chỉ", columns: [("Hành động", "")], rows: SettingsWindow.gestureRows))
    }

    private func buildAdvancedTab() {
        guard current == nil else {
            advancedHost.addArrangedSubview(note("Cài đặt nâng cao áp dụng chung cho mọi app. Chọn “Mặc định (mọi app)” ở ô Áp dụng cho để chỉnh."))
            return
        }
        // Đời remote
        let models: [(String, String)] = [("auto", "Tự nhận (khuyên dùng)"), ("gen1", "Đời 1 (A1513 / A1844)"),
                                          ("gen23", "Đời 2 / 3 (A2540 / A2854, USB-C)")]
        let detected = detectedProductID == 0 ? "chưa thấy remote" : "product ID 0x" + String(detectedProductID, radix: 16)
        advancedHost.addArrangedSubview(vstack([
            heading("Đời remote"),
            hstack([idPopup(models, selected: cfg.global["remotemodel"] ?? "auto", action: #selector(modelChanged(_:))),
                    NSTextField(labelWithString: "(đang nhận: \(detected))")]),
            note("Đời 2/3 hiện thêm các nút click ring, Back, TV, Mute, Power ở tab Nút bấm (mã nút theo chuẩn HID, chưa kiểm chứng trên máy thật)."),
        ]))

        // Thời gian
        advancedHost.addArrangedSubview(vstack([
            heading("Thời gian"),
            hstack([NSTextField(labelWithString: "Giữ nút (giây):"), textField("holdtime", "0.8", width: 56),
                    NSTextField(labelWithString: "   Nhấn đúp (giây):"), textField("doubletime", "0.3", width: 56)]),
        ]))

        // Mã cảm ứng
        advancedHost.addArrangedSubview(vstack([
            heading("Mã cảm ứng (family)"),
            textField("touchfamily", "160,145", width: 140),
            note("Đời 1 = 160, đời 3 = 145 (luôn được thử). Với đời khác: bật “Ghi log nút bấm” (menu → Nâng cao), nối lại remote, xem dòng `family` trong log và thêm vào đây, cách nhau bằng dấu phẩy."),
        ]))

        // Nút tự học
        var learnViews: [NSView] = [
            heading("Nút tự học"),
            NSButton(title: "Học nút mới…", target: self, action: #selector(learnButton)),
            note("Dùng khi một nút chưa có trong danh sách: bấm “Học nút mới…”, bấm nút đó trên remote rồi đặt tên. Nút sẽ xuất hiện ở tab Nút bấm."),
        ]
        for name in cfg.custom.keys.sorted() {
            let del = NSButton(title: "Xóa", target: self, action: #selector(removeCustom(_:)))
            del.identifier = NSUserInterfaceItemIdentifier(name)
            learnViews.append(hstack([NSTextField(labelWithString: "\(name)  →  \(cfg.custom[name] ?? "")"), del], spacing: 10))
        }
        advancedHost.addArrangedSubview(vstack(learnViews))

        // Back/Forward thử nghiệm
        advancedHost.addArrangedSubview(checkbox("navinvert", "Đảo chiều hiệu ứng Back/Forward (hành động thử nghiệm nav:*)", "0"))
    }

    // MARK: Ô chọn hành động

    private func makePopup(_ key: String) -> NSPopUpButton {
        let p = NSPopUpButton(frame: .zero, pullsDown: false)
        p.menu?.autoenablesItems = false
        p.identifier = NSUserInterfaceItemIdentifier(key)
        p.target = self; p.action = #selector(actionChanged(_:))
        p.widthAnchor.constraint(equalToConstant: 170).isActive = true

        func add(_ title: String, _ rep: String?) {      // rep = nil: tiêu đề nhóm, không chọn được
            let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            mi.representedObject = rep
            mi.isEnabled = rep != nil
            p.menu?.addItem(mi)
        }
        if current != nil { add("↩ Mặc định: " + label(for: cfg.global[key]), "@inherit") }
        add("Không làm gì", "none")
        for (group, items) in SettingsWindow.actionGroups {
            p.menu?.addItem(.separator())
            add("— " + group + " —", nil)
            for (spec, title) in items { add(title, spec) }
        }
        p.menu?.addItem(.separator())
        add("Mở ứng dụng…", "@app")
        add("Phím tắt…", "@key")

        let cur: String? = current == nil ? (cfg.global[key] ?? "none") : cfg.apps[current!]?[key]
        if let cur = cur {
            if let i = p.itemArray.firstIndex(where: { ($0.representedObject as? String) == cur }) {
                p.selectItem(at: i)
            } else {
                let mi = NSMenuItem(title: label(for: cur), action: nil, keyEquivalent: "")
                mi.representedObject = cur
                p.menu?.insertItem(mi, at: current != nil ? 1 : 0)
                p.select(mi)
            }
        } else {
            p.selectItem(at: 0)     // “↩ Mặc định”
        }
        return p
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
        commit()
    }

    @objc private func applyTemplate(_ sender: NSMenuItem) {
        guard SettingsWindow.templates.indices.contains(sender.tag) else { return }
        let (name, specs) = SettingsWindow.templates[sender.tag]
        let target = current.map { appName($0) } ?? "mặc định (mọi app)"
        let a = NSAlert()
        a.messageText = "Áp dụng mẫu “\(name)” cho \(target)?"
        a.informativeText = "Các nút và cử chỉ có trong mẫu sẽ được thay; những nút khác giữ nguyên."
        a.addButton(withTitle: "Áp dụng"); a.addButton(withTitle: "Hủy")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        for (k, v) in specs {
            if let bid = current { cfg.apps[bid, default: [:]][k] = v } else { cfg.global[k] = v }
        }
        commit()
    }

    @objc private func touchModeChanged(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        cfg.global["touchmode"] = id
        commit()
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
        }
        commit()
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
        let disk = NSMenuItem(title: "Chọn từ thư mục Applications…", action: #selector(addFromDisk), keyEquivalent: "")
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
        a.messageText = "Xóa cấu hình riêng của \(appName(bid))?"
        a.addButton(withTitle: "Xóa"); a.addButton(withTitle: "Hủy")
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
        a.messageText = "Nhập phím tắt"
        a.informativeText = "Ví dụ: cmd+w, cmd+shift+4, ctrl+right, space. Phím bổ trợ: cmd, ctrl, alt, shift."
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        a.accessoryView = f
        a.addButton(withTitle: "OK"); a.addButton(withTitle: "Hủy")
        a.window.initialFirstResponder = f
        guard a.runModal() == .alertFirstButtonReturn else { return nil }
        let text = f.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { return nil }
        guard Action.parse("key:" + text) != nil else {
            let e = NSAlert()
            e.messageText = "Phím không hợp lệ: \(text)"
            e.runModal()
            return nil
        }
        return text
    }

    // MARK: Nút tự học

    @objc private func learnButton() {
        let a = NSAlert()
        a.messageText = "Bấm một nút trên remote…"
        a.informativeText = "Nút đầu tiên bạn bấm sẽ được ghi nhận (không chạy hành động)."
        a.addButton(withTitle: "Hủy")
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
            e.messageText = "Nút này đã có tên: \(existing)"
            e.informativeText = "Mã nút: \(key)"
            e.runModal()
            return
        }
        let a = NSAlert()
        a.messageText = "Đặt tên cho nút (mã \(key))"
        a.informativeText = "Chữ thường, không dấu, không khoảng trắng. Ví dụ: ring_up"
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        a.accessoryView = f
        a.addButton(withTitle: "Lưu"); a.addButton(withTitle: "Hủy")
        a.window.initialFirstResponder = f
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let name = f.stringValue.lowercased().trimmingCharacters(in: .whitespaces)
        let ok = !name.isEmpty && !name.contains(where: { " +:".contains($0) }) && buttonNames[name] == nil
        guard ok else {
            let e = NSAlert()
            e.messageText = "Tên không hợp lệ hoặc đã tồn tại: \(name)"
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
