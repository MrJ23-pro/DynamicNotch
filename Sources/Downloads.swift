import Foundation

final class Downloads: ObservableObject {
    struct Item: Identifiable, Equatable {
        let id: String
        let name: String
        var fraction: Double?
        var bytes: Int64
    }

    @Published private(set) var active: [Item] = []
    var onFinish: ((String) -> Void)?

    private let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    private var source: DispatchSourceFileSystemObject?
    private var poll: Timer?

    // chrome / brave / edge, safari, firefox
    private static let partialExtensions: Set<String> = ["crdownload", "download", "part"]

    init() {
        let fd = open(dir.path, O_EVTONLY)
        if fd >= 0 {
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
            src.setEventHandler { [weak self] in self?.scan() }
            src.setCancelHandler { close(fd) }
            src.resume()
            source = src
        }
        scan(initial: true)
    }

    private func scan(initial: Bool = false) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let partials = names.filter { Self.partialExtensions.contains(($0 as NSString).pathExtension.lowercased()) }

        let items = partials.sorted().map { file -> Item in
            let path = dir.appendingPathComponent(file).path
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            let bytes = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            return Item(id: file, name: (file as NSString).deletingPathExtension,
                        fraction: Self.progress(path), bytes: bytes)
        }

        // partial file gone and the final one is there: finished. otherwise it was cancelled
        if !initial {
            for old in active where !partials.contains(old.id) && names.contains(old.name) {
                onFinish?(old.name)
            }
        }

        if items != active { active = items }

        // folder events don't fire while a file grows, so poll only while something downloads
        if items.isEmpty {
            poll?.invalidate()
            poll = nil
        } else if poll == nil {
            poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.scan() }
            poll?.tolerance = 0.3
        }
    }

    // browsers publish their progress here, it's what finder uses for the progress bar on the icon
    private static func progress(_ path: String) -> Double? {
        let attr = "com.apple.progress.fractionCompleted"
        let len = getxattr(path, attr, nil, 0, 0, 0)
        guard len > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: len)
        guard getxattr(path, attr, &buf, len, 0, 0) == len,
              let s = String(bytes: buf, encoding: .utf8),
              let v = Double(s.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))) else { return nil }
        return min(1, max(0, v))
    }
}
