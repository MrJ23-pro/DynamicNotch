import AppKit
import ImageIO
import SwiftUI

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
