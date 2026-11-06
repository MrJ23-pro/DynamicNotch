import Foundation
import IOKit.ps

final class Battery: ObservableObject {
    @Published private(set) var level = 0
    @Published private(set) var charging = false
    private(set) var present = false
    private var onAC = false
    private var source: CFRunLoopSource?

    var onPlug: ((Int) -> Void)?

    init() {
        read(initial: true)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { ctx in
            guard let ctx else { return }
            Unmanaged<Battery>.fromOpaque(ctx).takeUnretainedValue().read(initial: false)
        }
        if let s = IOPSNotificationCreateRunLoopSource(callback, ctx)?.takeRetainedValue() {
            source = s
            CFRunLoopAddSource(CFRunLoopGetMain(), s, .defaultMode)
        }
    }

    private func read(initial: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }

        let ac = (IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?) == "AC Power"
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            present = true
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            let lvl = max > 0 ? cur * 100 / max : cur
            if lvl != level { level = lvl }
            let c = d[kIOPSIsChargingKey] as? Bool ?? false
            if c != charging { charging = c }
        }

        if present && ac && !onAC && !initial { onPlug?(level) }
        onAC = ac
    }
}
