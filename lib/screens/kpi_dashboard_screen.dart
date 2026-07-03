import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../providers/session_provider.dart';
import '../services/tracking_ws_service.dart';

// ── Data model ────────────────────────────────────────────────────────────────

class _KpiData {
  const _KpiData({
    required this.tiempoAsignacionMin,
    required this.tiempoLlegadaMin,
    required this.tiempoAtencionMin,
    required this.total,
    required this.activas,
    required this.completadas,
    required this.canceladas,
    required this.tasaCompletados,
    required this.incidentesPorTipo,
    required this.solicitudesPorDia,
    required this.calculadoEn,
  });

  final double? tiempoAsignacionMin;
  final double? tiempoLlegadaMin;
  final double? tiempoAtencionMin;
  final int total;
  final int activas;
  final int completadas;
  final int canceladas;
  final double tasaCompletados;
  final Map<String, int> incidentesPorTipo;
  final List<_PeriodoItem> solicitudesPorDia;
  final String calculadoEn;

  factory _KpiData.fromJson(Map<String, dynamic> json) => _KpiData(
        tiempoAsignacionMin:
            (json['tiempo_asignacion_promedio_min'] as num?)?.toDouble(),
        tiempoLlegadaMin:
            (json['tiempo_llegada_promedio_min'] as num?)?.toDouble(),
        tiempoAtencionMin:
            (json['tiempo_atencion_promedio_min'] as num?)?.toDouble(),
        total: json['total_solicitudes'] as int? ?? 0,
        activas: json['solicitudes_activas'] as int? ?? 0,
        completadas: json['solicitudes_completadas'] as int? ?? 0,
        canceladas: json['solicitudes_canceladas'] as int? ?? 0,
        tasaCompletados: (json['tasa_completados'] as num?)?.toDouble() ?? 0.0,
        incidentesPorTipo: Map<String, int>.from(
            (json['incidentes_por_tipo'] as Map<String, dynamic>? ?? {})
                .map((k, v) => MapEntry(k, (v as num).toInt()))),
        solicitudesPorDia: (json['solicitudes_por_dia'] as List<dynamic>? ?? [])
            .map((e) => _PeriodoItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        calculadoEn: json['calculado_en'] as String? ?? '',
      );
}

class _PeriodoItem {
  const _PeriodoItem({
    required this.fecha,
    required this.total,
    required this.completados,
    required this.cancelados,
  });

  final String fecha;
  final int total;
  final int completados;
  final int cancelados;

  factory _PeriodoItem.fromJson(Map<String, dynamic> json) => _PeriodoItem(
        fecha: json['fecha'] as String,
        total: json['total'] as int? ?? 0,
        completados: json['completados'] as int? ?? 0,
        cancelados: json['cancelados'] as int? ?? 0,
      );
}

// ── Screen ─────────────────────────────────────────────────────────────────────

enum _DateRange { today, week, month, all }

class KpiDashboardScreen extends StatefulWidget {
  const KpiDashboardScreen({super.key});

  @override
  State<KpiDashboardScreen> createState() => _KpiDashboardScreenState();
}

class _KpiDashboardScreenState extends State<KpiDashboardScreen> {
  _KpiData? _data;
  bool _loading = false;
  String? _error;
  _DateRange _range = _DateRange.month;
  StreamSubscription<void>? _kpiRefreshSub;
  Timer? _autoRefreshTimer;
  bool _exportLoading = false;

