#include <WiFi.h>
#include <HTTPClient.h>
#include <Wire.h>
#include "Adafruit_SGP30.h"
#include "Adafruit_VEML7700.h"
#include "DHT.h"
#include <ModbusMaster.h>

// -----------------------------
// WiFi + Google Script
// -----------------------------
const char* ssid = "SpectrumSetup-1840";
const char* password = "suredrama311";

String scriptURL =
  "https://script.google.com/macros/s/AKfycbz4J7s8mP5pNpOV2S5WLDN7AIYCFtmoZuq9-tSolxDw_2oxGKJuR1vHLDr9ELy08F05/exec";

// Cloud Function Endpoint
const char* cloudFunctionURL = "https://us-central1-agrivoltaics-flutter-firebase.cloudfunctions.net/ingestSensorData";

// Organization, Site, and Zone IDs
const char* ORGANIZATION_ID = "GS6e4032WK70vQ42WTYc";
const char* SITE_ID = "5LvgyAAaFpAmlfcUrpTU";
const char* ZONE_ID = "7aZzv6juGouqsbicdC8J";

// Sensor IDs
const char* SENSOR_ID_TEMP_HUMIDITY = "sdkJbkRh6hkK4XJYpPrP";
const char* SENSOR_ID_LIGHT = "EFR2gToaxfxtPLkQFeYG";
const char* SENSOR_ID_SOIL = "qx8EIYdyf8VGUxWh38AO";
const char* SENSOR_ID_CO2_TVOC = "zgDucecynnHWDlGwmfp1";

// Unit Constants
const char* UNIT_FAHRENHEIT = "°F";
const char* UNIT_CELSIUS = "°C";
const char* UNIT_PERCENT = "%";
const char* UNIT_LUX = "lux";
const char* UNIT_PPM = "ppm";
const char* UNIT_MOISTURE = "VWC%";
const char* UNIT_EC = "μS/cm";

// -----------------------------
// LED Logic Config
// -----------------------------
// ⚠️ Set to true if using COMMON ANODE RGB LED
#define COMMON_ANODE false

const int redPin = 4;
const int greenPin = 18;
const int bluePin = 19;

// -----------------------------
// Sensors
// -----------------------------
Adafruit_SGP30 sgp;
Adafruit_VEML7700 veml;
TwoWire I2C_VEML = TwoWire(1);

#define DHTPIN 14
#define DHTTYPE DHT11
DHT dht(DHTPIN, DHTTYPE);

ModbusMaster node;

// -----------------------------
// Sensor Data
// -----------------------------
float tempF = 0;
float humidity = 0;
uint16_t soilMoisture = 0;
float soilTempF = 0;
uint16_t soilEC = 0;
float luxValue = 0;
uint16_t co2 = 400;
uint16_t tvoc = 0;

// -----------------------------
unsigned long lastSend = 0;
const unsigned long SEND_INTERVAL = 15000;
// -----------------------------

void setup() {
  Serial.begin(115200);

  // RGB LED Setup
  pinMode(redPin, OUTPUT);
  pinMode(greenPin, OUTPUT);
  pinMode(bluePin, OUTPUT);
  setLEDColor(255, 0, 0); // RED = Starting, no WiFi

  // Connect to WiFi
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500); Serial.print(".");
  }

  Serial.println("\nWiFi connected");
  setLEDColor(0, 0, 255); // BLUE = WiFi Connected

  Wire.begin(26, 27);
  Wire.setClock(100000);

  if (!sgp.begin()) {
    Serial.println("SGP30 failed");
    while (1);
  }
  sgp.IAQinit();

  I2C_VEML.begin(32, 33);
  veml.begin(&I2C_VEML);

  dht.begin();

  Serial2.begin(9600, SERIAL_8N1, 16, 17);
  node.begin(1, Serial2);
}

void loop() {
  // If WiFi drops, turn RED
  if (WiFi.status() != WL_CONNECTED) {
    setLEDColor(255, 0, 0); // RED = No WiFi
  }

  // SGP30 should be read every 1 second
  static unsigned long lastSGP = 0;
  if (millis() - lastSGP >= 1000) {
    lastSGP = millis();
    if (sgp.IAQmeasure()) {
      co2 = sgp.eCO2;
      tvoc = sgp.TVOC;
    }
  }

  // Send data every SEND_INTERVAL
  if (millis() - lastSend >= SEND_INTERVAL) {
    lastSend = millis();

    // Read Soil Sensor
    if (node.readHoldingRegisters(0x00, 3) == node.ku8MBSuccess) {
      soilMoisture = node.getResponseBuffer(0);
      soilTempF = (node.getResponseBuffer(1) / 10.0) * 9.0 / 5.0 + 32.0;
      soilEC = node.getResponseBuffer(2);
    }

    // Read DHT11
    float tC = dht.readTemperature();
    float h = dht.readHumidity();
    if (!isnan(tC)) tempF = tC * 1.8 + 32;
    if (!isnan(h)) humidity = h;

    // Read Lux
    luxValue = veml.readLux();

    // Send to Cloud
    sendDataToCloud();

    // Backup send to Google Sheet
    sendToGoogleSheet();
  }
}

