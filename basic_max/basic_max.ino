/**
 * MAX30105 Breakout: Output all the raw Red/IR/Green readings via BLE
 * 
 * Hardware Connections (ESP32 Nano):
 * -3.3V = 3.3V
 * -GND = GND
 * -SDA = GPIO 21 (or default SDA)
 * -SCL = GPIO 22 (or default SCL)
 * -INT = Not connected
 * 
 * BLE UUIDs: Nordic UART Service (NUS) for iOS/Android compatibility
 * Service UUID: 6E400001-B5A3-F393-E0A9-E50E24DCCA9E
 * TX Characteristic: 6E400002-B5A3-F393-E0A9-E50E24DCCA9E (Notify)
 * RX Characteristic: 6E400003-B5A3-F393-E0A9-E50E24DCCA9E (Write)
 */

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Wire.h>
#include "MAX30105.h"

#define SERVICE_UUID           "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_TX_UUID "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_RX_UUID "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

// BLE global objects
BLEServer* pServer = nullptr;
BLECharacteristic* pTxCharacteristic = nullptr;
BLECharacteristic* pRxCharacteristic = nullptr;

bool deviceConnected = false;
bool oldDeviceConnected = false;
bool sensorAvailable = false;

MAX30105 particleSensor;

class ServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
        deviceConnected = true;
    }
    void onDisconnect(BLEServer* pServer) {
        deviceConnected = false;
        pServer->getAdvertising()->start();
    }
};

class RxCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic* pCharacteristic) {
        Serial.println("RX received");
    }
};

void setup() {
    Serial.begin(115200);
    delay(1000);
    
    Serial.println("MAX30105 BLE Starting...");
    
    if (particleSensor.begin() == false) {
        Serial.println("MAX30105 was not found. Please check wiring/power.");
    } else {
        sensorAvailable = true;
        particleSensor.setup();
        Serial.println("MAX30105 ready");
    }

    BLEDevice::init("MAX30105-BLE");
    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new ServerCallbacks());

    BLEService* pService = pServer->createService(SERVICE_UUID);

    pTxCharacteristic = pService->createCharacteristic(
        CHARACTERISTIC_TX_UUID,
        BLECharacteristic::PROPERTY_NOTIFY
    );
    pTxCharacteristic->addDescriptor(new BLE2902());

    pRxCharacteristic = pService->createCharacteristic(
        CHARACTERISTIC_RX_UUID,
        BLECharacteristic::PROPERTY_WRITE
    );
    pRxCharacteristic->setCallbacks(new RxCallbacks());

    pService->start();

    BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID);
    pAdvertising->setScanResponse(true);
    BLEDevice::startAdvertising();

    Serial.println("Advertising...");
}

void loop() {
    if (!deviceConnected && oldDeviceConnected) {
        delay(500);
        pServer->getAdvertising()->start();
        oldDeviceConnected = deviceConnected;
    }
    if (deviceConnected && !oldDeviceConnected) {
        oldDeviceConnected = deviceConnected;
    }

    if (deviceConnected) {
        String msg;
        if (sensorAvailable) {
            uint32_t red = particleSensor.getRed();
            uint32_t ir = particleSensor.getIR();
            uint32_t green = particleSensor.getGreen();
            msg = " R[" + String(red) + "] IR[" + String(ir) + "] G[" + String(green) + "]";
        } else {
            msg = " Sensor: Not Connected";
        }
        
        Serial.println(msg);
        pTxCharacteristic->setValue(msg.c_str());
        pTxCharacteristic->notify();
    }

    delay(100);
}