  static const Duration _autoRefreshInterval = Duration(minutes: 15);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadKpis();
      _subscribeToWsRefresh();
      _startAutoRefresh();
    });

  }

  @override
  void dispose() {
    _kpiRefreshSub?.cancel();
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  void _subscribeToWsRefresh() {
    final ws = context.read<TrackingWsService>();
    _kpiRefreshSub = ws.kpiRefreshStream.listen((_) {
      if (mounted) _loadKpis();
    });
  }

  void _startAutoRefresh() {
    _autoRefreshTimer = Timer.periodic(_autoRefreshInterval, (_) {
      if (mounted) _loadKpis();
    });
  }

  Future<void> _loadKpis() async {
    final token = context.read<SessionProvider>().token;
    if (token == null) return;

    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final query = _buildDateQuery();
      final uri = Uri.parse(
        '${AppConfig.apiBaseUrl}/kpis/resumen${query.isNotEmpty ? '?$query' : ''}',
      );
      final response = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      }).timeout(const Duration(seconds: 20));

      if (response.statusCode == 403) {
        throw Exception('No tienes permisos para ver los KPIs');
      }
      if (response.statusCode >= 400) {
        throw Exception('Error al cargar KPIs (${response.statusCode})');
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = _KpiData.fromJson(body);

      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  String _buildDateQuery() {
    final now = DateTime.now().toUtc();
    switch (_range) {
      case _DateRange.today:
        final desde = DateTime(now.year, now.month, now.day).toIso8601String();
        return 'desde=$desde';
      case _DateRange.week:
        final desde =
            now.subtract(const Duration(days: 7)).toIso8601String();
        return 'desde=$desde';
      case _DateRange.month:
        final desde =
            now.subtract(const Duration(days: 30)).toIso8601String();
        return 'desde=$desde';
      case _DateRange.all:
        return '';
    }
  }

  Future<void> _exportPdf() async {
    final token = context.read<SessionProvider>().token;
    if (token == null || _data == null) return;

    setState(() => _exportLoading = true);
    try {
      // Build a simple HTML-based report and open it, or download from backend.
      // For now, we generate a minimal CSV and open it.
      final rows = StringBuffer()
        ..writeln('KPI Dashboard — ${_data!.calculadoEn}')
        ..writeln()
        ..writeln('Métrica,Valor')
        ..writeln(
            'Total solicitudes,${_data!.total}')
        ..writeln('Activas,${_data!.activas}')
        ..writeln('Completadas,${_data!.completadas}')
        ..writeln('Canceladas,${_data!.canceladas}')
        ..writeln(
            'Tasa completados,${(_data!.tasaCompletados * 100).toStringAsFixed(1)}%')
        ..writeln(
            'T. asignación prom. (min),${_data!.tiempoAsignacionMin?.toStringAsFixed(1) ?? "N/A"}')
        ..writeln(
            'T. llegada prom. (min),${_data!.tiempoLlegadaMin?.toStringAsFixed(1) ?? "N/A"}')
        ..writeln(
            'T. atención prom. (min),${_data!.tiempoAtencionMin?.toStringAsFixed(1) ?? "N/A"}')
        ..writeln()
        ..writeln('Incidentes por tipo')
        ..writeln('Tipo,Total');
      for (final e in _data!.incidentesPorTipo.entries) {
        rows.writeln('${e.key},${e.value}');
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/kpi_report_${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsString(rows.toString(), flush: true);
      await OpenFilex.open(file.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al exportar: $e')),
      );
    } finally {
      if (mounted) setState(() => _exportLoading = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('KPI Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Exportar CSV',
            onPressed: _exportLoading ? null : _exportPdf,
            icon: _exportLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loading ? null : () => _loadKpis(),
            icon: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          // Date range selector
          _DateRangeSelector(
            selected: _range,
            onChanged: (r) {
              setState(() => _range = r);
              _loadKpis();
            },
          ),
          Expanded(
            child: _error != null
                ? _ErrorView(error: _error!, onRetry: () => _loadKpis())
                : _data == null && _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _data == null
                        ? const Center(child: Text('Sin datos disponibles'))
                        : RefreshIndicator(
                            onRefresh: () => _loadKpis(),
                            child: ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                _SummaryCards(data: _data!),
                                const SizedBox(height: 20),
                                _SectionTitle(title: 'Incidentes por tipo', theme: theme),
                                const SizedBox(height: 8),
                                _IncidentTypeChart(data: _data!),
                                const SizedBox(height: 20),
                                _SectionTitle(title: 'Tendencia diaria (últimos 30 días)', theme: theme),
                                const SizedBox(height: 8),
                                _DailyTrendChart(data: _data!),
                                const SizedBox(height: 20),
                                Text(
                                  'Actualizado: ${_formatTs(_data!.calculadoEn)}',
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: theme.colorScheme.outline),
                                  textAlign: TextAlign.end,
                                ),
                                const SizedBox(height: 8),
                              ],
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  String _formatTs(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/'
          '${dt.year}  '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _DateRangeSelector extends StatelessWidget {
  const _DateRangeSelector({
    required this.selected,
    required this.onChanged,
  });

  final _DateRange selected;
  final ValueChanged<_DateRange> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = [
      (_DateRange.today, 'Hoy'),
      (_DateRange.week, '7 días'),
      (_DateRange.month, '30 días'),
      (_DateRange.all, 'Todo'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: options.map((opt) {
          final (range, label) = opt;
          final active = range == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(label),
              selected: active,
              onSelected: (_) => onChanged(range),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.theme});

  final String title;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) =>
      Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600));
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.data});

  final _KpiData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    String fmtMin(double? v) =>
        v != null ? '${v.toStringAsFixed(1)} min' : 'N/A';
    String fmtPct(double v) => '${(v * 100).toStringAsFixed(1)}%';

    final cards = [
      _CardData('Total', data.total.toString(), Icons.list_alt, scheme.primary),
      _CardData('Activas', data.activas.toString(), Icons.pending_actions, scheme.tertiary),
      _CardData('Completadas', data.completadas.toString(), Icons.check_circle_outline, Colors.green.shade600),
      _CardData('Canceladas', data.canceladas.toString(), Icons.cancel_outlined, Colors.red.shade400),
      _CardData('Tasa completados', fmtPct(data.tasaCompletados), Icons.percent, scheme.secondary),
      _CardData('T. asignación', fmtMin(data.tiempoAsignacionMin), Icons.schedule, scheme.primary),
      _CardData('T. llegada', fmtMin(data.tiempoLlegadaMin), Icons.directions_car, scheme.tertiary),
      _CardData('T. atención', fmtMin(data.tiempoAtencionMin), Icons.handyman_outlined, Colors.orange.shade600),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 2.0,
      children: cards.map(_buildCard).toList(),
    );
  }

  Widget _buildCard(_CardData d) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: d.color.withAlpha((255 * 0.25).round())),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(d.icon, color: d.color, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(d.value,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: d.color)),
                  Text(d.label,
                      style: const TextStyle(fontSize: 11),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardData {
  const _CardData(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

// ── Bar chart — incidents by type ─────────────────────────────────────────────

class _IncidentTypeChart extends StatelessWidget {
  const _IncidentTypeChart({required this.data});

  final _KpiData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = data.incidentesPorTipo.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (entries.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(child: Text('Sin datos de incidentes')),
      );
    }

    final maxY = entries.first.value.toDouble();
    final barGroups = entries.asMap().entries.map((e) {
      return BarChartGroupData(
        x: e.key,
        barRods: [
          BarChartRodData(
            toY: e.value.value.toDouble(),
            color: scheme.primary,
            width: 18,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
      );
    }).toList();

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          maxY: maxY * 1.2,
          barGroups: barGroups,
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: (maxY / 4).clamp(1, double.infinity),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                getTitlesWidget: (v, _) => Text(
                  v.toInt().toString(),
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, _) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= entries.length) {
                    return const SizedBox.shrink();
                  }
                  final label = entries[idx].key;
                  final short = label.length > 10 ? '${label.substring(0, 9)}…' : label;
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(short, style: const TextStyle(fontSize: 9)),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final label = entries[group.x].key;
                return BarTooltipItem(
                  '$label\n${rod.toY.toInt()}',
                  const TextStyle(fontSize: 11, color: Colors.white),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ── Line chart — daily trend ──────────────────────────────────────────────────

class _DailyTrendChart extends StatelessWidget {
  const _DailyTrendChart({required this.data});

  final _KpiData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final days = data.solicitudesPorDia;

    if (days.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(child: Text('Sin datos de tendencia')),
      );
    }

    final totalSpots = days.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.total.toDouble()))
        .toList();
    final completadosSpots = days.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.completados.toDouble()))
        .toList();

    final maxY = days
        .map((d) => d.total.toDouble())
        .fold(1.0, (a, b) => a > b ? a : b);

    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY * 1.2,
          lineBarsData: [
            LineChartBarData(
              spots: totalSpots,
              isCurved: true,
              color: scheme.primary,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: scheme.primary.withAlpha((255 * 0.08).round()),
              ),
            ),
            LineChartBarData(
              spots: completadosSpots,
              isCurved: true,
              color: Colors.green.shade500,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              dashArray: [5, 4],
            ),
          ],
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: (maxY / 4).clamp(1, double.infinity),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                getTitlesWidget: (v, _) => Text(
                  v.toInt().toString(),
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: (days.length / 5).clamp(1, double.infinity),
                getTitlesWidget: (value, _) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= days.length) {
                    return const SizedBox.shrink();
                  }
                  final fecha = days[idx].fecha;
                  // Show only MM-DD
                  final short = fecha.length >= 10 ? fecha.substring(5) : fecha;
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(short, style: const TextStyle(fontSize: 9)),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots.map((spot) {
                final idx = spot.x.toInt();
                final label = idx < days.length ? days[idx].fecha.substring(5) : '';
                final seriesName = spot.barIndex == 0 ? 'Total' : 'Completados';
                return LineTooltipItem(
                  '$seriesName $label\n${spot.y.toInt()}',
                  const TextStyle(fontSize: 11, color: Colors.white),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Error widget ──────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
