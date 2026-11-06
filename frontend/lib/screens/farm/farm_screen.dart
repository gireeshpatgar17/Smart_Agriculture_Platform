import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import 'farm_charts.dart';

class FarmScreen extends StatefulWidget {
  const FarmScreen({super.key});

  @override
  State<FarmScreen> createState() => _FarmScreenState();
}

class _FarmScreenState extends State<FarmScreen> {
  // ==========================================================
  // FARM
  // ==========================================================

  static const int farmId = 1;

  String cropName = 'Loading...';
  String variety = 'Not available';
  int cropAge = 0;
  String growthStage = 'Calculating...';

  // ==========================================================
  // FIELD DATA
  // ==========================================================

  double soilMoisture = 0;
  double averageTemperature = 0;

  // ==========================================================
  // IRRIGATION DATA
  // ==========================================================

  int irrigationCount = 0;
  double irrigationDuration = 0;
  String lastIrrigation = 'No irrigation recorded';

  // ==========================================================
  // DISEASE DATA
  // ==========================================================

  int diseasesDetected = 0;
  int diseasesTreated = 0;

  String lastDisease = 'No disease recorded';
  String diseaseStatus = 'No issues';

  // ==========================================================
  // HEALTH
  // ==========================================================

  double cropHealth = 100;

  // ==========================================================
  // ACTIVITY
  // ==========================================================

  List<Map<String, dynamic>> recentActivities = [];

  // ==========================================================
  // RAW HISTORIES FOR PICTORIAL CHARTS & ANALYTICS
  // ==========================================================

  List<dynamic> rawIrrigationHistory = [];
  Map<String, dynamic> rawIrrigationSummary = {};
  List<dynamic> rawDiseaseHistory = [];

  // ==========================================================
  // STATE
  // ==========================================================

  bool isLoading = true;
  String? errorMessage;

  Timer? refreshTimer;

