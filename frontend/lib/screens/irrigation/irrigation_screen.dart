import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/api_service.dart';

class IrrigationScreen extends StatefulWidget {
  const IrrigationScreen({super.key});

  @override
  State<IrrigationScreen> createState() => _IrrigationScreenState();
}

class _IrrigationScreenState extends State<IrrigationScreen> {
  // ==========================================================
  // REAL SENSOR DATA
  // ==========================================================

  double soilMoisture = 0.0;
  double temperature = 0.0;
  double humidity = 0.0;

  bool waterAvailable = false;
  bool rainDetected = false;

  // ==========================================================
  // IRRIGATION STATE
  // ==========================================================

  // false = AUTO
  // true  = MANUAL
  bool manualMode = false;

  // Real pump state from ESP32/Blynk
  bool motorOn = false;

  // Rain lockout
  bool rainLockout = false;

  // Remaining rain lockout time
  int lockoutSeconds = 0;

  // Environment Guard Auto-Trip Information
  Map<String, dynamic>? lastTrip;

  // ==========================================================
  // API / REFRESH STATE
  // ==========================================================

  bool isLoading = true;
  String? errorMessage;

  Timer? refreshTimer;

  // ==========================================================
  // INIT
  // ==========================================================

  @override
  void initState() {
    super.initState();

    // Load data immediately when screen opens.
    refreshData();

    // Automatically refresh every 1.5 seconds for instant real-time sync.
    refreshTimer = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => refreshData(),
    );
  }

  // ==========================================================
  // REFRESH SENSOR DATA
  // ==========================================================

  Future<void> refreshData() async {
    try {
      final data = await ApiService.getSensorData();

      if (!mounted) return;

      setState(() {
        // ------------------------------------------------------
        // SENSOR VALUES
        // ------------------------------------------------------

        soilMoisture =
            (data['soil_moisture'] as num?)?.toDouble() ?? 0.0;

        temperature =
            (data['temperature'] as num?)?.toDouble() ?? 0.0;

        humidity =
            (data['humidity'] as num?)?.toDouble() ?? 0.0;

        // ------------------------------------------------------
        // WATER STATUS
        // ------------------------------------------------------

        waterAvailable =
            data['water_status']?.toString().toUpperCase() == 'AVAILABLE';

        // ------------------------------------------------------
        // RAIN STATUS
        // ------------------------------------------------------

        rainDetected =
            data['rain_status']?.toString().toUpperCase() == 'RAIN';

        // ------------------------------------------------------
        // PUMP STATUS
        // ------------------------------------------------------

        motorOn =
            data['pump_status']?.toString().toUpperCase() == 'ON';

        // ------------------------------------------------------
        // CONTROL MODE
        // 0 = AUTO
        // 1 = MANUAL
        // ------------------------------------------------------

        manualMode =
            (data['control_mode'] as num?)?.toInt() == 1;

        // ------------------------------------------------------
        // RAIN LOCKOUT
        // ------------------------------------------------------

        rainLockout =
            (data['rain_lockout'] as num?)?.toInt() == 1;

        // ------------------------------------------------------
        // LOCKOUT REMAINING TIME
        // ------------------------------------------------------

        lockoutSeconds =
            (data['lockout_remaining_seconds'] as num?)?.toInt() ?? 0;

        // ------------------------------------------------------
        // ENVIRONMENT GUARD AUTO-TRIP INFO
        // ------------------------------------------------------

        if (data['last_environmental_trip'] != null &&
            data['last_environmental_trip'] is Map) {
          lastTrip = Map<String, dynamic>.from(
              data['last_environmental_trip'] as Map);
        } else {
          lastTrip = null;
        }

        // ------------------------------------------------------
        // API SUCCESS
        // ------------------------------------------------------

        isLoading = false;
        errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        errorMessage = 'Failed to load sensor data';
      });
    }
  }

  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    refreshTimer?.cancel();
    super.dispose();
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F3),

      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F9F3),
        elevation: 0,

        title: const Text(
          'Irrigation',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),

        actions: [
          IconButton(
            onPressed: refreshData,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 8),
        ],
      ),

      body: RefreshIndicator(
        onRefresh: refreshData,

        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),

          padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              // ==================================================
              // ERROR MESSAGE
              // ==================================================

              if (errorMessage != null)
                _buildErrorCard(),

              // ==================================================
              // LOADING
              // ==================================================

              if (isLoading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: LinearProgressIndicator(),
                ),

              // ==================================================
              // CURRENT STATUS
              // ==================================================

              _buildPumpStatus(),

              if (lastTrip != null && !motorOn) ...[
                const SizedBox(height: 14),
                _buildEnvironmentGuardCard(lastTrip!),
              ],

              const SizedBox(height: 24),

              // ==================================================
              // CONTROLS
              // ==================================================

              const Text(
                'Irrigation Controls',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              _buildControlCard(),

              const SizedBox(height: 24),

              // ==================================================
              // FIELD CONDITIONS
              // ==================================================

              const Text(
                'Field Conditions',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              _buildSensorGrid(),

              const SizedBox(height: 24),

              // ==================================================
              // SAFETY & ENVIRONMENT
              // ==================================================

              const Text(
                'Safety & Environment',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              // Rain status
              _buildRainStatus(),

              const SizedBox(height: 10),

              // Rain lockout
              _buildLockoutStatus(),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // ERROR CARD
  // ==========================================================

  Widget _buildErrorCard() {
    return Container(
      width: double.infinity,

      margin: const EdgeInsets.only(bottom: 16),

      padding: const EdgeInsets.all(14),

      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.red.shade200,
        ),
      ),

      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: Colors.red.shade700,
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Text(
              errorMessage!,
              style: TextStyle(
                color: Colors.red.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          IconButton(
            onPressed: refreshData,
            icon: const Icon(Icons.refresh_rounded),
            color: Colors.red.shade700,
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // PUMP STATUS
  // ==========================================================

  Widget _buildPumpStatus() {
    final Color statusColor =
        motorOn ? Colors.blue : Colors.grey.shade600;

    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),

        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,

          colors: motorOn
              ? [
                  Colors.blue.shade50,
                  Colors.white,
                ]
              : [
                  Colors.white,
                  Colors.grey.shade50,
                ],
        ),

        border: Border.all(
          color: Colors.grey.shade200,
        ),
      ),

      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,

                decoration: BoxDecoration(
                  shape: BoxShape.circle,

                  color: motorOn
                      ? Colors.blue.shade100
                      : Colors.grey.shade200,
                ),

                child: Icon(
                  Icons.water_drop_rounded,
                  size: 31,
                  color: statusColor,
                ),
              ),

              const SizedBox(width: 15),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,

                  children: [
                    Text(
                      'Motor',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      motorOn ? 'Running' : 'Stopped',

                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              _statusBadge(
                motorOn ? 'ON' : 'OFF',
                motorOn ? Colors.blue : Colors.grey,
              ),
            ],
          ),

          const SizedBox(height: 18),

          Container(
            width: double.infinity,

            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 11,
            ),

            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(14),
            ),

            child: Row(
              children: [
                Icon(
                  manualMode
                      ? Icons.touch_app_rounded
                      : Icons.auto_awesome_rounded,

                  size: 19,

                  color: manualMode
                      ? Colors.orange.shade700
                      : Colors.green.shade700,
                ),

                const SizedBox(width: 8),

                Text(
                  manualMode
                      ? 'Manual control active'
                      : 'Automatic irrigation active',

                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // ENVIRONMENT GUARD AUTO-PROTECTION CARD
  // ==========================================================

  Widget _buildEnvironmentGuardCard(Map<String, dynamic> trip) {
    final reason = trip['reason']?.toString() ?? 'Auto Protection Activated';
    final details = trip['details']?.toString() ?? '';
    final timestamp = trip['timestamp']?.toString() ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF86EFAC), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFFDCFCE7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  color: Color(0xFF16A34A),
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI Environment Guard Auto-Stop',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF166534),
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      reason,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF14532D),
                      ),
                    ),
                  ],
                ),
              ),
              if (timestamp.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    timestamp,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF15803D),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              details,
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.green.shade900,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ==========================================================
  // CONTROL CARD
  // ==========================================================

  Widget _buildControlCard() {
    return Container(
      width: double.infinity,

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(22),

        border: Border.all(
          color: Colors.grey.shade200,
        ),
      ),

      child: Column(
        children: [
          // --------------------------------------------------
          // MANUAL MODE
          // --------------------------------------------------

          Padding(
            padding: const EdgeInsets.fromLTRB(
              17,
              17,
              12,
              15,
            ),

            child: Row(
              children: [
                _controlIcon(
                  Icons.tune_rounded,
                  Colors.orange,
                ),

                const SizedBox(width: 13),

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,

                    children: [
                      const Text(
                        'Manual Mode',

                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 3),

                      Text(
                        manualMode
                            ? 'You control the motor'
                            : 'ESP32 controls irrigation',

                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),

                Switch(
                  value: manualMode,
                  activeThumbColor: const Color(0xFF2E7D32),
                  onChanged: (val) async {
                    setState(() {
                      manualMode = val;
                      if (!val) {
                        motorOn = false;
                      }
                    });
                    try {
                      await ApiService.setDeviceControl(
                        mode: val ? 'MANUAL' : 'AUTO',
                        manualPumpRequest: motorOn,
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(val ? 'Switched to Manual Control' : 'Switched to Automatic Control'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      }
                      refreshData();
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to update control mode: $e')),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),

          Divider(
            height: 1,
            color: Colors.grey.shade200,
          ),

          // --------------------------------------------------
          // MOTOR
          // --------------------------------------------------

          Padding(
            padding: const EdgeInsets.fromLTRB(
              17,
              15,
              12,
              17,
            ),

            child: Row(
              children: [
                _controlIcon(
                  Icons.power_settings_new_rounded,

                  manualMode
                      ? (motorOn ? Colors.blue : Colors.orange)
                      : Colors.grey,
                ),

                const SizedBox(width: 13),

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,

                    children: [
                      const Text(
                        'Motor',

                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 3),

                      Text(
                        !manualMode
                            ? 'Enable Manual Mode first'
                            : rainDetected || rainLockout
                            ? 'Warning: Rain active'
                            : motorOn
                            ? 'Motor is actively running'
                            : 'Motor is stopped (Tap to start)',

                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),

                Switch(
                  value: motorOn,
                  activeThumbColor: Colors.blue.shade700,
                  onChanged: (val) async {
                    if (val && !waterAvailable) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('⚠️ Notice: Water tank is empty/low. Motor manually started.'),
                          backgroundColor: Colors.orange,
                          duration: Duration(seconds: 3),
                        ),
                      );
                    } else if (val && (rainDetected || rainLockout)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('⚠️ Rain protection active. Check field sensor.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                    setState(() {
                      manualMode = true;
                      motorOn = val;
                    });
                    try {
                      await ApiService.setDeviceControl(
                        mode: 'MANUAL',
                        manualPumpRequest: val,
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(val ? '⚡ Motor started (ON)' : '🛑 Motor stopped (OFF)'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      }
                      refreshData();
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to toggle motor: $e')),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // SENSOR GRID
  // ==========================================================

  Widget _buildSensorGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _sensorCard(
                icon: Icons.grass_rounded,
                iconColor: Colors.green,
                title: 'Soil Moisture',

                value:
                    '${soilMoisture.toStringAsFixed(0)}%',

                subtitle: soilMoisture < 30
                    ? 'Dry'
                    : soilMoisture < 60
                    ? 'Moderate'
                    : 'Moist',
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: _sensorCard(
                icon: Icons.thermostat_rounded,
                iconColor: Colors.orange,
                title: 'Temperature',

                value:
                    '${temperature.toStringAsFixed(1)}°C',

                subtitle: 'Current',
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: _sensorCard(
                icon: Icons.water_rounded,
                iconColor: Colors.indigo,
                title: 'Humidity',

                value:
                    '${humidity.toStringAsFixed(1)}%',

                subtitle: 'Air humidity',
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: _sensorCard(
                icon: Icons.water_drop_rounded,
                iconColor: Colors.blue,
                title: 'Water Supply',

                value: waterAvailable
                    ? 'Available'
                    : 'Unavailable',

                subtitle: 'Tank status',
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ==========================================================
  // SENSOR CARD
  // ==========================================================

  Widget _sensorCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(20),

        border: Border.all(
          color: Colors.grey.shade200,
        ),
      ),

      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [
          Container(
            width: 42,
            height: 42,

            decoration: BoxDecoration(
              shape: BoxShape.circle,

              color: iconColor.withValues(
                alpha: 0.12,
              ),
            ),

            child: Icon(
              icon,
              color: iconColor,
              size: 23,
            ),
          ),

          const SizedBox(height: 14),

          Text(
            title,

            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            value,

            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 3),

          Text(
            subtitle,

            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // RAIN STATUS
  // ==========================================================

  Widget _buildRainStatus() {
    return _environmentCard(
      icon: rainDetected
          ? Icons.umbrella_rounded
          : Icons.wb_sunny_rounded,

      iconColor: rainDetected
          ? Colors.blue
          : Colors.amber.shade700,

      title: 'Rain Status',

      value: rainDetected
          ? 'Rain detected'
          : 'No rain',

      description: rainDetected
          ? 'Irrigation is temporarily blocked'
          : 'Weather conditions are clear',
    );
  }

  // ==========================================================
  // RAIN LOCKOUT
  // ==========================================================

  Widget _buildLockoutStatus() {
    if (!rainLockout) {
      return _environmentCard(
        icon: Icons.lock_open_rounded,

        iconColor: Colors.green,

        title: 'Rain Lockout',

        value: 'Inactive',

        description:
            'No rain lockout is active',
      );
    }

    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(
        color: Colors.orange.shade50,

        borderRadius: BorderRadius.circular(20),

        border: Border.all(
          color: Colors.orange.shade200,
        ),
      ),

      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,

            decoration: BoxDecoration(
              shape: BoxShape.circle,

              color: Colors.orange.shade100,
            ),

            child: Icon(
              Icons.lock_clock_rounded,
              color: Colors.orange.shade800,
            ),
          ),

          const SizedBox(width: 13),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,

              children: [
                const Text(
                  'Rain Lockout',

                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  'Active • '
                  '${_formatDuration(lockoutSeconds)} '
                  'remaining',

                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // ENVIRONMENT CARD
  // ==========================================================

  Widget _environmentCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String description,
  }) {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(15),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(20),

        border: Border.all(
          color: Colors.grey.shade200,
        ),
      ),

      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,

            decoration: BoxDecoration(
              shape: BoxShape.circle,

              color: iconColor.withValues(
                alpha: 0.12,
              ),
            ),

            child: Icon(
              icon,
              color: iconColor,
              size: 22,
            ),
          ),

          const SizedBox(width: 13),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,

              children: [
                Text(
                  title,

                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  value,

                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 2),

                Text(
                  description,

                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),

          Icon(
            Icons.check_circle_rounded,
            color: iconColor,
            size: 21,
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // CONTROL ICON
  // ==========================================================

  Widget _controlIcon(
    IconData icon,
    Color color,
  ) {
    return Container(
      width: 44,
      height: 44,

      decoration: BoxDecoration(
        shape: BoxShape.circle,

        color: color.withValues(
          alpha: 0.12,
        ),
      ),

      child: Icon(
        icon,
        color: color,
        size: 22,
      ),
    );
  }

  // ==========================================================
  // STATUS BADGE
  // ==========================================================

  Widget _statusBadge(
    String text,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 7,
      ),

      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.12,
        ),

        borderRadius: BorderRadius.circular(30),
      ),

      child: Text(
        text,

        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12,
          color: color,
        ),
      ),
    );
  }

  // ==========================================================
  // FORMAT LOCKOUT TIME
  // ==========================================================

  String _formatDuration(int seconds) {
    final int minutes = seconds ~/ 60;

    final int remainingSeconds =
        seconds % 60;

    return '${minutes.toString().padLeft(2, '0')}:'
        '${remainingSeconds.toString().padLeft(2, '0')}';
  }
}