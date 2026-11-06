/*
 * AgroEYE - Smart Irrigation System using Agentic AI & IoT
 * ESP32 Controller Firmware (HTTP / FastAPI Local Migration)
 * 
 * Hardware Pinout:
 *   - GPIO 34 : Capacitive Soil Moisture Sensor (Analog Input)
 *   - GPIO 35 : Rain Sensor Analog Output AO (Analog Input)
 *   - GPIO 27 : Rain Sensor Digital Output DO (Digital Input - optional)
 *   - GPIO 26 : Water Tank / Float Level Sensor (Digital Input)
 *   - GPIO 04 : DHT22 Temperature & Humidity Sensor (Data)
 *   - GPIO 25 : Push Button with Internal Pullup (Digital Input)
 *   - GPIO 23 : Pump Relay Control (Digital Output, Active-HIGH)
 * 
 * Communication:
 *   - Local Wi-Fi station mode
 *   - RESTful HTTP JSON communication directly with local FastAPI backend
 *   - Telemetry endpoint : POST /api/device/telemetry
 *   - Command endpoint   : GET  /api/device/command
 *   - Control endpoint   : POST /api/device/control
 */

#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <DHT.h>

// =====================================================
// 1. WIFI & FASTAPI CONFIGURATION
// =====================================================

// Replace with your local Wi-Fi credentials
const char* ssid = "YOUR_WIFI_NAME";
const char* pass = "YOUR_WIFI_PASSWORD";

// Local FastAPI server base address.
// Use the IPv4 address of your computer running FastAPI (e.g. 192.168.31.122).
// DO NOT use "localhost" or "127.0.0.1", as those refer to the ESP32 itself.
const char* API_BASE = "http://192.168.31.122:8000";

// Endpoints
const char* TELEMETRY_URL = "/api/device/telemetry";
const char* COMMAND_URL   = "/api/device/command";
const char* CONTROL_URL   = "/api/device/control";


// =====================================================
// 2. PIN DEFINITIONS
// =====================================================

#define SOIL_PIN       34
#define RAIN_AO_PIN    35
#define RAIN_DO_PIN    27
#define WATER_PIN      26
#define DHT_PIN         4
#define BUTTON_PIN     25
#define RELAY_PIN      23

#define DHTTYPE DHT22

DHT dht(DHT_PIN, DHTTYPE);


// =====================================================
// 3. SETTINGS & THRESHOLDS
// =====================================================

// Soil moisture hysteresis: higher raw reading = drier soil.
// Dry threshold triggers pump ON; wet threshold turns pump OFF.
const int SOIL_DRY_THRESHOLD = 3200;
const int SOIL_WET_THRESHOLD = 2600;

// Relay logic: Set to false if your relay turns ON with HIGH (Active-HIGH).
// Set to true if your relay turns ON with LOW (Active-LOW).
// (Your relay is Active-HIGH: HIGH = Motor ON, LOW = Motor OFF).
const bool RELAY_ACTIVE_LOW = false;

// =====================================================
// WATER LEVEL SENSOR CONFIGURATION (GPIO 26)
// =====================================================
// TODAY (Sensor not connected / not working):
// Keep set to true so water status is always AVAILABLE and never blocks the pump.
//
// TOMORROW (When connecting your new water level sensor):
// Simply change BYPASS_WATER_SENSOR_FOR_TESTING to false!
// - If your new sensor connects GPIO 26 to GND when water is available: set WATER_SENSOR_ACTIVE_LOW = true
// - If your new sensor outputs HIGH (3.3V) when water is available: set WATER_SENSOR_ACTIVE_LOW = false
const bool BYPASS_WATER_SENSOR_FOR_TESTING = false;
const bool WATER_SENSOR_ACTIVE_LOW = false;

// Rain detection threshold on analog AO pin:
// Values below RAIN_THRESHOLD indicate moisture/rain on probe.
// Dry ambient reading is ~4000; actual liquid droplets drop reading to < 2000.
const int RAIN_THRESHOLD = 2500;

// Rain lockout duration (10 minutes)
const unsigned long RAIN_LOCKOUT_TIME = 10UL * 60UL * 1000UL;

// Water level debounce filter duration (2 seconds)
const unsigned long WATER_STABLE_TIME = 2000;

// Timing intervals (milliseconds)
const unsigned long SENSOR_INTERVAL    = 2000;
const unsigned long CONTROL_INTERVAL   = 500;
const unsigned long BUTTON_INTERVAL    = 50;
const unsigned long TELEMETRY_INTERVAL = 2000;
const unsigned long COMMAND_INTERVAL   = 2000;


