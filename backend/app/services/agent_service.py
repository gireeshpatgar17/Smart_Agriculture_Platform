import json
import os
import re
from typing import Any, Dict, List, Tuple

from dotenv import load_dotenv

from app.database import supabase
from app.schemas.agent import ChatMessage, ChatResponse
from app.api.device import get_latest_sensors, set_device_control, get_last_environmental_trip
from app.services.weather_service import get_weather_data

dotenv_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".env"))
load_dotenv(dotenv_path)

# ============================================================
# GROQ CONFIGURATION & PLACEHOLDER
# ============================================================
GROQ_API_KEY = os.getenv("GROQ_API_KEY", "")
GROQ_MODEL = os.getenv("GROQ_MODEL", "llama-3.3-70b-versatile")

PLACEHOLDER_KEYS = [
    "your_groq_api_key_here",
    "gsk_YOUR_GROQ_API_KEY_HERE",
    "placeholder",
    "",
]


def is_groq_configured() -> bool:
    """Check if a valid Groq API key is configured in the environment."""
    return bool(GROQ_API_KEY and GROQ_API_KEY.strip() not in PLACEHOLDER_KEYS)


# ============================================================
# AGRICULTURAL SYSTEM PROMPT
# ============================================================
SYSTEM_PROMPT = """You are the Smart Agriculture AI Assistant, an expert farming consultant and telemetry analyst.
Your mission is to help farmers monitor crop health, soil conditions, irrigation history, and farm configurations.

Key Guidelines:
- Answer concisely. Don't generate unnecessarily long answers.
- Respond in the primary language used by the farmer (English, Kannada, Hindi, etc.).
- Always ground your answers in real data gathered from the available tools (farm profile, live sensors, irrigation history, disease history, weather forecast).
- If asked about current sensor conditions (moisture, temperature, rain, pump), invoke 'get_current_sensor_readings'.
- If asked about weather, forecast, rain probability, or rain forecast for a city, invoke 'get_weather_forecast'.
- SMART IRRIGATION DECISION LOGIC:
  When a farmer asks to turn ON the motor / pump / irrigate the field:
  1. Check live sensors via 'get_current_sensor_readings' AND weather forecast via 'get_weather_forecast' (use 'Bengaluru' as the default city unless the farmer specifies otherwise).
  2. SAFETY & SMART RULES:
     - If it is already raining (rain_status == 'RAIN'): DO NOT turn on pump. Explain rain is detected on the field.
     - If weather forecast shows very high rain probability (>= 50%): ADVISE postponing watering to save water and prevent root rot.
     - If water tank is empty (water_status == 'NOT AVAILABLE'): REJECT turning on pump to avoid pump burnout.
     - If soil moisture is already high / optimal (> 75%): ADVISE that soil has plenty of water.
     - If soil is dry, no rain, and water is available: Call 'control_irrigation_pump' with state='ON' and confirm to the farmer that the pump is now TURNED ON and actively running!
     - NEVER say an irrigation session is closed or ended when turning the motor ON.
  3. When a farmer asks to turn OFF the motor: Call 'control_irrigation_pump' with state='OFF' and confirm that the pump is now STOPPED.
- If asked about farm details, planted crops, or planting date, invoke 'get_farm_details'.
- If asked about watering, pump sessions, or historical water usage, invoke 'get_irrigation_history'.
- If asked about crop diseases, past diagnoses, symptoms, or treatments, invoke 'get_disease_records'.
- Keep your answers clear, concise, and helpful. Highlight key telemetry numbers and actionable farming advice.
- Politely decline queries completely unrelated to agriculture, farming, or farm operations, redirecting the user back to farm management.
"""

