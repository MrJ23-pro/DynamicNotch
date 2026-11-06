import AppKit
import CoreAudio
import CoreMediaIO

final class PrivacyWatch: ObservableObject {
    @Published private(set) var micActive = false
    @Published private(set) var cameraActive = false

    var onMic: ((String) -> Void)?
    var onCamera: (() -> Void)?

    private var inputDevice = AudioObjectID(kAudioObjectUnknown)
    private var cameras = Set<CMIOObjectID>()
    private lazy var micListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.checkMic() }

    init() {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { [weak self] _, _ in
            self?.bindMic()
        }
        bindMic()

        var devices = Self.cmio(kCMIOHardwarePropertyDevices)
        CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &devices, .main) { [weak self] _, _ in
            self?.bindCameras()
        }
        bindCameras()
    }

    // MARK: Mic

    private func bindMic() {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        if inputDevice != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(inputDevice, &addr, .main, micListener)
        }
        inputDevice = defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
        guard inputDevice != kAudioObjectUnknown else { return }
        AudioObjectAddPropertyListenerBlock(inputDevice, &addr, .main, micListener)
        checkMic(initial: true)
    }

    private func checkMic(initial: Bool = false) {
        let on = audioUInt32(inputDevice, kAudioDevicePropertyDeviceIsRunningSomewhere) != 0
        guard on != micActive else { return }
        micActive = on
        guard on, !initial else { return }
        // the per process flags lag a bit behind the device flag
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.micActive else { return }
            self.onMic?(self.micUsers().first ?? "En cours")
        }
    }

    private func micUsers() -> [String] {
        guard #available(macOS 14.2, *) else { return [] }
        let system = AudioObjectID(kAudioObjectSystemObject)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }

        var names: [String] = []
        for id in ids where audioUInt32(id, kAudioProcessPropertyIsRunningInput) != 0 {
            var pidAddr = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            var pid: pid_t = 0
            var s = UInt32(MemoryLayout<pid_t>.size)
            guard AudioObjectGetPropertyData(id, &pidAddr, 0, nil, &s, &pid) == noErr,
                  let name = appName(for: pid), !names.contains(name) else { continue }
            names.append(name)
        }
        return names
    }

    // MARK: Camera

    private static func cmio<T: BinaryInteger>(_ selector: T) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(selector),
                                  mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private func bindCameras() {
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var addr = Self.cmio(kCMIOHardwarePropertyDevices)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == 0, size > 0 else { return }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &addr, 0, nil, size, &used, &ids) == 0 else { return }

        for id in ids where !cameras.contains(id) {
            cameras.insert(id)
            var running = Self.cmio(kCMIODevicePropertyDeviceIsRunningSomewhere)
            CMIOObjectAddPropertyListenerBlock(id, &running, .main) { [weak self] _, _ in self?.checkCamera() }
        }
        checkCamera(initial: true)
    }

    private func checkCamera(initial: Bool = false) {
        let on = cameras.contains { id in
            var addr = Self.cmio(kCMIODevicePropertyDeviceIsRunningSomewhere)
            var value: UInt32 = 0
            var used: UInt32 = 0
            let err = CMIOObjectGetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value)
            return err == 0 && value != 0
        }
        guard on != cameraActive else { return }
        cameraActive = on
        if on && !initial { onCamera?() }
    }
}

func appName(for pid: pid_t) -> String? {
    if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular,
       let name = app.localizedName {
        return name
    }
    var buf = [CChar](repeating: 0, count: 4096)
    guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return nil }
    let path = String(cString: buf)
    // helper processes live inside the main app bundle
    if let r = path.range(of: ".app/") {
        let bundle = String(path[..<r.lowerBound]) + ".app"
        return FileManager.default.displayName(atPath: bundle).replacingOccurrences(of: ".app", with: "")
    }
    return (path as NSString).lastPathComponent
}
