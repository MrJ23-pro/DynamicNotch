import AppKit
import Combine
import ImageIO
import SwiftUI

// MARK: - Spotify

final class Spotify: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var playing = false
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var duration: Double = 0
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accent: Color = .green
    @Published private(set) var deep: Color = .black
    @Published private(set) var basePosition: Double = 0
    @Published private(set) var baseDate = Date()

    private var trackID = ""
    private let queue = DispatchQueue(label: "dynamicnotch.spotify", qos: .userInitiated)
    private var compiled: [String: NSAppleScript] = [:]

    var hasTrack: Bool { running && !title.isEmpty }

    init() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil, queue: .main
        ) { [weak self] n in self?.handle(n.userInfo ?? [:]) }

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard Self.isSpotify(n) else { return }
            self?.running = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.resync() }
        }
        ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard Self.isSpotify(n) else { return }
            self?.clear()
        }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.resync()
        }

        if isSpotifyRunning { running = true; resync() }
    }

    private static func isSpotify(_ n: Notification) -> Bool {
        (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == "com.spotify.client"
    }

    // checked before every script: `tell application "Spotify"` would relaunch it
    private var isSpotifyRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.spotify.client" }
    }

    func position(at date: Date) -> Double {
        guard playing else { return basePosition }
        return min(duration, basePosition + date.timeIntervalSince(baseDate))
    }

    private func handle(_ info: [AnyHashable: Any]) {
        running = true
        let state = info["Player State"] as? String ?? ""
        if state == "Stopped" { setIfChanged(\.playing, false); setIfChanged(\.title, ""); return }
        guard let name = info["Name"] as? String else { resync(); return }

        apply(playing: state == "Playing",
              title: name,
              artist: info["Artist"] as? String ?? "",
              durationMs: (info["Duration"] as? NSNumber)?.doubleValue ?? 0,
              position: (info["Playback Position"] as? NSNumber)?.doubleValue ?? position(at: Date()),
              trackID: info["Track ID"] as? String ?? name)
    }

    func resync() {
        guard isSpotifyRunning else { if running { clear() }; return }
        running = true
        let script = """
        tell application "Spotify"
            if player state is stopped then return "stopped"
            set t to current track
            return (player state as string) & "||" & (name of t) & "||" & (artist of t) & "||" & ((duration of t) as string) & "||" & ((player position) as string) & "||" & (id of t)
        end tell
        """
        run(script) { [weak self] out in
            guard let self, let out else { return }
            if out == "stopped" { self.setIfChanged(\.playing, false); self.setIfChanged(\.title, ""); return }
            let p = out.components(separatedBy: "||")
            guard p.count == 6 else { return }
            self.apply(playing: p[0] == "playing", title: p[1], artist: p[2],
                       durationMs: Self.number(p[3]), position: Self.number(p[4]), trackID: p[5])
        }
    }

    private func apply(playing: Bool, title: String, artist: String, durationMs: Double, position: Double, trackID: String) {
        setIfChanged(\.playing, playing)
        setIfChanged(\.title, title)
        setIfChanged(\.artist, artist)
        setIfChanged(\.duration, durationMs / 1000)
        if abs(self.position(at: Date()) - position) > 1.5 || !playing {
            basePosition = position
            baseDate = Date()
        }
        if trackID != self.trackID {
            self.trackID = trackID
            loadArtwork()
        }
    }

    private func clear() {
        running = false; playing = false; title = ""; artist = ""; artwork = nil; trackID = ""
    }

    private func loadArtwork() {
        let id = trackID
        run("tell application \"Spotify\" to artwork url of current track") { [weak self] s in
            guard let s, let url = URL(string: s) else { return }
            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data, let thumb = Self.thumbnail(data, maxPixels: 160) else { return }
                let colors = Self.colors(of: thumb)
                let img = NSImage(cgImage: thumb, size: NSSize(width: thumb.width, height: thumb.height))
                DispatchQueue.main.async {
                    guard let self, self.trackID == id else { return }
                    self.artwork = img
                    if let colors { self.accent = Color(nsColor: colors.vivid); self.deep = Color(nsColor: colors.deep) }
                }
            }.resume()
        }
    }

    private static func thumbnail(_ data: Data, maxPixels: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    private static func colors(of cg: CGImage) -> (vivid: NSColor, deep: NSColor)? {
        var px = [UInt8](repeating: 0, count: 4)
        let ok: Bool = px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                      bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard ok else { return nil }
        let c = NSColor(deviceRed: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (NSColor(deviceHue: h, saturation: min(1, s * 1.3), brightness: max(b, 0.8), alpha: 1),
                NSColor(deviceHue: h, saturation: min(1, s * 1.2), brightness: 0.32, alpha: 1))
    }

    func playPause() {
        let pos = position(at: Date())
        playing.toggle(); basePosition = pos; baseDate = Date()
        command("playpause")
    }
    func next()     { command("next track") }
    func previous() { command("previous track") }
    func seek(to seconds: Double) {
        basePosition = seconds; baseDate = Date()
        command("set player position to \(Int(seconds))", cache: false)
    }

    private func command(_ c: String, cache: Bool = true) {
        guard isSpotifyRunning else { return }
        run("tell application \"Spotify\" to \(c)", cache: cache) { _ in }
    }

    private func run(_ source: String, cache: Bool = true, completion: @escaping (String?) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let script: NSAppleScript?
            if let s = self.compiled[source] { script = s }
            else {
                script = NSAppleScript(source: source)
                script?.compileAndReturnError(nil)
                if cache { self.compiled[source] = script }
            }
            var err: NSDictionary?
            let out = script?.executeAndReturnError(&err).stringValue
            if let err { NSLog("DynamicNotch AppleScript: \(err)") }
            DispatchQueue.main.async { completion(err == nil ? out : nil) }
        }
    }

    // french locale returns "12,5"
    private static func number(_ s: String) -> Double {
        Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private func setIfChanged<T: Equatable>(_ kp: ReferenceWritableKeyPath<Spotify, T>, _ v: T) {
        if self[keyPath: kp] != v { self[keyPath: kp] = v }
    }
}

// MARK: - Themes

enum Theme: String, CaseIterable {
    case classique = "Classique"
    case pochette  = "Pochette"
    case spotify   = "Spotify"
    case neon      = "Néon"
    case mono      = "Mono"

    static let spotifyGreen = Color(red: 0.11, green: 0.73, blue: 0.33)

    func accent(_ s: Spotify) -> Color {
        switch self {
        case .spotify: return Self.spotifyGreen
        case .mono:    return .white
        default:       return s.accent
        }
    }

    func fill(_ s: Spotify, expanded: Bool) -> AnyShapeStyle {
        // compact island stays black so it blends with the notch
        guard expanded else { return AnyShapeStyle(Color.black) }
        switch self {
        case .pochette:
            return AnyShapeStyle(LinearGradient(stops: [.init(color: .black, location: 0),
                                                        .init(color: .black, location: 0.22),
                                                        .init(color: s.deep, location: 1)],
                                                startPoint: .top, endPoint: .bottom))
        case .spotify:
            return AnyShapeStyle(LinearGradient(stops: [.init(color: .black, location: 0),
                                                        .init(color: .black, location: 0.4),
                                                        .init(color: Color(red: 0.03, green: 0.16, blue: 0.08), location: 1)],
                                                startPoint: .top, endPoint: .bottom))
        default:
            return AnyShapeStyle(Color.black)
        }
    }

    var glows: Bool { self == .neon }
    var secondaryText: Double { self == .mono ? 0.5 : 0.62 }

    var next: Theme {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

final class Prefs: ObservableObject {
    @Published var theme: Theme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme") }
    }
    @Published var flash: String?

    init() {
        theme = Theme(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .classique
    }

    func set(_ t: Theme) {
        withAnimation(.easeInOut(duration: 0.3)) { theme = t }
        flash = t.rawValue
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in
            if self?.flash == t.rawValue { self?.flash = nil }
        }
    }
    func cycle() { set(theme.next) }
}

// MARK: - Island

final class Island: ObservableObject {
    @Published var expanded = false
    var notch = CGSize(width: 185, height: 32)
    let ear: CGFloat = 8

    func size(hasTrack: Bool) -> CGSize {
        if expanded && hasTrack { return CGSize(width: max(notch.width + 200, 400), height: notch.height + 140) }
        if hasTrack { return CGSize(width: notch.width + 2 * (notch.height + 8), height: notch.height) }
        return notch
    }
}

struct NotchShape: Shape {
    var ear: CGFloat
    var bottomRadius: CGFloat
    var closed = true
    var animatableData: CGFloat { get { bottomRadius } set { bottomRadius = newValue } }

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + ear, y: r.minY + ear), control: CGPoint(x: r.minX + ear, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + ear, y: r.maxY - bottomRadius))
        p.addQuadCurve(to: CGPoint(x: r.minX + ear + bottomRadius, y: r.maxY), control: CGPoint(x: r.minX + ear, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - ear - bottomRadius, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - ear, y: r.maxY - bottomRadius), control: CGPoint(x: r.maxX - ear, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - ear, y: r.minY + ear))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - ear, y: r.minY))
        if closed { p.closeSubpath() }
        return p
    }
}