// =====================================================
// 4. SYSTEM STATE VARIABLES
// =====================================================

bool pumpState = false;

// 0 = AUTO (soil moisture governed), 1 = MANUAL (user/app governed)
// Default to 1 (MANUAL) so the motor stays safely OFF at startup
// instead of blasting water when the soil sensor is sitting in dry air (4095 > 3200)!
int controlMode = 1;

bool manualPumpRequest = false;

bool rainLockout = false;
unsigned long rainLockoutStart = 0;

bool rawWaterState = false;
bool stableWaterState = false;
unsigned long waterChangeTime = 0;

bool lastButtonState = HIGH;

int soilRaw = 0;
int soilPercent = 0;
int rainRaw = 0;

bool rainDetected = false;

float temperature = NAN;
float humidity = NAN;

unsigned long lastSensorTime = 0;
unsigned long lastControlTime = 0;
unsigned long lastButtonTime = 0;
unsigned long lastTelemetryTime = 0;
unsigned long lastCommandTime = 0;
unsigned long lastWiFiAttempt = 0;
unsigned long lastRelaySwitch = 0;
const unsigned long RELAY_DEBOUNCE_MS = 150; // Protect relay contacts and prevent back-EMF spikes


// =====================================================
// 5. PUMP RELAY CONTROL
// =====================================================

void setPump(bool state) {
  if (pumpState == state) {
    return;
  }
  lastRelaySwitch = millis();

  pumpState = state;

  // Active-LOW relay logic (LOW = relay closed/energized, HIGH = relay open/released).
  if (RELAY_ACTIVE_LOW) {
    digitalWrite(RELAY_PIN, state ? LOW : HIGH);
  } else {
    digitalWrite(RELAY_PIN, state ? HIGH : LOW);
  }

  Serial.print("[PUMP] Relay switched -> ");
  Serial.println(state ? "ON" : "OFF");
}


// =====================================================
// 6. WIFI CONNECTION MANAGEMENT
// =====================================================

bool isWiFiConfigured() {
  return (strcmp(ssid, "YOUR_WIFI_NAME") != 0 && strlen(ssid) > 0);
}

void connectWiFi() {
  if (!isWiFiConfigured()) {
    return; // Operating offline via USB Serial Bridge. Do not attempt Wi-Fi.
  }

  if (WiFi.status() == WL_CONNECTED) {
    return;
  }

  if (millis() - lastWiFiAttempt < 10000) {
    return;
  }

  lastWiFiAttempt = millis();

  Serial.println("[WIFI] Attempting connection...");
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, pass);
}

void printWiFiStatus() {
  if (isWiFiConfigured() && WiFi.status() == WL_CONNECTED) {
    Serial.print("[WIFI] Connected successfully! ESP32 IP: ");
    Serial.println(WiFi.localIP());
  } else if (!isWiFiConfigured()) {
    Serial.println("[SYSTEM] USB Serial Bridge Mode (100% Offline / Jammer-Proof)");
  } else {
    Serial.println("[WIFI] Not connected. Operating in local failsafe mode.");
  }
}


// =====================================================
// 7. WATER SENSOR STABILITY FILTER
// =====================================================

void updateWaterSensor() {
  if (BYPASS_WATER_SENSOR_FOR_TESTING) {
    stableWaterState = true;
    rawWaterState = true;
    return;
  }

  int pinReading = digitalRead(WATER_PIN);
  bool currentRaw = WATER_SENSOR_ACTIVE_LOW ? (pinReading == LOW) : (pinReading == HIGH);

  if (currentRaw != rawWaterState) {
    rawWaterState = currentRaw;
    waterChangeTime = millis();
  }

  if (millis() - waterChangeTime >= WATER_STABLE_TIME) {
    stableWaterState = rawWaterState;
  }
}


// =====================================================
// 8. RAIN DETECTION AND LOCKOUT
// =====================================================

void checkRain() {
  rainRaw = analogRead(RAIN_AO_PIN);
  rainDetected = (rainRaw < RAIN_THRESHOLD);

  if (rainDetected && !rainLockout) {
    rainLockout = true;
    rainLockoutStart = millis();

    Serial.println();
    Serial.println("****************************************");
    Serial.println("[SAFETY] RAIN DETECTED! 10-MIN LOCKOUT STARTED");
    Serial.println("****************************************");

    // Only auto-stop pump in AUTO mode! In MANUAL mode, user/AI has direct control!
    if (controlMode == 0) {
      setPump(false);
      manualPumpRequest = false;
    }
  }

  if (rainLockout) {
    unsigned long elapsed = millis() - rainLockoutStart;

    if (elapsed >= RAIN_LOCKOUT_TIME) {
      rainLockout = false;

      Serial.println();
      Serial.println("****************************************");
      Serial.println("[SAFETY] RAIN LOCKOUT EXPIRED - CONTROL RESTORED");
      Serial.println("****************************************");
    }
  }
}


