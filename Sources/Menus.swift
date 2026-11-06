import AppKit
import ApplicationServices

// where the frontmost app's menus end, so the island can stay out of their way
final class MenuWatch: ObservableObject {
    @Published private(set) var end: CGFloat = 0

    // global x of the notch center, menus past it don't count
    var limit: CGFloat = .greatestFiniteMagnitude

    private let queue = DispatchQueue(label: "menus", qos: .utility)
    private var token: NSObjectProtocol?

    init() {
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.measure(app?.processIdentifier)
        }
        measure(NSWorkspace.shared.frontmostApplication?.processIdentifier)
    }

    deinit {
        if let token { NSWorkspace.shared.notificationCenter.removeObserver(token) }
    }

    // the system dialog only once, after that it's up to the user in System Settings
    static func askOnce() {
        let key = "askedAccessibility"
        if AXIsProcessTrusted() || UserDefaults.standard.bool(forKey: key) { return }
        UserDefaults.standard.set(true, forKey: key)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func refresh() { measure(NSWorkspace.shared.frontmostApplication?.processIdentifier) }

    private func measure(_ pid: pid_t?) {
        guard let pid, pid != getpid(), AXIsProcessTrusted() else {
            if end != 0 { end = 0 }
            return
        }
        let limit = self.limit
        // an app that just launched builds its menu bar a moment after it activates
        for delay in [0.0, 1.0] {
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                let value = Self.menuEnd(pid, limit: limit)
                DispatchQueue.main.async {
                    guard let self, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                    if self.end != value { self.end = value }
                }
            }
        }
    }

    private static func menuEnd(_ pid: pid_t, limit: CGFloat) -> CGFloat {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        guard let bar = attribute(app, kAXMenuBarAttribute),
              let items = attribute(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] else { return 0 }

        var end: CGFloat = 0
        for item in items {
            guard let p = attribute(item, kAXPositionAttribute), let s = attribute(item, kAXSizeAttribute) else { continue }
            var origin = CGPoint.zero
            var size = CGSize.zero
            AXValueGetValue(p as! AXValue, .cgPoint, &origin)
            AXValueGetValue(s as! AXValue, .cgSize, &size)
            if size.width > 0 && origin.x < limit { end = max(end, origin.x + size.width) }
        }
        return end
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
