/**
 * BLEManager - Core Bluetooth logic for connecting to ESP32 BLE UART server
 * 
 * Architecture:
 * - Uses CoreBluetooth framework (Apple's BLE API for iOS)
 * - Implements CBCentralManagerDelegate for managing the BLE connection lifecycle
 * - Implements CBPeripheralDelegate for handling communication with ESP32
 * - Uses @Published properties with Combine to automatically update SwiftUI views
 * 
 * BLE Role: iOS app acts as "Central" device, ESP32 is the "Peripheral"
 * 
 * Service Discovery Flow:
 * 1. Scan for peripherals advertising the UART service UUID
 * 2. Connect to chosen peripheral
 * 3. Discover the UART service
 * 4. Discover TX and RX characteristics
 * 5. Subscribe to TX notifications (to receive ESP32 data)
 * 6. Use RX characteristic to send commands to ESP32
 */

import Foundation
import CoreBluetooth
import Combine

/// Main BLE manager class that handles all Bluetooth Low Energy operations.
/// Acts as the bridge between the SwiftUI UI and CoreBluetooth APIs.
class BLEManager: NSObject, ObservableObject {
    // =============================================================================
    // CoreBluetooth Objects
    // =============================================================================
    private var centralManager: CBCentralManager!     // Manages BLE scanning and connections
    private var peripheral: CBPeripheral?            // The connected ESP32 device
    private var uartService: CBService?               // Nordic UART Service on ESP32
    private var txCharacteristic: CBCharacteristic?   // TX: ESP32→iOS (receive notifications)
    private var rxCharacteristic: CBCharacteristic?   // RX: iOS→ESP32 (send commands)

    // =============================================================================
    // Published Properties (SwiftUI bindings)
    // These @Published properties automatically trigger UI updates when changed
    // =============================================================================
    @Published var state: BLEState = .disconnected           // Current connection state
    @Published var messageLog: [String] = []                // Timestamped log messages for UI
    @Published var discoveredDevices: [CBPeripheral] = []    // List of found ESP32 devices
    @Published var connectedDeviceName: String?             // Name of connected device
    @Published var redValue: UInt32 = 0                      // MAX30102 Red reading
    @Published var irValue: UInt32 = 0                       // MAX30102 IR reading
    @Published var greenValue: UInt32 = 0                    // MAX30102 Green reading
    @Published var bpm: Int = 0                              // Current BPM
    @Published var avgBpm: Int = 0                           // Average BPM
    @Published var fingerOnSensor: Bool = true               // Finger detection
    @Published var bpmHistory: [(Date, Int)] = []          // BPM over time for graphing

    // =============================================================================
    // BLE UUIDs - Must match the ESP32 firmware exactly
    // Nordic UART Service (NUS) provides serial-like communication over BLE
    // =============================================================================
    private let uartServiceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private let txCharacteristicUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    private let rxCharacteristicUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

