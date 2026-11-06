import 'dart:async';
import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../widgets/sensor_card.dart';
import '../chat/chat_screen.dart';

class DashboardScreen extends StatefulWidget {
  final void Function(int index)? onNavigateTab;

  const DashboardScreen({super.key, this.onNavigateTab});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Sensible default state so the screen renders instantly without infinite loading
  Map<String, dynamic> sensorData = {
    'soil_raw': 1,
    'soil_moisture': 65.0,
    'temperature': 28.1,
    'humidity': 82.2,
    'rain_status': 'NO RAIN',
    'water_status': 'AVAILABLE',
    'pump_status': 'OFF',
    'control_mode': 0,
    'manual_pump_request': 0,
    'rain_lockout': 0,
    'lockout_remaining_seconds': 0,
  };

  String selectedCity = 'Bengaluru';
  Map<String, dynamic> weatherData = {
    'city': 'Bengaluru',
    'temperature': 27.0,
    'humidity': 65.0,
    'wind_speed': 7.5,
    'rain_probability': 15,
    'weather_condition': 'Partly Cloudy',
    'rain_expected': false,
    'recommendation': 'Low rain probability. Safe for scheduled irrigation.',
  };
  bool isWeatherSyncing = false;

  bool isSyncing = false;
  bool isInitialLoaded = false;
  String? syncNotice;
  DateTime lastUpdated = DateTime.now();
  Timer? refreshTimer;

