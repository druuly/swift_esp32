#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#define SERVICE_UUID           "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_TX_UUID "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_RX_UUID "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

BLEServer* pServer = nullptr;
BLECharacteristic* pTxCharacteristic = nullptr;
BLECharacteristic* pRxCharacteristic = nullptr;
bool deviceConnected = false;
bool oldDeviceConnected = false;

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
        pTxCharacteristic->setValue(msg.c_str());
        pTxCharacteristic->notify();
        delay(5000);
    }

    delay(100);
}