// =====================================================
// 9. AUTOMATIC SOIL CONTROL
// =====================================================

void automaticPumpControl(int currentSoilRaw) {
  if (controlMode != 0) {
    return;
  }

  if (rainLockout) {
    setPump(false);
    return;
  }

  if (!stableWaterState) {
    setPump(false);
    return;
  }

  if (currentSoilRaw > SOIL_DRY_THRESHOLD) {
    setPump(true);
  } else if (currentSoilRaw < SOIL_WET_THRESHOLD) {
    setPump(false);
  }
  // Between thresholds, maintain existing pump state (hysteresis).
}


// =====================================================
// 10. FETCH COMMANDS FROM FASTAPI (AUTO/MANUAL & PUMP)
// =====================================================

void getDeviceCommand() {
  if (WiFi.status() != WL_CONNECTED) {
    return;
  }

  HTTPClient http;
  http.setTimeout(1500);
  http.begin(String(API_BASE) + COMMAND_URL);

  int statusCode = http.GET();

  if (statusCode == HTTP_CODE_OK) {
    #if ARDUINOJSON_VERSION_MAJOR >= 7
      JsonDocument doc;
    #else
      StaticJsonDocument<256> doc;
    #endif

    DeserializationError error = deserializeJson(doc, http.getString());

    if (!error) {
      const char* mode = doc["mode"] | "AUTO";
      int newMode = (strcmp(mode, "MANUAL") == 0) ? 1 : 0;
      bool newManualRequest = doc["manual_pump_request"] | false;

      if (newMode != controlMode) {
        controlMode = newMode;
        Serial.print("[MODE] Switched via FastAPI to: ");
        Serial.println(controlMode == 0 ? "AUTO" : "MANUAL");

        if (controlMode == 1) {
          manualPumpRequest = false;
          setPump(false);
        } else {
          manualPumpRequest = false;
        }
      } else if (controlMode == 1) {
        manualPumpRequest = newManualRequest;
      }
    } else {
      Serial.println("[HTTP] Command deserialization error.");
    }
  } else if (statusCode > 0) {
    Serial.print("[HTTP] Command GET status: ");
    Serial.println(statusCode);
  }

  http.end();
}


// =====================================================
// 11. SEND MANUAL CONTROL TO FASTAPI
// =====================================================

void sendManualControl() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[HTTP] Cannot sync manual control: Wi-Fi offline.");
    return;
  }

  HTTPClient http;
  http.setTimeout(1500);
  http.begin(String(API_BASE) + CONTROL_URL);
  http.addHeader("Content-Type", "application/json");

  #if ARDUINOJSON_VERSION_MAJOR >= 7
    JsonDocument doc;
  #else
    StaticJsonDocument<128> doc;
  #endif

  doc["mode"] = (controlMode == 0) ? "AUTO" : "MANUAL";
  doc["manual_pump_request"] = manualPumpRequest;

  String payload;
  serializeJson(doc, payload);

  int statusCode = http.POST(payload);

  Serial.print("[HTTP] Manual control POST status: ");
  Serial.println(statusCode);

  http.end();
}


// =====================================================
// 12. PHYSICAL PUSH BUTTON
// =====================================================

void checkButton() {
  bool buttonState = digitalRead(BUTTON_PIN);

  // Active-LOW trigger with INPUT_PULLUP
  if (lastButtonState == HIGH && buttonState == LOW) {
    Serial.println("[BUTTON] Physical button pressed.");

    if (controlMode != 1) {
      Serial.println("[BUTTON] Ignored: System in AUTO mode.");
    } else if (rainLockout) {
      Serial.println("[BUTTON] Blocked: Rain lockout is active.");
    } else if (!stableWaterState) {
      Serial.println("[BUTTON] Blocked: Water unavailable in reservoir.");
    } else {
      manualPumpRequest = !manualPumpRequest;
      setPump(manualPumpRequest);
      sendManualControl();
    }
  }

  lastButtonState = buttonState;
}


// =====================================================
// 13. SENSOR READING & LOCAL SERIAL TELEMETRY
// =====================================================

