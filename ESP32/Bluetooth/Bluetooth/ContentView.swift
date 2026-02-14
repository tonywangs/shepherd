import SwiftUI
import CoreBluetooth

private enum BLEConstants {
    static let serviceUUID = CBUUID(string: "8A4E1E45-1E84-4AA2-B4B8-3D960D6CE001")
    static let dataCharacteristicUUID = CBUUID(string: "8A4E1E45-1E84-4AA2-B4B8-3D960D6CE002")
}

struct DiscoveredPeripheral: Identifiable {
    let id: UUID
    let peripheral: CBPeripheral
    var name: String
    var rssi: NSNumber
}

@MainActor
final class BLEManager: NSObject, ObservableObject {
    @Published var isBluetoothReady = false
    @Published var isScanning = false
    @Published var discoveredPeripherals: [DiscoveredPeripheral] = []
    @Published var connectedName: String?
    @Published var statusMessage: String?

    @Published var angle: Float = 0
    @Published var distance: Float = 0
    @Published var mode: Float = 0

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var sendTimer: Timer?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func toggleScan() {
        guard isBluetoothReady else {
            statusMessage = "Bluetooth is not ready yet. Use a physical iPhone, enable Bluetooth, and grant app permission in Settings > Privacy & Security > Bluetooth."
            return
        }

        if isScanning {
            centralManager.stopScan()
            isScanning = false
        } else {
            discoveredPeripherals = []
            centralManager.scanForPeripherals(withServices: [BLEConstants.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
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

        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(packet, for: characteristic, type: writeType)
    }
}

extension BLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            isBluetoothReady = central.state == .poweredOn
            if !isBluetoothReady {
                isScanning = false
                discoveredPeripherals = []
                connectedName = nil
                stopSendingLoop()

                statusMessage = switch central.state {
                case .unauthorized:
                    "Bluetooth permission denied. Enable it in Settings > Privacy & Security > Bluetooth."
                case .unsupported:
                    "This device does not support BLE central mode."
                case .poweredOff:
                    "Bluetooth is off. Turn it on in iPhone Settings."
                case .resetting, .unknown:
                    "Bluetooth is initializing. Try scan again in a moment."
                @unknown default:
                    "Bluetooth is currently unavailable."
                }
            } else {
                statusMessage = nil
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
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
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            connectedName = peripheral.name ?? "ESP32"
            peripheral.discoverServices([BLEConstants.serviceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        Task { @MainActor in
            connectedName = nil
            writeCharacteristic = nil
            connectedPeripheral = nil
            stopSendingLoop()
        }
    }
}

extension BLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard error == nil, let services = peripheral.services else { return }

        for service in services where service.uuid == BLEConstants.serviceUUID {
            peripheral.discoverCharacteristics([BLEConstants.dataCharacteristicUUID], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        guard error == nil, let characteristics = service.characteristics else { return }

        if let characteristic = characteristics.first(where: { $0.uuid == BLEConstants.dataCharacteristicUUID }) {
            Task { @MainActor in
                writeCharacteristic = characteristic
                startSendingLoop()
            }
        }
    }
}

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

struct ContentView: View {
    @StateObject private var ble = BLEManager()

    var body: some View {
        NavigationStack {
            Form {
                Section("Bluetooth") {
                    HStack {
                        Label(ble.isBluetoothReady ? "Powered On" : "Unavailable", systemImage: ble.isBluetoothReady ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle")
                            .foregroundStyle(ble.isBluetoothReady ? .green : .red)
                        Spacer()
                        Button(ble.isScanning ? "Stop Scan" : "Scan") {
                            ble.toggleScan()
                        }
                    }

                    if let connectedName = ble.connectedName {
                        HStack {
                            Text("Connected: \(connectedName)")
                            Spacer()
                            Button("Disconnect", role: .destructive) {
                                ble.disconnect()
                            }
                        }
                    }

                    if let statusMessage = ble.statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if ble.discoveredPeripherals.isEmpty {
                        Text("No ESP32 devices found yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(ble.discoveredPeripherals) { device in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(device.name)
                                    Text("RSSI: \(device.rssi)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Pair") {
                                    ble.connect(device.peripheral)
                                }
                            }
                        }
                    }
                }

                Section("Outgoing fields (10 Hz)") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Angle: \(ble.angle, specifier: "%.2f")")
                        Slider(value: $ble.angle, in: -180...180)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Distance: \(ble.distance, specifier: "%.2f")")
                        Slider(value: $ble.distance, in: 0...100)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mode: \(Int(ble.mode.rounded()))")
                        Slider(value: $ble.mode, in: 0...10, step: 1)
                    }
                }
            }
            .navigationTitle("ESP32 BLE Sender")
        }
    }
}

#Preview {
    ContentView()
}