void sendToGoogleSheet() {
  if (WiFi.status() != WL_CONNECTED) {
    setLEDColor(255, 0, 0); // RED = No WiFi
    return;
  }

  HTTPClient http;

  String url = scriptURL +
    "?temp=" + String(tempF, 1) +
    "&hum=" + String(humidity, 1) +
    "&moist=" + String(soilMoisture) +
    "&soiltemp=" + String(soilTempF, 1) +
    "&ec=" + String(soilEC) +
    "&lux=" + String(luxValue, 1) +
    "&co2=" + String(co2) +
    "&tvoc=" + String(tvoc);

  Serial.println(url);

  http.begin(url);
  int httpCode = http.GET();
  http.end();

  if (httpCode >= 200 && httpCode < 400) {
    setLEDColor(0, 255, 0); // GREEN = Success
  } else {
    setLEDColor(255, 0, 0); // RED = Fail
  }

  delay(2000); // Briefly show result color
  setLEDColor(0, 0, 255); // BLUE = idle, WiFi OK
}

void sendDataToCloud() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi not connected, skipping cloud send");
    return;
  }

  HTTPClient http;
  http.begin(cloudFunctionURL);
  http.addHeader("Content-Type", "application/json");

  // Get current timestamp
  unsigned long timestamp = millis() / 1000; // Simple timestamp in seconds

  // Build JSON payload
  String jsonPayload = "{";
  jsonPayload += "\"organizationId\":\"" + String(ORGANIZATION_ID) + "\",";
  jsonPayload += "\"siteId\":\"" + String(SITE_ID) + "\",";
  jsonPayload += "\"zoneId\":\"" + String(ZONE_ID) + "\",";
  jsonPayload += "\"sensors\":[";

  // Sensor 1: Temperature and Humidity
  jsonPayload += "{";
  jsonPayload += "\"sensorId\":\"" + String(SENSOR_ID_TEMP_HUMIDITY) + "\",";
  jsonPayload += "\"timestamp\":" + String(timestamp) + ",";
  jsonPayload += "\"readings\":{";
  jsonPayload += "\"temperature\":{\"value\":" + String(tempF, 1) + ",\"unit\":\"" + UNIT_FAHRENHEIT + "\"},";
  jsonPayload += "\"humidity\":{\"value\":" + String(humidity, 1) + ",\"unit\":\"" + UNIT_PERCENT + "\"}";
  jsonPayload += "}";
  jsonPayload += "},";

  // Sensor 2: Light
  jsonPayload += "{";
  jsonPayload += "\"sensorId\":\"" + String(SENSOR_ID_LIGHT) + "\",";
  jsonPayload += "\"timestamp\":" + String(timestamp) + ",";
  jsonPayload += "\"readings\":{";
  jsonPayload += "\"light\":{\"value\":" + String(luxValue, 1) + ",\"unit\":\"" + UNIT_LUX + "\"}";
  jsonPayload += "}";
  jsonPayload += "},";

  // Sensor 3: Soil Data
  jsonPayload += "{";
  jsonPayload += "\"sensorId\":\"" + String(SENSOR_ID_SOIL) + "\",";
  jsonPayload += "\"timestamp\":" + String(timestamp) + ",";
  jsonPayload += "\"readings\":{";
  jsonPayload += "\"soilMoisture\":{\"value\":" + String(soilMoisture) + ",\"unit\":\"" + UNIT_MOISTURE + "\"},";
  jsonPayload += "\"soilTemperature\":{\"value\":" + String(soilTempF, 1) + ",\"unit\":\"" + UNIT_CELSIUS + "\"},";
  jsonPayload += "\"soilElectricalConductivity\":{\"value\":" + String(soilEC) + ",\"unit\":\"" + UNIT_EC + "\"}";
  jsonPayload += "}";
  jsonPayload += "},";

  // Sensor 4: CO2 and TVOC
  jsonPayload += "{";
  jsonPayload += "\"sensorId\":\"" + String(SENSOR_ID_CO2_TVOC) + "\",";
  jsonPayload += "\"timestamp\":" + String(timestamp) + ",";
  jsonPayload += "\"readings\":{";
  jsonPayload += "\"co2\":{\"value\":" + String(co2) + ",\"unit\":\"" + UNIT_PPM + "\"},";
  jsonPayload += "\"tvoc\":{\"value\":" + String(tvoc) + ",\"unit\":\"" + UNIT_PPM + "\"}";
  jsonPayload += "}";
  jsonPayload += "}";

  jsonPayload += "]";
  jsonPayload += "}";

  Serial.println("Sending to cloud:");
  Serial.println(jsonPayload);

  int httpCode = http.POST(jsonPayload);
  String response = http.getString();

  http.end();

  Serial.print("Cloud response code: ");
  Serial.println(httpCode);
  Serial.print("Cloud response: ");
  Serial.println(response);
}

// -----------------------------
// RGB LED Helper
// -----------------------------
void setLEDColor(int r, int g, int b) {
  if (COMMON_ANODE) {
    r = 255 - r;
    g = 255 - g;
    b = 255 - b;
  }

  analogWrite(redPin,   r);
  analogWrite(greenPin, g);
  analogWrite(bluePin,  b);

  Serial.print("LED set to R:"); Serial.print(r);
  Serial.print(" G:"); Serial.print(g);
  Serial.print(" B:"); Serial.println(b);
}
