import Foundation
import IOBluetooth

final class BluetoothWatch: NSObject {
    var onConnect: ((String, String) -> Void)?

    private var note: IOBluetoothUserNotification?
    private let launched = Date()

    override init() {
        super.init()
        note = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connected(_:device:)))
    }

    @objc private func connected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        // devices that are already connected get reported right after registering
        guard Date().timeIntervalSince(launched) > 3 else { return }
        let name = device.name ?? "Bluetooth"
        onConnect?(name, Self.symbol(name: name, major: device.deviceClassMajor, minor: device.deviceClassMinor))
    }

    private static func symbol(name: String, major: BluetoothDeviceClassMajor, minor: BluetoothDeviceClassMinor) -> String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        switch major {
        case 0x04:
            return "headphones"
        case 0x05:
            if minor & 0x10 != 0 { return "keyboard" }
            if minor & 0x20 != 0 { return "computermouse" }
            return "gamecontroller"
        default:
            return "dot.radiowaves.left.and.right"
        }
    }
}