// MARK: - Views

struct Equalizer: View {
    var playing: Bool
    var color: Color
    var height: CGFloat = 14

    var body: some View {
        EqualizerLayers(playing: playing, color: NSColor(color), height: height)
            .frame(width: 18, height: height)
    }
}

private struct EqualizerLayers: NSViewRepresentable {
    var playing: Bool
    var color: NSColor
    var height: CGFloat

    func makeNSView(context: Context) -> EqualizerNSView { EqualizerNSView() }
    func updateNSView(_ v: EqualizerNSView, context: Context) {
        v.barHeight = height
        v.update(playing: playing, color: color)
    }
}

// plain CALayer animations, swiftui was redrawing every frame for this
final class EqualizerNSView: NSView {
    private var bars: [CALayer] = []
    private var isPlaying: Bool?
    private var color: NSColor?
    var barHeight: CGFloat = 14 { didSet { if barHeight != oldValue { needsLayout = true } } }

    private static let durations: [CFTimeInterval] = [0.42, 0.55, 0.36, 0.48]
    private static let lows: [CGFloat] = [0.3, 0.2, 0.45, 0.25]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for _ in 0..<4 {
            let b = CALayer()
            b.cornerRadius = 1.5
            layer?.addSublayer(b)
            bars.append(b)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (i, b) in bars.enumerated() {
            b.bounds = CGRect(x: 0, y: 0, width: 3, height: barHeight)
            b.position = CGPoint(x: 1.5 + CGFloat(i) * 5, y: bounds.midY)
        }
        CATransaction.commit()
    }

