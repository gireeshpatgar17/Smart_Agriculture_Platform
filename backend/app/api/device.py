
from datetime import datetime, timezone
from threading import Lock
from typing import Any, Dict

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/api/device", tags=["ESP32 Device"])

state_lock = Lock()

latest_sensors: Dict[str, Any] = {
    "soil_raw": 0,
    "soil_moisture": 0.0,
    "rain_raw": 4095,
    "rain_detected": False,
    "rain_status": "NO RAIN",
    "water_available": True,
    "water_status": "AVAILABLE",
    "temperature": None,
    "humidity": None,
    "pump_on": False,
    "pump_status": "OFF",
    "control_mode": 1,
    "manual_pump_request": 0,
    "rain_lockout": 0,
    "lockout_remaining_seconds": 0,
    "last_environmental_trip": None,
    "updated_at": None,
}

control: Dict[str, Any] = {
    "mode": "MANUAL",
    "manual_pump_request": False,
}


def get_latest_sensors() -> Dict[str, Any]:
    """Return a thread-safe snapshot of the latest sensor telemetry."""
    with state_lock:
        return latest_sensors.copy()


def get_device_control() -> Dict[str, Any]:
    """Return a thread-safe copy of the current device control command."""
    with state_lock:
        return control.copy()


def get_last_environmental_trip() -> Dict[str, Any] | None:
    """Return the last environmental auto-stop event if any."""
    with state_lock:
        trip = latest_sensors.get("last_environmental_trip")
        return trip.copy() if trip else None


def set_device_control(
    mode: str,
    manual_pump_request: bool = False,
    trip_info: Dict[str, Any] | None = None
) -> Dict[str, Any]:
    """Thread-safe update of the device control command."""
    normalized_mode = mode.upper()
    if normalized_mode not in ("AUTO", "MANUAL"):
        raise ValueError("Mode must be AUTO or MANUAL")

    with state_lock:
        control["mode"] = normalized_mode
        control["manual_pump_request"] = (
            bool(manual_pump_request) if normalized_mode == "MANUAL" else False
        )
        latest_sensors["control_mode"] = 1 if normalized_mode == "MANUAL" else 0
        latest_sensors["manual_pump_request"] = 1 if control["manual_pump_request"] else 0
        if normalized_mode == "MANUAL":
            latest_sensors["pump_on"] = control["manual_pump_request"]
            latest_sensors["pump_status"] = "ON" if control["manual_pump_request"] else "OFF"

        if manual_pump_request:
            latest_sensors["last_environmental_trip"] = None
        elif trip_info:
            latest_sensors["last_environmental_trip"] = trip_info

        latest_sensors["updated_at"] = datetime.now(timezone.utc).isoformat()
        return control.copy()


class SensorData(BaseModel):
    soil_raw: int = Field(default=0, ge=0, le=4095)
    soil_moisture: float = Field(default=0.0, ge=0.0, le=100.0)
    rain_raw: int = Field(default=4095, ge=0, le=4095)
    rain_detected: bool
    water_available: bool
    temperature: float | None = None
    humidity: float | None = None
    pump_on: bool
    control_mode: int | None = 0
    manual_pump_request: bool | int | None = False
    rain_lockout: bool | int | None = False
    lockout_remaining_seconds: int | None = 0


class PumpControl(BaseModel):
    mode: str
    manual_pump_request: bool = False


@router.post("/telemetry")
def receive_telemetry(data: SensorData):
    with state_lock:
        payload = data.model_dump()
        latest_sensors.update(payload)

        # Populate derived status strings for frontend and monitor compatibility
        latest_sensors["rain_status"] = "RAIN" if data.rain_detected else "NO RAIN"
        latest_sensors["water_status"] = (
            "AVAILABLE" if data.water_available else "NOT AVAILABLE"
        )
        latest_sensors["pump_status"] = "ON" if data.pump_on else "OFF"
        latest_sensors["control_mode"] = int(data.control_mode or 0)
        latest_sensors["manual_pump_request"] = (
            1 if data.manual_pump_request else 0
        )
        latest_sensors["rain_lockout"] = 1 if data.rain_lockout else 0
        latest_sensors["lockout_remaining_seconds"] = int(
            data.lockout_remaining_seconds or 0
        )
        latest_sensors["updated_at"] = datetime.now(timezone.utc).isoformat()

    return {"received": True}


@router.get("/sensors")
def get_sensors():
    return get_latest_sensors()


@router.get("/command")
def get_command():
    return get_device_control()


@router.post("/control")
def set_control(data: PumpControl):
    mode = data.mode.upper()

    if mode not in ("AUTO", "MANUAL"):
        raise HTTPException(
            status_code=400,
            detail="Mode must be AUTO or MANUAL",
        )

    return set_device_control(mode, data.manual_pump_request)

