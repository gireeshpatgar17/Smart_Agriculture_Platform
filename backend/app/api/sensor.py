from fastapi import APIRouter

from app.api.device import get_device_control, get_latest_sensors
from app.schemas.sensor import SensorData

router = APIRouter(
    prefix="/sensors",
    tags=["Sensors"]
)


@router.get("/", response_model=SensorData)
def get_sensor_data():
    sensors = get_latest_sensors()
    ctrl = get_device_control()

    def parse_float(val, default=0.0):
        try:
            return float(val) if val is not None else default
        except (ValueError, TypeError):
            return default

    def parse_int(val, default=0):
        try:
            return int(float(val)) if val is not None else default
        except (ValueError, TypeError):
            return default

    control_mode = sensors.get("control_mode")
    if control_mode is None:
        control_mode = 1 if ctrl.get("mode") == "MANUAL" else 0

    manual_request = sensors.get("manual_pump_request")
    if manual_request is None:
        manual_request = 1 if ctrl.get("manual_pump_request") else 0

    return {
        "soil_raw": parse_int(sensors.get("soil_raw"), default=0),
        "soil_moisture": parse_float(sensors.get("soil_moisture"), default=0.0),
        "temperature": parse_float(sensors.get("temperature"), default=0.0) if sensors.get("temperature") is not None else None,
        "humidity": parse_float(sensors.get("humidity"), default=0.0) if sensors.get("humidity") is not None else None,

        "rain_status": str(sensors.get("rain_status") or ("RAIN" if sensors.get("rain_detected") else "NO RAIN")),
        "water_status": str(sensors.get("water_status") or ("AVAILABLE" if sensors.get("water_available") else "NOT AVAILABLE")),
        "pump_status": str(sensors.get("pump_status") or ("ON" if sensors.get("pump_on") else "OFF")),

        "control_mode": parse_int(control_mode, default=0),
        "manual_pump_request": parse_int(manual_request, default=0),
        "rain_lockout": parse_int(sensors.get("rain_lockout"), default=0),
        "lockout_remaining_seconds": parse_int(sensors.get("lockout_remaining_seconds"), default=0),
    }