    func update(playing: Bool, color: NSColor) {
        if color != self.color {
            self.color = color
            CATransaction.begin(); CATransaction.setAnimationDuration(0.3)
            for b in bars { b.backgroundColor = color.cgColor }
            CATransaction.commit()
        }

        guard playing != isPlaying else { return }
        isPlaying = playing
        for (i, b) in bars.enumerated() {
            b.removeAnimation(forKey: "eq")
            if playing {
                b.transform = CATransform3DIdentity
                let a = CABasicAnimation(keyPath: "transform.scale.y")
                a.fromValue = Self.lows[i]
                a.toValue = 1
                a.duration = Self.durations[i]
                a.autoreverses = true
                a.repeatCount = .infinity
                a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                b.add(a, forKey: "eq")
            } else {
                b.transform = CATransform3DMakeScale(1, 0.2, 1)
            }
        }
    }
}

struct Artwork: View {
    var image: NSImage?
    var size: CGFloat
    var radius: CGFloat

    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().interpolation(.medium).aspectRatio(contentMode: .fill) }
            else { ZStack { Color(white: 0.15); Image(systemName: "music.note").foregroundStyle(.gray) } }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct IslandView: View {
    @ObservedObject var spotify: Spotify
    @ObservedObject var island: Island
    @ObservedObject var prefs: Prefs

    var body: some View {
        let size = island.size(hasTrack: spotify.hasTrack)
        let big = island.expanded && spotify.hasTrack
        let theme = prefs.theme
        let accent = theme.accent(spotify)
        let radius = big ? 26 : min(12, size.height / 2.6)

        ZStack(alignment: .top) {
            NotchShape(ear: island.ear, bottomRadius: radius)
                .fill(theme.fill(spotify, expanded: big))
                .frame(width: size.width + 2 * island.ear, height: size.height)

            if theme.glows && spotify.hasTrack {
                NotchShape(ear: island.ear, bottomRadius: radius, closed: false)
                    .stroke(accent, lineWidth: 1.5)
                    .shadow(color: accent.opacity(0.9), radius: big ? 8 : 5)
                    .frame(width: size.width + 2 * island.ear, height: size.height)
                    .allowsHitTesting(false)
            }

            Group {
                if big { expanded(accent: accent, theme: theme) }
                else if spotify.hasTrack { compact(accent: accent) }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipped()
            .transition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.36, dampingFraction: 0.8), value: big)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: spotify.hasTrack)
    }

    private func compact(accent: Color) -> some View {
        let h = island.notch.height
        return HStack {
            Artwork(image: spotify.artwork, size: h - 10, radius: 5)
            Spacer()
            Equalizer(playing: spotify.playing, color: accent, height: h * 0.42)
        }
        .padding(.horizontal, 12)
        .frame(height: h)
    }

    private func expanded(accent: Color, theme: Theme) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Artwork(image: spotify.artwork, size: 62, radius: 12)
                VStack(alignment: .leading, spacing: 3) {
                    Text(spotify.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    Group {
                        if let f = prefs.flash { Text("Thème : \(f)").foregroundStyle(accent) }
                        else { Text(spotify.artist).foregroundStyle(.white.opacity(theme.secondaryText)) }
                    }
                    .font(.system(size: 12))
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                Equalizer(playing: spotify.playing, color: accent, height: 18)
            }

            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let pos = spotify.position(at: ctx.date)
                HStack(spacing: 8) {
                    Text(fmt(pos)).monospacedDigit()
                    ProgressBar(fraction: spotify.duration > 0 ? pos / spotify.duration : 0, color: accent) { f in
                        spotify.seek(to: f * spotify.duration)
                    }
                    Text("-" + fmt(max(0, spotify.duration - pos))).monospacedDigit()
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(theme.secondaryText - 0.07))
            }

            ZStack {
                HStack(spacing: 34) {
                    ControlButton(symbol: "backward.fill", size: 17) { spotify.previous() }
                    ControlButton(symbol: spotify.playing ? "pause.fill" : "play.fill", size: 24) { spotify.playPause() }
                    ControlButton(symbol: "forward.fill", size: 17) { spotify.next() }
                }
                HStack {
                    Spacer()
                    ControlButton(symbol: "paintpalette.fill", size: 12, tint: accent.opacity(0.85)) { prefs.cycle() }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, island.notch.height + 6)
        .padding(.bottom, 14)
    }

    private func fmt(_ s: Double) -> String {
        let t = Int(s.isFinite ? s : 0)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

struct ProgressBar: View {
    var fraction: Double
    var color: Color
    var onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule().fill(color).frame(width: g.size.width * max(0, min(1, fraction)))
            }
            .frame(height: 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { v in
                onSeek(max(0, min(1, v.location.x / g.size.width)))
            })
        }
        .frame(height: 12)
    }
}

