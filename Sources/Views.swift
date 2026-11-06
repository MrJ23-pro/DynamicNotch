import AppKit
import SwiftUI

// MARK: - Island

struct IslandView: View {
    @ObservedObject var hub: Hub

    var body: some View {
        let size = hub.size
        let theme = hub.prefs.theme
        let accent = theme.accent(hub.spotify)
        let radius: CGFloat = hub.expanded ? 26 : min(12, size.height / 2.6)
        let shapeWidth = size.width + 2 * hub.ear

        ZStack(alignment: .top) {
            NotchShape(ear: hub.ear, bottomRadius: radius)
                .fill(theme.fill(hub.spotify, expanded: hub.expanded && hub.spotify.hasTrack))
                .frame(width: shapeWidth, height: size.height)

            if theme.glows && !hub.isIdle {
                NotchShape(ear: hub.ear, bottomRadius: radius, closed: false)
                    .stroke(accent, lineWidth: 1.5)
                    .shadow(color: accent.opacity(0.9), radius: hub.expanded ? 8 : 5)
                    .frame(width: shapeWidth, height: size.height)
                    .allowsHitTesting(false)
            }

            content(accent: accent, theme: theme)
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipped()
        }
        .modifier(Shake(amount: hub.shake))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.36, dampingFraction: 0.8), value: size)
    }

    @ViewBuilder
    private func content(accent: Color, theme: Theme) -> some View {
        if hub.expanded {
            ExpandedView(hub: hub, accent: accent, theme: theme).transition(.opacity)
        } else if let b = hub.banner {
            BannerView(banner: b, height: hub.notch.height).transition(.opacity)
        } else if !hub.isIdle {
            CompactView(hub: hub, accent: accent).transition(.opacity)
        }
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

struct Shake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat { get { amount } set { amount = newValue } }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: sin(amount * .pi * 8) * 5, y: 0))
    }
}

// MARK: - Compact

struct CompactView: View {
    let hub: Hub
    let accent: Color

    var body: some View {
        let h = hub.notch.height
        HStack(spacing: 6) {
            switch hub.compact {
            case .music?:
                Artwork(image: hub.spotify.artwork, size: h - 10, radius: 5)
                Spacer(minLength: 0)
                Equalizer(playing: hub.spotify.playing, color: accent, height: h * 0.42)
            case .timer?:
                Image(systemName: "timer").foregroundStyle(.orange)
                Spacer(minLength: 0)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(clock(hub.countdown.remaining(at: ctx.date), roundUp: true))
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                }
            case .download?:
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue)
                Spacer(minLength: 0)
                Ring(fraction: hub.downloads.active.first?.fraction, color: .blue)
                    .frame(width: 15, height: 15)
            case nil:
                Spacer(minLength: 0)
            }
            ForEach(Array(hub.dots.enumerated()), id: \.offset) { _, color in
                Circle().fill(color).frame(width: 6, height: 6)
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, 12)
        .frame(height: h)
    }
}

// MARK: - Banner

struct BannerView: View {
    let banner: Banner
    let height: CGFloat

    var body: some View {
        let w = banner.side - 14
        HStack(spacing: 0) {
            left.frame(width: w, alignment: .leading)
            Spacer(minLength: 0)
            right.frame(width: w, alignment: .trailing)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .frame(height: height)
    }

    @ViewBuilder
    private var left: some View {
        switch banner.kind {
        case .charging:
            IconText(symbol: "bolt.fill", text: "En charge", tint: .green)
        case .volume(let v, let muted):
            Image(systemName: speakerSymbol(v, muted: muted))
        case .bluetooth(let name, let symbol):
            IconText(symbol: symbol, text: name, tint: .white)
        case .downloaded:
            IconText(symbol: "arrow.down.circle.fill", text: "Téléchargé", tint: .blue)
        case .timerDone:
            IconText(symbol: "timer", text: "Minuteur", tint: .orange)
        case .mic:
            IconText(symbol: "mic.fill", text: "Micro", tint: .orange)
        case .camera:
            IconText(symbol: "video.fill", text: "Caméra", tint: .green)
        }
    }

    @ViewBuilder
    private var right: some View {
        switch banner.kind {
        case .charging(let level):
            HStack(spacing: 4) {
                Text("\(level) %").monospacedDigit()
                Image(systemName: batterySymbol(level, charging: true))
            }
            .foregroundStyle(.green)
        case .volume(let v, let muted):
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule().fill(.white).frame(width: 56 * CGFloat(muted ? 0 : v))
            }
            .frame(width: 56, height: 5)
        case .bluetooth:
            Text("Connecté").foregroundStyle(.blue)
        case .downloaded(let name):
            Text(name).truncationMode(.middle).foregroundStyle(.white.opacity(0.7))
        case .timerDone:
            Text("Terminé").foregroundStyle(.orange)
        case .mic(let app):
            Text(app).foregroundStyle(.white.opacity(0.8))
        case .camera:
            Text("Active").foregroundStyle(.green)
        }
    }
}

struct IconText: View {
    let symbol: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text)
        }
    }
}

// MARK: - Expanded

