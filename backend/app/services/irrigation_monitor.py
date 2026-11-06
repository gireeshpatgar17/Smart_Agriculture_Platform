import asyncio
from datetime import datetime, timezone

from app.api.device import (
    get_device_control,
    get_latest_sensors,
    set_device_control,
    get_last_environmental_trip,
)
from app.database import supabase


# ============================================================
# CONFIGURATION
# ============================================================

FARM_ID = 1
CHECK_INTERVAL_SECONDS = 2


# ============================================================
# CURRENT IRRIGATION STATE
# ============================================================

previous_pump_status = None
active_irrigation = None


# ============================================================
# READ PUMP STATUS
# ============================================================

def get_pump_status():
    """
    Read pump status directly from the latest ESP32 telemetry.
    """
    sensors = get_latest_sensors()
    return "ON" if sensors.get("pump_on") else "OFF"


# ============================================================
# READ SENSOR SNAPSHOT
# ============================================================

def get_sensor_snapshot():
    """
    Read all values needed when irrigation starts from live telemetry.
    """
    sensors = get_latest_sensors()
    ctrl = get_device_control()

    control_mode = sensors.get("control_mode")
    if control_mode is None:
        control_mode = 1 if ctrl.get("mode") == "MANUAL" else 0

    return {
        "soil_raw": int(sensors.get("soil_raw") or 0),
        "soil_moisture": float(sensors.get("soil_moisture") or 0.0),
        "temperature": float(sensors.get("temperature") or 0.0),
        "humidity": float(sensors.get("humidity") or 0.0),

        "rain_status": str(sensors.get("rain_status") or ("RAIN" if sensors.get("rain_detected") else "NO RAIN")),
        "water_status": str(sensors.get("water_status") or ("AVAILABLE" if sensors.get("water_available") else "NOT AVAILABLE")),

        "control_mode": int(control_mode),
    }



# ============================================================
# START IRRIGATION
# ============================================================

def start_irrigation(snapshot):
    global active_irrigation

    if snapshot["control_mode"] == 0:
        mode = "AUTO"
        trigger_reason = "Automatic irrigation"
    else:
        mode = "MANUAL"
        trigger_reason = "Manual irrigation"

    active_irrigation = {
        "farm_id": FARM_ID,

        "start_time": datetime.now(timezone.utc),

        "mode": mode,
        "trigger_reason": trigger_reason,

        "soil_moisture_at_start":
            snapshot["soil_moisture"],

        "soil_raw_at_start":
            snapshot["soil_raw"],

        "temperature_at_start":
            snapshot["temperature"],

        "humidity_at_start":
            snapshot["humidity"],

        "rain_detected_at_start":
            snapshot["rain_status"].strip().upper() == "RAIN",

        "water_available_at_start":
            snapshot["water_status"].strip().upper() == "AVAILABLE",
    }

    print()
    print("========================================")
    print("IRRIGATION STARTED")
    print("========================================")
    print(f"Farm: {FARM_ID}")
    print(f"Mode: {mode}")
    print(f"Trigger: {trigger_reason}")
    print(f"Soil moisture: {snapshot['soil_moisture']}")
    print(f"Soil raw: {snapshot['soil_raw']}")
    print(f"Temperature: {snapshot['temperature']}")
    print(f"Humidity: {snapshot['humidity']}")
    print(f"Rain: {snapshot['rain_status']}")
    print(f"Water: {snapshot['water_status']}")
    print("========================================")
    print()


# ============================================================
# END IRRIGATION
# ============================================================

def _async_save_irrigation_record(data, duration_minutes):
    try:
        supabase.table("irrigation_history").insert(data).execute()
        print(f"[DATABASE] Irrigation record saved ({duration_minutes:.2f} mins).")
    except Exception as e:
        print(f"[DATABASE] Note: Supabase save skipped (offline/network issue: {e})")


def end_irrigation():
    global active_irrigation

    if active_irrigation is None:
        return

    end_time = datetime.now(timezone.utc)
    start_time = active_irrigation["start_time"]
    duration_seconds = (end_time - start_time).total_seconds()
    duration_minutes = duration_seconds / 60.0

    data = {
        "farm_id": active_irrigation["farm_id"],
        "start_time": start_time.isoformat(),
        "end_time": end_time.isoformat(),
        "duration_minutes": duration_minutes,
        "mode": active_irrigation["mode"],
        "trigger_reason": active_irrigation["trigger_reason"],
        "soil_moisture_at_start": active_irrigation["soil_moisture_at_start"],
        "soil_raw_at_start": active_irrigation["soil_raw_at_start"],
        "temperature_at_start": active_irrigation["temperature_at_start"],
        "humidity_at_start": active_irrigation["humidity_at_start"],
        "rain_detected_at_start": active_irrigation["rain_detected_at_start"],
        "water_available_at_start": active_irrigation["water_available_at_start"],
    }

    print()
    print("========================================")
    print("IRRIGATION ENDED")
    print(f"Duration: {duration_minutes:.2f} minutes")
    print("========================================")
    print()

    # Offload network save to non-blocking daemon thread so event loop never freezes!
    import threading
    threading.Thread(target=_async_save_irrigation_record, args=(data, duration_minutes), daemon=True).start()

    active_irrigation = None


