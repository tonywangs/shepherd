//
//  ESPBluetoothManager.swift
//  SmartCane
//
//  BLE manager for manual ESP32 pairing and motor control.
//  Ported from the Bluetooth branch's standalone pairing app.
//  Uses service/characteristic UUIDs matching the ESP32 firmware.
//

import Foundation
import CoreBluetooth
import Combine

private enum ESPBLEConstants {
    static let serviceUUID = CBUUID(string: "8A4E1E45-1E84-4AA2-B4B8-3D960D6CE001")
    static let dataCharacteristicUUID = CBUUID(string: "8A4E1E45-1E84-4AA2-B4B8-3D960D6CE002")
}

struct DiscoveredPeripheral: Identifiable, @unchecked Sendable {
    let id: UUID
    let peripheral: CBPeripheral
    var name: String
    var rssi: NSNumber
}

class ESPBluetoothManager: NSObject, ObservableObject {
    @Published var isBluetoothReady = false
    @Published var isScanning = false
    @Published var discoveredPeripherals: [DiscoveredPeripheral] = []
    @Published var connectedName: String?
    @Published var statusMessage: String?

    @Published var angle: Float = 0
    @Published var distance: Float = 0
    @Published var mode: Float = 0

    // Steering tuning parameters (adjustable via Bluetooth tab)
    @Published var steeringSensitivity: Float = 2.0  // Distance threshold in meters
    @Published var steeringMagnitude: Float = 2.0    // Motor intensity multiplier

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var sendTimer: Timer?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    func toggleScan() {
        guard isBluetoothReady else {
            statusMessage = "Bluetooth is not ready. Enable Bluetooth in Settings."
            return
        }

        if isScanning {
            centralManager.stopScan()
            isScanning = false
        } else {
            discoveredPeripherals = []
            centralManager.scanForPeripherals(
                withServices: [ESPBLEConstants.serviceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
            isScanning = true
        }
    }

    func connect(_ peripheral: CBPeripheral) {
        statusMessage = nil
        centralManager.stopScan()
        isScanning = false
        connectedPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }

    func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        centralManager.cancelPeripheralConnection(peripheral)
    }

    private func startSendingLoop() {
        stopSendingLoop()
        sendTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.sendPacket()
        }
    }

    private func stopSendingLoop() {
        sendTimer?.invalidate()
        sendTimer = nil
    }

    private func sendPacket() {
        guard
            let peripheral = connectedPeripheral,
            let characteristic = writeCharacteristic
        else { return }

        var packet = Data(capacity: 12)
        packet.appendLittleEndian(angle)
        packet.appendLittleEndian(distance)
        packet.appendLittleEndian(UInt32(mode.rounded()))

        let writeType: CBCharacteristicWriteType =
            characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(packet, for: characteristic, type: writeType)
    }
}

// MARK: - CBCentralManagerDelegate
extension ESPBluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        isBluetoothReady = central.state == .poweredOn
        if !isBluetoothReady {
            isScanning = false
            discoveredPeripherals = []
            connectedName = nil
            stopSendingLoop()

            switch central.state {
            case .unauthorized:
                statusMessage = "Bluetooth permission denied. Enable in Settings > Privacy > Bluetooth."
            case .unsupported:
                statusMessage = "This device does not support BLE."
            case .poweredOff:
                statusMessage = "Bluetooth is off. Turn it on in Settings."
            default:
                statusMessage = "Bluetooth is currently unavailable."
            }
        } else {
            statusMessage = nil
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let id = peripheral.identifier
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let resolvedName = peripheral.name ?? advName ?? "Unnamed ESP32"

        if let idx = discoveredPeripherals.firstIndex(where: { $0.id == id }) {
            discoveredPeripherals[idx].name = resolvedName
            discoveredPeripherals[idx].rssi = RSSI
        } else {
            discoveredPeripherals.append(
                DiscoveredPeripheral(id: id, peripheral: peripheral, name: resolvedName, rssi: RSSI)
            )
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedName = peripheral.name ?? "ESP32"
        peripheral.discoverServices([ESPBLEConstants.serviceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        connectedName = nil
        writeCharacteristic = nil
        connectedPeripheral = nil
        stopSendingLoop()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        statusMessage = "Failed to connect: \(error?.localizedDescription ?? "Unknown error")"
        connectedPeripheral = nil
    }
}

// MARK: - CBPeripheralDelegate
extension ESPBluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else { return }

        for service in services where service.uuid == ESPBLEConstants.serviceUUID {
            peripheral.discoverCharacteristics([ESPBLEConstants.dataCharacteristicUUID], for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil, let characteristics = service.characteristics else { return }

        if let characteristic = characteristics.first(where: { $0.uuid == ESPBLEConstants.dataCharacteristicUUID }) {
            writeCharacteristic = characteristic
            startSendingLoop()
        }
    }
}

// MARK: - Data Helpers
private extension Data {
    mutating func appendLittleEndian(_ value: Float) {
        var little = value.bitPattern.littleEndian
        Swift.withUnsafeBytes(of: &little) { bytes in
            append(bytes.bindMemory(to: UInt8.self))
        }
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { bytes in
            append(bytes.bindMemory(to: UInt8.self))
        }
    }
}
