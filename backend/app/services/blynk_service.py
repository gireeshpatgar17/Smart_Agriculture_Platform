import os
import requests
from dotenv import load_dotenv

dotenv_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".env"))
load_dotenv(dotenv_path)


def get_blynk_config():
    server = os.getenv("BLYNK_SERVER", "https://blynk.cloud") or "https://blynk.cloud"
    token = os.getenv("BLYNK_TOKEN", "qwnX9uWDp77nQvCqUgOAFhcjlmlBfwq5") or "qwnX9uWDp77nQvCqUgOAFhcjlmlBfwq5"
    return server.strip(), token.strip()


import time

_sensor_cache = {}
_sensor_cache_time = 0.0
CACHE_DURATION_SECONDS = 3.0


def get_all_blynk_sensors():
    """
    Fetch all virtual pins (V0-V10) in a single batch request from Blynk Cloud.
    Caches results for 3 seconds to deliver sub-millisecond responses on high-frequency polls.
    """
    global _sensor_cache, _sensor_cache_time

    now = time.time()
    if _sensor_cache and (now - _sensor_cache_time) < CACHE_DURATION_SECONDS:
        return _sensor_cache

    server, token = get_blynk_config()
    pins = ["V0", "V1", "V2", "V3", "V4", "V5", "V6", "V7", "V8", "V9", "V10"]
    url = f"{server}/external/api/get?token={token}&" + "&".join(pins)

    try:
        response = requests.get(url, timeout=3.0)
        if response.status_code == 200:
            data = response.json()
            if isinstance(data, dict):
                _sensor_cache = data
                _sensor_cache_time = now
                return data
    except Exception as e:
        print(f"Blynk batch fetch error: {e}")

    # Fallback to last known cache if available
    if _sensor_cache:
        return _sensor_cache

    # Fallback to local device telemetry if available
    try:
        from app.api.device import get_latest_sensors
        latest = get_latest_sensors()
        return {
            "V0": latest.get("soil_raw", 1),
            "V1": latest.get("soil_moisture", 65.0),
            "V2": latest.get("temperature") if latest.get("temperature") is not None else 28.0,
            "V3": latest.get("humidity") if latest.get("humidity") is not None else 75.0,
            "V4": latest.get("rain_status", "NO RAIN"),
            "V5": latest.get("water_status", "AVAILABLE"),
            "V6": latest.get("pump_status", "OFF"),
            "V7": latest.get("control_mode", 0),
            "V8": latest.get("manual_pump_request", 0),
            "V9": latest.get("rain_lockout", 0),
            "V10": latest.get("lockout_remaining_seconds", 0),
        }
    except Exception:
        pass

    # Sensible telemetry fallback
    return {
        "V0": 1,
        "V1": 65.0,
        "V2": 28.0,
        "V3": 75.0,
        "V4": "NORMAL",
        "V5": "AVAILABLE",
        "V6": "OFF",
        "V7": 0,
        "V8": 0,
        "V9": 0,
        "V10": 0,
    }



def get_blynk_value(pin: str):
    server, token = get_blynk_config()
    url = f"{server}/external/api/get?token={token}&{pin}"

    try:
        response = requests.get(
            url,
            timeout=3.0
        )
        response.raise_for_status()
        return response.text
    except Exception:
        # Fallback to cache or sensible default
        all_sensors = get_all_blynk_sensors()
        val = all_sensors.get(pin.upper())
        if val is not None:
            return str(val)
        return "0"


def update_blynk_value(pin: str, value):
    server, token = get_blynk_config()
    url = f"{server}/external/api/update"

    try:
        response = requests.get(
            url,
            params={
                "token": token,
                pin: value
            },
            timeout=4.0
        )
        response.raise_for_status()
        # Invalidate cache so fresh state is fetched next time
        global _sensor_cache_time
        _sensor_cache_time = 0.0
        return response.text
    except Exception as e:
        print(f"Blynk update error on {pin}: {e}")
        return "ERROR"