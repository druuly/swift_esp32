//
//  ContentView.swift
//  new_esp32
//
//  Created by Oscar Euceda on 4/1/26.
//

import SwiftUI
import CoreBluetooth

struct ContentView: View {
    @StateObject private var bleManager = BLEManager()
    @State private var inputText = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Status bar
                statusBar

                // Device list (shown when scanning or disconnected)
                if bleManager.state == .scanning || (bleManager.state == .disconnected && bleManager.discoveredDevices.isEmpty) {
                    deviceList
                }

                // Message log
                messageLog

                // Input field (only when connected)
                if bleManager.state == .connected {
                    inputField
                }
            }
            .navigationTitle("ESP32 BLE")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if bleManager.state == .disconnected || bleManager.state == .scanning {
                        Button(bleManager.state == .scanning ? "Stop" : "Scan") {
                            if bleManager.state == .scanning {
                                bleManager.stopScan()
                            } else {
                                bleManager.scan()
                            }
                        }
                    } else if bleManager.state == .connected {
                        Button("Disconnect") {
                            bleManager.disconnect()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
    }

    private var statusBar: some View {
        HStack {
            Circle()
                .fill(stateColor)
                .frame(width: 10, height: 10)
            Text(bleManager.state.rawValue)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            if let name = bleManager.connectedDeviceName {
                Text(name)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }

    private var stateColor: Color {
        switch bleManager.state {
        case .disconnected: return .red
        case .scanning: return .yellow
        case .connecting: return .orange
        case .connected: return .green
        }
    }

    private var deviceList: some View {
        Group {
            if bleManager.discoveredDevices.isEmpty && bleManager.state == .scanning {
                VStack {
                    Spacer()
                    ProgressView("Scanning for ESP32 devices...")
                    Spacer()
                }
            } else if !bleManager.discoveredDevices.isEmpty {
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
                .onChange(of: bleManager.messageLog.count) {
                    withAnimation {
                        proxy.scrollTo(bleManager.messageLog.count - 1, anchor: .bottom)
                    }
                }
            }
        }
    }

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