  @override
  void initState() {
    super.initState();
    loadSensorData(isSilent: false);
    loadWeatherData();

    // Refresh every 5 seconds silently in background
    refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => loadSensorData(isSilent: true),
    );
  }

  Future<void> loadWeatherData({String? city}) async {
    final targetCity = city ?? selectedCity;
    setState(() {
      isWeatherSyncing = true;
    });
    try {
      final data = await ApiService.getWeather(targetCity);
      if (!mounted) return;
      setState(() {
        weatherData = data;
        selectedCity = data['city']?.toString() ?? targetCity;
        isWeatherSyncing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        isWeatherSyncing = false;
      });
    }
  }

  Future<void> loadSensorData({bool isSilent = true}) async {
    if (!isSilent) {
      setState(() {
        isSyncing = true;
      });
    }

    try {
      final data = await ApiService.getSensorData();

      if (!mounted) return;

      setState(() {
        sensorData = data;
        isInitialLoaded = true;
        isSyncing = false;
        syncNotice = null;
        lastUpdated = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isInitialLoaded = true;
        isSyncing = false;
        // Keep showing cached data, just update notice
        syncNotice = 'Using cached telemetry';
      });
    }
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primaryGreen = Color(0xFF2E7D32);
    const bgLight = Color(0xFFF8FAF7);

    return Scaffold(
      backgroundColor: bgLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.eco_rounded,
                color: primaryGreen,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Smart Paddy Farm',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: syncNotice == null
                              ? const Color(0xFF10B981)
                              : Colors.amber.shade700,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          syncNotice ?? 'Live IoT Connected',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'AgroEye AI',
            icon: Container(
              padding: const EdgeInsets.all(7),
              decoration: const BoxDecoration(
                color: Color(0xFFE8F5E9),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.smart_toy_rounded,
                color: primaryGreen,
                size: 20,
              ),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ChatScreen()),
              );
            },
          ),
          IconButton(
            tooltip: 'Refresh telemetry',
            icon: isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: primaryGreen,
                    ),
                  )
                : const Icon(
                    Icons.refresh_rounded,
                    color: primaryGreen,
                  ),
            onPressed: () => loadSensorData(isSilent: false),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        color: primaryGreen,
        onRefresh: () async {
          await Future.wait([
            loadSensorData(isSilent: false),
            loadWeatherData(),
          ]);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Hero Field Overview Banner
              _buildHeroCard(),

              const SizedBox(height: 14),

              // 1B. City Weather & Rain Forecast Banner (Same size/styling)
              _buildWeatherHeroCard(),

              const SizedBox(height: 18),

              // 2. Section Header: Field Conditions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Field Telemetry',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  Text(
                    'Auto-syncs every 5s',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // 3. 2x2 Sensor Cards Grid
              _buildSensorGrid(),

              const SizedBox(height: 20),

              // 4. Irrigation & Pump Control Card
              _buildIrrigationCard(),

              const SizedBox(height: 20),

              // 5. Smart Agriculture Quick Actions
              _buildQuickActions(),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard() {
    final soilMoisture = (sensorData['soil_moisture'] as num?)?.toDouble() ?? 65.0;
    final rainStatus = sensorData['rain_status']?.toString().toUpperCase() ?? 'NO RAIN';
    final isRaining = rainStatus.contains('RAIN') && !rainStatus.contains('NO');

    String moistureHealth;
    Color healthColor;
    if (soilMoisture < 40.0) {
      moistureHealth = 'Low Moisture • Irrigation Advised';
      healthColor = const Color(0xFFF59E0B);
    } else if (soilMoisture > 85.0) {
      moistureHealth = 'High Moisture • Well Hydrated';
      healthColor = const Color(0xFF06B6D4);
    } else {
      moistureHealth = 'Optimal Moisture (60% - 80%)';
      healthColor = const Color(0xFF34D399);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF1B4332),
            Color(0xFF2D6A4F),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B4332).withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.grass_rounded, size: 14, color: Colors.white),
                    SizedBox(width: 5),
                    Text(
                      'Crop: Rice (Paddy)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isRaining
                      ? Colors.lightBlue.shade700.withValues(alpha: 0.4)
                      : Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isRaining ? Icons.water_drop_rounded : Icons.wb_sunny_rounded,
                      size: 14,
                      color: isRaining ? Colors.lightBlueAccent : Colors.amberAccent,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isRaining ? 'Rainfall Active' : 'Clear Sky',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Paddy Field Station #1',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            moistureHealth,
            style: TextStyle(
              color: healthColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          // Moisture Bar Indicator
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Soil Moisture Level',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Text(
                    '${soilMoisture.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: (soilMoisture / 100.0).clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  valueColor: AlwaysStoppedAnimation<Color>(healthColor),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // WEATHER & RAIN FORECAST HERO CARD (Identical template size/styling)
  // ==========================================================
  Widget _buildWeatherHeroCard() {
    final city = weatherData['city']?.toString() ?? selectedCity;
    final temp = (weatherData['temperature'] as num?)?.toDouble() ?? 27.0;
    final humidity = (weatherData['humidity'] as num?)?.toDouble() ?? 65.0;
    final wind = (weatherData['wind_speed'] as num?)?.toDouble() ?? 7.5;
    final rainProb = (weatherData['rain_probability'] as num?)?.toInt() ?? 15;
    final condition = weatherData['weather_condition']?.toString() ?? 'Partly Cloudy';

    Color probColor;
    String riskText;
    if (rainProb >= 60) {
      probColor = const Color(0xFFF87171); // Red/Orange
      riskText = 'High Rain Probability • Postpone Irrigation';
    } else if (rainProb >= 35) {
      probColor = const Color(0xFFFBBF24); // Amber
      riskText = 'Moderate Rain Probability • Monitor Weather';
    } else {
      probColor = const Color(0xFF38BDF8); // Cyan/Sky blue
      riskText = 'Low Rain Probability • Safe for Irrigation';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0F2B48),
            Color(0xFF1B4965),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F2B48).withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Pills Row
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_outlined, size: 14, color: Colors.white),
                    SizedBox(width: 5),
                    Text(
                      'Live Weather & Forecast',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: _showChangeCityDialog,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.amberAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.amberAccent.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        size: 14,
                        color: Colors.amberAccent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        city,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Icon(
                        Icons.edit_rounded,
                        size: 13,
                        color: Colors.white70,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Main Forecast Title
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$city Region',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      condition,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (isWeatherSyncing)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white70,
                  ),
                ),
            ],
          ),

          const SizedBox(height: 8),

          // Rain risk guidance text
          Text(
            riskText,
            style: TextStyle(
              color: probColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 14),

          // Rain Probability Bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Precipitation / Rain Probability',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Text(
                    '$rainProb%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: (rainProb / 100.0).clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  valueColor: AlwaysStoppedAnimation<Color>(probColor),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Metric Chips: Temp, Humidity, Wind
          Row(
            children: [
              _buildWeatherMiniChip(Icons.thermostat_rounded, '${temp.toStringAsFixed(1)}°C'),
              const SizedBox(width: 8),
              _buildWeatherMiniChip(Icons.water_drop_outlined, '${humidity.toStringAsFixed(0)}% Hum'),
              const SizedBox(width: 8),
              _buildWeatherMiniChip(Icons.air_rounded, '${wind.toStringAsFixed(1)} km/h'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherMiniChip(IconData icon, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: Colors.white70),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showChangeCityDialog() {
    final textController = TextEditingController(text: selectedCity);
    final popularCities = [
      'Bengaluru',
      'Shimoga',
      'Mysuru',
      'Mangaluru',
      'Hubballi',
      'Belagavi',
      'Delhi',
      'Pune',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Change Farm City / Location',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Real-time rain forecast and probability will be loaded via Open-Meteo.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: textController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Enter city or region name',
                  prefixIcon: const Icon(Icons.location_city_rounded, color: Color(0xFF2E7D32)),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32)),
                    onPressed: () {
                      final input = textController.text.trim();
                      if (input.isNotEmpty) {
                        Navigator.pop(ctx);
                        loadWeatherData(city: input);
                      }
                    },
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (val) {
                  if (val.trim().isNotEmpty) {
                    Navigator.pop(ctx);
                    loadWeatherData(city: val.trim());
                  }
                },
              ),
              const SizedBox(height: 16),
              const Text(
                'Quick Select Regional Cities:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: popularCities.map((c) {
                  final isSelected = c.toLowerCase() == selectedCity.toLowerCase();
                  return ActionChip(
                    label: Text(
                      c,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.white : Colors.grey.shade800,
                      ),
                    ),
                    backgroundColor: isSelected ? const Color(0xFF2E7D32) : Colors.grey.shade100,
                    onPressed: () {
                      Navigator.pop(ctx);
                      loadWeatherData(city: c);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSensorGrid() {
    final temp = sensorData['temperature'];
    final humidity = sensorData['humidity'];
    final soil = sensorData['soil_moisture'];
    final waterStatus = sensorData['water_status']?.toString().toUpperCase() ?? 'AVAILABLE';

    final tempVal = temp is num ? temp.toDouble().toStringAsFixed(1) : (temp?.toString() ?? '28.0');
    final humVal = humidity is num ? humidity.toDouble().toStringAsFixed(1) : (humidity?.toString() ?? '80.0');
    final soilVal = soil is num ? soil.toDouble().toStringAsFixed(1) : (soil?.toString() ?? '65.0');

    final bool waterOk = !waterStatus.contains('NOT') && !waterStatus.contains('LOW');

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: SensorCard(
                title: 'Soil Moisture',
                value: '$soilVal%',
                icon: Icons.grass_rounded,
                status: 'Optimal',
                accentColor: const Color(0xFF2E7D32),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SensorCard(
                title: 'Temperature',
                value: '$tempVal°C',
                icon: Icons.thermostat_rounded,
                status: 'Ideal',
                accentColor: const Color(0xFFE65100),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SensorCard(
                title: 'Air Humidity',
                value: '$humVal%',
                icon: Icons.water_rounded,
                status: 'High',
                accentColor: const Color(0xFF0288D1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SensorCard(
                title: 'Water Supply',
                value: waterOk ? 'Available' : 'Low',
                icon: Icons.water_drop_rounded,
                status: waterOk ? 'Full' : 'Check Tank',
                accentColor: waterOk ? const Color(0xFF1565C0) : const Color(0xFFD32F2F),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIrrigationCard() {
    final pumpStatus = sensorData['pump_status']?.toString().toUpperCase() ?? 'OFF';
    final isPumpOn = pumpStatus == 'ON';
    final rainLockout = (sensorData['rain_lockout'] as num?)?.toInt() ?? 0;
    final lockoutSeconds = (sensorData['lockout_remaining_seconds'] as num?)?.toInt() ?? 0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isPumpOn
                      ? Colors.blue.shade50
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.water_drop_rounded,
                  color: isPumpOn ? Colors.blue.shade700 : Colors.grey.shade600,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Irrigation Pump',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isPumpOn ? 'Actively watering the field' : 'Pump currently standby',
                      style: TextStyle(
                        fontSize: 12,
                        color: isPumpOn ? Colors.blue.shade700 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isPumpOn ? Colors.blue.shade100 : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isPumpOn ? 'RUNNING' : 'STANDBY',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isPumpOn ? Colors.blue.shade800 : Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),

          if (rainLockout == 1 && lockoutSeconds > 0) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.umbrella_rounded, size: 18, color: Colors.amber.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Rain lockout active ($lockoutSeconds s remaining)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick AI Actions',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildActionTile(
                title: 'Disease Doctor',
                subtitle: 'Scan rice leaves',
                icon: Icons.camera_alt_rounded,
                color: const Color(0xFF2E7D32),
                onTap: () {
                  if (widget.onNavigateTab != null) {
                    widget.onNavigateTab!(2); // AI Tab
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionTile(
                title: 'Ask AI Advisor',
                subtitle: 'Smart farm chat',
                icon: Icons.smart_toy_rounded,
                color: const Color(0xFF1565C0),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ChatScreen(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
