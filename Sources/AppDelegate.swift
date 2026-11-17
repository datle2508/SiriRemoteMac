// AppDelegate.swift
// Biểu tượng + menu trên thanh menu, quyền truy cập, khởi động cùng macOS.

import Cocoa
import IOKit.hid
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private let statusLine = NSMenuItem()
    private let loginItem = NSMenuItem()
    private let seizeItem = NSMenuItem()
    private let debugItem = NSMenuItem()
    private var modeItems: [TouchMode: NSMenuItem] = [:]
    private var settingsWindow: SettingsWindow?

    private func entry(_ title: String, _ sel: Selector, key: String = "") -> NSMenuItem {
        let m = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        m.target = self
        return m
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let host = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu()
        items.forEach { menu.addItem($0) }
        host.submenu = menu
        return host
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            touchEngine.invalidateScreens()
        }
        item.button?.image = AppDelegate.makeMenuIcon()
        item.button?.imagePosition = .imageOnly

        loginItem.title = "Khởi động cùng macOS"; loginItem.action = #selector(toggleLogin); loginItem.target = self
        seizeItem.title = "Chiếm quyền remote (khi gán lại Vol/Play)"; seizeItem.action = #selector(toggleSeize); seizeItem.target = self
        debugItem.title = "Ghi log nút bấm"; debugItem.action = #selector(toggleDebug); debugItem.target = self

        var modeMenuItems: [NSMenuItem] = []
        for mode in [TouchMode.cursor, .swipe, .off] {
            let mi = entry(mode.title, #selector(setTouchMode(_:)))
            mi.representedObject = mode.rawValue
            modeItems[mode] = mi
            modeMenuItems.append(mi)
        }

        let menu = NSMenu()
        for m in [statusLine, .separator(),
                  entry("Cài đặt…", #selector(openSettings), key: ","),
                  submenu("Chế độ cảm ứng", modeMenuItems), .separator(),
                  loginItem,
                  submenu("Nâng cao", [seizeItem, debugItem, .separator(),
                                       entry("Mở file cấu hình", #selector(openConfig)),
                                       entry("Nạp lại cấu hình", #selector(reload)),
                                       entry("Mở file log", #selector(openLog))]),
                  .separator(),
                  entry("Thoát", #selector(quit), key: "q")] {
            menu.addItem(m)
        }
        item.menu = menu

        // Menu chính tối thiểu để Cmd+C / Cmd+V hoạt động trong ô nhập của cửa sổ cài đặt.
        let mainMenu = NSMenu(), editHost = NSMenuItem(), edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editHost.submenu = edit
        mainMenu.addItem(editHost)
        NSApp.mainMenu = mainMenu

        if !AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) {
            log("Chưa có quyền Accessibility")
        }
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)

        migrateConfig()
        controller.start()
        touchEngine.start(force: true)
        refresh()
    }

    /// Biểu tượng thanh menu (template, đơn sắc), cùng bố cục với icon app:
    /// touchpad phẳng tràn viền ở trên; bên dưới cột trái 3 nút tròn, cột phải 1 nút tròn + 1 nút dài.
    private static func makeMenuIcon() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let body = NSBezierPath(roundedRect: NSRect(x: 4.5, y: 0.5, width: 9, height: 17), xRadius: 2.4, yRadius: 2.4)
            body.lineWidth = 1.2
            body.stroke()
            NSGraphicsContext.saveGraphicsState()
            body.addClip()
            NSRect(x: 4.5, y: 11.4, width: 9, height: 6.6).fill()        // touchpad phẳng, tràn viền
            NSGraphicsContext.restoreGraphicsState()
            func dot(_ x: CGFloat, _ y: CGFloat) {
                NSBezierPath(ovalIn: NSRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6)).fill()
            }
            for y in [9.3, 6.3, 3.3] as [CGFloat] { dot(6.7, y) }          // cột trái: 3 nút tròn
            dot(11.3, 9.3)                                                  // cột phải: nút tròn trên cùng
            NSBezierPath(roundedRect: NSRect(x: 10.5, y: 2.5, width: 1.6, height: 4.6),
                         xRadius: 0.8, yRadius: 0.8).fill()                  // cột phải: nút dài
            return true
        }
        img.isTemplate = true
        return img
    }

    /// Hiện chữ ngắn cạnh biểu tượng thanh menu (báo đã đổi chế độ).
    func flash(_ text: String) {
        item.button?.imagePosition = .imageLeft
        item.button?.title = " " + text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.item.button?.title = ""
            self?.item.button?.imagePosition = .imageOnly
        }
    }

    func refresh() {
        settingsWindow?.updateStatus()
        let trusted = AXIsProcessTrusted()
        item.button?.appearsDisabled = !controller.isConnected
        statusLine.title = !trusted ? "⚠ Thiếu quyền Accessibility (nút sẽ không có tác dụng)"
            : controller.isConnected ? "Remote: đã kết nối" : "Remote: chưa thấy (ghép qua Bluetooth)"
        seizeItem.state = controller.seize ? .on : .off
        debugItem.state = debugLog ? .on : .off
        for (mode, mi) in modeItems { mi.state = mode == touchMode ? .on : .off }
        let inApp = Bundle.main.bundlePath.hasSuffix(".app")
        loginItem.isEnabled = inApp      // chỉ bật được khi chạy từ SiriRemoteMac.app
        loginItem.state = (inApp && SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    @objc private func setTouchMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        var c = ConfigFile.load()
        c.global["touchmode"] = raw
        c.save()
        controller.reloadMap()
        refresh()
    }
    @objc private func toggleSeize() { controller.seize.toggle(); controller.start(); refresh() }
    @objc private func toggleDebug() { debugLog.toggle(); refresh() }
    @objc private func toggleLogin() {
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled { try svc.unregister() } else { try svc.register() }
        } catch {
            log("Không đổi được khởi động cùng macOS: \(error.localizedDescription)")
            let a = NSAlert()
            a.messageText = "Không bật được khởi động cùng macOS"
            a.informativeText = "Hãy chép SiriRemoteMac.app vào thư mục Applications rồi mở từ đó, hoặc thêm thủ công trong System Settings → General → Login Items.\n\n\(error.localizedDescription)"
            a.runModal()
        }
        refresh()
    }
    @objc private func openSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindow() }
        settingsWindow?.show()
    }
    @objc private func quit() { controller.stop(); NSApp.terminate(nil) }
    @objc private func reload() { controller.reloadMap() }
    @objc private func openConfig() { NSWorkspace.shared.open(URL(fileURLWithPath: configPath)) }
    @objc private func openLog() { NSWorkspace.shared.open(URL(fileURLWithPath: logPath)) }
}

let appDelegate = AppDelegate()
