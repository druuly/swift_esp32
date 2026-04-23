# MAX30102 Wiring Guide for ESP32 Nano

## Connections

| MAX30102 Module | ESP32 Nano |
|-----------------|------------|
| VIN             | 3.3V       |
| GND             | GND        |
| SDA             | A4 (GPIO 1)     |
| SCL             | A5 (GPIO 2)     |

## Important Notes

- **Use 3.3V**, not 5V. The MAX30102 is a 3.3V device and can be damaged by 5V.
- The ESP32 Nano has 3.3V logic levels, so no level shifting is needed.
- SDA/SCL pins (GPIO 6/8) correspond to the correct Arduino pins (D3/D5) for I2C on the ESP32 Nano.

## Quick Check

After wiring and uploading, check the Serial Monitor (115200 baud). You should see:

```
Starting BLE UART...
Checking for MAX30102 sensor...
MAX30102 heart rate sensor detected!
```

Or if wiring is incorrect:

```
Starting BLE UART...
Checking for MAX30102 sensor...
MAX30102 not found - check wiring (SDA/SCL)
```

## Troubleshooting

1. **No detection**: Check SDA/SCL connections, ensure 3.3V is connected
2. **Intermittent readings**: Check for loose wires, ensure good ground connection
3. **Wrong values**: Make sure the sensor is positioned correctly (see sensor usage guide)
