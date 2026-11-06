from fastapi import APIRouter, Query
from app.services.weather_service import get_weather_data

router = APIRouter(
    prefix="/weather",
    tags=["Weather"]
)


@router.get("/")
def get_weather(city: str = Query("Bengaluru", description="City name to fetch weather and rain probability for")):
    """
    Get current weather, temperature, humidity, wind speed,
    and rain probability for the specified city via Open-Meteo.
    """
    return get_weather_data(city)
