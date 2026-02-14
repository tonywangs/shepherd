//
//  BLEManager.swift
//  SmartCane
//
//  Ultra-low-latency BLE communication with ESP32
//  Sends 1-byte steering commands: -1, 0, +1
//

import Foundation
import CoreBluetooth
import Combine

class BLEManager: NSObject, ObservableObject {
    // BLE UUIDs - MUST MATCH ESP32 CODE
    private let serviceUUID = CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")
    private let steeringCharUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")
    private let hapticCharUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a9")

    @Published var isConnected = false
    @Published var lastLatencyMs: Double = 0.0

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var steeringCharacteristic: CBCharacteristic?
    private var hapticCharacteristic: CBCharacteristic?

    private var lastCommandSentTime: CFAbsoluteTime = 0

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    func startScanning() {
        guard centralManager.state == .poweredOn else {
            print("[BLE] Cannot scan - Bluetooth not powered on")
            return
        }

        print("[BLE] Scanning for Smart Cane ESP32...")
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }

    func stopScanning() {
        centralManager.stopScan()
        print("[BLE] Stopped scanning")
    }

    func disconnect() {
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    // Send steering command (-1, 0, +1) as single signed byte
    func sendSteeringCommand(_ command: Int8) {
        guard let characteristic = steeringCharacteristic,
              let peripheral = connectedPeripheral,
              isConnected else {
            return
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Convert to Data (1 byte)
        var cmd = command
        let data = Data(bytes: &cmd, count: 1)

        // Write without response for lowest latency
        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)

        // Calculate latency (write + previous round trip estimate)
        let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        lastLatencyMs = latency

        lastCommandSentTime = CFAbsoluteTimeGetCurrent()

        // Debug output (throttle to avoid spam)
        if command != 0 {
            print("[BLE] Sent: \(command) | Latency: \(String(format: "%.2f", latency))ms")
        }
    }

    // Send haptic trigger command
    func sendHapticTrigger(intensity: UInt8) {
        guard let characteristic = hapticCharacteristic,
              let peripheral = connectedPeripheral,
              isConnected else {
            return
        }

        var value = intensity
        let data = Data(bytes: &value, count: 1)
        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("[BLE] Bluetooth powered on")
            startScanning()
        case .poweredOff:
            print("[BLE] Bluetooth powered off")
        case .unauthorized:
            print("[BLE] Bluetooth unauthorized")
        case .unsupported:
            print("[BLE] Bluetooth unsupported")
        default:
            print("[BLE] Bluetooth state: \(central.state.rawValue)")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                       advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("[BLE] Discovered: \(peripheral.name ?? "Unknown") | RSSI: \(RSSI)")

        // Connect to first discovered device
        connectedPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
        stopScanning()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("[BLE] Connected to \(peripheral.name ?? "Unknown")")
        isConnected = true

        // Discover services
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("[BLE] Disconnected: \(error?.localizedDescription ?? "No error")")
        isConnected = false
        connectedPeripheral = nil
        steeringCharacteristic = nil
        hapticCharacteristic = nil

        // Auto-reconnect
        print("[BLE] Attempting to reconnect...")
        startScanning()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("[BLE] Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
        connectedPeripheral = nil

        // Retry scanning
        startScanning()
    }
}

// MARK: - CBPeripheralDelegate
extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            print("[BLE] Error discovering services: \(error!.localizedDescription)")
            return
        }

        guard let services = peripheral.services else { return }

        for service in services {
            if service.uuid == serviceUUID {
                print("[BLE] Found Smart Cane service")
                peripheral.discoverCharacteristics([steeringCharUUID, hapticCharUUID], for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            print("[BLE] Error discovering characteristics: \(error!.localizedDescription)")
            return
        }

        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            if characteristic.uuid == steeringCharUUID {
                print("[BLE] Found steering characteristic")
                steeringCharacteristic = characteristic
            } else if characteristic.uuid == hapticCharUUID {
                print("[BLE] Found haptic characteristic")
                hapticCharacteristic = characteristic
            }
        }

        // Check if we have all required characteristics
        if steeringCharacteristic != nil && hapticCharacteristic != nil {
            print("[BLE] ✅ All characteristics ready - system operational")
        }
    }
}