void sendSensorData() {
  soilRaw = analogRead(SOIL_PIN);

  // Map 12-bit ADC reading (4095 = bone dry, ~2000 = saturated wet)
  soilPercent = map(soilRaw, 4095, 2000, 0, 100);
  soilPercent = constrain(soilPercent, 0, 100);

  rainRaw = analogRead(RAIN_AO_PIN);
  rainDetected = (rainRaw < RAIN_THRESHOLD);

  updateWaterSensor();

  temperature = dht.readTemperature();
  humidity = dht.readHumidity();

  unsigned long remainingSeconds = 0;
  if (rainLockout) {
    unsigned long elapsed = millis() - rainLockoutStart;
    if (elapsed < RAIN_LOCKOUT_TIME) {
      remainingSeconds = (RAIN_LOCKOUT_TIME - elapsed + 999) / 1000;
    }
  }

  Serial.println();
  Serial.println("========================================");
  Serial.println("       AGROEYE SMART IRRIGATION");
  Serial.println("========================================");
  Serial.printf("Soil Raw ADC   : %d\n", soilRaw);
  Serial.printf("Soil Moisture  : %d %%\n", soilPercent);
  Serial.printf("Rain Raw ADC   : %d\n", rainRaw);
  Serial.printf("Rain Status    : %s\n", rainDetected ? "RAIN" : "NO RAIN");
  if (BYPASS_WATER_SENSOR_FOR_TESTING) {
    Serial.printf("Water Level    : AVAILABLE (Test Mode Active - Pin 26: %d)\n", digitalRead(WATER_PIN));
  } else {
    Serial.printf("Water Level    : %s (Pin 26: %d)\n", stableWaterState ? "AVAILABLE" : "EMPTY / LOW", digitalRead(WATER_PIN));
  }

  if (!isnan(temperature) && !isnan(humidity)) {
    Serial.printf("Temperature    : %.1f C\n", temperature);
    Serial.printf("Humidity       : %.1f %%\n", humidity);
  } else {
    Serial.println("DHT22 Sensor   : Reading Error");
  }

  Serial.printf("Control Mode   : %s\n", controlMode == 0 ? "AUTO" : "MANUAL");
  Serial.printf("Pump State     : %s\n", pumpState ? "ON" : "OFF");
  Serial.printf("Rain Lockout   : %s (%lu sec remaining)\n", rainLockout ? "ACTIVE" : "OFF", remainingSeconds);
  Serial.println("========================================");
}


// =====================================================
// 14. SEND TELEMETRY TO LOCAL FASTAPI SERVER
// =====================================================

void sendTelemetry() {
  if (WiFi.status() != WL_CONNECTED) {
    return;
  }

  HTTPClient http;
  http.setTimeout(1500);
  http.begin(String(API_BASE) + TELEMETRY_URL);
  http.addHeader("Content-Type", "application/json");

  #if ARDUINOJSON_VERSION_MAJOR >= 7
    JsonDocument doc;
  #else
    StaticJsonDocument<512> doc;
  #endif

  unsigned long remainingSeconds = 0;
  if (rainLockout) {
    unsigned long elapsed = millis() - rainLockoutStart;
    if (elapsed < RAIN_LOCKOUT_TIME) {
      remainingSeconds = (RAIN_LOCKOUT_TIME - elapsed + 999) / 1000;
    }
  }

  doc["soil_raw"] = soilRaw;
  doc["soil_moisture"] = soilPercent;
  doc["rain_raw"] = rainRaw;
  doc["rain_detected"] = rainDetected;
  doc["water_available"] = stableWaterState;

  if (isnan(temperature)) {
    doc["temperature"] = nullptr;
  } else {
    doc["temperature"] = temperature;
  }

  if (isnan(humidity)) {
    doc["humidity"] = nullptr;
  } else {
    doc["humidity"] = humidity;
  }

  doc["pump_on"] = pumpState;
  doc["control_mode"] = controlMode;
  doc["manual_pump_request"] = manualPumpRequest;
  doc["rain_lockout"] = rainLockout;
  doc["lockout_remaining_seconds"] = remainingSeconds;

  String payload;
  serializeJson(doc, payload);

  int statusCode = http.POST(payload);

  if (statusCode != HTTP_CODE_OK && statusCode > 0) {
    Serial.print("[HTTP] Telemetry POST response: ");
    Serial.println(statusCode);
  }

  http.end();
}


// =====================================================
// 15. MAIN PUMP CONTROL TASK
// =====================================================

void controlPump() {
  updateWaterSensor();
  checkRain();

  // Control logic
  if (controlMode == 0) {
    // AUTO Mode: Safety Rule 1 - Rain lockout overrides auto cycles
    if (rainLockout) {
      setPump(false);
      return;
    }

    // AUTO Mode: Safety Rule 2 - Water reservoir must have water for auto cycles
    if (!stableWaterState) {
      setPump(false);
      return;
    }
    automaticPumpControl(analogRead(SOIL_PIN));
  } else {
    // MANUAL Mode: Direct user / AI command (allows user override & testing)
    setPump(manualPumpRequest);
  }
}


