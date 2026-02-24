# Stationary Sensors Information

> Documentation for environmental monitoring sensors used in the agrivoltaics system for measuring agricultural and atmospheric conditions.

## Overview

| Sensor Type | Measurements | Interface |
|------------|--------------|-----------|
| DHT22 Temperature/Humidity | Temperature, Humidity | Digital |
| VEML7700 Light | Ambient Light | I2C |
| DFRobot Soil Sensor | Soil Temperature, Moisture, EC | RS485/MODBUS |
| SGP30 Gas | CO₂, TVOC | I2C |
| KY-016 RGB LED | RGB Light (indicator) | Digital |

---

## Sensor Details

### 1. Outdoor Temperature/Humidity Sensor (DHT22)

**Product:** Teyleten Robot DHT22 / AM2302 Digital Temperature Humidity Sensor Module for Arduino  
**Purchase Link:** [Amazon - DHT22 Sensor][dht22-link]

#### Measurements
- **Temperature**
  - Range: -40°C to 80°C
  - Resolution: 0.1°C
  - Accuracy: ±0.5°C
- **Humidity**
  - Range: 0-100% RH
  - Resolution: 0.1% RH
  - Accuracy: ±2% RH

---

### 2. Ambient Light Sensor (VEML7700)

**Product:** 2 Pcs 16-bit I2C Interface VEML7700 Ambient Light Sensor Module for Arduino  
**Purchase Link:** [Amazon - VEML7700 Sensor][veml7700-link]

#### Measurements
- **Ambient Light**
  - Range: 0-120,000 lux
  - Interface: 16-bit I2C
  - Resolution: High precision ambient light detection

---

### 3. Soil Temperature/Moisture/EC Sensor

**Product:** RS485 MODBUS-RTU IP68 Soil Temperature & Moisture Sensor for Automatic Irrigation  
**Purchase Link:** [DFRobot - Soil Sensor][soil-link]

#### Measurements
- **Soil Temperature**
  - Range: -40°C to 80°C
  - Resolution: 0.1°C
  - Accuracy: ±0.5°C
  
- **Soil Moisture**
  - Range: 0-100% RH
  - Resolution: 0.1% RH
  - Accuracy: 
    - 0-50%: ±2% RH
    - 50-100%: ±3% RH
  
- **Soil Electrical Conductivity (EC)**
  - Range: 0-20,000 µs/cm
  - Resolution: 1 µs/cm
  - Accuracy:
    - 0-10,000 µs/cm: ±3% FS
    - 10,000-20,000 µs/cm: ±5% FS
  - Temperature Compensation: 0-50°C (memory-based)

#### Features
- IP68 waterproof rating
- RS485/MODBUS-RTU interface
- Arduino compatible

---

### 4. Carbon Dioxide Sensor (SGP30)

**Product:** GY-SGP30 Gas Sensor, Air Quality CO₂ Formaldehyde Monitoring Module  
**Purchase Link:** [Amazon - SGP30 Sensor][co2-link]

#### Measurements
- **Carbon Dioxide (CO₂)**
  - Measured in parts per million (PPM)
  - Digital multi-pixel gas sensor technology
  
- **Total Volatile Organic Compounds (TVOC)**
  - Indoor air quality monitoring
  
#### Features
- I2C interface
- Indoor air quality monitoring
- Arduino compatible

---

### 5. RGB Light Sensor/Indicator (KY-016)

**Product:** 3 Pack KY-016 Three Colors RGB LED Sensor Module DIY Starter Kit  
**Purchase Link:** [Amazon - KY-016 RGB Module][rgb-link]

#### Function
- RGB LED indicator module
- Used for visual status indication
- 3-color output (Red, Green, Blue)

---

## Reference Links

[dht22-link]: https://www.amazon.com/Teyleten-Robot-Digital-Temperature-Humidity/dp/B0CPHQC9SF
[veml7700-link]: https://www.amazon.com/GODIYMODULES-Interface-VEML7700-Ambient-Arduino/dp/B0DRRGVTLH
[soil-link]: https://www.dfrobot.com/product-2816.html
[co2-link]: https://www.amazon.com/EC-Buying-Formaldehyde-Monitoring-Multi-Pixel/dp/B0B389LQCQ
[rgb-link]: https://www.amazon.com/KY-016-Colors-Sensor-Arduino-Starter/dp/B0786CQD5P