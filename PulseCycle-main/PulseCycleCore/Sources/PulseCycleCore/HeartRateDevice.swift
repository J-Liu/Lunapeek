// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation
import CoreBluetooth

public struct HeartRateDevice: Codable, Equatable {
    public let uuid: String
    public let name: String

    public var identifier: UUID {
        UUID(uuidString: uuid) ?? UUID()
    }
}

public class DeviceManager {
    public static let shared = DeviceManager()

    private let devicesKey = "saved_heart_rate_devices"
    private let defaultDeviceKey = "default_heart_rate_device"

    public private(set) var devices: [HeartRateDevice] = []
    public private(set) var defaultDeviceUUID: String?

    private init() {
        loadDevices()
        loadDefaultDevice()
    }

    private func loadDevices() {
        if let data = UserDefaults.standard.data(forKey: devicesKey),
           let decoded = try? JSONDecoder().decode([HeartRateDevice].self, from: data) {
            devices = decoded
        }
    }

    private func loadDefaultDevice() {
        defaultDeviceUUID = UserDefaults.standard.string(forKey: defaultDeviceKey)
    }

    public func saveDevice(_ peripheral: CBPeripheral) {
        let uuid = peripheral.identifier.uuidString
        let name = peripheral.name ?? "Unknown Device"

        // Check if device already exists
        if let index = devices.firstIndex(where: { $0.uuid == uuid }) {
            // Update name if changed
            if devices[index].name != name {
                devices[index] = HeartRateDevice(uuid: uuid, name: name)
                saveDevices()
                NotificationCenter.default.post(name: NSNotification.Name("DeviceListUpdated"), object: nil)
            }
        } else {
            // Add new device
            devices.append(HeartRateDevice(uuid: uuid, name: name))
            saveDevices()

            // Set as default if it's the first device
            if devices.count == 1 {
                setDefaultDevice(uuid: uuid)
            }

            NotificationCenter.default.post(name: NSNotification.Name("DeviceListUpdated"), object: nil)
        }
    }

    public func removeDevice(at index: Int) {
        guard index < devices.count else { return }
        let device = devices[index]
        devices.remove(at: index)
        saveDevices()

        // Post notifications
        NotificationCenter.default.post(
            name: NSNotification.Name("DeviceRemoved"),
            object: nil,
            userInfo: ["uuid": device.uuid]
        )
        NotificationCenter.default.post(name: NSNotification.Name("DeviceListUpdated"), object: nil)

        // If removed device was default, clear default
        if defaultDeviceUUID == device.uuid {
            defaultDeviceUUID = nil
            UserDefaults.standard.removeObject(forKey: defaultDeviceKey)

            // Set first remaining device as default if exists
            if let firstDevice = devices.first {
                setDefaultDevice(uuid: firstDevice.uuid)
            }
        }
    }

    public func setDefaultDevice(uuid: String) {
        defaultDeviceUUID = uuid
        UserDefaults.standard.set(uuid, forKey: defaultDeviceKey)
        NotificationCenter.default.post(name: NSNotification.Name("DeviceListUpdated"), object: nil)
    }

    public func getDefaultDevice() -> HeartRateDevice? {
        guard let uuid = defaultDeviceUUID else { return nil }
        return devices.first { $0.uuid == uuid }
    }

    public func getDevice(byUUID uuid: String) -> HeartRateDevice? {
        return devices.first { $0.uuid == uuid }
    }

    private func saveDevices() {
        if let encoded = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(encoded, forKey: devicesKey)
        }
    }
}
