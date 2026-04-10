/**
 * ESP32 BLE UART with MAX30102 Heart Rate Sensor
 * 
 * This firmware implements a BLE UART server on the ESP32 Nano that:
 * - Advertises as "ESP32-Nano-BLE" for iOS/Android apps to connect
 * - Uses Nordic UART Service (NUS) UUIDs for compatibility with standard BLE UART apps
 * - Reads heart rate/SpO2 data from a MAX30102 sensor via I2C
 * - Sends periodic heartbeat messages with sensor data to connected clients
 * - Receives messages from clients and echoes them back
 * 
 * BLE UUIDs follow the Nordic UART Service profile:
 * - Service UUID: 6E400001-B5A3-F393-E0A9-E50E24DCCA9E
 * - TX Characteristic (Server→Client): 6E400002-B5A3-F393-E0A9-E50E24DCCA9E (Notify)
 * - RX Characteristic (Client→Server): 6E400003-B5A3-F393-E0A9-E50E24DCCA9E (Write)
 * 
 * MAX30102 Wiring (ESP32 Nano):
 * - VIN  → 3.3V
 * - GND  → GND
 * - SDA  → GPIO 8
 * - SCL  → GPIO 9
 */

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Wire.h>

// =============================================================================
// BLE UUIDs - Nordic UART Service (NUS) profile for BLE serial communication
// =============================================================================
#define SERVICE_UUID           "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_TX_UUID "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_RX_UUID "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

// =============================================================================
// MAX30102 Pulse Oximeter Configuration
// =============================================================================
#define MAX30102_I2C_ADDR      0x57
#define MAX30102_PART_ID       0x15
#define MAX30102_SDA_PIN       8
#define MAX30102_SCL_PIN       9

#define REG_PART_ID            0xFF
#define REG_FIFO_DATA          0x07
#define REG_FIFO_CONFIG        0x08
#define REG_MODE_CONFIG        0x09
#define REG_MODE_CONFIG_SHDN   0x80
#define REG_SPO2_CONFIG        0x0A
#define REG_LED1_PA            0x0C
#define REG_LED2_PA            0x0D

// =============================================================================
// Global BLE Objects
// =============================================================================
BLEServer* pServer = nullptr;
BLECharacteristic* pTxCharacteristic = nullptr;
BLECharacteristic* pRxCharacteristic = nullptr;

bool deviceConnected = false;
bool oldDeviceConnected = false;
bool sensorAvailable = false;

bool isMax30102Connected() {
    Wire.beginTransmission(MAX30102_I2C_ADDR);
    return (Wire.endTransmission() == 0);
}

bool readMax30102Register(uint8_t reg, uint8_t& value) {
    Wire.beginTransmission(MAX30102_I2C_ADDR);
    Wire.write(reg);
    if (Wire.endTransmission(false) != 0) return false;
    Wire.requestFrom((int)MAX30102_I2C_ADDR, 1);
    if (Wire.available()) {
        value = Wire.read();
        return true;
    }
    return false;
}

void writeMax30102Register(uint8_t reg, uint8_t value) {
    Wire.beginTransmission(MAX30102_I2C_ADDR);
    Wire.write(reg);
    Wire.write(value);
    Wire.endTransmission();
}

void enableMax30102() {
    writeMax30102Register(REG_FIFO_CONFIG, 0x0F);
    writeMax30102Register(REG_SPO2_CONFIG, 0x27);
    writeMax30102Register(REG_MODE_CONFIG, 0x03);
    writeMax30102Register(REG_LED1_PA, 0x24);
    writeMax30102Register(REG_LED2_PA, 0x24);
}

class ServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
        deviceConnected = true;
        Serial.println("Connected");
    }

    void onDisconnect(BLEServer* pServer) {
        deviceConnected = false;
        Serial.println("Disconnected");
        pServer->getAdvertising()->start();
        Serial.println("Advertising restarted");
    }
};

class RxCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic* pCharacteristic) {
        std::string rxValue = pCharacteristic->getValue();
        if (rxValue.length() > 0) {
            Serial.print("Received: ");
            for (size_t i = 0; i < rxValue.length(); i++) {
                Serial.print(rxValue[i]);
            }
            Serial.println();

            String response = "ESP32 got: ";
            response += String(rxValue.c_str());
            pTxCharacteristic->setValue(response.c_str());
            pTxCharacteristic->notify();
        }
    }
};

void setup() {
    Serial.begin(115200);
    while (!Serial) {
        delay(10);
    }
    delay(1000);
    Serial.println("Starting BLE UART...");

    Serial.println("Checking for MAX30102 sensor...");
    Wire.begin(MAX30102_SDA_PIN, MAX30102_SCL_PIN);
    Wire.setClock(400000);
    delay(10);

    if (isMax30102Connected()) {
        uint8_t partId;
        if (readMax30102Register(REG_PART_ID, partId) && partId == MAX30102_PART_ID) {
            Serial.println("MAX30102 heart rate sensor detected!");
            sensorAvailable = true;
            enableMax30102();
        } else {
            Serial.println("MAX30102 invalid part ID");
            sensorAvailable = false;
        }
    } else {
        Serial.println("MAX30102 not found - check wiring (SDA/SCL)");
        sensorAvailable = false;
    }

    BLEDevice::init("ESP32-Nano-BLE");

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
    pAdvertising->setMinPreferred(0x06);
    pAdvertising->setMaxPreferred(0x12);
    BLEDevice::startAdvertising();

    Serial.println("Advertising started. Waiting for connection...");
}

void loop() {
    if (!deviceConnected && oldDeviceConnected) {
        delay(500);
        pServer->getAdvertising()->start();
        Serial.println("Restarting advertising");
        oldDeviceConnected = deviceConnected;
    }

    if (deviceConnected && !oldDeviceConnected) {
        oldDeviceConnected = deviceConnected;
    }

    if (deviceConnected) {
        String msg = "Heartbeat: " + String(millis() / 1000) + "s";

        if (sensorAvailable) {
            uint8_t buffer[6];
            Wire.beginTransmission(MAX30102_I2C_ADDR);
            Wire.write(REG_FIFO_DATA);
            Wire.endTransmission(false);
            Wire.requestFrom((int)MAX30102_I2C_ADDR, 6);
            
            if (Wire.available() >= 6) {
                for (int i = 0; i < 6; i++) buffer[i] = Wire.read();
                
                uint32_t red = ((uint32_t)buffer[0] << 16) | ((uint32_t)buffer[1] << 8) | buffer[2];
                uint32_t ir = ((uint32_t)buffer[3] << 16) | ((uint32_t)buffer[4] << 8) | buffer[5];
                red &= 0x3FFFF;
                ir &= 0x3FFFF;

                if (red > 0 && ir > 0) {
                    float ratio = (float)red / (float)ir;
                    float spo2 = 104.0f - 17.5f * ratio;
                    spo2 = constrain(spo2, 70.0f, 100.0f);
                    msg += " | SpO2: " + String(spo2, 1) + "%";
                }
            }
        } else {
            msg += " | Sensor: Not Connected";
        }

        pTxCharacteristic->setValue(msg.c_str());
        pTxCharacteristic->notify();
        delay(5000);
    }

    delay(100);
}
