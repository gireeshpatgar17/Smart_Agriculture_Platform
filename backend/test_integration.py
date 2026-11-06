import sys
from fastapi.testclient import TestClient

print("--- Testing Imports ---")
from app.main import app
from app.api.device import get_latest_sensors, get_device_control, set_device_control
from app.services.irrigation_monitor import get_pump_status, get_sensor_snapshot
from app.services.agent_service import tool_get_current_sensor_readings
from app.services.blynk_service import get_all_blynk_sensors, get_blynk_value

print("All imports successful!")

client = TestClient(app)

print("\n--- Testing Root Endpoint ---")
r = client.get("/")
assert r.status_code == 200, f"Root returned {r.status_code}"
print("Root OK:", r.json())

print("\n--- Testing Device Command (Initial) ---")
r = client.get("/api/device/command")
assert r.status_code == 200, f"Command returned {r.status_code}"
cmd = r.json()
print("Initial Command:", cmd)
assert cmd["mode"] == "AUTO"
assert cmd["manual_pump_request"] is False

print("\n--- Testing Device Telemetry (POST from ESP32) ---")
sample_telemetry = {
    "soil_raw": 3450,
    "soil_moisture": 32,
    "rain_raw": 3900,
    "rain_detected": False,
    "water_available": True,
    "temperature": 29.4,
    "humidity": 65.2,
    "pump_on": True,
    "control_mode": 0,
    "manual_pump_request": False,
    "rain_lockout": False,
    "lockout_remaining_seconds": 0
}
r = client.post("/api/device/telemetry", json=sample_telemetry)
assert r.status_code == 200, f"Telemetry POST returned {r.status_code}: {r.text}"
print("Telemetry POST OK:", r.json())

print("\n--- Testing Device Sensors (GET) ---")
r = client.get("/api/device/sensors")
assert r.status_code == 200
sensors = r.json()
print("Latest Sensors:", sensors)
assert sensors["soil_raw"] == 3450
assert sensors["soil_moisture"] == 32
assert sensors["rain_status"] == "NO RAIN"
assert sensors["water_status"] == "AVAILABLE"
assert sensors["pump_status"] == "ON"
assert sensors["pump_on"] is True
assert sensors["updated_at"] is not None

print("\n--- Testing Frontend /sensors/ Endpoint ---")
r = client.get("/sensors/")
assert r.status_code == 200, f"/sensors/ returned {r.status_code}: {r.text}"
frontend_data = r.json()
print("Frontend /sensors/ data:", frontend_data)
assert frontend_data["soil_raw"] == 3450
assert frontend_data["soil_moisture"] == 32.0
assert frontend_data["temperature"] == 29.4
assert frontend_data["humidity"] == 65.2
assert frontend_data["water_status"] == "AVAILABLE"
assert frontend_data["rain_status"] == "NO RAIN"
assert frontend_data["pump_status"] == "ON"
assert frontend_data["control_mode"] == 0
assert frontend_data["rain_lockout"] == 0
assert frontend_data["lockout_remaining_seconds"] == 0

print("\n--- Testing Irrigation Monitor Integration ---")
current_pump = get_pump_status()
print("Monitor Pump Status:", current_pump)
assert current_pump == "ON"
snapshot = get_sensor_snapshot()
print("Monitor Snapshot:", snapshot)
assert snapshot["soil_raw"] == 3450
assert snapshot["pump_status" if "pump_status" in snapshot else "soil_moisture"] == 32.0

print("\n--- Testing AI Agent Tool Integration ---")
agent_readings = tool_get_current_sensor_readings()
print("Agent Tool Sensor Readings:", agent_readings)
assert agent_readings["status"] == "success"
assert agent_readings["sensors"]["soil_moisture_percent"] == 32.0
assert agent_readings["sensors"]["pump_status"] == "ON"

print("\n--- Testing Device Control (POST Mode & Pump Request) ---")
# 1. Switch to MANUAL with pump True
r = client.post("/api/device/control", json={"mode": "MANUAL", "manual_pump_request": True})
assert r.status_code == 200
control_state = r.json()
print("Updated Control to MANUAL:", control_state)
assert control_state["mode"] == "MANUAL"
assert control_state["manual_pump_request"] is True

# 2. Check ESP32 command endpoint reflects this
r = client.get("/api/device/command")
assert r.status_code == 200
cmd = r.json()
assert cmd["mode"] == "MANUAL"
assert cmd["manual_pump_request"] is True

# 3. Switch back to AUTO -> manual_pump_request should reset to False
r = client.post("/api/device/control", json={"mode": "AUTO", "manual_pump_request": True})
assert r.status_code == 200
assert r.json()["mode"] == "AUTO"
assert r.json()["manual_pump_request"] is False

# 4. Invalid mode error check
r = client.post("/api/device/control", json={"mode": "INVALID_MODE"})
assert r.status_code == 400
print("Invalid mode rejected with 400 as expected.")

print("\n--- Testing Telemetry with NULL Temperature & Humidity (DHT error simulation) ---")
dht_fail_telemetry = {
    "soil_raw": 2800,
    "soil_moisture": 60,
    "rain_raw": 1800,
    "rain_detected": True,
    "water_available": False,
    "temperature": None,
    "humidity": None,
    "pump_on": False,
    "control_mode": 0,
    "manual_pump_request": False,
    "rain_lockout": True,
    "lockout_remaining_seconds": 580
}
r = client.post("/api/device/telemetry", json=dht_fail_telemetry)
assert r.status_code == 200
r = client.get("/sensors/")
assert r.status_code == 200
data = r.json()
assert data["temperature"] is None or data["temperature"] == 0.0
assert data["rain_status"] == "RAIN"
assert data["water_status"] == "NOT AVAILABLE"
assert data["pump_status"] == "OFF"
assert data["rain_lockout"] == 1
assert data["lockout_remaining_seconds"] == 580
print("DHT Error & Rain Lockout Telemetry verified successfully!")

print("\nALL INTEGRATION TESTS PASSED SUCCESSFULLY!")