  @override
  void initState() {
    super.initState();

    loadFarmData();

    // Keep sensor information reasonably fresh.
    refreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => loadFarmData(),
    );
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    super.dispose();
  }

  // ==========================================================
  // LOAD ALL FARM DATA
  // ==========================================================

  Future<void> loadFarmData() async {
    try {
      final results = await Future.wait([
        ApiService.getFarm(farmId),
        ApiService.getSensorData(),
        ApiService.getIrrigationHistory(farmId),
        ApiService.getIrrigationSummary(farmId),
        ApiService.getDiseaseHistory(farmId),
      ]);

      final farm = results[0] as Map<String, dynamic>;
      final sensor = results[1] as Map<String, dynamic>;
      final irrigationHistory = results[2] as List<dynamic>;
      final irrigationSummary = results[3] as Map<String, dynamic>;
      final diseaseHistory = results[4] as List<dynamic>;

      // --------------------------------------------------------
      // FARM
      // --------------------------------------------------------

      final plantingDate = DateTime.tryParse(
        farm['planting_date']?.toString() ?? '',
      );

      int calculatedCropAge = 0;

      if (plantingDate != null) {
        final now = DateTime.now();

        calculatedCropAge = now.difference(plantingDate).inDays;

        if (calculatedCropAge < 0) {
          calculatedCropAge = 0;
        }
      }

      // Growth stage is not currently stored in your database.
      final calculatedGrowthStage = _calculateGrowthStage(calculatedCropAge);

      // Variety is also not currently stored in your database.
      const databaseVariety = 'Not available';

      // --------------------------------------------------------
      // SENSOR
      // --------------------------------------------------------

      final newSoilMoisture = _toDouble(sensor['soil_moisture']);

      final newTemperature = _toDouble(sensor['temperature']);

      // --------------------------------------------------------
      // IRRIGATION
      // --------------------------------------------------------

      final newIrrigationCount = _toInt(irrigationSummary['total_events']);

      final newIrrigationDuration = _toDouble(
        irrigationSummary['total_duration_minutes'],
      );

      String newLastIrrigation = 'No irrigation recorded';

      if (irrigationHistory.isNotEmpty) {
        final latest = Map<String, dynamic>.from(irrigationHistory.first);

        final startTime = DateTime.tryParse(
          latest['start_time']?.toString() ?? '',
        );

        if (startTime != null) {
          newLastIrrigation = _formatDateTime(startTime);
        }
      }

      // --------------------------------------------------------
      // DISEASE
      // --------------------------------------------------------

      final newDiseaseCount = diseaseHistory.length;

      int newTreatedCount = 0;

      // Your current disease table does NOT have a
      // "treated" or "status" column.
      //
      // Therefore we do NOT pretend that diseases were treated.
      // Treated count remains 0 until treatment tracking
      // is added to the database.

      String newLastDisease = 'No disease recorded';
      String newDiseaseStatus = 'No issues';

      if (diseaseHistory.isNotEmpty) {
        final latestDisease = Map<String, dynamic>.from(diseaseHistory.first);

        newLastDisease =
            latestDisease['disease_name']?.toString() ?? 'Unknown disease';

        newDiseaseStatus = 'Detected';
      }

      // --------------------------------------------------------
      // HEALTH INDICATOR
      // --------------------------------------------------------

      final newCropHealth = _calculateHealth(
        soilMoisture: newSoilMoisture,
        diseaseCount: newDiseaseCount,
        temperature: newTemperature,
      );

      // --------------------------------------------------------
      // RECENT ACTIVITY
      // --------------------------------------------------------

      final activities = _buildRecentActivities(
        irrigationHistory,
        diseaseHistory,
        newCropHealth,
      );

      if (!mounted) return;

      setState(() {
        cropName = farm['crop_type']?.toString() ?? 'Unknown crop';

        variety = databaseVariety;

        cropAge = calculatedCropAge;

        growthStage = calculatedGrowthStage;

        soilMoisture = newSoilMoisture;

        averageTemperature = newTemperature;

        irrigationCount = newIrrigationCount;

        irrigationDuration = newIrrigationDuration;

        lastIrrigation = newLastIrrigation;

        diseasesDetected = newDiseaseCount;

        diseasesTreated = newTreatedCount;

        lastDisease = newLastDisease;

        diseaseStatus = newDiseaseStatus;

        cropHealth = newCropHealth;

        recentActivities = activities;

        rawIrrigationHistory = irrigationHistory;
        rawIrrigationSummary = irrigationSummary;
        rawDiseaseHistory = diseaseHistory;

        isLoading = false;

        errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        errorMessage = e.toString();
      });
    }
  }

  // ==========================================================
  // REFRESH
  // ==========================================================

  Future<void> refreshFarmData() async {
    await loadFarmData();
  }

  // ==========================================================
  // HELPERS
  // ==========================================================

  double _toDouble(dynamic value) {
    if (value == null) return 0;

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString()) ?? 0;
  }

  int _toInt(dynamic value) {
    if (value == null) return 0;

    if (value is int) return value;

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value.toString()) ?? 0;
  }

  String _calculateGrowthStage(int age) {
    if (age <= 20) {
      return 'Seedling';
    } else if (age <= 45) {
      return 'Tillering';
    } else if (age <= 70) {
      return 'Vegetative';
    } else if (age <= 100) {
      return 'Reproductive';
    } else {
      return 'Maturity';
    }
  }

  // This is a simple field-health indicator, NOT an AI
  // prediction. It will be replaced later if you build
  // a proper crop-health model.
  double _calculateHealth({
    required double soilMoisture,
    required int diseaseCount,
    required double temperature,
  }) {
    double score = 100;

    // Disease history affects the indicator.
    if (diseaseCount > 0) {
      score -= 20;
    }

    // Soil moisture outside a reasonable field range
    // reduces the indicator.
    if (soilMoisture < 30 || soilMoisture > 80) {
      score -= 10;
    }

    // Temperature outside a broad reasonable range.
    if (temperature > 0 && (temperature < 15 || temperature > 40)) {
      score -= 10;
    }

    if (score < 0) score = 0;

    return score;
  }

  String _formatDateTime(DateTime dateTime) {
    final local = dateTime.toLocal();

    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;

    final minute = local.minute.toString().padLeft(2, '0');

    final period = local.hour >= 12 ? 'PM' : 'AM';

    final today = DateTime.now();

    final isToday =
        local.year == today.year &&
        local.month == today.month &&
        local.day == today.day;

    if (isToday) {
      return 'Today, $hour:$minute $period';
    }

    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year}, $hour:$minute $period';
  }

  List<Map<String, dynamic>> _buildRecentActivities(
    List<dynamic> irrigationHistory,
    List<dynamic> diseaseHistory,
    double health,
  ) {
    final activities = <Map<String, dynamic>>[];

    // Irrigation activity
    for (final item in irrigationHistory) {
      final record = Map<String, dynamic>.from(item);

      final startTime = DateTime.tryParse(
        record['start_time']?.toString() ?? '',
      );

      activities.add({
        'type': 'irrigation',
        'title': 'Irrigation completed',
        'subtitle': 'Motor operated ${record['mode'] ?? 'AUTO'}',
        'time': startTime != null ? _formatDateTime(startTime) : 'Unknown time',
        'date': startTime ?? DateTime(2000),
      });
    }

    // Disease activity
    for (final item in diseaseHistory) {
      final record = Map<String, dynamic>.from(item);

      final detectedAt = DateTime.tryParse(
        record['detected_at']?.toString() ?? '',
      );

      final disease = record['disease_name']?.toString() ?? 'Disease';

      activities.add({
        'type': 'disease',
        'title': 'Disease detected',
        'subtitle': disease,
        'time': detectedAt != null
            ? _formatDateTime(detectedAt)
            : 'Unknown time',
        'date': detectedAt ?? DateTime(2000),
      });
    }

    // Sort newest first.
    activities.sort(
      (a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime),
    );

    // Add health indicator only if there is room.
    activities.add({
      'type': 'health',
      'title': 'Field health indicator updated',
      'subtitle': 'Current indicator: ${health.toStringAsFixed(0)}%',
      'time': 'Current',
      'date': DateTime.now(),
    });

    return activities.take(5).toList();
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
          'Farm Management',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),

        actions: [
          IconButton(
            onPressed: isLoading ? null : refreshFarmData,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 8),
        ],
      ),

      body: RefreshIndicator(
        onRefresh: refreshFarmData,

        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),

          padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              if (errorMessage != null) _buildErrorCard(),

              _buildCropOverview(),

              const SizedBox(height: 22),

              const Text(
                'Crop Health',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 10),

              _buildHealthCard(),

              const SizedBox(height: 22),

              const Text(
                'Irrigation Summary',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 10),

              _buildIrrigationSummary(),

              const SizedBox(height: 14),

              IrrigationWaterAnalyticsCard(
                history: rawIrrigationHistory,
                summary: rawIrrigationSummary,
              ),

              const SizedBox(height: 22),

              const Text(
                'Disease & Treatment',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 10),

              _buildDiseaseSummary(),

              const SizedBox(height: 14),

              DiseaseAnalyticsCard(
                diseaseHistory: rawDiseaseHistory,
              ),

              const SizedBox(height: 22),

              const Text(
                'Recent Farm Activity',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 10),

              _buildActivityTimeline(),
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
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.red.shade100),
      ),

      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.red.shade700),

          const SizedBox(width: 10),

          Expanded(
            child: Text(
              'Unable to load some farm data.\n'
              'Check that the phone and computer are on the same network.',
              style: TextStyle(fontSize: 12, color: Colors.red.shade800),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // CROP OVERVIEW
  // ==========================================================

  Widget _buildCropOverview() {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.green.shade700, Colors.green.shade500],
        ),

        borderRadius: BorderRadius.circular(25),
      ),

      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,

            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.18),
            ),

            child: const Icon(
              Icons.grass_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),

          const SizedBox(width: 15),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  cropName,

                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  'Variety: $variety',

                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  '$cropAge days • $growthStage stage',

                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
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
  // HEALTH CARD
  // ==========================================================

  Widget _buildHealthCard() {
    Color healthColor;

    if (cropHealth >= 80) {
      healthColor = Colors.green;
    } else if (cropHealth >= 60) {
      healthColor = Colors.orange;
    } else {
      healthColor = Colors.red;
    }

    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(22),

        border: Border.all(color: Colors.grey.shade200),
      ),

      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,

                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: healthColor.withValues(alpha: 0.12),
                ),

                child: Icon(
                  Icons.favorite_rounded,
                  color: healthColor,
                  size: 27,
                ),
              ),

              const SizedBox(width: 13),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    const Text(
                      'Overall Crop Health',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      cropHealth >= 80
                          ? 'Healthy'
                          : cropHealth >= 60
                          ? 'Needs attention'
                          : 'At risk',

                      style: TextStyle(
                        fontSize: 12,
                        color: healthColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              Text(
                '${cropHealth.toStringAsFixed(0)}%',

                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.bold,
                  color: healthColor,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          ClipRRect(
            borderRadius: BorderRadius.circular(10),

            child: LinearProgressIndicator(
              value: cropHealth / 100,
              minHeight: 9,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(healthColor),
            ),
          ),

          const SizedBox(height: 13),

          Text(
            'Indicator based on current field '
            'conditions and recorded disease history. '
            'This is not an AI prediction.',

            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // IRRIGATION SUMMARY
  // ==========================================================

  Widget _buildIrrigationSummary() {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(22),

        border: Border.all(color: Colors.grey.shade200),
      ),

      child: Column(
        children: [
          Row(
            children: [
              _summaryIcon(Icons.water_drop_rounded, Colors.blue),

              const SizedBox(width: 12),

              const Expanded(
                child: Text(
                  'Irrigation Activity',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          Row(
            children: [
              Expanded(
                child: _miniStat(
                  '$irrigationCount',
                  'Irrigations',
                  Icons.water_rounded,
                ),
              ),

              Expanded(
                child: _miniStat(
                  '${irrigationDuration.toStringAsFixed(0)} min',
                  'Irrigation time',
                  Icons.timer_rounded,
                ),
              ),
            ],
          ),

          const SizedBox(height: 15),

          Container(
            width: double.infinity,

            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),

            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(13),
            ),

            child: Row(
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 18,
                  color: Colors.blue.shade700,
                ),

                const SizedBox(width: 8),

                Expanded(
                  child: Text(
                    'Last irrigation: $lastIrrigation',

                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue.shade800,
                      fontWeight: FontWeight.w500,
                    ),
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
  // DISEASE SUMMARY
  // ==========================================================

  Widget _buildDiseaseSummary() {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(22),

        border: Border.all(color: Colors.grey.shade200),
      ),

      child: Column(
        children: [
          Row(
            children: [
              _summaryIcon(Icons.health_and_safety_rounded, Colors.green),

              const SizedBox(width: 12),

              const Expanded(
                child: Text(
                  'Disease History',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),

              _statusBadge(
                diseasesDetected == 0 ? 'No issues' : 'Monitored',
                diseasesDetected == 0 ? Colors.green : Colors.orange,
              ),
            ],
          ),

          const SizedBox(height: 18),

          Row(
            children: [
              Expanded(
                child: _miniStat(
                  '$diseasesDetected',
                  'Detected',
                  Icons.search_rounded,
                ),
              ),

              Expanded(
                child: _miniStat(
                  '$diseasesTreated',
                  'Treated',
                  Icons.medical_services_rounded,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (diseasesDetected > 0)
            Container(
              width: double.infinity,

              padding: const EdgeInsets.all(13),

              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(14),
              ),

              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange.shade700,
                  ),

                  const SizedBox(width: 9),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [
                        Text(
                          lastDisease,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),

                        const SizedBox(height: 3),

                        Text(
                          'Status: $diseaseStatus',

                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              'No disease has been recorded.',

              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
        ],
      ),
    );
  }

  // ==========================================================
  // ACTIVITY TIMELINE
  // ==========================================================

  Widget _buildActivityTimeline() {
    if (recentActivities.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),

        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.grey.shade200),
        ),

        child: Text(
          'No recent farm activity.',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
      );
    }

    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(22),

        border: Border.all(color: Colors.grey.shade200),
      ),

      child: Column(
        children: List.generate(recentActivities.length, (index) {
          final activity = recentActivities[index];

          final type = activity['type']?.toString();

          final isLast = index == recentActivities.length - 1;

          IconData icon;
          Color iconColor;

          if (type == 'irrigation') {
            icon = Icons.water_drop_rounded;
            iconColor = Colors.blue;
          } else if (type == 'disease') {
            icon = Icons.health_and_safety_rounded;
            iconColor = Colors.orange;
          } else {
            icon = Icons.eco_rounded;
            iconColor = Colors.green;
          }

          return _activityItem(
            icon: icon,
            iconColor: iconColor,
            title: activity['title']?.toString() ?? '',
            subtitle: activity['subtitle']?.toString() ?? '',
            time: activity['time']?.toString() ?? '',
            isLast: isLast,
          );
        }),
      ),
    );
  }

  // ==========================================================
  // SUMMARY ICON
  // ==========================================================

  Widget _summaryIcon(IconData icon, Color color) {
    return Container(
      width: 43,
      height: 43,

      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.12),
      ),

      child: Icon(icon, color: color, size: 23),
    );
  }

  // ==========================================================
  // MINI STAT
  // ==========================================================

  Widget _miniStat(String value, String label, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 21, color: Colors.grey.shade600),

        const SizedBox(height: 6),

        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 2),

        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
        ),
      ],
    );
  }

  // ==========================================================
  // ACTIVITY ITEM
  // ==========================================================

  Widget _activityItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String time,
    required bool isLast,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        Column(
          children: [
            Container(
              width: 40,
              height: 40,

              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: iconColor.withValues(alpha: 0.12),
              ),

              child: Icon(icon, color: iconColor, size: 21),
            ),

            if (!isLast)
              Container(width: 2, height: 42, color: Colors.grey.shade200),
          ],
        ),

        const SizedBox(width: 12),

        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 18),

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),

                const SizedBox(height: 3),

                Text(
                  time,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // STATUS BADGE
  // ==========================================================

  Widget _statusBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),

      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),

      child: Text(
        text,

        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 10,
          color: color,
        ),
      ),
    );
  }
}
