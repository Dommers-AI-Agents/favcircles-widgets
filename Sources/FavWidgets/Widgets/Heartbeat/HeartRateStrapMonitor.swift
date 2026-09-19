import Foundation
import Combine
import FavWidgetsCore
#if canImport(CoreBluetooth)
import CoreBluetooth
#endif

/// Live heart rate from any Bluetooth strap or armband that speaks the
/// standard Heart Rate profile (Polar, Garmin, Wahoo, most gym straps).
/// The central manager is created on the first "Find a strap" tap, because
/// constructing it is what triggers the Bluetooth permission prompt.
@MainActor
final class HeartRateStrapMonitor: NSObject, ObservableObject {
    struct Device: Identifiable, Equatable {
        let id: UUID
        let name: String
    }

    enum State: Equatable { case idle, scanning, connecting(String), connected(String), unavailable(String) }

    @Published private(set) var state: State = .idle
    @Published private(set) var devices: [Device] = []
    @Published private(set) var bpm: Int?
    @Published private(set) var lastUpdate: Date?

    #if canImport(CoreBluetooth)
    static let heartRateService = CBUUID(string: "180D")
    static let measurementCharacteristic = CBUUID(string: "2A37")
    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connected: CBPeripheral?
    private var wantsScan = false
    #endif

    var connectedName: String? {
        if case .connected(let name) = state { return name }
        return nil
    }

    func scan() {
        #if canImport(CoreBluetooth)
        devices = []
        wantsScan = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil)
            state = .scanning
            return
        }
        startScanIfReady()
        #else
        state = .unavailable("Bluetooth isn't available here.")
        #endif
    }

    func connect(_ device: Device) {
        #if canImport(CoreBluetooth)
        guard let central, let peripheral = peripherals[device.id] else { return }
        central.stopScan()
        state = .connecting(device.name)
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
        #endif
    }

    func disconnect() {
        #if canImport(CoreBluetooth)
        central?.stopScan()
        if let connected { central?.cancelPeripheralConnection(connected) }
        connected = nil
        #endif
        bpm = nil
        state = .idle
    }

    #if canImport(CoreBluetooth)
    private func startScanIfReady() {
        guard let central, wantsScan else { return }
        switch central.state {
        case .poweredOn:
            state = .scanning
            central.scanForPeripherals(withServices: [Self.heartRateService], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        case .unauthorized:
            state = .unavailable("Allow Bluetooth for Circles in Settings to use a strap.")
        case .poweredOff:
            state = .unavailable("Turn on Bluetooth to find a strap.")
        case .unsupported:
            state = .unavailable("This device has no Bluetooth.")
        default:
            break // still powering up; the delegate will call back
        }
    }

    /// Heart Rate Measurement: flags byte, then 8- or 16-bit bpm.
    nonisolated static func parseMeasurement(_ data: Data) -> Int? {
        guard data.count >= 2 else { return nil }
        let flags = data[data.startIndex]
        if flags & 0x01 == 0 {
            return Int(data[data.startIndex + 1])
        }
        guard data.count >= 3 else { return nil }
        return Int(data[data.startIndex + 1]) | (Int(data[data.startIndex + 2]) << 8)
    }
    #endif
}

#if canImport(CoreBluetooth)
extension HeartRateStrapMonitor: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in self.startScanIfReady() }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Heart rate sensor"
        let id = peripheral.identifier
        Task { @MainActor in
            self.peripherals[id] = peripheral
            if !self.devices.contains(where: { $0.id == id }) { self.devices.append(Device(id: id, name: name)) }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let name = peripheral.name ?? "Strap"
        Task { @MainActor in
            self.connected = peripheral
            self.state = .connected(name)
        }
        peripheral.discoverServices([Self.heartRateService])
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in self.state = .unavailable("Couldn't connect: \(error?.localizedDescription ?? "unknown error")") }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.connected = nil
            self.bpm = nil
            self.state = .idle
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] where service.uuid == Self.heartRateService {
            peripheral.discoverCharacteristics([Self.measurementCharacteristic], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] where characteristic.uuid == Self.measurementCharacteristic {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.measurementCharacteristic, let data = characteristic.value,
              let bpm = Self.parseMeasurement(data) else { return }
        Task { @MainActor in
            self.bpm = bpm
            self.lastUpdate = Date()
        }
    }
}
#endif