# ============================================================
# MAIN MONITOR
# ============================================================

async def monitor_irrigation():
    global previous_pump_status

    print("========================================")
    print("IRRIGATION MONITOR STARTED")
    print("========================================")

    while True:

        try:
            # --------------------------------------------
            # Only read V6 during normal monitoring
            # --------------------------------------------

            current_pump_status = get_pump_status()

            # --------------------------------------------
            # First reading
            # --------------------------------------------
            if previous_pump_status is None:
                previous_pump_status = current_pump_status
                print(f"Initial pump status: {current_pump_status}")

            # --------------------------------------------
            # OFF -> ON
            # --------------------------------------------
            elif (
                previous_pump_status == "OFF"
                and current_pump_status == "ON"
            ):
                print("Pump transition detected: OFF -> ON")
                snapshot = get_sensor_snapshot()
                if active_irrigation is None:
                    start_irrigation(snapshot)

            # --------------------------------------------
            # ON -> OFF
            # --------------------------------------------
            elif (
                previous_pump_status == "ON"
                and current_pump_status == "OFF"
            ):
                print("Pump transition detected: ON -> OFF")
                if active_irrigation is not None:
                    end_irrigation()

            previous_pump_status = current_pump_status

            # --------------------------------------------
            # AI ENVIRONMENT-AWARE AUTO PROTECTION
            # Automatically stop pump if rain, empty reservoir, or saturated soil
            # --------------------------------------------
            if current_pump_status == "ON":
                sensors = get_latest_sensors()
                ctrl = get_device_control()
                is_manual = (ctrl.get("mode") == "MANUAL") or (sensors.get("control_mode") == 1)

                # Grace period: allow motor to run for at least 15 seconds before checking auto-trip
                time_running_seconds = 0.0
                if active_irrigation and active_irrigation.get("start_time"):
                    time_running_seconds = (datetime.now(timezone.utc) - active_irrigation["start_time"]).total_seconds()

                if time_running_seconds >= 15.0:
                    # 1. Rain Detection (Raw ADC drops below 2200 only when water touches probe)
                    rain_raw = int(sensors.get("rain_raw") or 4095)
                    rain_detected = (0 < rain_raw < 2200) or (
                        sensors.get("rain_status") == "RAIN" and rain_raw < 2500
                    )

                    # 2. Water Tank Empty / Unavailable (Exempt in MANUAL mode as requested by user)
                    water_avail = bool(sensors.get("water_available", True))
                    water_status = str(sensors.get("water_status", "AVAILABLE")).upper()
                    water_empty = (not water_avail) or ("NOT" in water_status) or ("EMPTY" in water_status)

                    # 3. Soil Moisture Saturated / Optimal (>= 80%)
                    soil_moist = float(sensors.get("soil_moisture") or 0.0)
                    soil_raw = int(sensors.get("soil_raw") or 4095)
                    soil_saturated = (soil_moist >= 80.0) or (0 < soil_raw < 2200)

                    trip_reason = None
                    trip_details = None

                    if rain_detected:
                        trip_reason = "Rain Detected"
                        trip_details = "Live field sensor detected rainfall. AI Agent automatically shut down the motor to prevent waterlogging and protect root health."
                    elif water_empty and not is_manual:
                        # Only auto-stop for water tank in AUTO mode. In MANUAL mode, user has direct override!
                        trip_reason = "Water Reservoir Empty"
                        trip_details = "Water level sensor detected reservoir is empty/low. AI Agent automatically shut down the motor to prevent dry-run burnout."
                    elif soil_saturated:
                        trip_reason = "Optimal Soil Moisture Reached"
                        trip_details = f"Soil moisture reached optimal level ({soil_moist:.1f}%). AI Agent automatically shut down the motor to conserve water."

                    if trip_reason:
                        print()
                        print("************************************************************")
                        print(f"[AI ENVIRONMENT GUARD] TRIP: {trip_reason}")
                        print(f"Details: {trip_details}")
                        print("************************************************************")
                        print()

                        trip_info = {
                            "reason": trip_reason,
                            "details": trip_details,
                            "timestamp": datetime.now(timezone.utc).strftime("%I:%M %p"),
                            "soil_moisture": soil_moist,
                        }
                        set_device_control(mode="MANUAL", manual_pump_request=False, trip_info=trip_info)
                        current_pump_status = "OFF"
                        previous_pump_status = "OFF"
                        if active_irrigation is not None:
                            end_irrigation()

        except Exception as e:

            print(
                f"Irrigation monitor error: {e}"
            )

        await asyncio.sleep(
            CHECK_INTERVAL_SECONDS
        )