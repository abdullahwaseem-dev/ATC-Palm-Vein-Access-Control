// Copyright (c) 2026 ATC. All rights reserved.
// Proprietary and confidential. Use, copying, modification or distribution without
// written permission from ATC is prohibited. See LICENSE in the repository root.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/app_state.dart';
import '../../core/db.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../widgets/common.dart';

class DashboardPage extends StatefulWidget {
  final ValueChanged<int> onNavigate;
  const DashboardPage({super.key, required this.onNavigate});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardData {
  final Map<String, int> users;
  final int grantedToday, deniedToday, present;
  final List<(DateTime, int, int)> daily;
  final List<int> hourly;
  final List<AccessLog> recent;
  _DashboardData(this.users, this.grantedToday, this.deniedToday, this.present, this.daily, this.hourly, this.recent);
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<_DashboardData> _f = _load();

  Future<_DashboardData> _load() async {
    final db = AppDb.instance;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final (g, d) = await db.countsBetween(today, today.add(const Duration(days: 1)));
    return _DashboardData(
      await db.userStats(),
      g,
      d,
      await db.presentNow(),
      await db.dailyCounts(7),
      await db.hourlyToday(),
      await db.logs(limit: 8),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => setState(() => _f = _load()),
      child: FutureBuilder<_DashboardData>(
        future: _f,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final x = snap.data!;
          final attendance = AppSettings.instance.mode == TerminalMode.attendance;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _scannerBanner(),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, c) {
                  final cols = c.maxWidth > 900 ? 4 : 2;
                  final tiles = [
                    _Stat(
                      'Users',
                      '${x.users['total']}',
                      '${x.users['enrolled']} enrolled · ${x.users['palms']} palms',
                      Icons.people,
                      Brand.blue,
                      () => widget.onNavigate(1),
                    ),
                    _Stat(
                      'Granted today',
                      '${x.grantedToday}',
                      'successful scans',
                      Icons.verified_user,
                      Brand.granted,
                      () => widget.onNavigate(2),
                    ),
                    _Stat(
                      'Denied today',
                      '${x.deniedToday}',
                      'rejected attempts',
                      Icons.gpp_bad,
                      Brand.denied,
                      () => widget.onNavigate(2),
                    ),
                    attendance
                        ? _Stat(
                            'Present now',
                            '${x.present}',
                            'checked in, not out',
                            Icons.how_to_reg,
                            Brand.warning,
                            () => widget.onNavigate(3),
                          )
                        : _Stat(
                            'Suspended',
                            '${x.users['suspended']}',
                            '${x.users['admins']} administrators',
                            Icons.block,
                            Brand.warning,
                            () => widget.onNavigate(1),
                          ),
                  ];
                  return GridView.count(
                    crossAxisCount: cols,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: cols == 4 ? 2.0 : (c.maxWidth > 600 ? 2.3 : 1.6),
                    children: tiles,
                  );
                },
              ),
              const SizedBox(height: 12),
              _chartCard('Last 7 days', _weekChart(x.daily)),
              const SizedBox(height: 12),
              _chartCard('Entries by hour (today)', _hourChart(x.hourly)),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      title: const Text('Recent activity', style: TextStyle(fontWeight: FontWeight.w700)),
                      trailing: TextButton(onPressed: () => widget.onNavigate(2), child: const Text('View all')),
                    ),
                    if (x.recent.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('No activity yet')),
                      ),
                    for (final l in x.recent)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          l.granted ? Icons.check_circle : Icons.cancel,
                          color: l.granted ? Brand.granted : Brand.denied,
                        ),
                        title: Text(l.userName ?? 'Unknown person'),
                        subtitle: Text(
                          '${Reason.label(l.reason)} · ${methodLabel(l.method)}'
                          '${l.direction.isEmpty ? '' : ' · ${l.direction == 'in' ? 'Check in' : 'Check out'}'}',
                        ),
                        trailing: Text(
                          DateUtils.isSameDay(l.ts, DateTime.now())
                              ? DateFormat('HH:mm').format(l.ts)
                              : DateFormat('EEE HH:mm').format(l.ts),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _scannerBanner() => ListenableBuilder(
    listenable: AppState.instance,
    builder: (context, _) {
      final st = AppState.instance;
      if (st.ready) return const SizedBox.shrink();
      return Card(
        color: const Color(0xFFFFF7ED),
        child: ListTile(
          leading: const Icon(Icons.warning_amber, color: Brand.warning),
          title: Text(st.statusLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(st.initMessage ?? 'Check the USB connection to the palm module.'),
          trailing: TextButton(onPressed: () => widget.onNavigate(5), child: const Text('Diagnose')),
        ),
      );
    },
  );

  Widget _chartCard(String title, Widget chart) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 16),
          SizedBox(height: 180, child: chart),
        ],
      ),
    ),
  );

  /// Whole-number axis step giving ~4 grid lines.
  double _interval(double maxY) => (maxY / 4).ceilToDouble().clamp(1, double.infinity);

  Widget _weekChart(List<(DateTime, int, int)> days) {
    final maxY = days.fold<int>(1, (m, d) => [m, d.$2, d.$3].reduce((a, b) => a > b ? a : b)).toDouble();
    return BarChart(
      BarChartData(
        maxY: _interval(maxY) * 5,
        gridData: FlGridData(drawVerticalLine: false, horizontalInterval: _interval(maxY)),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32, interval: _interval(maxY))),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, meta) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(DateFormat('E').format(days[v.toInt()].$1), style: const TextStyle(fontSize: 11)),
              ),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < days.length; i++)
            BarChartGroupData(
              x: i,
              barsSpace: 3,
              barRods: [
                BarChartRodData(
                  toY: days[i].$2.toDouble(),
                  color: Brand.granted,
                  width: 10,
                  borderRadius: BorderRadius.circular(3),
                ),
                BarChartRodData(
                  toY: days[i].$3.toDouble(),
                  color: Brand.denied,
                  width: 10,
                  borderRadius: BorderRadius.circular(3),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _hourChart(List<int> hours) {
    final maxY = hours.fold<int>(1, (m, v) => v > m ? v : m).toDouble();
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: _interval(maxY) * 5,
        gridData: FlGridData(drawVerticalLine: false, horizontalInterval: _interval(maxY)),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32, interval: _interval(maxY))),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 3,
              getTitlesWidget: (v, meta) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${v.toInt()}h', style: const TextStyle(fontSize: 11)),
              ),
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [for (var h = 0; h < 24; h++) FlSpot(h.toDouble(), hours[h].toDouble())],
            isCurved: true,
            preventCurveOverShooting: true,
            color: Brand.blue,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: Brand.blue.withValues(alpha: .12)),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value, sub;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _Stat(this.label, this.value, this.sub, this.icon, this.color, this.onTap);

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}