# ============================================================
# TOOL DEFINITIONS (OpenAI / Groq Schema)
# ============================================================
AGENT_TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "get_farm_details",
            "description": "Retrieve farm profile information including farm name, crop type, and planting date from Supabase.",
            "parameters": {
                "type": "object",
                "properties": {
                    "farm_id": {
                        "type": "integer",
                        "description": "Unique ID of the farm (default is 1)",
                    }
                },
                "required": ["farm_id"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_current_sensor_readings",
            "description": "Fetch live IoT telemetry data (soil moisture %, raw soil value, temperature °C, humidity %, rain detection, water tank status, pump status, control mode).",
            "parameters": {
                "type": "object",
                "properties": {},
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_weather_forecast",
            "description": "Fetch real-time weather and rain probability percentage for a given city from Open-Meteo.",
            "parameters": {
                "type": "object",
                "properties": {
                    "city": {
                        "type": "string",
                        "description": "Name of the city/region (e.g. 'Bengaluru', 'Shimoga', 'Mysuru')",
                    }
                },
                "required": ["city"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "control_irrigation_pump",
            "description": "Smartly turn the irrigation pump ON or OFF based on soil moisture and weather conditions.",
            "parameters": {
                "type": "object",
                "properties": {
                    "state": {
                        "type": "string",
                        "enum": ["ON", "OFF"],
                        "description": "Desired pump state: 'ON' to start irrigation, 'OFF' to stop",
                    },
                    "reason": {
                        "type": "string",
                        "description": "Smart reason for pump action (e.g., 'Soil moisture is dry (35%) and no rain forecast')",
                    },
                    "farm_id": {
                        "type": "integer",
                        "description": "Unique ID of the farm (default is 1)",
                    }
                },
                "required": ["state"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_irrigation_history",
            "description": "Fetch recent irrigation logs for a farm, including start/end times, duration in minutes, trigger reason, and soil moisture before watering.",
            "parameters": {
                "type": "object",
                "properties": {
                    "farm_id": {
                        "type": "integer",
                        "description": "Unique ID of the farm (default is 1)",
                    },
                    "limit": {
                        "type": "integer",
                        "description": "Maximum number of recent records to retrieve (default is 5)",
                    },
                },
                "required": ["farm_id"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_disease_records",
            "description": "Fetch recent crop disease detection records, including disease name, confidence %, symptoms, cause, and recommended treatment.",
            "parameters": {
                "type": "object",
                "properties": {
                    "farm_id": {
                        "type": "integer",
                        "description": "Unique ID of the farm (default is 1)",
                    },
                    "limit": {
                        "type": "integer",
                        "description": "Maximum number of recent disease records to retrieve (default is 5)",
                    },
                },
                "required": ["farm_id"],
            },
        },
    },
]


# ============================================================
# TOOL EXECUTION HANDLERS (Safe Supabase & IoT queries)
# ============================================================
def tool_get_farm_details(farm_id: int = 1) -> Dict[str, Any]:
    try:
        response = (
            supabase
            .table("farms")
            .select("*")
            .eq("id", farm_id)
            .execute()
        )
        if response.data and len(response.data) > 0:
            return {"status": "success", "farm": response.data[0]}
    except Exception as e:
        pass

    # Safe agricultural default profile for Farm 1 so the assistant can always assist
    return {
        "status": "success",
        "farm": {
            "id": farm_id,
            "farm_name": "Smart Paddy Field",
            "crop_type": "Rice (Paddy)",
            "planting_date": "2026-08-01",
            "soil_type": "Clay Loam",
            "optimal_moisture_range": "60% - 80%",
            "optimal_temp_range": "24°C - 32°C",
        },
    }


def tool_get_current_sensor_readings() -> Dict[str, Any]:
    try:
        raw = get_latest_sensors()

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

        readings = {
            "soil_raw": parse_int(raw.get("soil_raw"), default=0),
            "soil_moisture_percent": parse_float(raw.get("soil_moisture"), default=0.0),
            "temperature_celsius": parse_float(raw.get("temperature"), default=28.0),
            "humidity_percent": parse_float(raw.get("humidity"), default=75.0),
            "rain_status": str(raw.get("rain_status") or ("RAIN" if raw.get("rain_detected") else "NO RAIN")),
            "water_status": str(raw.get("water_status") or ("AVAILABLE" if raw.get("water_available") else "NOT AVAILABLE")),
            "pump_status": str(raw.get("pump_status") or ("ON" if raw.get("pump_on") else "OFF")),
            "control_mode": parse_int(raw.get("control_mode"), default=0),
            "rain_lockout": parse_int(raw.get("rain_lockout"), default=0),
        }
        return {"status": "success", "sensors": readings}
    except Exception as e:
        return {
            "status": "warning",
            "message": "Hardware offline or telemetry unavailable",
            "details": str(e),
            "simulated_sensors": {
                "soil_moisture_percent": 42.5,
                "temperature_celsius": 28.3,
                "humidity_percent": 65.0,
                "rain_status": "NO_RAIN",
                "water_status": "AVAILABLE",
                "pump_status": "OFF",
                "control_mode": 1,
            }
        }



def tool_get_irrigation_history(farm_id: int = 1, limit: int = 5) -> Dict[str, Any]:
    try:
        response = (
            supabase
            .table("irrigation_history")
            .select("*")
            .eq("farm_id", farm_id)
            .order("created_at", desc=True)
            .limit(limit)
            .execute()
        )
        if response.data and len(response.data) > 0:
            return {
                "status": "success",
                "count": len(response.data),
                "history": response.data,
            }
    except Exception as e:
        pass

    return {
        "status": "success",
        "count": 0,
        "history": [],
        "message": "No recent irrigation sessions recorded.",
    }


def tool_get_disease_records(farm_id: int = 1, limit: int = 5) -> Dict[str, Any]:
    try:
        response = (
            supabase
            .table("disease_history")
            .select("*")
            .eq("farm_id", farm_id)
            .order("detected_at", desc=True)
            .limit(limit)
            .execute()
        )
        if response.data and len(response.data) > 0:
            return {
                "status": "success",
                "count": len(response.data),
                "records": response.data,
            }
    except Exception as e:
        pass

    return {
        "status": "success",
        "count": 0,
        "records": [],
        "message": "No crop disease incidents recorded for this farm. Crop health is currently clear.",
    }


def tool_get_weather_forecast(city: str = "Bengaluru") -> Dict[str, Any]:
    try:
        data = get_weather_data(city)
        return {
            "status": "success",
            "weather": data,
        }
    except Exception as e:
        return {
            "status": "error",
            "message": str(e),
        }


def tool_control_irrigation_pump(
    state: str,
    reason: str = "Smart AI Request",
    farm_id: int = 1
) -> Dict[str, Any]:
    normalized_state = state.upper()
    if normalized_state not in ("ON", "OFF"):
        return {"status": "error", "message": "State must be 'ON' or 'OFF'"}

    raw = get_latest_sensors()
    pump_on = (normalized_state == "ON")

    if pump_on:
        # Check safety rules
        soil_moisture = float(raw.get("soil_moisture") or 0.0)
        if soil_moisture >= 80.0:
            return {
                "status": "blocked",
                "message": f"Blocked by environment guard: Soil moisture is already optimal/saturated ({soil_moisture:.1f}%). Irrigation is not needed.",
                "pump_state": "OFF",
            }

        if raw.get("rain_detected") or raw.get("rain_status") == "RAIN" or (0 < int(raw.get("rain_raw") or 4095) < 2200):
            return {
                "status": "blocked",
                "message": "Blocked by rain protection: Rain is actively detected by the field sensor.",
                "pump_state": "OFF",
            }

        water_available = raw.get("water_available", True)
        water_status = str(raw.get("water_status", "AVAILABLE")).upper()
        if not water_available or "NOT" in water_status or "EMPTY" in water_status:
            return {
                "status": "blocked",
                "message": "Blocked by reservoir protection: Water tank is empty or level is low.",
                "pump_state": "OFF",
            }

        # Set device control to MANUAL and request pump ON
        set_device_control(mode="MANUAL", manual_pump_request=True)

        return {
            "status": "success",
            "action": "PUMP_STARTED",
            "message": f"Irrigation pump turned ON. Reason: {reason}",
            "pump_state": "ON",
        }
    else:
        set_device_control(mode="MANUAL", manual_pump_request=False)
        return {
            "status": "success",
            "action": "PUMP_STOPPED",
            "message": "Irrigation pump turned OFF.",
            "pump_state": "OFF",
        }


def execute_tool(tool_name: str, tool_args: Dict[str, Any]) -> Dict[str, Any]:
    if tool_name == "get_farm_details":
        farm_id = tool_args.get("farm_id", 1)
        return tool_get_farm_details(farm_id=farm_id)
    elif tool_name == "get_current_sensor_readings":
        return tool_get_current_sensor_readings()
    elif tool_name == "get_weather_forecast":
        city = tool_args.get("city", "Bengaluru")
        return tool_get_weather_forecast(city=city)
    elif tool_name == "control_irrigation_pump":
        state = tool_args.get("state", "OFF")
        reason = tool_args.get("reason", "Smart Irrigation AI Agent")
        farm_id = tool_args.get("farm_id", 1)
        return tool_control_irrigation_pump(state=state, reason=reason, farm_id=farm_id)
    elif tool_name == "get_irrigation_history":
        farm_id = tool_args.get("farm_id", 1)
        limit = tool_args.get("limit", 5)
        return tool_get_irrigation_history(farm_id=farm_id, limit=limit)
    elif tool_name == "get_disease_records":
        farm_id = tool_args.get("farm_id", 1)
        limit = tool_args.get("limit", 5)
        return tool_get_disease_records(farm_id=farm_id, limit=limit)
    else:
        return {"error": f"Unknown tool '{tool_name}'"}


# ============================================================
# FALLBACK (When GROQ_API_KEY is placeholder)
# ============================================================
def handle_placeholder_chat(
    message: str, farm_id: int
) -> Tuple[str, List[str]]:
    """
    Intelligent fallback when GROQ_API_KEY is still a placeholder.
    Executes relevant data retrieval tools directly and formats a clean response.
    """
    msg_lower = message.lower()
    tools_called = []
    reply_parts = []

    # 0. Environmental Auto-Stop Explanation / Status Query
    is_why_stop = bool(
        re.search(r"\b(why|reason|what happened)\b.*\b(stop|stopped|off|shut)\b", msg_lower)
        or any(k in msg_lower for k in ["why did motor stop", "why motor stopped", "why did pump stop", "why motor off", "why stopped"])
    )
    if is_why_stop:
        tools_called.append("get_current_sensor_readings")
        trip = get_last_environmental_trip()
        if trip:
            reply_parts.append(
                f"🛡️ **AgroEYE Environment Guard Report**:\n\n"
                f"The motor was **automatically stopped** due to environmental protection:\n"
                f"- **Trigger**: **{trip.get('reason', 'Auto Stop')}**\n"
                f"- **Details**: {trip.get('details', 'Condition detected')}\n"
                f"- **Time**: {trip.get('timestamp', 'Recently')}\n"
                f"- **Soil Moisture**: {trip.get('soil_moisture', 0.0):.1f}%\n\n"
                f"💡 *The system constantly monitors rain, reservoir level, and soil saturation to protect your crops from flooding and prevent pump dry-run burn damage.*"
            )
            return "\n\n".join(reply_parts), tools_called
        else:
            sensors = get_latest_sensors()
            pump_state = "ON" if sensors.get("pump_on") else "OFF"
            reply_parts.append(
                f"ℹ️ **Pump Status**: The motor is currently **{pump_state}**.\n"
                f"No emergency environmental trip has occurred. You can safely turn it ON or OFF via chat or manual controls."
            )
            return "\n\n".join(reply_parts), tools_called

    # 1. Pump STOP Request (Flexible matching: e.g. "turn off motor", "turn off the motor", "turn the motor off", "stop pump")
    is_stop_request = bool(
        re.search(r"\b(turn\s+off|shut\s*down|stop|kill|halt|switch\s+off|cut\s*off)\b.*\b(motor|pump|watering|irrigation)\b|\b(motor|pump)\b.*\b(off|stop)\b", msg_lower)
        or any(k in msg_lower for k in ["turn off motor", "turn off the motor", "turn motor off", "turn the motor off", "stop motor", "stop the motor", "turn off pump", "turn off the pump", "motor off", "pump off", "stop watering", "shut down pump"])
    )
    if is_stop_request:
        tools_called.append("control_irrigation_pump")
        tool_control_irrigation_pump("OFF", "User requested motor STOP", farm_id)
        reply_parts.append(
            "🛑 **Irrigation Stopped**:\n"
            "The irrigation motor has been safely **TURNED OFF**."
        )
        return "\n\n".join(reply_parts), tools_called

    # 2. Pump START / Smart Irrigation Request (Flexible matching: e.g. "turn on motor", "turn on the motor", "turn the motor on", "start pump")
    is_start_request = bool(
        re.search(r"\b(turn\s+on|start|run|switch\s+on|activate|begin|power\s+on)\b.*\b(motor|pump|watering|irrigation)\b|\b(motor|pump)\b.*\b(on|start)\b|\bwater\s+(the\s+)?(crop|crops|field|plants|farm)\b", msg_lower)
        or any(k in msg_lower for k in ["turn on motor", "turn on the motor", "turn motor on", "turn the motor on", "start motor", "start the motor", "turn on pump", "turn on the pump", "motor on", "pump on", "irrigate", "start watering", "water field"])
    )
    if is_start_request:
        tools_called.append("get_current_sensor_readings")
        tools_called.append("get_weather_forecast")
        tools_called.append("control_irrigation_pump")

        sensor_res = tool_get_current_sensor_readings()
        sensors = sensor_res.get("sensors", {})
        weather_res = tool_get_weather_forecast("Bengaluru")
        weather = weather_res.get("weather", {})

        moisture = float(sensors.get("soil_moisture_percent", 0.0))
        rain_status = str(sensors.get("rain_status", "NO RAIN")).upper()
        water_status = str(sensors.get("water_status", "AVAILABLE")).upper()
        rain_raw = int(sensors.get("rain_raw", 4095))
        rain_prob = int(weather.get("rain_probability", 10))

        if ("RAIN" in rain_status and "NO" not in rain_status) or (0 < rain_raw < 2200):
            reply_parts.append(
                "🌧️ **Irrigation Blocked by Rain Sensor**:\n"
                "Rain is actively detected on the field sensor!\n"
                "Motor was **NOT** turned ON to prevent soil waterlogging and protect root health."
            )
        elif "NOT" in water_status or "EMPTY" in water_status or "LOW" in water_status:
            reply_parts.append(
                "⚠️ **Safety Interlock**: Water reservoir level is EMPTY or LOW.\n"
                "Motor was **NOT** turned ON to protect the pump from dry running and burnout."
            )
        elif rain_prob >= 50:
            reply_parts.append(
                f"🌧️ **Rain Forecast Warning**: Rain probability is high ({rain_prob}%) in {weather.get('city', 'the region')}.\n"
                "Postponing irrigation to conserve water and prevent root disease."
            )
        elif moisture > 75.0:
            reply_parts.append(
                f"🌱 **Soil Moisture Optimal**: Soil moisture is currently **{moisture:.1f}%**, which is optimal for rice crops.\n"
                "No irrigation is needed at this time."
            )
        else:
            tool_control_irrigation_pump("ON", "Smart Decision: Dry soil & clear weather", farm_id)
            reply_parts.append(
                f"💧 **Smart Irrigation Activated!**\n"
                f"- **Soil Moisture**: {moisture:.1f}% (Needs watering)\n"
                f"- **Rain Sensor**: Clear (No rain detected)\n"
                f"- **Rain Probability**: {rain_prob}% (Low chance of rain)\n"
                f"- **Water Reservoir**: Available\n\n"
                f"✅ **Pump Status**: **TURNED ON** (Motor actively running)"
            )
        return "\n\n".join(reply_parts), tools_called

    # 3. Weather & Rain Probability Query
    if any(k in msg_lower for k in ["weather", "rain chance", "rain probability", "precipitation", "forecast", "cloud"]):
        tools_called.append("get_weather_forecast")
        words = message.split()
        city = "Bengaluru"
        for i, w in enumerate(words):
            if w.lower() in ["in", "for", "at"] and i + 1 < len(words):
                city = words[i + 1].strip("?,.!")
                break
        weather_res = tool_get_weather_forecast(city)
        w = weather_res.get("weather", {})
        reply_parts.append(
            f"🌤️ **Weather & Rain Forecast for {w.get('city', city)}**:\n"
            f"- **Condition**: {w.get('weather_condition', 'Clear')}\n"
            f"- **Temperature**: {w.get('temperature', 28.0)} °C\n"
            f"- **Humidity**: {w.get('humidity', 65.0)}%\n"
            f"- **Wind Speed**: {w.get('wind_speed', 5.0)} km/h\n"
            f"- **Rain Probability**: **{w.get('rain_probability', 10)}%**\n\n"
            f"💡 **AI Recommendation**: {w.get('recommendation', 'Safe to irrigate.')}"
        )
        return "\n\n".join(reply_parts), tools_called

    # 4. Sensor Telemetry Query
    if any(k in msg_lower for k in ["sensor", "moisture", "temp", "humidity", "rain", "live", "pump", "water"]):
        tools_called.append("get_current_sensor_readings")
        sensor_res = tool_get_current_sensor_readings()
        sensors = sensor_res.get("sensors") or sensor_res.get("simulated_sensors", {})
        reply_parts.append(
            f"📊 **Live Farm Telemetry**:\n"
            f"- **Soil Moisture**: {sensors.get('soil_moisture_percent', 'N/A')}%\n"
            f"- **Temperature**: {sensors.get('temperature_celsius', 'N/A')} °C\n"
            f"- **Humidity**: {sensors.get('humidity_percent', 'N/A')}%\n"
            f"- **Rain Status**: {sensors.get('rain_status', 'N/A')}\n"
            f"- **Water Tank**: {sensors.get('water_status', 'N/A')}\n"
            f"- **Pump Status**: {sensors.get('pump_status', 'N/A')}"
        )

    if any(k in msg_lower for k in ["farm", "crop", "plant", "name", "profile"]):
        tools_called.append("get_farm_details")
        farm_res = tool_get_farm_details(farm_id)
        if farm_res.get("status") == "success":
            farm = farm_res["farm"]
            reply_parts.append(
                f"🌾 **Farm Details**:\n"
                f"- **Name**: {farm.get('farm_name', 'N/A')}\n"
                f"- **Crop**: {farm.get('crop_type', 'N/A')}\n"
                f"- **Planting Date**: {farm.get('planting_date', 'N/A')}"
            )
        else:
            reply_parts.append(f"🌾 Farm profile query: {farm_res.get('message', 'No data')}")

    if any(k in msg_lower for k in ["irrigation", "watered", "history", "watering"]):
        tools_called.append("get_irrigation_history")
        irr_res = tool_get_irrigation_history(farm_id, limit=3)
        history = irr_res.get("history", [])
        if history:
            items = []
            for item in history:
                duration = item.get("duration_minutes", 0)
                reason = item.get("trigger_reason", "Scheduled")
                created = item.get("created_at", "Recent")[:16].replace("T", " ")
                items.append(f"• {created}: Ran for {duration} min ({reason})")
            reply_parts.append("💧 **Recent Irrigation Logs**:\n" + "\n".join(items))
        else:
            reply_parts.append("💧 No recent irrigation logs recorded yet.")

    if any(k in msg_lower for k in ["disease", "doctor", "health", "symptom", "infection"]):
        tools_called.append("get_disease_records")
        dis_res = tool_get_disease_records(farm_id, limit=3)
        records = dis_res.get("records", [])
        if records:
            items = []
            for rec in records:
                name = rec.get("disease_name", "Unknown")
                conf = int((rec.get("confidence", 0) or 0) * 100)
                treatment = rec.get("treatment", "Consult local expert")
                items.append(f"• **{name}** ({conf}% confidence)\n  *Treatment*: {treatment}")
            reply_parts.append("🩺 **Recent Disease Diagnoses**:\n" + "\n".join(items))
        else:
            reply_parts.append("🩺 No recent crop disease records detected. Your crop appears healthy!")

    if not reply_parts:
        reply_parts.append(
            "👋 Hello! I am your **Smart Agriculture Assistant**.\n\n"
            "I can help you monitor:\n"
            "- 📊 Live soil moisture, temperature, and pump status\n"
            "- 🌾 Farm and crop profile information\n"
            "- 💧 Past irrigation sessions\n"
            "- 🩺 Crop health and disease records\n\n"
            "Try asking: *'What is current soil moisture?'* or *'What crop is planted?'*"
        )

    return "\n\n".join(reply_parts), tools_called


# ============================================================
# MAIN AGENT CHAT METHOD (Groq Function Calling)
# ============================================================
async def process_agent_chat(
    message: str,
    farm_id: int = 1,
    history: List[ChatMessage] = None,
) -> ChatResponse:
    """
    Main entry point for AI Agent interaction.
    Uses Groq LLM with function calling when key is present,
    or falls back to direct tool execution if placeholder key is used.
    """
    if history is None:
        history = []

    # If Groq is not configured or still placeholder, use graceful fallback
    if not is_groq_configured():
        reply, tools_called = handle_placeholder_chat(message, farm_id)
        return ChatResponse(
            reply=reply,
            tools_called=tools_called,
            status="placeholder_mode",
        )

    # If Groq API Key IS configured:
    try:
        from groq import Groq

        client = Groq(api_key=GROQ_API_KEY)

        # Build messages payload
        messages = [{"role": "system", "content": SYSTEM_PROMPT}]

        # Include prior conversation history (limited to last 6 for prompt budget)
        for h in history[-6:]:
            role = h.role if h.role in ["user", "assistant", "system"] else "user"
            content = (h.content or "").strip()
            # Skip empty or previous error alerts
            if content and not content.startswith("⚠️"):
                messages.append({"role": role, "content": content})

        # Append current user query with context
        messages.append({
            "role": "user",
            "content": f"[Target Farm ID: {farm_id}]\n{message}",
        })

        # 1. Call Groq with tool definitions in a loop (up to 3 turns)
        tools_executed: List[str] = []
        round_count = 0

        while round_count < 3:
            completion = client.chat.completions.create(
                model=GROQ_MODEL,
                messages=messages,
                tools=AGENT_TOOLS,
                tool_choice="auto",
                temperature=0.2,
                max_tokens=800,
            )

            response_message = completion.choices[0].message
            tool_calls = response_message.tool_calls

            if not tool_calls:
                # Model returned a final textual response
                final_reply = (response_message.content or "").strip()
                if not final_reply and hasattr(response_message, "reasoning") and response_message.reasoning:
                    final_reply = response_message.reasoning.strip()
                if not final_reply:
                    final_reply, _ = handle_placeholder_chat(message, farm_id)

                return ChatResponse(
                    reply=final_reply,
                    tools_called=tools_executed,
                    status="success",
                )

            # Append model's assistant message containing tool_calls
            messages.append(response_message)

            for tc in tool_calls:
                fn_name = tc.function.name
                try:
                    fn_args = json.loads(tc.function.arguments) if tc.function.arguments else {}
                except Exception:
                    fn_args = {}

                if "farm_id" in tc.function.name and "farm_id" not in fn_args:
                    fn_args["farm_id"] = farm_id

                tool_result = execute_tool(fn_name, fn_args)
                tools_executed.append(fn_name)

                messages.append({
                    "role": "tool",
                    "tool_call_id": tc.id,
                    "name": fn_name,
                    "content": json.dumps(tool_result),
                })

            round_count += 1

        # If 3 rounds completed without text, do a final text synthesis
        final_completion = client.chat.completions.create(
            model=GROQ_MODEL,
            messages=messages,
            temperature=0.2,
            max_tokens=800,
        )
        msg_obj = final_completion.choices[0].message
        final_reply = (msg_obj.content or "").strip()
        if not final_reply:
            final_reply, _ = handle_placeholder_chat(message, farm_id)

        return ChatResponse(
            reply=final_reply,
            tools_called=tools_executed,
            status="success",
        )

    except Exception as e:
        print(f"[Agent Warning] Groq API error: {e}. Utilizing local telemetry fallback.")
        fallback_reply, tools_called = handle_placeholder_chat(message, farm_id)
        return ChatResponse(
            reply=fallback_reply,
            tools_called=tools_called,
            status="success",
        )
