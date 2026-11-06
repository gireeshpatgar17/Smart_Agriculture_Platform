import 'dart:math' as math;
import 'package:flutter/material.dart';

// ============================================================
// DATA MODELS
// ============================================================

class DailyIrrigationData {
  final String dayLabel; // e.g. "Mon"
  final DateTime date;
  final double totalMinutes;
  final int sessionCount;

  DailyIrrigationData({
    required this.dayLabel,
    required this.date,
    required this.totalMinutes,
    required this.sessionCount,
  });
}

class PieChartSegment {
  final String label;
  final double value;
  final Color color;
  final IconData icon;

  PieChartSegment({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });
}

// ============================================================
// CUSTOM DONUT / PIE CHART PAINTER
// ============================================================

class DonutChartPainter extends CustomPainter {
  final List<PieChartSegment> segments;
  final double strokeWidth;

  DonutChartPainter({
    required this.segments,
    this.strokeWidth = 24.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = segments.fold<double>(0.0, (sum, s) => sum + s.value);
    if (total <= 0) {
      // Paint an empty placeholder ring
      final paint = Paint()
        ..color = Colors.grey.shade200
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        (size.width - strokeWidth) / 2,
        paint,
      );
      return;
    }

    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: (size.width - strokeWidth) / 2,
    );

    double startAngle = -math.pi / 2;

    for (final seg in segments) {
      if (seg.value <= 0) continue;
      final sweepAngle = (seg.value / total) * 2 * math.pi;

      final paint = Paint()
        ..color = seg.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      // Draw arc slightly indented for rounded caps if multiple segments
      final gap = segments.length > 1 ? 0.05 : 0.0;
      final actualSweep = math.max(0.01, sweepAngle - gap);

      canvas.drawArc(rect, startAngle + (gap / 2), actualSweep, false, paint);
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant DonutChartPainter oldDelegate) => true;
}

// ============================================================
// IRRIGATION & WATER ANALYTICS CARD (FARMER-FRIENDLY & OVERFLOW-PROOF)
// ============================================================

class IrrigationWaterAnalyticsCard extends StatefulWidget {
  final List<dynamic> history;
  final Map<String, dynamic> summary;

  const IrrigationWaterAnalyticsCard({
    super.key,
    required this.history,
    required this.summary,
  });

  @override
  State<IrrigationWaterAnalyticsCard> createState() =>
      _IrrigationWaterAnalyticsCardState();
}

