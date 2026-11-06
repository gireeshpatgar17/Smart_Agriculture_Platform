"""
AgroEYE USB Serial Bridge
-------------------------
Reads live telemetry directly from the ESP32 over USB Serial (e.g. COM4)
and forwards it to the local FastAPI backend (http://127.0.0.1:8000).

Why this is essential:
- 100% OFFLINE: Requires NO Wi-Fi and NO Mobile Data.
- JAMMER-PROOF: Completely immune to college/campus signal jammers.
- Works simultaneously alongside USB debugging (adb reverse) on your phone.
"""

import json
import re
import sys
import time
import requests
import serial
import serial.tools.list_ports

BACKEND_URL = "http://127.0.0.1:8000/api/device/telemetry"
COMMAND_URL = "http://127.0.0.1:8000/api/device/command"
BAUD_RATE = 115200


def find_esp32_port():
    """Auto-detect the ESP32 COM port."""
    ports = list(serial.tools.list_ports.comports())
    if not ports:
        return None

    # Priority 1: Match common USB-UART chips
    for p in ports:
        desc = (p.description or "").upper()
        hwid = (p.hwid or "").upper()
        if any(chip in desc or chip in hwid for chip in ["CH340", "CH9102", "CP210", "FTDI", "USB-SERIAL", "UART"]):
            return p.device

    # Priority 2: COM4 or any available port
    for p in ports:
        if p.device == "COM4":
            return p.device

    return ports[0].device


def parse_telemetry_line(line: str, current_data: dict) -> bool:
    """
    Parses a single line of serial text and updates current_data.
    Returns True if a full telemetry block separator is reached.
    """
    line = line.strip()
    if not line:
        return False

    # Block separator
    if line.startswith("========"):
        return False

    # Soil Raw
    m = re.search(r"Soil Raw(?: ADC)?\s*:\s*(\d+)", line, re.I)
    if m:
        current_data["soil_raw"] = int(m.group(1))
        return False

    # Soil Moisture percentage
    m = re.search(r"Soil Moisture\s*:\s*([\d.]+)\s*%", line, re.I)
    if m:
        current_data["soil_moisture"] = float(m.group(1))
        return False

    # Rain Raw ADC
    m = re.search(r"Rain Raw(?: ADC)?\s*:\s*(\d+)", line, re.I)
    if m:
        current_data["rain_raw"] = int(m.group(1))
        return False

    # Rain Status
    m = re.search(r"Rain Status\s*:\s*(RAIN|NO RAIN)", line, re.I)
    if m:
        current_data["rain_detected"] = (m.group(1).upper() == "RAIN")
        return False

    # Rain Detected inline: e.g. "Rain Raw ADC : 3868 (NO RAIN)"
    m = re.search(r"\((RAIN|NO RAIN)\)", line, re.I)
    if m:
        current_data["rain_detected"] = (m.group(1).upper() == "RAIN")
        return False

    # Water Level / Water Status
    m = re.search(r"Water (?:Level|Status)\s*:\s*(.+)", line, re.I)
    if m:
        status = m.group(1).strip().upper()
        current_data["water_available"] = not any(w in status for w in ["NOT", "EMPTY", "LOW"])
        return False

    # Temperature
    m = re.search(r"Temperature\s*:\s*([\d.]+)\s*C", line, re.I)
    if m:
        current_data["temperature"] = float(m.group(1))
        return False

    # Humidity
    m = re.search(r"Humidity\s*:\s*([\d.]+)\s*%", line, re.I)
    if m:
        current_data["humidity"] = float(m.group(1))
        return False

    # Control Mode
    m = re.search(r"Control Mode\s*:\s*(AUTO|MANUAL)", line, re.I)
    if m:
        current_data["control_mode"] = 1 if m.group(1).upper() == "MANUAL" else 0
        return False

    # Pump State
    m = re.search(r"Pump(?: State)?\s*:\s*(ON|OFF)", line, re.I)
    if m:
        current_data["pump_on"] = (m.group(1).upper() == "ON")
        return False

    # Rain Lockout - End of telemetry block!
    m = re.search(r"Rain Lockout\s*:\s*(ACTIVE|OFF)", line, re.I)
    if m:
        current_data["rain_lockout"] = 1 if m.group(1).upper() == "ACTIVE" else 0
        return True

    # Lockout Remaining Seconds
    m = re.search(r"(?:Remaining|\((\d+)\s*sec remaining\))\s*:?\s*(\d+)?", line, re.I)
    if m:
        sec = m.group(1) or m.group(2)
        if sec:
            current_data["lockout_remaining_seconds"] = int(sec)
        return False

    return False


