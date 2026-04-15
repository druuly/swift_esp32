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
#define REG_RED_DATA           0x06
#define REG_IR_DATA            0x05
#define REG_GREEN_DATA         0x04

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

uint32_t getMax30102Red() {
    uint8_t buffer[3];
    Wire.beginTransmission(MAX30102_I2C_ADDR);
    Wire.write(REG_RED_DATA);
    Wire.endTransmission(false);
    Wire.requestFrom((int)MAX30102_I2C_ADDR, 3);
    if (Wire.available() >= 3) {
        buffer[0] = Wire.read();
        buffer[1] = Wire.read();
        buffer[2] = Wire.read();
        return ((uint32_t)buffer[0] << 16) | ((uint32_t)buffer[1] << 8) | buffer[2];
    }
    return 0;
}

uint32_t getMax30102IR() {
    uint8_t buffer[3];
    Wire.beginTransmission(MAX30102_I2C_ADDR);
    Wire.write(REG_IR_DATA);
    Wire.endTransmission(false);
    Wire.requestFrom((int)MAX30102_I2C_ADDR, 3);
    if (Wire.available() >= 3) {
        buffer[0] = Wire.read();
        buffer[1] = Wire.read();
        buffer[2] = Wire.read();
        return ((uint32_t)buffer[0] << 16) | ((uint32_t)buffer[1] << 8) | buffer[2];
    }
    return 0;
}

uint32_t getMax30102Green() {
    uint8_t buffer[3];
    Wire.beginTransmission(MAX30102_I2C_ADDR);
    Wire.write(REG_GREEN_DATA);
    Wire.endTransmission(false);
    Wire.requestFrom((int)MAX30102_I2C_ADDR, 3);
    if (Wire.available() >= 3) {
        buffer[0] = Wire.read();
        buffer[1] = Wire.read();
        buffer[2] = Wire.read();
        return ((uint32_t)buffer[0] << 16) | ((uint32_t)buffer[1] << 8) | buffer[2];
    }
    return 0;
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
        String rxValue = pCharacteristic->getValue();
        if (rxValue.length() > 0) {
            Serial.print("Received: ");
            Serial.println(rxValue);

            String response = "ESP32 got: " + rxValue;
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
        String msg = "";

        if (sensorAvailable) {
            uint32_t red = getMax30102Red();
            uint32_t ir = getMax30102IR();
            uint32_t green = getMax30102Green();

            red &= 0x3FFFF;
            ir &= 0x3FFFF;
            green &= 0x3FFFF;

            msg = " R[" + String(red) + "] IR[" + String(ir) + "] G[" + String(green) + "]";
        } else {
            msg = " Sensor: Not Connected";
        }

        Serial.println(msg);
        pTxCharacteristic->setValue(msg.c_str());
        pTxCharacteristic->notify();
        delay(100);
    }

    delay(100);
}
