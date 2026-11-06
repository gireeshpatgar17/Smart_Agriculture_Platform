from fastapi import APIRouter
from app.database import supabase
from app.schemas.irrigation import IrrigationCreate

router = APIRouter(
    prefix="/irrigation",
    tags=["Irrigation"]
)


@router.get("/{farm_id}")
def get_irrigation_history(farm_id: int):
    response = (
        supabase
        .table("irrigation_history")
        .select("*")
        .eq("farm_id", farm_id)
        .order("created_at", desc=True)
        .execute()
    )

    return response.data


@router.post("/")
def create_irrigation_event(irrigation: IrrigationCreate):
    data = {
        "farm_id": irrigation.farm_id,
        "start_time": irrigation.start_time.isoformat() if irrigation.start_time else None,
        "end_time": irrigation.end_time.isoformat() if irrigation.end_time else None,
        "duration_minutes": irrigation.duration_minutes,
        "mode": irrigation.mode,
        "trigger_reason": irrigation.trigger_reason,
        "soil_moisture_at_start": irrigation.soil_moisture_at_start,
        "soil_raw_at_start": irrigation.soil_raw_at_start,
        "temperature_at_start": irrigation.temperature_at_start,
        "humidity_at_start": irrigation.humidity_at_start,
        "rain_detected_at_start": irrigation.rain_detected_at_start,
        "water_available_at_start": irrigation.water_available_at_start,
    }

    response = (
        supabase
        .table("irrigation_history")
        .insert(data)
        .execute()
    )

    return response.data
@router.get("/{farm_id}/summary")
def get_irrigation_summary(farm_id: int):
    response = (
        supabase
        .table("irrigation_history")
        .select("duration_minutes, mode, trigger_reason")
        .eq("farm_id", farm_id)
        .execute()
    )

    records = response.data

    total_events = len(records)

    total_duration = sum(
        float(record["duration_minutes"] or 0)
        for record in records
    )

    auto_events = sum(
        1
        for record in records
        if record["mode"] == "AUTO"
    )

    manual_events = sum(
        1
        for record in records
        if record["mode"] == "MANUAL"
    )

    return {
        "total_events": total_events,
        "total_duration_minutes": total_duration,
        "auto_events": auto_events,
        "manual_events": manual_events
    }