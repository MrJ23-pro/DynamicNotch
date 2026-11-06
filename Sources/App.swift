import AppKit
import Combine
import SwiftUI

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class IslandHostingView<V: View>: NSHostingView<V> {
    var contextMenu: (() -> NSMenu)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func rightMouseDown(with event: NSEvent) {
        if let m = contextMenu?() { NSMenu.popUpContextMenu(m, with: event, for: self) }
        else { super.rightMouseDown(with: event) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let hub = Hub()
    var panel: IslandPanel!
    var monitors: [Any] = []
    var exitTimer: Timer?
    var collapseWork: DispatchWorkItem?
    var hideWork: DispatchWorkItem?
    var bag = Set<AnyCancellable>()
    let windowSize = CGSize(width: 640, height: 360)

    func applicationDidFinishLaunching(_ n: Notification) {
        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        let host = IslandHostingView(rootView: IslandView(hub: hub))
        host.contextMenu = { [weak self] in self?.buildMenu() ?? NSMenu() }
        panel.contentView = host

        place()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.place() }

        // objectWillChange fires before the value lands, hop once so we read the new state
        hub.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.updateVisibility() }
            .store(in: &bag)
        updateVisibility()

        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in self?.trackMouse() }) {
            monitors.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in self?.trackMouse(); return e }) {
            monitors.append(l)
        }
    }

    // nothing to show: take the window off screen so the window server has nothing to composite
    private func updateVisibility() {
        if !hub.isIdle {
            hideWork?.cancel()
            hideWork = nil
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else if panel.isVisible && hideWork == nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.hideWork = nil
                if self.hub.isIdle { self.panel.orderOut(nil) }
            }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }
    }

    // TODO: follow the screen the mouse is on instead of always picking the notch one
    private var screen: NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func place() {
        let s = screen
        if s.safeAreaInsets.top > 0, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
            hub.notch = CGSize(width: s.frame.width - l.width - r.width, height: s.safeAreaInsets.top)
            hub.hasNotch = true
        } else {
            let menuBar = s.frame.maxY - s.visibleFrame.maxY
            hub.notch = CGSize(width: 160, height: menuBar > 0 ? menuBar : 24)
            hub.hasNotch = false
        }
        panel.setFrame(NSRect(x: s.frame.midX - windowSize.width / 2, y: s.frame.maxY - windowSize.height,
                              width: windowSize.width, height: windowSize.height), display: true)
    }

    private func trackMouse() {
        // without a notch there's nothing to hover while idle
        guard hub.hasNotch || !hub.isIdle else { return }
        let m = NSEvent.mouseLocation
        let s = screen
        if !hub.expanded && m.y < s.frame.maxY - hub.notch.height - 8 {
            if !panel.ignoresMouseEvents { panel.ignoresMouseEvents = true }
            return
        }

        let size = hub.size
        let margin: CGFloat = hub.expanded ? 12 : 4
        let rect = NSRect(x: s.frame.midX - size.width / 2 - margin, y: s.frame.maxY - size.height - margin,
                          width: size.width + 2 * margin, height: size.height + margin + 1)
        let inside = rect.contains(m)

        // only grab clicks over the island so the menu bar keeps working
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }

        if inside {
            collapseWork?.cancel()
            collapseWork = nil
            if !hub.expanded {
                hub.expanded = true
                if hub.spotify.hasTrack { hub.spotify.resync() }
                startExitTimer()
            }
        } else if hub.expanded && collapseWork == nil {
            let work = DispatchWorkItem { [weak self] in
                self?.hub.expanded = false
                self?.collapseWork = nil
                self?.exitTimer?.invalidate()
                self?.exitTimer = nil
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }
    }

    // mouseMoved isn't enough when the cursor jumps to another screen
    private func startExitTimer() {
        exitTimer?.invalidate()
        exitTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in self?.trackMouse() }
        exitTimer?.tolerance = 0.1
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let themes = NSMenu()
        for t in Theme.allCases {
            let item = NSMenuItem(title: t.rawValue, action: #selector(pickTheme(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = t.rawValue
            item.state = (t == hub.prefs.theme) ? .on : .off
            themes.addItem(item)
        }
        let themeItem = NSMenuItem(title: "Thème", action: nil, keyEquivalent: "")
        themeItem.submenu = themes
        menu.addItem(themeItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quitter DynamicNotch", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    @objc private func pickTheme(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let t = Theme(rawValue: raw) { hub.prefs.set(t) }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

@main
enum DynamicNotchApp {
    static let delegate = AppDelegate()
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}