    /**
     * Initialize the BLE manager and central manager.
     * CBCentralManagerDelegate callbacks will be received on the main thread (queue: nil).
     */
    override init() {
        super.init()
        // Creating CBCentralManager triggers centralManagerDidUpdateState delegate call
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // =============================================================================
    // Public API - Called from SwiftUI to control BLE operations
    // =============================================================================

    /**
     * Starts scanning for BLE peripherals advertising the UART service.
     * Filters scan results to only show ESP32 devices.
     * Updates state to .scanning and populates discoveredDevices list.
     */
    func scan() {
        // Bluetooth must be powered on before scanning
        guard centralManager.state == .poweredOn else {
            addLog("Bluetooth not powered on")
            return
        }
        // Clear previous scan results
        discoveredDevices.removeAll()
        state = .scanning
        addLog("Scanning for devices...")
        // scanForPeripherals with service UUIDs filters to only UART devices
        centralManager.scanForPeripherals(withServices: [uartServiceUUID], options: nil)
    }

    /**
     * Stops the current BLE scan.
     * If we were scanning, returns to disconnected state.
     */
    func stopScan() {
        centralManager.stopScan()
        if state == .scanning {
            state = .disconnected
        }
    }

    /**
     * Initiates connection to a selected peripheral (ESP32 device).
     * This is the "connect" action triggered when user taps a device in the list.
     * 
     * @param peripheral The CBPeripheral device to connect to
     */
    func connect(to peripheral: CBPeripheral) {
        stopScan()  // Stop scanning when connecting (saves power)
        self.peripheral = peripheral
        peripheral.delegate = self  // Receive peripheral delegate callbacks
        state = .connecting
        connectedDeviceName = peripheral.name ?? "Unknown"
        addLog("Connecting to \(peripheral.name ?? "Unknown")...")
        centralManager.connect(peripheral, options: nil)
    }

    /**
     * Disconnects from the currently connected peripheral.
     * Uses cancelPeripheralConnection which triggers didDisconnectPeripheral delegate.
     */
    func disconnect() {
        guard let peripheral = peripheral else { return }
        centralManager.cancelPeripheralConnection(peripheral)
    }

    /**
     * Sends a text message to the ESP32 via the RX characteristic.
     * Messages are encoded as UTF-8 data and written with response type.
     * 
     * @param message The string to send to the ESP32
     */
    func send(_ message: String) {
        guard let rxCharacteristic = rxCharacteristic,
              let peripheral = peripheral,
              peripheral.state == .connected else {
            addLog("Not connected")
            return
        }
        let data = message.data(using: .utf8)!
        // .withResponse: ESP32 will acknowledge receipt (triggers callback)
        peripheral.writeValue(data, for: rxCharacteristic, type: .withResponse)
        addLog("Sent: \(message)")
    }

    /**
     * Adds a timestamped message to the log.
     * Thread-safe: dispatches to main thread for SwiftUI updates.
     * Maintains a rolling buffer of max 100 messages to prevent memory issues.
     * 
     * @param message The log message to add
     */
    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        DispatchQueue.main.async {
            self.messageLog.append("[\(timestamp)] \(message)")
            // Keep log size bounded to prevent memory growth
            if self.messageLog.count > 100 {
                self.messageLog.removeFirst()
            }
        }
    }
}

// =============================================================================
// CBCentralManagerDelegate - Handles BLE state changes and connection events
// =============================================================================

extension BLEManager: CBCentralManagerDelegate {
    /**
     * Called whenever Bluetooth state changes (powered on/off, unauthorized, etc.).
     * This is the first delegate method called after CBCentralManager creation.
     * 
     * @param central The CBCentralManager that updated its state
     */
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

    /**
     * Called when a peripheral is discovered during scanning.
     * Filters out duplicates using the peripheral's unique identifier.
     * 
     * @param peripheral The discovered peripheral device
     * @param advertisementData Advertisement data including local name, TX power, etc.
     * @param rssi Signal strength in dBm (negative value, closer to 0 = stronger)
     */
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // Avoid adding duplicates (same peripheral may appear multiple times)
        if !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredDevices.append(peripheral)
            addLog("Found: \(peripheral.name ?? "Unknown")")
        }
    }

    /**
     * Called when connection to a peripheral succeeds.
     * After connecting, we must discover services to know what the device offers.
     * 
     * @param peripheral The peripheral that was successfully connected
     */
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        addLog("Connected to \(peripheral.name ?? "Unknown")")
        state = .connected
        // Discover services - this triggers didDiscoverServices delegate callback
        peripheral.discoverServices([uartServiceUUID])
    }

    /**
     * Called when connection attempt fails.
     * 
     * @param peripheral The peripheral that failed to connect
     * @param error Error describing why the connection failed
     */
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        state = .disconnected
        addLog("Connection failed: \(error?.localizedDescription ?? "Unknown error")")
    }

    /**
     * Called when an established connection is lost (disconnect).
     * Cleans up all characteristic and service references.
     * 
     * @param peripheral The peripheral that was disconnected
     * @param error If non-nil, indicates unexpected disconnect (e.g., connection lost)
     */
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        state = .disconnected
        // Clear all references to disconnected device's services/characteristics
        uartService = nil
        txCharacteristic = nil
        rxCharacteristic = nil
        addLog("Disconnected")
    }
}

// =============================================================================
// CBPeripheralDelegate - Handles communication with the connected ESP32
// =============================================================================

