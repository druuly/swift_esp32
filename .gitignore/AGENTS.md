# ESP32 BLE UART with MAX30102 Heart Rate Sensor

## Project Overview

This is a simple BLE (Bluetooth Low Energy) communication project between an ESP32 Nano and an iOS app. The ESP32 reads heart rate/SpO2 data from a MAX30102 sensor and sends it to the iOS app.

## Hardware

- **ESP32 Nano** - BLE peripheral (server)
- **MAX30102** - Pulse oximeter sensor connected via I2C (GPIO 8=SDA, GPIO 9=SCL)
- **iOS device** - BLE central (client)

## Software Architecture

### ESP32 Firmware (`esp32_ble_uart/`)
- Acts as BLE server advertising as "ESP32-Nano-BLE"
- Uses Nordic UART Service (NUS) profile for serial-like BLE communication
- Reads SpO2 data from MAX30102 via I2C every 5 seconds
- Echoes received messages back to iOS app
- Sends heartbeat messages: `Heartbeat: Xs | SpO2: XX.X%`

### iOS App (`new_esp32/`)
- SwiftUI app using CoreBluetooth
- Scans for and connects to ESP32
- Displays received messages in a log
- Allows sending text commands to ESP32
- BLE UUIDs match ESP32 firmware exactly

## BLE UUIDs (must match on both sides)

| Component | UUID |
|-----------|------|
| UART Service | `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` |
| TX Characteristic (ESP32→iOS) | `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` |
| RX Characteristic (iOS→ESP32) | `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` |

## Key Files

- `esp32_ble_uart/esp32_ble_uart.ino` - Arduino/ESP-IDF firmware
- `new_esp32/new_esp32/BLEManager.swift` - CoreBluetooth logic
- `new_esp32/new_esp32/ContentView.swift` - SwiftUI interface
