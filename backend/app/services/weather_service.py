"""
Weather service using Open-Meteo API (100% Free, No API Key required).
Provides live weather forecast, temperature, humidity, wind speed,
and rain probability for any city.
Includes offline resilience with smart defaults in case college jammers
block external internet connections.
"""

import json
import logging
import urllib.parse
import urllib.request
from typing import Any, Dict

logger = logging.getLogger(__name__)

# Weather code descriptions from WMO Weather interpretation codes
WMO_WEATHER_CODES = {
    0: ("Clear sky", "wb_sunny_rounded"),
    1: ("Mainly clear", "wb_sunny_rounded"),
    2: ("Partly cloudy", "cloud_queue_rounded"),
    3: ("Overcast", "cloud_rounded"),
    45: ("Foggy", "cloud_rounded"),
    48: ("Depositing rime fog", "cloud_rounded"),
    51: ("Light drizzle", "grain_rounded"),
    53: ("Moderate drizzle", "grain_rounded"),
    55: ("Dense drizzle", "grain_rounded"),
    61: ("Slight rain", "water_drop_rounded"),
    63: ("Moderate rain", "water_drop_rounded"),
    65: ("Heavy rain", "thunderstorm_rounded"),
    71: ("Slight snow", "ac_unit_rounded"),
    73: ("Moderate snow", "ac_unit_rounded"),
    75: ("Heavy snow", "ac_unit_rounded"),
    80: ("Slight rain showers", "water_drop_rounded"),
    81: ("Moderate rain showers", "water_drop_rounded"),
    82: ("Violent rain showers", "thunderstorm_rounded"),
    95: ("Thunderstorm", "thunderstorm_rounded"),
    96: ("Thunderstorm with hail", "thunderstorm_rounded"),
    99: ("Heavy thunderstorm with hail", "thunderstorm_rounded"),
}

# Cache to store last known weather per city
_weather_cache: Dict[str, Dict[str, Any]] = {}


def get_default_weather(city: str) -> Dict[str, Any]:
    """Fallback weather when offline or if network is jammed."""
    return {
        "city": city.title(),
        "latitude": 12.9719,
        "longitude": 77.5937,
        "temperature": 27.5,
        "humidity": 68.0,
        "wind_speed": 8.5,
        "rain_probability": 15,
        "weather_code": 1,
        "weather_condition": "Partly Cloudy",
        "rain_expected": False,
        "recommendation": "Low rain probability. Safe for scheduled irrigation.",
        "is_offline": True,
    }


def get_weather_data(city: str = "Bengaluru") -> Dict[str, Any]:
    """
    Fetches real-time weather & rain probability for any city from Open-Meteo.
    """
    clean_city = city.strip() or "Bengaluru"
    cache_key = clean_city.lower()

    try:
        # 1. Geocode City Name -> Lat, Lon
        encoded_name = urllib.parse.quote(clean_city)
        geo_url = f"https://geocoding-api.open-meteo.com/v1/search?name={encoded_name}&count=1&format=json"

        req = urllib.request.Request(
            geo_url,
            headers={"User-Agent": "AgroEYE-Smart-Agriculture/1.0"}
        )
        with urllib.request.urlopen(req, timeout=3.5) as resp:
            geo_data = json.loads(resp.read().decode())

        results = geo_data.get("results")
        if not results:
            if cache_key in _weather_cache:
                return _weather_cache[cache_key]
            return get_default_weather(clean_city)

        lat = results[0].get("latitude", 12.9719)
        lon = results[0].get("longitude", 77.5937)
        resolved_name = results[0].get("name", clean_city)

        # 2. Fetch Open-Meteo Forecast
        forecast_url = (
            f"https://api.open-meteo.com/v1/forecast?"
            f"latitude={lat}&longitude={lon}&"
            f"current=temperature_2m,relative_humidity_2m,wind_speed_10m,precipitation,weather_code&"
            f"hourly=temperature_2m,relative_humidity_2m,wind_speed_10m,precipitation_probability,precipitation&"
            f"forecast_days=1"
        )

        req2 = urllib.request.Request(
            forecast_url,
            headers={"User-Agent": "AgroEYE-Smart-Agriculture/1.0"}
        )
        with urllib.request.urlopen(req2, timeout=4.0) as resp2:
            data = json.loads(resp2.read().decode())

        current = data.get("current", {})
        hourly = data.get("hourly", {})

        temperature = float(current.get("temperature_2m", 28.0))
        humidity = float(current.get("relative_humidity_2m", 70.0))
        wind_speed = float(current.get("wind_speed_10m", 5.0))
        weather_code = int(current.get("weather_code", 1))

        # Rain probability (use next 3 hours maximum or current hour)
        rain_probs = hourly.get("precipitation_probability", [10])
        next_hours_prob = rain_probs[:4] if len(rain_probs) >= 4 else rain_probs
        rain_probability = int(max(next_hours_prob)) if next_hours_prob else 10

        cond_desc, _ = WMO_WEATHER_CODES.get(weather_code, ("Clear sky", "wb_sunny_rounded"))
        rain_expected = rain_probability >= 40 or current.get("precipitation", 0.0) > 0.1

        if rain_expected:
            recommendation = (
                f"Rain probability is high ({rain_probability}%). "
                "Postpone irrigation to conserve water and prevent waterlogging."
            )
        else:
            recommendation = (
                f"Rain probability is low ({rain_probability}%). "
                "Soil moisture should dictate irrigation. Safe to water."
            )

        result = {
            "city": resolved_name,
            "latitude": lat,
            "longitude": lon,
            "temperature": round(temperature, 1),
            "humidity": round(humidity, 1),
            "wind_speed": round(wind_speed, 1),
            "rain_probability": rain_probability,
            "weather_code": weather_code,
            "weather_condition": cond_desc,
            "rain_expected": rain_expected,
            "recommendation": recommendation,
            "is_offline": False,
        }

        _weather_cache[cache_key] = result
        return result

    except Exception as e:
        logger.warning(f"Failed to fetch live weather for '{clean_city}': {e}")
        if cache_key in _weather_cache:
            cached = _weather_cache[cache_key].copy()
            cached["is_offline"] = True
            return cached
        return get_default_weather(clean_city)
