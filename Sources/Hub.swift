import AppKit
import Combine
import SwiftUI

struct Banner: Equatable {
    enum Kind: Equatable {
        case charging(Int)
        case volume(Float, Bool)
        case bluetooth(String, String)
        case downloaded(String)
        case timerDone
        case mic(String)
        case camera
    }

    var kind: Kind

    var side: CGFloat {
        switch kind {
        case .volume: return 78
        case .bluetooth, .downloaded: return 132
        default: return 112
        }
    }
}

enum CompactKind {
    case music, timer, download
}

final class Hub: ObservableObject {
    let spotify = Spotify()
    let battery = Battery()
    let countdown = Countdown()
    let downloads = Downloads()
    let privacy = PrivacyWatch()
    let volume = VolumeWatch()
    let bluetooth = BluetoothWatch()
    let prefs = Prefs()

    @Published var expanded = false
    @Published private(set) var banner: Banner?
    @Published private(set) var shake: CGFloat = 0

    var notch = CGSize(width: 185, height: 32)
    var hasNotch = true
    let ear: CGFloat = 8

    static let musicHeight: CGFloat = 128
    static let rowHeight: CGFloat = 24
    static let toolsHeight: CGFloat = 30
    static let spacing: CGFloat = 12

    private var bag = Set<AnyCancellable>()
    private var bannerWork: DispatchWorkItem?

    init() {
        Publishers.MergeMany(spotify.objectWillChange, battery.objectWillChange, countdown.objectWillChange,
                             downloads.objectWillChange, privacy.objectWillChange, prefs.objectWillChange)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &bag)

        battery.onPlug = { [weak self] level in self?.show(.charging(level)) }
        volume.onChange = { [weak self] v, muted in self?.show(.volume(v, muted), for: 1.5) }
        bluetooth.onConnect = { [weak self] name, symbol in self?.show(.bluetooth(name, symbol)) }
        downloads.onFinish = { [weak self] name in self?.show(.downloaded(name), for: 3) }
        privacy.onMic = { [weak self] app in self?.show(.mic(app)) }
        privacy.onCamera = { [weak self] in self?.show(.camera) }
        countdown.onFinish = { [weak self] in self?.timerDone() }
    }

    var compact: CompactKind? {
        if countdown.isActive { return .timer }
        if !downloads.active.isEmpty { return .download }
        if spotify.hasTrack { return .music }
        return nil
    }

    var dots: [Color] {
        var d: [Color] = []
        if privacy.cameraActive { d.append(.green) }
        if privacy.micActive { d.append(.orange) }
        return d
    }

    var isIdle: Bool { !expanded && banner == nil && compact == nil && dots.isEmpty }

    var visibleDownloads: [Downloads.Item] { Array(downloads.active.prefix(3)) }

    var size: CGSize {
        if expanded { return expandedSize }
        if let b = banner { return CGSize(width: notch.width + 2 * b.side, height: notch.height) }

        var side: CGFloat
        switch compact {
        case .music?, .download?: side = notch.height + 8
        case .timer?: side = 58
        case nil: side = 0
        }
        if !dots.isEmpty { side += CGFloat(dots.count) * 10 + (side == 0 ? 12 : 4) }
        if side == 0 { return hasNotch ? notch : .zero }
        return CGSize(width: notch.width + 2 * side, height: notch.height)
    }

    // must match the stack in ExpandedView
    private var expandedSize: CGSize {
        var blocks: [CGFloat] = [Self.toolsHeight]
        if spotify.hasTrack { blocks.append(Self.musicHeight) }
        blocks += visibleDownloads.map { _ in Self.rowHeight }
        let content = blocks.reduce(0, +) + CGFloat(blocks.count - 1) * Self.spacing
        return CGSize(width: max(notch.width + 200, 400), height: notch.height + 8 + content + 14)
    }

    func show(_ kind: Banner.Kind, for seconds: Double = 2.5) {
        bannerWork?.cancel()
        banner = Banner(kind: kind)
        let work = DispatchWorkItem { [weak self] in self?.banner = nil }
        bannerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func timerDone() {
        show(.timerDone, for: 4)
        NSSound(named: "Glass")?.play()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        withAnimation(.linear(duration: 0.7)) { shake += 1 }
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
