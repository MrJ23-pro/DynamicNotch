import Foundation

final class Countdown: ObservableObject {
    @Published private(set) var endDate: Date?
    @Published private(set) var pausedRemaining: TimeInterval?

    var onFinish: (() -> Void)?
    private var work: DispatchWorkItem?

    var isActive: Bool { endDate != nil || pausedRemaining != nil }
    var isPaused: Bool { pausedRemaining != nil }

    func remaining(at date: Date) -> TimeInterval {
        if let p = pausedRemaining { return p }
        guard let endDate else { return 0 }
        return max(0, endDate.timeIntervalSince(date))
    }

    func start(minutes: Int) { schedule(TimeInterval(minutes * 60)) }

    func togglePause() {
        if let p = pausedRemaining {
            schedule(p)
        } else if let endDate {
            work?.cancel()
            pausedRemaining = max(0, endDate.timeIntervalSinceNow)
            self.endDate = nil
        }
    }

    func stop() {
        work?.cancel()
        endDate = nil
        pausedRemaining = nil
    }

    private func schedule(_ seconds: TimeInterval) {
        work?.cancel()
        pausedRemaining = nil
        endDate = Date().addingTimeInterval(seconds)
        let w = DispatchWorkItem { [weak self] in
            self?.endDate = nil
            self?.onFinish?()
        }
        work = w
        // wall clock so it still fires at the right time after the mac sleeps
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + seconds, execute: w)
    }
}
