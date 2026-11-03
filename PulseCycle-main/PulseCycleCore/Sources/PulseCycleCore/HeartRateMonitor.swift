// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import CoreBluetooth

public protocol HeartRateMonitorDelegate: AnyObject {
    func heartRateMonitor(_ monitor: HeartRateMonitor, didUpdateHeartRate bpm: Int)
    func heartRateMonitor(_ monitor: HeartRateMonitor, didChangeState state: HeartRateMonitorState)
    func heartRateMonitor(_ monitor: HeartRateMonitor, didFailWithError error: Error)
    func heartRateMonitor(_ monitor: HeartRateMonitor, didConnectDevice name: String)
}

public enum HeartRateMonitorState {
    case idle
    case scanning
    case connecting
    case connected
    case disconnected
}

public class HeartRateMonitor: NSObject {
    public weak var delegate: HeartRateMonitorDelegate?

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var heartRateCharacteristic: CBCharacteristic?
    private let queue = DispatchQueue(label: "com.pulsecycle.bluetooth")

    private let heartRateServiceUUID = CBUUID(string: "180D")
    private let heartRateMeasurementUUID = CBUUID(string: "2A37")

    private var scanTimer: DispatchSourceTimer?
    private var connectionTimeoutTimer: DispatchSourceTimer?
    private var targetDeviceUUID: String?
    private var isAutoConnecting = false
    private var scanTimeoutHandler: (() -> Void)?

    public var connectedDeviceName: String? {
        return connectedPeripheral?.name
    }

    public override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: queue)
    }

    // Auto-connect to default device or try other saved devices
    public func autoConnect() {
        guard centralManager.state == .poweredOn else { return }

        isAutoConnecting = true

        // Disconnect previous device if connected
        if let currentPeripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(currentPeripheral)
        }

        // Try default device first
        if let defaultDevice = DeviceManager.shared.getDefaultDevice(),
           let uuid = UUID(uuidString: defaultDevice.uuid) {
            let peripherals = centralManager.retrievePeripherals(withIdentifiers: [uuid])
            if let peripheral = peripherals.first {
                targetDeviceUUID = defaultDevice.uuid
                connectedPeripheral = peripheral
                peripheral.delegate = self
                delegate?.heartRateMonitor(self, didChangeState: .connecting)
                centralManager.connect(peripheral, options: nil)
                return
            }
        }

        // Try other saved devices
        for device in DeviceManager.shared.devices {
            if device.uuid != DeviceManager.shared.defaultDeviceUUID,
               let uuid = UUID(uuidString: device.uuid) {
                let peripherals = centralManager.retrievePeripherals(withIdentifiers: [uuid])
                if let peripheral = peripherals.first {
                    targetDeviceUUID = device.uuid
                    connectedPeripheral = peripheral
                    peripheral.delegate = self
                    delegate?.heartRateMonitor(self, didChangeState: .connecting)
                    centralManager.connect(peripheral, options: nil)
                    return
                }
            }
        }

        // No saved devices or all failed, scan for new devices
        isAutoConnecting = false
        startScanning()
    }

    // Connect to a specific device by UUID
    public func connectToDevice(uuid: String) {
        guard centralManager.state == .poweredOn else { return }

        // Disconnect previous device if connected
        if let currentPeripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(currentPeripheral)
        }

        if let uuidObj = UUID(uuidString: uuid) {
            let peripherals = centralManager.retrievePeripherals(withIdentifiers: [uuidObj])
            if let peripheral = peripherals.first {
                targetDeviceUUID = uuid
                connectedPeripheral = peripheral
                peripheral.delegate = self
                delegate?.heartRateMonitor(self, didChangeState: .connecting)
                centralManager.connect(peripheral, options: nil)
            }
        }
    }

    public func startScanning(timeoutHandler: (() -> Void)? = nil) {
        guard centralManager.state == .poweredOn else {
            delegate?.heartRateMonitor(self, didChangeState: .disconnected)
            return
        }

        scanTimeoutHandler = timeoutHandler
        delegate?.heartRateMonitor(self, didChangeState: .scanning)
        centralManager.scanForPeripherals(withServices: [heartRateServiceUUID], options: nil)
        startScanTimeout()
    }

    public func stopScanning() {
        centralManager.stopScan()
        scanTimer?.cancel()
        scanTimer = nil
    }

    public func disconnect() {
        connectionTimeoutTimer?.cancel()
        connectionTimeoutTimer = nil
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        heartRateCharacteristic = nil
        delegate?.heartRateMonitor(self, didChangeState: .disconnected)
    }

    public func isConnectedDevice(uuid: String) -> Bool {
        return connectedPeripheral?.identifier.uuidString == uuid
    }

    public func getConnectedDeviceUUID() -> String? {
        return connectedPeripheral?.identifier.uuidString
    }

    private func startConnectionTimeout() {
        connectionTimeoutTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 3)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            if self.connectedPeripheral != nil {
                // No heart rate data for 3 seconds, show disconnected state
                self.connectedPeripheral = nil
                self.heartRateCharacteristic = nil
                DispatchQueue.main.async {
                    self.delegate?.heartRateMonitor(self, didChangeState: .disconnected)
                    NotificationCenter.default.post(name: NSNotification.Name("HeartRateMonitorStateChanged"), object: nil)
                }
            }
        }
        timer.resume()
        connectionTimeoutTimer = timer
    }

    private func resetConnectionTimeout() {
        connectionTimeoutTimer?.cancel()
        startConnectionTimeout()
    }

    private func startScanTimeout() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 30)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.stopScanning()
            if self.connectedPeripheral == nil {
                self.delegate?.heartRateMonitor(self, didChangeState: .disconnected)
                DispatchQueue.main.async {
                    self.scanTimeoutHandler?()
                    self.scanTimeoutHandler = nil
                }
            }
        }
        timer.resume()
        scanTimer = timer
    }

    private func parseHeartRate(_ data: Data) -> Int? {
        guard !data.isEmpty else { return nil }

        let firstByte = data[0]
        let isUInt16 = (firstByte & 0x01) != 0

        if isUInt16 {
            guard data.count >= 3 else { return nil }
            let bpm = UInt16(data[1]) | (UInt16(data[2]) << 8)
            return Int(bpm)
        } else {
            guard data.count >= 2 else { return nil }
            return Int(data[1])
        }
    }
}