extension BLEManager: CBPeripheralDelegate {
    /**
     * Called after services are discovered on the connected peripheral.
     * Once UART service is found, discovers its characteristics.
     * 
     * @param peripheral The peripheral whose services were discovered
     * @param error Error if service discovery failed
     */
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            addLog("Service discovery error: \(error.localizedDescription)")
            return
        }
        guard let services = peripheral.services else { return }
        for service in services {
            if service.uuid == uartServiceUUID {
                uartService = service
                // Discover TX and RX characteristics within the UART service
                peripheral.discoverCharacteristics([txCharacteristicUUID, rxCharacteristicUUID], for: service)
                addLog("Found UART service")
            }
        }
    }

    /**
     * Called after characteristics are discovered within a service.
     * Configures TX for notifications (to receive ESP32 data).
     * Stores reference to RX for sending commands.
     * 
     * @param service The service containing the discovered characteristics
     * @param error Error if characteristic discovery failed
     */
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            addLog("Characteristic discovery error: \(error.localizedDescription)")
            return
        }
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == txCharacteristicUUID {
                // TX characteristic: ESP32 sends data to iOS via notifications
                txCharacteristic = characteristic
                // Subscribe to notifications - triggers didUpdateNotificationStateFor callback
                peripheral.setNotifyValue(true, for: characteristic)
                addLog("Found TX characteristic (notifications enabled)")
            } else if characteristic.uuid == rxCharacteristicUUID {
                // RX characteristic: iOS sends commands to ESP32 via writes
                rxCharacteristic = characteristic
                addLog("Found RX characteristic")
            }
        }
    }

    /**
     * Called when notification state changes for a characteristic (enabled/disabled).
     * This confirms that TX notifications are now active.
     * 
     * @param characteristic The characteristic whose notification state changed
     * @param error Error if state change failed
     */
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            addLog("Notification error: \(error.localizedDescription)")
        }
        if characteristic.uuid == txCharacteristicUUID {
            addLog("TX notifications \(characteristic.isNotifying ? "enabled" : "disabled")")
        }
    }

    /**
     * Called when a characteristic value is updated.
     * This is how we receive data from the ESP32 (TX notifications).
     * 
     * @param characteristic The characteristic that received new value
     * @param error Error if value update failed
     */
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            addLog("Value update error: \(error.localizedDescription)")
            return
        }
        if characteristic.uuid == txCharacteristicUUID,
           let data = characteristic.value,
           let message = String(data: data, encoding: .utf8) {
            addLog("Received: \(message)")
            
            if message.contains("Place finger") {
                DispatchQueue.main.async {
                    self.fingerOnSensor = false
                    self.bpm = 0
                    self.avgBpm = 0
                    self.bpmHistory.removeAll()
                }
            } else if message.contains("Heartbeat:") {
                if let irRange = message.range(of: "IR\\[[0-9]+\\]", options: .regularExpression) {
                    let irStr = message[irRange].replacingOccurrences(of: "IR[", with: "").replacingOccurrences(of: "]", with: "")
                    DispatchQueue.main.async {
                        self.irValue = UInt32(irStr) ?? 0
                    }
                }
                if let bpmRange = message.range(of: "Heartbeat:[0-9]+", options: .regularExpression) {
                    let bpmStr = message[bpmRange]
                        .replacingOccurrences(of: "Heartbeat:", with: "")
                        .replacingOccurrences(of: " BPM", with: "")
                    DispatchQueue.main.async {
                        self.fingerOnSensor = true
                        self.bpm = Int(bpmStr) ?? 0
                        self.avgBpm = Int(bpmStr) ?? 0
                        self.bpmHistory.append((Date(), self.bpm))
                        if self.bpmHistory.count > 120 {
                            self.bpmHistory.removeFirst()
                        }
                    }
                }
            }
            
            if let redRange = message.range(of: "R\\[[0-9]+\\]", options: .regularExpression),
               let irRange = message.range(of: "IR\\[[0-9]+\\]", options: .regularExpression),
               let greenRange = message.range(of: "G\\[[0-9]+\\]", options: .regularExpression) {
                let redStr = message[redRange].replacingOccurrences(of: "R[", with: "").replacingOccurrences(of: "]", with: "")
                let irStr = message[irRange].replacingOccurrences(of: "IR[", with: "").replacingOccurrences(of: "]", with: "")
                let greenStr = message[greenRange].replacingOccurrences(of: "G[", with: "").replacingOccurrences(of: "]", with: "")
                
                DispatchQueue.main.async {
                    self.redValue = UInt32(redStr) ?? 0
                    self.irValue = UInt32(irStr) ?? 0
                    self.greenValue = UInt32(greenStr) ?? 0
                }
            }
        }
    }
}

// =============================================================================
// BLEState - Connection state enum for UI representation
// =============================================================================

/// Represents the current state of the BLE connection.
/// Used by SwiftUI to conditionally render UI elements.
enum BLEState: String {
    case disconnected = "Disconnected"
    case scanning = "Scanning"
    case connecting = "Connecting"
    case connected = "Connected"
}
