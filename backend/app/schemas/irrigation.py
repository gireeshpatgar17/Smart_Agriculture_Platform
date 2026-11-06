from datetime import datetime
from typing import Optional

from pydantic import BaseModel


class IrrigationCreate(BaseModel):
    farm_id: int
    start_time: Optional[datetime] = None
    end_time: Optional[datetime] = None
    duration_minutes: Optional[float] = None
    mode: Optional[str] = None
    trigger_reason: Optional[str] = None
    soil_moisture_at_start: Optional[float] = None
    soil_raw_at_start: Optional[int] = None
    temperature_at_start: Optional[float] = None
    humidity_at_start: Optional[float] = None
    rain_detected_at_start: Optional[bool] = None
    water_available_at_start: Optional[bool] = None