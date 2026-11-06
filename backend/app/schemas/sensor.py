from pydantic import BaseModel


class SensorData(BaseModel):
    soil_raw: int | None = None
    soil_moisture: float | None = None
    temperature: float | None = None
    humidity: float | None = None
    rain_status: str | None = None
    water_status: str | None = None
    pump_status: str | None = None
    control_mode: int | None = None
    manual_pump_request: int | None = None
    rain_lockout: int | None = None
    lockout_remaining_seconds: int | None = None