// =====================================================
// 16. SETUP
// =====================================================

void setup() {
  Serial.begin(115200);
  delay(1000);

  analogReadResolution(12);

  pinMode(RAIN_DO_PIN, INPUT);
  pinMode(WATER_PIN, INPUT_PULLUP);
  pinMode(BUTTON_PIN, INPUT_PULLUP);
  pinMode(RELAY_PIN, OUTPUT);

  // Pump starts in a confirmed SAFE OFF state
  digitalWrite(RELAY_PIN, RELAY_ACTIVE_LOW ? HIGH : LOW);
  pumpState = false;

  bool initialWater = WATER_SENSOR_ACTIVE_LOW ? (digitalRead(WATER_PIN) == LOW) : (digitalRead(WATER_PIN) == HIGH);
  rawWaterState = BYPASS_WATER_SENSOR_FOR_TESTING ? true : initialWater;
  stableWaterState = rawWaterState;
  waterChangeTime = millis();

  dht.begin();

  Serial.println();
  Serial.println("========================================");
  Serial.println(" AgroEYE ESP32 Smart Irrigation System ");
  Serial.println("  Local FastAPI HTTP Migration Build   ");
  Serial.println("========================================");

  if (isWiFiConfigured()) {
    WiFi.mode(WIFI_STA);
    WiFi.begin(ssid, pass);
    lastWiFiAttempt = millis();
  } else {
    WiFi.mode(WIFI_OFF);
  }

  // Stagger network timers so command GET and telemetry POST do not run concurrently
  lastCommandTime = 1000;
  lastTelemetryTime = 0;

  printWiFiStatus();
}


// =====================================================
// 15B. USB SERIAL COMMAND HANDLER (Non-Blocking)
// =====================================================

void checkSerialCommands() {
  static char serialBuf[64];
  static uint8_t bufIdx = 0;

  while (Serial.available() > 0) {
    char c = (char)Serial.read();
    if (c == '\r') continue;

    if (c == '\n') {
      serialBuf[bufIdx] = '\0';
      if (bufIdx > 0) {
        String cmd = String(serialBuf);
        cmd.trim();

        if (cmd.startsWith("CMD:")) {
          Serial.print("[USB CMD] Processing: ");
          Serial.println(cmd);

          if (cmd.indexOf("MODE=MANUAL") >= 0) {
            controlMode = 1;
          } else if (cmd.indexOf("MODE=AUTO") >= 0) {
            controlMode = 0;
          }

          if (cmd.indexOf("PUMP=1") >= 0) {
            controlMode = 1;
            manualPumpRequest = true;
            rainLockout = false;
            setPump(true);
          } else if (cmd.indexOf("PUMP=0") >= 0) {
            manualPumpRequest = false;
            setPump(false);
          }
        }
      }
      bufIdx = 0;
    } else {
      if (bufIdx < sizeof(serialBuf) - 1) {
        serialBuf[bufIdx++] = c;
      }
    }
  }
}


// =====================================================
// 17. MAIN LOOP
// =====================================================

void loop() {
  unsigned long now = millis();

  // 0. Process USB Serial Commands (Instantaneous)
  checkSerialCommands();

  // 1. Physical push button check (every 50 ms)
  if (now - lastButtonTime >= BUTTON_INTERVAL) {
    lastButtonTime = now;
    checkButton();
  }

  // 2. Local pump control & safety enforcement (every 500 ms)
  if (now - lastControlTime >= CONTROL_INTERVAL) {
    lastControlTime = now;
    controlPump();
  }

  // 3. Sensor reading and local serial telemetry (every 2000 ms)
  if (now - lastSensorTime >= SENSOR_INTERVAL) {
    lastSensorTime = now;
    sendSensorData();
  }

  // 4. Background Wi-Fi reconnect check
  if (WiFi.status() != WL_CONNECTED) {
    connectWiFi();
  }

  // 5. Poll FastAPI server for mode/manual command (every 2000 ms, offset)
  if (now - lastCommandTime >= COMMAND_INTERVAL) {
    lastCommandTime = now;
    getDeviceCommand();
  }

  // 6. Push telemetry to FastAPI server (every 2000 ms, offset)
  if (now - lastTelemetryTime >= TELEMETRY_INTERVAL) {
    lastTelemetryTime = now;
    sendTelemetry();
  }
}
