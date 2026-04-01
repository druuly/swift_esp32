import Foundation
import CoreBluetooth
import Combine

class BLEManager: NSObject, ObservableObject {
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var uartService: CBService?
    private var txCharacteristic: CBCharacteristic?
    private var rxCharacteristic: CBCharacteristic?

    @Published var state: BLEState = .disconnected
    @Published var messageLog: [String] = []
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var connectedDeviceName: String?

    private let uartServiceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private let txCharacteristicUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    private let rxCharacteristicUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func scan() {
        guard centralManager.state == .poweredOn else {
            addLog("Bluetooth not powered on")
            return
        }
        discoveredDevices.removeAll()
        state = .scanning
        addLog("Scanning for devices...")
        centralManager.scanForPeripherals(withServices: [uartServiceUUID], options: nil)
    }

    func stopScan() {
        centralManager.stopScan()
        if state == .scanning {
            state = .disconnected
        }
    }

    func connect(to peripheral: CBPeripheral) {
        stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        state = .connecting
        connectedDeviceName = peripheral.name ?? "Unknown"
        addLog("Connecting to \(peripheral.name ?? "Unknown")...")
        centralManager.connect(peripheral, options: nil)
    }

    func disconnect() {
        guard let peripheral = peripheral else { return }
        centralManager.cancelPeripheralConnection(peripheral)
    }

    func send(_ message: String) {
        guard let rxCharacteristic = rxCharacteristic,
              let peripheral = peripheral,
              peripheral.state == .connected else {
            addLog("Not connected")
            return
        }
        let data = message.data(using: .utf8)!
        peripheral.writeValue(data, for: rxCharacteristic, type: .withResponse)
        addLog("Sent: \(message)")
    }

    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        DispatchQueue.main.async {
            self.messageLog.append("[\(timestamp)] \(message)")
            if self.messageLog.count > 100 {
                self.messageLog.removeFirst()
            }
        }
    }
}

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            addLog("Bluetooth powered on")
        case .poweredOff:
            state = .disconnected
            addLog("Bluetooth powered off")
        case .unauthorized:
            addLog("Bluetooth unauthorized")
        case .unsupported:
            addLog("Bluetooth unsupported")
        default:
            addLog("Bluetooth state: \(central.state.rawValue)")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredDevices.append(peripheral)
            addLog("Found: \(peripheral.name ?? "Unknown")")
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        addLog("Connected to \(peripheral.name ?? "Unknown")")
        state = .connected
        peripheral.discoverServices([uartServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        state = .disconnected
        addLog("Connection failed: \(error?.localizedDescription ?? "Unknown error")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        state = .disconnected
        uartService = nil
        txCharacteristic = nil
        rxCharacteristic = nil
        addLog("Disconnected")
    }
}

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            addLog("Service discovery error: \(error.localizedDescription)")
            return
        }
        guard let services = peripheral.services else { return }
        for service in services {
            if service.uuid == uartServiceUUID {
                uartService = service
                peripheral.discoverCharacteristics([txCharacteristicUUID, rxCharacteristicUUID], for: service)
                addLog("Found UART service")
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            addLog("Characteristic discovery error: \(error.localizedDescription)")
            return
        }
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == txCharacteristicUUID {
                txCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                addLog("Found TX characteristic (notifications enabled)")
            } else if characteristic.uuid == rxCharacteristicUUID {
                rxCharacteristic = characteristic
                addLog("Found RX characteristic")
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            addLog("Notification error: \(error.localizedDescription)")
        }
        if characteristic.uuid == txCharacteristicUUID {
            addLog("TX notifications \(characteristic.isNotifying ? "enabled" : "disabled")")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            addLog("Value update error: \(error.localizedDescription)")
            return
        }
        if characteristic.uuid == txCharacteristicUUID,
           let data = characteristic.value,
           let message = String(data: data, encoding: .utf8) {
            addLog("Received: \(message)")
        }
    }
}

enum BLEState: String {
    case disconnected = "Disconnected"
    case scanning = "Scanning"
    case connecting = "Connecting"
    case connected = "Connected"
}