struct ExpandedView: View {
    let hub: Hub
    let accent: Color
    let theme: Theme

    var body: some View {
        VStack(spacing: Hub.spacing) {
            if hub.spotify.hasTrack {
                MusicBlock(spotify: hub.spotify, accent: accent, theme: theme)
                    .frame(height: Hub.musicHeight)
            }
            ForEach(hub.visibleDownloads) { item in
                DownloadRow(item: item).frame(height: Hub.rowHeight)
            }
            ToolsRow(hub: hub, accent: accent).frame(height: Hub.toolsHeight)
        }
        .padding(.horizontal, 22)
        .padding(.top, hub.notch.height + 8)
        .padding(.bottom, 14)
    }
}

struct MusicBlock: View {
    let spotify: Spotify
    let accent: Color
    let theme: Theme

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Artwork(image: spotify.artwork, size: 62, radius: 12)
                VStack(alignment: .leading, spacing: 3) {
                    Text(spotify.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    Text(spotify.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(theme.secondaryText))
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                Equalizer(playing: spotify.playing, color: accent, height: 18)
            }

            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let pos = spotify.position(at: ctx.date)
                HStack(spacing: 8) {
                    Text(clock(pos)).monospacedDigit()
                    ProgressBar(fraction: spotify.duration > 0 ? pos / spotify.duration : 0, color: accent) { f in
                        spotify.seek(to: f * spotify.duration)
                    }
                    Text("-" + clock(max(0, spotify.duration - pos))).monospacedDigit()
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(theme.secondaryText - 0.07))
            }

            HStack(spacing: 34) {
                ControlButton(symbol: "backward.fill", size: 17) { spotify.previous() }
                ControlButton(symbol: spotify.playing ? "pause.fill" : "play.fill", size: 24) { spotify.playPause() }
                ControlButton(symbol: "forward.fill", size: 17) { spotify.next() }
            }
        }
    }
}

struct DownloadRow: View {
    let item: Downloads.Item

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue)
            Text(item.name).lineLimit(1).truncationMode(.middle).foregroundStyle(.white)
            Spacer(minLength: 8)
            if let f = item.fraction {
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule().fill(.blue).frame(width: 80 * f)
                }
                .frame(width: 80, height: 4)
                Text("\(Int(f * 100)) %")
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 36, alignment: .trailing)
            } else {
                Text(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .font(.system(size: 12, weight: .medium))
    }
}

struct ToolsRow: View {
    let hub: Hub
    let accent: Color

    var body: some View {
        let countdown = hub.countdown
        HStack(spacing: 8) {
            Image(systemName: "timer").foregroundStyle(.orange)
            if countdown.isActive {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(clock(countdown.remaining(at: ctx.date), roundUp: true))
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                ControlButton(symbol: countdown.isPaused ? "play.fill" : "pause.fill", size: 11, width: 26) {
                    countdown.togglePause()
                }
                ControlButton(symbol: "xmark", size: 11, width: 26) { countdown.stop() }
            } else {
                ForEach([5, 25, 50], id: \.self) { m in
                    Button { countdown.start(minutes: m) } label: {
                        Text("\(m) min")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(.white.opacity(0.12)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 4)

            if let f = hub.prefs.flash {
                Text("Thème : \(f)").foregroundStyle(accent)
            } else if hub.battery.present {
                HStack(spacing: 3) {
                    Image(systemName: batterySymbol(hub.battery.level, charging: hub.battery.charging))
                    Text("\(hub.battery.level) %").monospacedDigit()
                }
                .foregroundStyle(.white.opacity(0.6))
            }
            ControlButton(symbol: "paintpalette.fill", size: 12, width: 28, tint: accent.opacity(0.85)) {
                hub.prefs.cycle()
            }
        }
        .font(.system(size: 11, weight: .medium))
    }
}

// MARK: - Small pieces

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

struct Ring: View {
    var fraction: Double?
    var color: Color

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: fraction ?? 0.15)
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
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
    var width: CGFloat = 36
    var tint: Color = .white
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundStyle(tint)
                .frame(width: width, height: 30)
                .contentShape(Rectangle())
                .scaleEffect(hover ? 1.12 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

// countdowns round up so they don't show 0:00 for the last second
func clock(_ seconds: Double, roundUp: Bool = false) -> String {
    let t = Int((seconds.isFinite ? seconds : 0).rounded(roundUp ? .up : .down))
    return String(format: "%d:%02d", t / 60, t % 60)
}

func batterySymbol(_ level: Int, charging: Bool) -> String {
    if charging { return "battery.100percent.bolt" }
    switch level {
    case ..<13: return "battery.0percent"
    case ..<38: return "battery.25percent"
    case ..<63: return "battery.50percent"
    case ..<88: return "battery.75percent"
    default: return "battery.100percent"
    }
}

func speakerSymbol(_ v: Float, muted: Bool) -> String {
    if muted || v == 0 { return "speaker.slash.fill" }
    if v < 0.33 { return "speaker.wave.1.fill" }
    if v < 0.66 { return "speaker.wave.2.fill" }
    return "speaker.wave.3.fill"
}