struct ControlButton: View {
    var symbol: String
    var size: CGFloat
    var tint: Color = .white
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundStyle(tint)
                .frame(width: 36, height: 30)
                .contentShape(Rectangle())
                .scaleEffect(hover ? 1.12 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

// MARK: - Window

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
    let spotify = Spotify()
    let island = Island()
    let prefs = Prefs()
    var panel: IslandPanel!
    var monitors: [Any] = []
    var exitTimer: Timer?
    var collapseWork: DispatchWorkItem?
    var hideWork: DispatchWorkItem?
    var bag = Set<AnyCancellable>()
    let windowSize = CGSize(width: 640, height: 260)

    func applicationDidFinishLaunching(_ n: Notification) {
        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        let host = IslandHostingView(rootView: IslandView(spotify: spotify, island: island, prefs: prefs))
        host.contextMenu = { [weak self] in self?.buildMenu() ?? NSMenu() }
        panel.contentView = host

        place()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.place() }

        spotify.$title.combineLatest(spotify.$running)
            .map { !$0.isEmpty && $1 }
            .removeDuplicates()
            .sink { [weak self] has in self?.setVisible(has) }
            .store(in: &bag)

        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in self?.trackMouse() }) {
            monitors.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in self?.trackMouse(); return e }) {
            monitors.append(l)
        }
    }

    private func setVisible(_ visible: Bool) {
        hideWork?.cancel(); hideWork = nil
        if visible {
            panel.orderFrontRegardless()
        } else {
            island.expanded = false
            // let the collapse animation finish first
            let work = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
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
            island.notch = CGSize(width: s.frame.width - l.width - r.width, height: s.safeAreaInsets.top)
        } else {
            let menuBar = s.frame.maxY - s.visibleFrame.maxY
            island.notch = CGSize(width: 160, height: menuBar > 0 ? menuBar : 24)
        }
        panel.setFrame(NSRect(x: s.frame.midX - windowSize.width / 2, y: s.frame.maxY - windowSize.height,
                              width: windowSize.width, height: windowSize.height), display: true)
    }

    private func trackMouse() {
        guard spotify.hasTrack else { return }
        let m = NSEvent.mouseLocation
        let s = screen
        if !island.expanded && m.y < s.frame.maxY - island.notch.height - 8 {
            if !panel.ignoresMouseEvents { panel.ignoresMouseEvents = true }
            return
        }

        let size = island.size(hasTrack: true)
        let margin: CGFloat = island.expanded ? 12 : 4
        let rect = NSRect(x: s.frame.midX - size.width / 2 - margin, y: s.frame.maxY - size.height - margin,
                          width: size.width + 2 * margin, height: size.height + margin + 1)
        let inside = rect.contains(m)

        // only grab clicks over the island so the menu bar keeps working
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }

        if inside {
            collapseWork?.cancel(); collapseWork = nil
            if !island.expanded {
                island.expanded = true
                spotify.resync()
                startExitTimer()
            }
        } else if island.expanded && collapseWork == nil {
            let work = DispatchWorkItem { [weak self] in
                self?.island.expanded = false
                self?.collapseWork = nil
                self?.exitTimer?.invalidate(); self?.exitTimer = nil
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
            item.state = (t == prefs.theme) ? .on : .off
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
        if let raw = sender.representedObject as? String, let t = Theme(rawValue: raw) { prefs.set(t) }
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