class _IrrigationWaterAnalyticsCardState
    extends State<IrrigationWaterAnalyticsCard> {
  // 0 = Mode Pie Chart, 1 = Daily Runtime, 2 = Motor Logs
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final dailyData = _computeDailyData(widget.history);

    final totalMinutes = widget.history.fold<double>(
      0.0,
      (sum, item) => sum + _parseDuration(item['duration_minutes']),
    );
    final totalSessions = widget.history.length;

    // Tally Auto vs Manual events
    int autoCount = 0;
    int manualCount = 0;
    double autoMinutes = 0.0;
    double manualMinutes = 0.0;

    for (final item in widget.history) {
      final mode = (item['mode'] ?? 'AUTO').toString().toUpperCase();
      final dur = _parseDuration(item['duration_minutes']);
      if (mode == 'MANUAL') {
        manualCount++;
        manualMinutes += dur;
      } else {
        autoCount++;
        autoMinutes += dur;
      }
    }

    final autoPercent = totalSessions > 0
        ? ((autoCount / totalSessions) * 100.0).round()
        : 100;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
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
          // ----------------------------------------------------
          // Header (Safely bounded with Expanded)
          // ----------------------------------------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.pie_chart_rounded,
                    color: Color(0xFF0284C7),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Irrigation & Motor Analytics',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      SizedBox(height: 1),
                      Text(
                        'Motor runtimes, operational modes & cycles',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ----------------------------------------------------
          // High-level Metric Pills (2 columns, perfectly balanced)
          // ----------------------------------------------------
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _metricCard(
                    icon: Icons.timer_rounded,
                    iconColor: const Color(0xFF0D9488),
                    title: 'Total Runtime',
                    value: totalMinutes >= 60
                        ? '${(totalMinutes / 60).toStringAsFixed(1)} hrs'
                        : '${totalMinutes.toStringAsFixed(1)} min',
                    subtitle: '$totalSessions session${totalSessions == 1 ? '' : 's'} logged',
                    bg: const Color(0xFFF0FDFA),
                    border: const Color(0xFFCCFBF1),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _metricCard(
                    icon: Icons.smart_toy_rounded,
                    iconColor: const Color(0xFF16A34A),
                    title: 'Smart Automation',
                    value: '$autoPercent% Auto',
                    subtitle: '$autoCount Auto • $manualCount Manual',
                    bg: const Color(0xFFF0FDF4),
                    border: const Color(0xFFDCFCE7),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ----------------------------------------------------
          // View Switcher Tabs (3 Tabs)
          // ----------------------------------------------------
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  _tabButton(0, 'Mode Pie Chart'),
                  _tabButton(1, 'Daily Runtime'),
                  _tabButton(2, 'Motor Runs'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ----------------------------------------------------
          // Active Graph / Content
          // ----------------------------------------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _buildActiveView(
                autoCount: autoCount,
                manualCount: manualCount,
                autoMinutes: autoMinutes,
                manualMinutes: manualMinutes,
                totalSessions: totalSessions,
                dailyData: dailyData,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(int index, String title) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedTab = index;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected
                  ? const Color(0xFF0F172A)
                  : const Color(0xFF64748B),
            ),
          ),
        ),
      ),
    );
  }

  Widget _metricCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String subtitle,
    required Color bg,
    required Color border,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: iconColor),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveView({
    required int autoCount,
    required int manualCount,
    required double autoMinutes,
    required double manualMinutes,
    required int totalSessions,
    required List<DailyIrrigationData> dailyData,
  }) {
    if (_selectedTab == 0) {
      return _buildPieChartView(
        autoCount: autoCount,
        manualCount: manualCount,
        autoMinutes: autoMinutes,
        manualMinutes: manualMinutes,
        totalSessions: totalSessions,
      );
    } else if (_selectedTab == 1) {
      return _buildDailyRuntimeGraph(dailyData);
    } else {
      return _buildMotorRunLogs();
    }
  }

  // ============================================================
  // TAB 0: PIE / DONUT CHART VIEW (AUTO VS MANUAL OPERATIONS)
  // ============================================================

  Widget _buildPieChartView({
    required int autoCount,
    required int manualCount,
    required double autoMinutes,
    required double manualMinutes,
    required int totalSessions,
  }) {
    if (totalSessions == 0) {
      return Container(
        key: const ValueKey('empty_pie'),
        padding: const EdgeInsets.symmetric(vertical: 24),
        alignment: Alignment.center,
        child: Column(
          children: [
            Icon(Icons.pie_chart_outline_rounded,
                size: 36, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              'No irrigation sessions recorded yet.\nTurn on the motor to view operational distribution.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    final segments = [
      PieChartSegment(
        label: 'Auto (AI & Sensors)',
        value: autoCount.toDouble(),
        color: const Color(0xFF16A34A), // vibrant green
        icon: Icons.smart_toy_rounded,
      ),
      PieChartSegment(
        label: 'Manual User Runs',
        value: manualCount.toDouble(),
        color: const Color(0xFF0284C7), // sky blue
        icon: Icons.touch_app_rounded,
      ),
    ];

    final autoPct = ((autoCount / totalSessions) * 100).round();
    final manualPct = 100 - autoPct;

    return Column(
      key: const ValueKey('pie_view'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title row (Safely bounded)
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Operational Mode Distribution',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  SizedBox(height: 1),
                  Text(
                    'Balance between AI automation and manual control',
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$totalSessions Cycles',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF334155),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Donut Chart & Legend Row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Donut Pie Painter
            SizedBox(
              width: 124,
              height: 124,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(124, 124),
                    painter: DonutChartPainter(
                      segments: segments,
                      strokeWidth: 20,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$autoPct%',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const Text(
                        'AI Auto',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF16A34A),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 22),

            // Legend & Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _legendItem(
                    color: const Color(0xFF16A34A),
                    title: 'Auto (AI Agent)',
                    count: '$autoCount cycles ($autoPct%)',
                    duration: '${autoMinutes.toStringAsFixed(1)} min',
                  ),
                  const SizedBox(height: 12),
                  _legendItem(
                    color: const Color(0xFF0284C7),
                    title: 'Manual Overrides',
                    count: '$manualCount cycles ($manualPct%)',
                    duration: '${manualMinutes.toStringAsFixed(1)} min',
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Farmer insight tip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.lightbulb_outline_rounded,
                size: 15,
                color: Color(0xFF0284C7),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  autoPct >= 60
                      ? 'AI Smart Mode is managing most watering cycles based on soil moisture & rain.'
                      : 'More manual overrides detected. Switch to AUTO mode to let AI optimize water.',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF334155)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _legendItem({
    required Color color,
    required String title,
    required String count,
    required String duration,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 3),
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              Text(
                count,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: Color(0xFF475569),
                ),
              ),
              Text(
                'Runtime: $duration',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // TAB 1: DAILY RUNTIME GRAPH (NO LITERS ESTIMATE, NO OVERFLOW)
  // ============================================================

  Widget _buildDailyRuntimeGraph(List<DailyIrrigationData> dailyData) {
    final maxMinutes = dailyData.fold<double>(
      0.0,
      (max, d) => math.max(max, d.totalMinutes),
    );
    final chartMax = maxMinutes > 0 ? maxMinutes * 1.25 : 10.0;
    final activeDaysCount = dailyData.where((d) => d.totalMinutes > 0).length;

    return Column(
      key: const ValueKey('daily_runtime_view'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title row (Safely bounded with Expanded)
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Daily Motor Runtime (Past 7 Days)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  SizedBox(height: 1),
                  Text(
                    'Total minutes motor operated each day',
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$activeDaysCount Days Active',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1D4ED8),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Custom Bar Chart (Minutes)
        SizedBox(
          height: 145,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: dailyData.map((day) {
              final ratio = (day.totalMinutes / chartMax).clamp(0.0, 1.0);
              final isToday = _isSameDay(day.date, DateTime.now());

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Minutes label on top
                      if (day.totalMinutes > 0)
                        Text(
                          '${day.totalMinutes.toStringAsFixed(1)}m',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: isToday
                                ? const Color(0xFF1D4ED8)
                                : const Color(0xFF475569),
                          ),
                        )
                      else
                        const SizedBox(height: 11),
                      const SizedBox(height: 4),

                      // Gradient Bar
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.0, end: ratio),
                            duration: const Duration(milliseconds: 550),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, child) {
                              return Container(
                                width: double.infinity,
                                height: math.max(value * 95.0, 4.0),
                                decoration: BoxDecoration(
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(5),
                                  ),
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: day.totalMinutes > 0
                                        ? (isToday
                                            ? [
                                                const Color(0xFF2563EB),
                                                const Color(0xFF60A5FA),
                                              ]
                                            : [
                                                const Color(0xFF0D9488),
                                                const Color(0xFF2DD4BF),
                                              ])
                                        : [
                                            Colors.grey.shade200,
                                            Colors.grey.shade200,
                                          ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Day label
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: isToday
                            ? BoxDecoration(
                                color: const Color(0xFFDBEAFE),
                                borderRadius: BorderRadius.circular(4),
                              )
                            : null,
                        child: Text(
                          day.dayLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight:
                                isToday ? FontWeight.bold : FontWeight.w500,
                            color: isToday
                                ? const Color(0xFF1E40AF)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 12),

        // Daily runtime note
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.calendar_today_rounded,
                size: 14,
                color: Color(0xFF0D9488),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  maxMinutes > 0
                      ? 'Longest daily runtime: ${maxMinutes.toStringAsFixed(1)} minutes. Shows exact pump activity per day.'
                      : 'No motor runs in the past 7 days. Pump activates when soil is dry.',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF334155)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // TAB 2: MOTOR RUN SESSIONS (ON / OFF TRACKING)
  // ============================================================

  Widget _buildMotorRunLogs() {
    final sessions = widget.history.take(6).toList();

    if (sessions.isEmpty) {
      return Container(
        key: const ValueKey('empty_sessions'),
        padding: const EdgeInsets.symmetric(vertical: 24),
        alignment: Alignment.center,
        child: Column(
          children: [
            Icon(Icons.history_toggle_off_rounded,
                size: 34, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              'No motor runs recorded yet.\nTurn on the motor in the Irrigation screen to track runs.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return Column(
      key: const ValueKey('sessions_list_view'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recent Motor ON / OFF Runs',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  SizedBox(height: 1),
                  Text(
                    'Exact start, end & duration per session',
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            Text(
              '${sessions.length} recorded',
              style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...sessions.map((item) {
          final session = Map<String, dynamic>.from(item);
          final duration = _parseDuration(session['duration_minutes']);
          final mode = (session['mode'] ?? 'AUTO').toString().toUpperCase();
          final trigger = session['trigger_reason']?.toString() ?? 'Irrigation';

          final startTime =
              DateTime.tryParse(session['start_time']?.toString() ?? '');
          final endTime =
              DateTime.tryParse(session['end_time']?.toString() ?? '');

          final isAuto = mode == 'AUTO';

          return Container(
            margin: const EdgeInsets.only(bottom: 9),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                // Icon
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: isAuto
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFE0F2FE),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isAuto ? Icons.smart_toy_rounded : Icons.touch_app_rounded,
                    color: isAuto
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF0284C7),
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),

                // Details (Expanded to prevent overflow)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              startTime != null
                                  ? _formatTimeRange(startTime, endTime)
                                  : 'Session',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: isAuto
                                  ? const Color(0xFFDCFCE7)
                                  : const Color(0xFFE0F2FE),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              mode,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: isAuto
                                    ? const Color(0xFF15803D)
                                    : const Color(0xFF0369A1),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        trigger,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Duration badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    _formatDurationDisplay(duration),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================

  static double _parseDuration(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static String _formatDurationDisplay(double durationMinutes) {
    if (durationMinutes < 1.0) {
      final seconds = (durationMinutes * 60).round();
      return '$seconds sec';
    }
    return '${durationMinutes.toStringAsFixed(1)} min';
  }

  static String _formatTimeRange(DateTime start, DateTime? end) {
    final localStart = start.toLocal();
    final startStr =
        '${localStart.hour.toString().padLeft(2, '0')}:${localStart.minute.toString().padLeft(2, '0')}';

    if (end != null) {
      final localEnd = end.toLocal();
      final endStr =
          '${localEnd.hour.toString().padLeft(2, '0')}:${localEnd.minute.toString().padLeft(2, '0')}';
      return '$startStr - $endStr';
    }
    return 'At $startStr';
  }

  static List<DailyIrrigationData> _computeDailyData(List<dynamic> history) {
    final now = DateTime.now();
    final List<DailyIrrigationData> result = [];
    final weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    for (int i = 6; i >= 0; i--) {
      final targetDate = now.subtract(Duration(days: i));
      final dayName = weekdayNames[targetDate.weekday - 1];

      double dayMinutes = 0.0;
      int dayCount = 0;

      for (final item in history) {
        final startStr = item['start_time']?.toString() ??
            item['created_at']?.toString() ??
            '';
        final parsed = DateTime.tryParse(startStr);
        if (parsed != null && _isSameDay(parsed.toLocal(), targetDate)) {
          dayMinutes += _parseDuration(item['duration_minutes']);
          dayCount++;
        }
      }

      result.add(
        DailyIrrigationData(
          dayLabel: dayName,
          date: targetDate,
          totalMinutes: dayMinutes,
          sessionCount: dayCount,
        ),
      );
    }

    return result;
  }
}

// ============================================================
// DISEASE HISTORY & AI CONFIDENCE ANALYTICS CARD (OVERFLOW-SAFE)
// ============================================================

class DiseaseAnalyticsCard extends StatelessWidget {
  final List<dynamic> diseaseHistory;

  const DiseaseAnalyticsCard({
    super.key,
    required this.diseaseHistory,
  });

  @override
  Widget build(BuildContext context) {
    if (diseaseHistory.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
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
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.verified_rounded,
                    color: Color(0xFF16A34A),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Crop Disease Analytics',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.health_and_safety_rounded,
                      color: Color(0xFF16A34A), size: 24),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No crop diseases detected!',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF166534),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Upload crop leaf photos in AI Disease Doctor to test and track health trends.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF15803D),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final Map<String, int> distribution = {};
    double sumConfidence = 0.0;
    int confidenceCount = 0;

    for (final item in diseaseHistory) {
      final name = item['disease_name']?.toString() ?? 'Unknown';
      distribution[name] = (distribution[name] ?? 0) + 1;

      final conf = item['confidence'];
      if (conf != null) {
        double val = (conf is num)
            ? conf.toDouble()
            : double.tryParse(conf.toString()) ?? 0.0;
        if (val > 0) {
          // If value is a ratio <= 1.0 (e.g. 0.8726), scale to percentage (87.26).
          // If already stored as percentage (e.g. 87.264), keep as-is.
          if (val <= 1.0) {
            val = val * 100.0;
          }
          sumConfidence += val;
          confidenceCount++;
        }
      }
    }

    final avgConfidence = confidenceCount > 0
        ? (sumConfidence / confidenceCount).clamp(0.0, 100.0)
        : 90.0;
    final totalDiseases = diseaseHistory.length;

    final colors = [
      const Color(0xFFEF4444), // red
      const Color(0xFFF59E0B), // amber
      const Color(0xFF8B5CF6), // purple
      const Color(0xFF06B6D4), // cyan
      const Color(0xFF10B981), // emerald
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
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
          // Header (Safely bounded)
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.coronavirus_rounded,
                  color: Colors.amber.shade800,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Crop Disease Analytics',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    SizedBox(height: 1),
                    Text(
                      'Pathology distribution & AI confidence',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  '$totalDiseases Logged',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Key metrics row (2 columns)
          Row(
            children: [
              Expanded(
                child: _statBox(
                  title: 'Avg AI Confidence',
                  value: '${avgConfidence.toStringAsFixed(1)}%',
                  color: Colors.purple,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statBox(
                  title: 'Unique Diagnoses',
                  value: '${distribution.keys.length}',
                  color: Colors.orange,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Distribution breakdown
          const Text(
            'Disease Distribution Breakdown',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),

          // Multi-segmented bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: Row(
                children: distribution.entries.toList().asMap().entries.map((e) {
                  final idx = e.key;
                  final entry = e.value;
                  final color = colors[idx % colors.length];
                  final flex = math.max(1, entry.value);

                  return Expanded(
                    flex: flex,
                    child: Container(color: color),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Breakdown list
          ...distribution.entries.toList().asMap().entries.map((e) {
            final idx = e.key;
            final entry = e.value;
            final color = colors[idx % colors.length];
            final percent = (entry.value / totalDiseases) * 100.0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF334155),
                      ),
                    ),
                  ),
                  Text(
                    '${entry.value}x (${percent.toStringAsFixed(0)}%)',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF475569),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _statBox({
    required String title,
    required String value,
    required MaterialColor color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, color: color.shade800),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
              color: color.shade900,
            ),
          ),
        ],
      ),
    );
  }
}