def main():
    print("=" * 60)
    print("   AgroEYE - USB Serial to Backend Telemetry Bridge")
    print("   (Jammer-Proof, 100% Offline Hardware Mode)")
    print("=" * 60)

    port = find_esp32_port()
    if not port:
        print("\n[!] No serial COM port found. Please plug in your ESP32 via USB!")
        sys.exit(1)

    print(f"\n[*] Found ESP32 on port: {port}")
    print(f"[*] Opening serial connection at {BAUD_RATE} baud...")

    try:
        ser = serial.Serial(port, BAUD_RATE, timeout=0.05)
    except Exception as e:
        print(f"[!] Error opening {port}: {e}")
        print("    If Arduino IDE Serial Monitor is open, please close it first!")
        sys.exit(1)

    print("[+] Connected to ESP32! Listening for sensor telemetry...\n")

    current_data = {
        "soil_raw": 4095,
        "soil_moisture": 0.0,
        "rain_raw": 4095,
        "rain_detected": False,
        "water_available": True,
        "temperature": None,
        "humidity": None,
        "pump_on": False,
        "control_mode": 1,
        "manual_pump_request": 0,
        "rain_lockout": 0,
        "lockout_remaining_seconds": 0,
    }

    session = requests.Session()

    last_post_time = 0
    last_cmd_check = 0
    last_sent_mode = None
    last_sent_pump = None
    last_mismatch_time = 0

    while True:
        try:
            now = time.time()

            # Poll backend for pump control commands every 0.35 seconds
            if (now - last_cmd_check) >= 0.35:
                last_cmd_check = now
                try:
                    cmd_res = session.get(COMMAND_URL, timeout=2.5)
                    if cmd_res.status_code == 200:
                        cmd = cmd_res.json()
                        mode = str(cmd.get("mode", "AUTO")).upper()
                        pump = bool(cmd.get("manual_pump_request", False))

                        esp32_pump = bool(current_data.get("pump_on", False))
                        state_mismatch = (mode == "MANUAL" and esp32_pump != pump)

                        should_send = (
                            mode != last_sent_mode
                            or pump != last_sent_pump
                            or (state_mismatch and (now - last_mismatch_time) >= 2.0)
                        )

                        if should_send:
                            last_sent_mode = mode
                            last_sent_pump = pump
                            last_mismatch_time = now
                            wire_cmd = f"CMD:MODE={mode},PUMP={1 if pump else 0}\n"
                            ser.write(wire_cmd.encode("utf-8"))
                            ser.flush()
                            print(f"\n [BACKEND -> ESP32] Command sent over USB: {wire_cmd.strip()}\n")
                except requests.RequestException:
                    pass

            raw_line = ser.readline()
            if not raw_line:
                continue

            try:
                line = raw_line.decode("utf-8", errors="ignore").strip()
            except Exception:
                continue

            if not line:
                continue

            # Print serial line for user visibility
            print(f" [ESP32] {line}")

            # Check if line contains JSON directly
            if line.startswith("{") and line.endswith("}"):
                try:
                    payload = json.loads(line)
                    res = session.post(BACKEND_URL, json=payload, timeout=3.0)
                    print(f" [BRIDGE -> BACKEND] JSON Posted -> HTTP {res.status_code}")
                    continue
                except Exception:
                    pass

            # Parse formatted text line
            is_separator = parse_telemetry_line(line, current_data)
            if is_separator:
                # Telemetry block completed; send to backend if we have readings
                if (now - last_post_time) >= 1.5:
                    try:
                        res = session.post(BACKEND_URL, json=current_data, timeout=3.0)
                        last_post_time = now
                        temp_str = f"{current_data['temperature']}°C" if current_data.get('temperature') is not None else "N/A"
                        hum_str = f"{current_data['humidity']}%" if current_data.get('humidity') is not None else "N/A"
                        print(
                            f"\n >>> [LIVE SYNC] Temp: {temp_str} | "
                            f"Humidity: {hum_str} | "
                            f"Soil: {current_data['soil_moisture']}% | "
                            f"Pump: {'ON' if current_data.get('pump_on') else 'OFF'} | "
                            f"HTTP {res.status_code} OK\n"
                        )
                    except requests.RequestException as err:
                        print(f" [!] Backend sync waiting (FastAPI restarting or busy): {err}")

        except KeyboardInterrupt:
            print("\nExiting serial bridge...")
            ser.close()
            break
        except Exception as e:
            print(f"[!] Serial error: {e}")
            time.sleep(1)


if __name__ == "__main__":
    main()