extension HeartRateMonitor: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            // Auto-connect when Bluetooth is ready
            autoConnect()
        } else {
            delegate?.heartRateMonitor(self, didChangeState: .disconnected)
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        stopScanning()

        // Disconnect previous device if connected
        if let currentPeripheral = connectedPeripheral {
            central.cancelPeripheralConnection(currentPeripheral)
        }

        connectedPeripheral = peripheral
        peripheral.delegate = self
        delegate?.heartRateMonitor(self, didChangeState: .connecting)
        central.connect(peripheral, options: nil)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // Save device to DeviceManager and set as default
        DeviceManager.shared.saveDevice(peripheral)
        DeviceManager.shared.setDefaultDevice(uuid: peripheral.identifier.uuidString)

        let deviceName = peripheral.name ?? "Unknown Device"
        delegate?.heartRateMonitor(self, didConnectDevice: deviceName)
        delegate?.heartRateMonitor(self, didChangeState: .connected)
        NotificationCenter.default.post(name: NSNotification.Name("HeartRateMonitorStateChanged"), object: nil)
        startConnectionTimeout()
        peripheral.discoverServices([heartRateServiceUUID])
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            delegate?.heartRateMonitor(self, didFailWithError: error)
        }
        connectedPeripheral = nil

        // If auto-connecting and failed, try next device or scan
        if isAutoConnecting {
            isAutoConnecting = false
            startScanning()
        } else {
            delegate?.heartRateMonitor(self, didChangeState: .disconnected)
        }
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectionTimeoutTimer?.cancel()
        connectionTimeoutTimer = nil
        connectedPeripheral = nil
        heartRateCharacteristic = nil
        delegate?.heartRateMonitor(self, didChangeState: .disconnected)
        NotificationCenter.default.post(name: NSNotification.Name("HeartRateMonitorStateChanged"), object: nil)

        if error != nil && !isAutoConnecting {
            startScanning()
        }
    }
}

extension HeartRateMonitor: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            delegate?.heartRateMonitor(self, didFailWithError: error!)
            return
        }

        if let service = peripheral.services?.first(where: { $0.uuid == heartRateServiceUUID }) {
            peripheral.discoverCharacteristics([heartRateMeasurementUUID], for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            delegate?.heartRateMonitor(self, didFailWithError: error!)
            return
        }

        if let characteristic = service.characteristics?.first(where: { $0.uuid == heartRateMeasurementUUID }) {
            heartRateCharacteristic = characteristic
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            delegate?.heartRateMonitor(self, didFailWithError: error!)
            return
        }

        if let data = characteristic.value, let bpm = parseHeartRate(data) {
            resetConnectionTimeout()
            // If peripheral still exists, we're still connected
            if connectedPeripheral != nil {
                let deviceName = connectedPeripheral?.name ?? "Unknown Device"
                DispatchQueue.main.async {
                    self.delegate?.heartRateMonitor(self, didConnectDevice: deviceName)
                    self.delegate?.heartRateMonitor(self, didChangeState: .connected)
                }
            }
            delegate?.heartRateMonitor(self, didUpdateHeartRate: bpm)
        }
    }
}
