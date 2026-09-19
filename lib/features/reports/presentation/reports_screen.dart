import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/formatters/currency_format.dart';
import '../../../core/formatters/date_formatter.dart';
import '../../../core/formatters/money_formatter.dart';
import '../../categories/category_appearance.dart';

/// Reports FE-07: Expense by Category (pie) + Income vs Expense (bar)
/// untuk rentang tanggal terpilih. Semua nominal display-only dalam IDR
/// (konversi di repository BE-05; transfer sudah dikecualikan di sana).
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  static const path = '/reports';

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  /// Warna legenda/slice bila kategori tidak punya warna tersimpan.
  static const _palette = <Color>[
    Colors.blue,
    Colors.red,
    Colors.amber,
    Colors.green,
    Colors.purple,
    Colors.orange,
    Colors.teal,
    Colors.pink,
  ];

  /// Index slice pie yang sedang disentuh (tooltip nominal), -1 = tidak ada.
  int _touchedSlice = -1;

  String _format(int minorUnit) =>
      MoneyFormatter().format(minorUnit, CurrencyFormat.fromCode('IDR'));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final range = ref.watch(reportsRangeProvider);
    final pie = ref.watch(expenseByCategoryProvider);
    final bar = ref.watch(incomeVsExpenseRangeProvider);
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final dateFmt = const DateFormatter();

    Color colorFor(int categoryId, int index) {
      for (final c in categories) {
        if (c.id == categoryId) return categoryColor(c.color);
      }
      return _palette[index % _palette.length];
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _RangePresets(range: range),
          const SizedBox(height: 4),
          Text(
            '${dateFmt.format(range.$1, style: DateStyle.short)} – '
            '${dateFmt.format(range.$2, style: DateStyle.short)}',
            key: const Key('reports.range.label'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          // --- Expense by Category (pie) ---
          Text('Expense by Category', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          pie.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                key: Key('reports.loading'),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => _ErrorState(
              key: const Key('reports.error'),
              message: 'Gagal memuat laporan: $e',
              onRetry: () {
                ref.invalidate(expenseByCategoryProvider);
                ref.invalidate(incomeVsExpenseRangeProvider);
              },
            ),
            data: (report) {
              if (report.categories.isEmpty) {
                return _EmptyState(
                  key: const Key('reports.pie.empty'),
                  message: 'Tidak ada expense pada periode ini.',
                );
              }
              final sections = <PieChartSectionData>[];
              for (var i = 0; i < report.categories.length; i++) {
                final cat = report.categories[i];
                final touched = i == _touchedSlice;
                sections.add(
                  PieChartSectionData(
                    value: cat.totalMinorUnit.toDouble(),
                    color: colorFor(cat.categoryId, i),
                    radius: touched ? 72 : 60,
                    showTitle: false,
                  ),
                );
              }
              final touchedCat = _touchedSlice >= 0 &&
                      _touchedSlice < report.categories.length
                  ? report.categories[_touchedSlice]
                  : null;
              return Column(
                children: [
                  SizedBox(
                    height: 180,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 36,
                        sections: sections,
                        pieTouchData: PieTouchData(
                          touchCallback: (event, response) {
                            setState(() {
                              _touchedSlice =
                                  event.isInterestedForInteractions &&
                                          response?.touchedSection != null
                                      ? response!
                                            .touchedSection!
                                            .touchedSectionIndex
                                      : -1;
                            });
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Tooltip nominal: slice yang disentuh (fallback: terbesar).
                  Text(
                    touchedCat != null
                        ? '${touchedCat.categoryName}: '
                              '${_format(touchedCat.totalMinorUnit)}'
                        : '${report.categories.first.categoryName}: '
                              '${_format(report.categories.first.totalMinorUnit)}',
                    key: const Key('reports.pie.touched'),
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  // Legenda: warna + nama + nominal (terbaca di layar kecil).
                  for (var i = 0; i < report.categories.length; i++)
                    _LegendRow(
                      key: Key('reports.legend.${report.categories[i].categoryId}'),
                      color: colorFor(report.categories[i].categoryId, i),
                      label: report.categories[i].categoryName,
                      amount: _format(report.categories[i].totalMinorUnit),
                    ),
                  if (!report.isComplete)
                    _MissingRateWarning(
                      currencies: report.missingRateCurrencies,
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          // --- Income vs Expense (bar) ---
          Text('Income vs Expense', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          bar.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => _ErrorState(
              message: 'Gagal memuat income vs expense: $e',
              onRetry: () => ref.invalidate(incomeVsExpenseRangeProvider),
            ),
            data: (report) {
              final empty =
                  report.incomeMinorUnit == 0 && report.expenseMinorUnit == 0;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Pemasukan'),
                      Text(
                        _format(report.incomeMinorUnit),
                        key: const Key('reports.bar.income'),
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Pengeluaran'),
                      Text(
                        _format(report.expenseMinorUnit),
                        key: const Key('reports.bar.expense'),
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (empty)
                    _EmptyState(
                      key: const Key('reports.bar.empty'),
                      message: 'Tidak ada transaksi pada periode ini.',
                    )
                  else
                    SizedBox(
                      height: 200,
                      child: BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          maxY: [
                            report.incomeMinorUnit.toDouble(),
                            report.expenseMinorUnit.toDouble(),
                          ].reduce((a, b) => a > b ? a : b) *
                              1.2,
                          barTouchData: BarTouchData(
                            touchTooltipData: BarTouchTooltipData(
                              getTooltipItem: (group, gIdx, rod, rIdx) =>
                                  BarTooltipItem(
                                    group.x == 0
                                        ? 'Pemasukan\n'
                                              '${_format(report.incomeMinorUnit)}'
                                        : 'Pengeluaran\n'
                                              '${_format(report.expenseMinorUnit)}',
                                    theme.textTheme.bodySmall!.copyWith(
                                      color: theme.colorScheme.onInverseSurface,
                                    ),
                                  ),
                            ),
                          ),
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          barGroups: [
                            BarChartGroupData(
                              x: 0,
                              barRods: [
                                BarChartRodData(
                                  toY: report.incomeMinorUnit.toDouble(),
                                  color: theme.colorScheme.primary,
                                  width: 40,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ],
                            ),
                            BarChartGroupData(
                              x: 1,
                              barRods: [
                                BarChartRodData(
                                  toY: report.expenseMinorUnit.toDouble(),
                                  color: theme.colorScheme.error,
                                  width: 40,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ],
                            ),
                          ],
                          titlesData: FlTitlesData(
                            leftTitles: const AxisTitles(),
                            rightTitles: const AxisTitles(),
                            topTitles: const AxisTitles(),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  final label = switch (value.toInt()) {
                                    0 => 'Income',
                                    1 => 'Expense',
                                    _ => '',
                                  };
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      label,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (!report.isComplete)
                    _MissingRateWarning(
                      currencies: report.missingRateCurrencies,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Tombol preset rentang + picker custom. Ubah rentang → kedua chart reload
/// (providers membaca `reportsRangeProvider`).
class _RangePresets extends ConsumerWidget {
  const _RangePresets({required this.range});

  final (DateTime, DateTime) range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presets = reportsPresets();
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 4,
      children: [
        for (final entry in presets.entries)
          ChoiceChip(
            key: Key('reports.preset.${entry.key}'),
            label: Text(entry.value.label),
            selected: range == (entry.value.from, entry.value.to),
            onSelected: (_) =>
                ref.read(reportsRangeProvider.notifier).state =
                    (entry.value.from, entry.value.to),
          ),
        ActionChip(
          key: const Key('reports.preset.custom'),
          avatar: const Icon(Icons.date_range, size: 18),
          label: const Text('Rentang lain'),
          onPressed: () async {
            final now = DateTime.now();
            final picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime(now.year - 5),
              lastDate: DateTime(now.year + 5),
              initialDateRange: DateTimeRange(
                start: range.$1,
                end: range.$2,
              ),
            );
            if (picked != null) {
              // Rentang inklusif sampai akhir hari terakhir.
              ref.read(reportsRangeProvider.notifier).state = (
                DateTime(
                  picked.start.year,
                  picked.start.month,
                  picked.start.day,
                ),
                DateTime(
                  picked.end.year,
                  picked.end.month,
                  picked.end.day + 1,
                ).subtract(const Duration(microseconds: 1)),
              );
            }
          },
        ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.label,
    required this.amount,
    super.key,
  });

  final Color color;
  final String label;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
          Text(amount, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(
            Icons.donut_large_outlined,
            size: 40,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _MissingRateWarning extends StatelessWidget {
  const _MissingRateWarning({required this.currencies});

  final List<String> currencies;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        key: const Key('reports.rate.missing'),
        'Sebagian transaksi belum terkonversi '
        '(rate ${currencies.join(', ')} ke IDR belum ada).',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry, super.key});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Coba lagi')),
        ],
      ),
    );
  }
}
