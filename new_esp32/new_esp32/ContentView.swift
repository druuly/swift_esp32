//
//  ContentView.swift
//  new_esp32
//
//  BLE UART Terminal Interface
//  Allows connecting to ESP32 BLE server and exchanging serial-like messages
//
//  Created by Oscar Euceda on 4/1/26.
//

import SwiftUI
import CoreBluetooth

/// Main view for the BLE UART app.
/// 
/// UI Layout (top to bottom):
/// 1. Status bar - Shows connection state and device name
/// 2. Device list - Scrolling list of discovered ESP32 devices (when scanning/disconnected)
/// 3. Message log - Timestamped log of sent/received messages
/// 4. Input field - Text field to send messages to ESP32 (only when connected)
///
/// State-based UI:
/// - Disconnected: Shows Scan button, empty device list
/// - Scanning: Shows Stop button, device list with progress indicator
/// - Connecting: Shows Disconnect button, message log
/// - Connected: Shows Disconnect button, message log, input field
struct ContentView: View {
    /// BLEManager is marked @StateObject so it's created once and persists across view updates
    @StateObject private var bleManager = BLEManager()
    /// Local state for the text field input (cleared after sending)
    @State private var inputText = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Connection status indicator with device name
                statusBar

                // Device list - visible when scanning OR when disconnected with no devices
                // Shows either: (1) scanning progress, or (2) list of found devices
                if bleManager.state == .scanning || (bleManager.state == .disconnected && bleManager.discoveredDevices.isEmpty) {
                    deviceList
                }

                // Message log - always visible, shows all BLE activity
                messageLog

                // Sensor readings - visible when connected
                if bleManager.state == .connected {
                    sensorReadings
                }

                // Input field - only visible when connected to ESP32
                if bleManager.state == .connected {
                    inputField
                }
            }
            .navigationTitle("ESP32 BLE")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    // Dynamic toolbar button based on connection state
                    if bleManager.state == .disconnected || bleManager.state == .scanning {
                        // Toggle between Scan and Stop based on current state
                        Button(bleManager.state == .scanning ? "Stop" : "Scan") {
                            if bleManager.state == .scanning {
                                bleManager.stopScan()
                            } else {
                                bleManager.scan()
                            }
                        }
                    } else if bleManager.state == .connected {
                        // Disconnect button (red to indicate destructive action)
                        Button("Disconnect") {
                            bleManager.disconnect()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
    }

    // =============================================================================
    // Status Bar View
    // =============================================================================
    
    /// Displays current connection state with color indicator and device name
    private var statusBar: some View {
        HStack {
            // Colored circle indicating state: red=disconnected, yellow=scanning, orange=connecting, green=connected
            Circle()
                .fill(stateColor)
                .frame(width: 10, height: 10)
            Text(bleManager.state.rawValue)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            // Show connected device name if we have one
            if let name = bleManager.connectedDeviceName {
                Text(name)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }

    /// Maps BLEState enum to UI color for status indicator
    private var stateColor: Color {
        switch bleManager.state {
        case .disconnected: return .red
        case .scanning: return .yellow
        case .connecting: return .orange
        case .connected: return .green
        }
    }

    // =============================================================================
    // Device List View
    // =============================================================================
    
    /**
     * Shows either:
     * - A centered progress spinner when scanning but no devices found yet
     * - A scrollable List of discovered devices when results are available
     * 
     * Tapping a device initiates connection via bleManager.connect()
     */
    private var deviceList: some View {
        Group {
            // No devices found yet - show spinner
            if bleManager.discoveredDevices.isEmpty && bleManager.state == .scanning {
                VStack {
                    Spacer()
                    ProgressView("Scanning for ESP32 devices...")
                    Spacer()
                }
            } else if !bleManager.discoveredDevices.isEmpty {
                // Devices available - show scrollable list
                List(bleManager.discoveredDevices, id: \.identifier) { device in
                    Button(action: {
                        bleManager.connect(to: device)
                    }) {
                        VStack(alignment: .leading) {
                            Text(device.name ?? "Unknown Device")
                                .font(.headline)
                            Text(device.identifier.uuidString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    // =============================================================================
    // Message Log View
    // =============================================================================
    
    /**
     * Scrollable log showing all BLE activity with timestamps.
     * Automatically scrolls to newest message when log grows.
     * 
     * Uses ScrollViewReader for programmatic scrolling to bottom.
     * onChange triggers scroll when messageLog.count changes.
     */
    private var messageLog: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(bleManager.messageLog.indices, id: \.self) { index in
                        Text(bleManager.messageLog[index])
                            .font(.system(.caption2, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6))
                            .cornerRadius(4)
                    }
                }
                .padding()
                // Auto-scroll to bottom when new messages arrive
                .onChange(of: bleManager.messageLog.count) {
                    withAnimation {
                        proxy.scrollTo(bleManager.messageLog.count - 1, anchor: .bottom)
                    }
                }
            }
        }
    }

    // =============================================================================
    // Sensor Readings View
    // =============================================================================
    
    private var sensorReadings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MAX30102 Readings")
                .font(.headline)
                .padding(.horizontal)
            
            HStack {
                VStack {
                    Text("IR")
                        .font(.caption)
                    Text("\(bleManager.irValue)")
                        .font(.system(.title3, design: .monospaced))
                }
                .frame(maxWidth: .infinity)
                
                VStack {
                    Text("BPM")
                        .font(.caption)
                    Text("\(bleManager.bpm)")
                        .font(.system(.title3, design: .monospaced))
                }
                .frame(maxWidth: .infinity)
                
                VStack {
                    Text("Avg BPM")
                        .font(.caption)
                    Text("\(bleManager.avgBpm)")
                        .font(.system(.title3, design: .monospaced))
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
            
            HStack {
                Circle()
                    .fill(bleManager.fingerOnSensor ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(bleManager.fingerOnSensor ? "Finger on sensor" : "Place finger on sensor")
                    .font(.caption)
                    .foregroundColor(bleManager.fingerOnSensor ? .green : .red)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)
        }
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .padding()
    }

    // =============================================================================
    // Input Field View
    // =============================================================================
    
    /**
     * Text input field for composing messages to send to ESP32.
     * Only visible when connected.
     * Clears input field after sending to prevent duplicate sends.
     */
    private var inputField: some View {
        HStack {
            TextField("Enter message...", text: $inputText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            Button("Send") {
                if !inputText.isEmpty {
                    bleManager.send(inputText)
                    inputText = ""
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
