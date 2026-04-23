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

const byte RATE_SIZE = 4;
byte rates[RATE_SIZE];
byte rateSpot = 0;
long lastBeat = 0;
float beatsPerMinute = 0;
int beatAvg = 0;

long tsLastReport = 0;
long currentTime = 0;

bool checkForBeat(long irValue)
{
    bool beatDetected = false;
    static long lastBeatTime = 0;
    static long averageIR = 0;
    static int beatCount = 0;
    
    averageIR = averageIR * 0.95 + irValue * 0.05;
    long delta = irValue - averageIR;
    
    if (delta > 50 && (millis() - lastBeatTime) > 300) {
        beatDetected = true;
        lastBeatTime = millis();
    }
    
    return beatDetected;
}

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
        particleSensor.setPulseAmplitudeRed(0x0A);
        particleSensor.setPulseAmplitudeGreen(0);
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

    if (sensorAvailable) {
        long irValue = particleSensor.getIR();

        if (checkForBeat(irValue) == true) {
            long delta = millis() - lastBeat;
            lastBeat = millis();

            beatsPerMinute = 60 / (delta / 1000.0);

            if (beatsPerMinute < 255 && beatsPerMinute > 20) {
                rates[rateSpot++] = (byte)beatsPerMinute;
                rateSpot %= RATE_SIZE;

                beatAvg = 0;
                for (byte x = 0 ; x < RATE_SIZE ; x++)
                    beatAvg += rates[x];
                beatAvg /= RATE_SIZE;
            }
        }

        Serial.print("IR=");
        Serial.print(irValue);
        Serial.print(", BPM=");
        Serial.print(beatsPerMinute);
        Serial.print(", Avg BPM=");
        Serial.print(beatAvg);

        if (irValue < 50000)
            Serial.print(" No finger?");

        Serial.println();

        if (deviceConnected) {
            String msg;
            if (irValue < 50000) {
                msg = "Place finger on sensor";
            } else {
                msg = "Heartbeat: " + String(beatAvg) + " BPM";
            }
            
            pTxCharacteristic->setValue(msg.c_str());
            pTxCharacteristic->notify();
        }
    }

    delay(100);
}
