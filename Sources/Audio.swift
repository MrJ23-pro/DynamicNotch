import AudioToolbox
import CoreAudio
import Foundation

func audioUInt32(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
                 scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32 {
    var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value)
    return value
}

func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioObjectID {
    var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    var id = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
    return id
}

final class VolumeWatch {
    var onChange: ((Float, Bool) -> Void)?

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var last: (Float, Bool)?
    private var ready = false
    private lazy var listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.changed() }

    // not every device exposes the same properties, so listen to whatever is there
    private static let watched: [(AudioObjectPropertySelector, AudioObjectPropertyElement)] = [
        (kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyElementMain),
        (kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain),
        (kAudioDevicePropertyVolumeScalar, 1),
        (kAudioDevicePropertyVolumeScalar, 2),
        (kAudioDevicePropertyMute, kAudioObjectPropertyElementMain),
    ]

    init() {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { [weak self] _, _ in
            self?.bind()
        }
        bind()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.ready = true }
    }

    private func addresses(_ id: AudioObjectID) -> [AudioObjectPropertyAddress] {
        guard id != kAudioObjectUnknown else { return [] }
        return Self.watched
            .map { AudioObjectPropertyAddress(mSelector: $0.0, mScope: kAudioDevicePropertyScopeOutput, mElement: $0.1) }
            .filter { var a = $0; return AudioObjectHasProperty(id, &a) }
    }

    private func bind() {
        for var a in addresses(device) { AudioObjectRemovePropertyListenerBlock(device, &a, .main, listener) }
        device = defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        for var a in addresses(device) { AudioObjectAddPropertyListenerBlock(device, &a, .main, listener) }
        last = read()
    }

    private func read() -> (Float, Bool) {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                              mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        var v: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &v)
        let muted = audioUInt32(device, kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput) != 0
        return (v, muted)
    }

    private func changed() {
        let now = read()
        defer { last = now }
        guard ready else { return }
        if let last, last.0 == now.0, last.1 == now.1 { return }
        onChange?(now.0, now.1)
    }
}
