import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/formatting/app_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/category_visuals.dart';
import '../../core/theme/design_tokens.dart';
import '../../domain/models/expense_category.dart';
import '../../domain/models/report_summary.dart';

/// One bar/point of a single-series chart.
class ChartDatum {
  const ChartDatum({
    required this.label,
    required this.valueMinor,
    required this.tooltipLabel,
    this.muted = false,
  });

  /// Short axis label (e.g. "Mon", "12", "Jan").
  final String label;
  final int valueMinor;

  /// Full label for tooltips and screen readers (e.g. "Mon, 12 Oct").
  final String tooltipLabel;

  /// Future/out-of-range points drawn in a recessive colour.
  final bool muted;
}

/// Rounds an axis maximum up to 1, 2, 2.5 or 5 × 10^n.
double niceCeiling(double v) {
  if (v <= 0) return 1;
  final exp = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
  final f = v / exp;
  final nice = f <= 1
      ? 1.0
      : f <= 2
      ? 2.0
      : f <= 2.5
      ? 2.5
      : f <= 5
      ? 5.0
      : 10.0;
  return nice * exp;
}

/// Axis scale with "nice" gridline steps (1, 2, 2.5, 5 × 10^n) and at
/// most about four intervals, always starting at zero.
({double maxY, double interval}) niceAxis(double maxValue) {
  final step = niceCeiling(maxValue <= 0 ? 1 : maxValue / 4);
  final steps = math.max(1, (maxValue / step).ceil());
  return (maxY: step * steps, interval: step);
}

String chartSummary(List<ChartDatum> data, AppFormat fmt) {
  if (data.every((d) => d.valueMinor == 0)) return 'No spending recorded.';
  final total = data.fold<int>(0, (s, d) => s + d.valueMinor);
  final max = data.reduce((a, b) => b.valueMinor > a.valueMinor ? b : a);
  return 'Total ${fmt.amount(total)}. Highest: ${max.tooltipLabel}, '
      '${fmt.amount(max.valueMinor)}.';
}

/// Single-series bar chart of spending (minor units). No legend: the card
/// title names the series. Bars are thin with 4 px rounded tops anchored to a
/// zero baseline; the y-axis always starts at zero.
class SpendingBarChart extends StatelessWidget {
  const SpendingBarChart({
    super.key,
    required this.data,
    required this.format,
    this.height = 200,
    this.semanticTitle = 'Spending chart',
    this.highlightIndex,
  });

  final List<ChartDatum> data;
  final AppFormat format;
  final double height;
  final String semanticTitle;

  /// Bar drawn at full strength (e.g. today); the others are softened so the
  /// current day stands out. Null draws every bar at full strength.
  final int? highlightIndex;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final app = context.appColors;
    final factor = format.currency.minorFactor;
    final maxValue = data.fold<int>(0, (m, d) => math.max(m, d.valueMinor));
    final axis = niceAxis(maxValue / factor);
    final maxY = axis.maxY;
    final labelStyle = context.text.labelSmall!.copyWith(
      color: colors.onSurfaceVariant,
    );
    // Show at most ~8 x-axis labels.
    final step = math.max(1, (data.length / 8).ceil());

    return Semantics(
      label: '$semanticTitle. ${chartSummary(data, format)}',
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final slot = constraints.maxWidth / math.max(1, data.length);
              final barWidth = (slot * 0.55).clamp(3.0, 28.0);
              return BarChart(
                BarChartData(
                  minY: 0,
                  maxY: maxY,
                  alignment: BarChartAlignment.spaceAround,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => colors.inverseSurface,
                      tooltipBorderRadius: BorderRadius.circular(Radii.sm),
                      fitInsideHorizontally: true,
                      fitInsideVertically: true,
                      getTooltipItem: (group, _, rod, _) {
                        final d = data[group.x];
                        return BarTooltipItem(
                          '${d.tooltipLabel}\n',
                          context.text.labelSmall!.copyWith(
                            color: colors.onInverseSurface,
                          ),
                          children: [
                            TextSpan(
                              text: format.amount(d.valueMinor),
                              style: context.text.labelLarge!.tabular.copyWith(
                                color: colors.onInverseSurface,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    horizontalInterval: axis.interval,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: app.chartGrid, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border(
                      bottom: BorderSide(color: colors.outlineVariant),
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 52,
                        interval: axis.interval,
                        getTitlesWidget: (value, meta) => SideTitleWidget(
                          meta: meta,
                          child: Text(
                            format.compact((value * factor).round()),
                            style: labelStyle,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= data.length || i % step != 0) {
                            return const SizedBox.shrink();
                          }
                          return SideTitleWidget(
                            meta: meta,
                            child: Text(data[i].label, style: labelStyle),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < data.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: data[i].valueMinor / factor,
                            width: barWidth,
                            color: data[i].muted
                                ? app.chartBarMuted
                                : (highlightIndex == null ||
                                          highlightIndex! < 0 ||
                                          highlightIndex == i
                                      ? app.chartBar
                                      : app.chartBar.withValues(alpha: 0.55)),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Single-series 2 px line for monthly trends with a crosshair tooltip.
class TrendLineChart extends StatelessWidget {
  const TrendLineChart({
    super.key,
    required this.data,
    required this.format,
    this.height = 180,
    this.semanticTitle = 'Monthly trend',
  });

  final List<ChartDatum> data;
  final AppFormat format;
  final double height;
  final String semanticTitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final app = context.appColors;
    final factor = format.currency.minorFactor;
    final maxValue = data.fold<int>(0, (m, d) => math.max(m, d.valueMinor));
    final axis = niceAxis(maxValue / factor);
    final maxY = axis.maxY;
    final labelStyle = context.text.labelSmall!.copyWith(
      color: colors.onSurfaceVariant,
    );

    return Semantics(
      label: '$semanticTitle. ${chartSummary(data, format)}',
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maxY,
              minX: 0,
              maxX: math.max(1, data.length - 1).toDouble(),
              lineTouchData: LineTouchData(
                getTouchedSpotIndicator: (bar, indexes) => [
                  for (final _ in indexes)
                    TouchedSpotIndicatorData(
                      FlLine(color: colors.outline, strokeWidth: 1),
                      FlDotData(
                        getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                          radius: 5,
                          color: app.chartBar,
                          strokeWidth: 2,
                          strokeColor: colors.surface,
                        ),
                      ),
                    ),
                ],
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => colors.inverseSurface,
                  fitInsideHorizontally: true,
                  getTooltipItems: (spots) => [
                    for (final s in spots)
                      LineTooltipItem(
                        '${data[s.x.toInt()].tooltipLabel}\n',
                        context.text.labelSmall!.copyWith(
                          color: colors.onInverseSurface,
                        ),
                        children: [
                          TextSpan(
                            text: format.amount(data[s.x.toInt()].valueMinor),
                            style: context.text.labelLarge!.tabular.copyWith(
                              color: colors.onInverseSurface,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: axis.interval,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: app.chartGrid, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 52,
                    interval: axis.interval,
                    getTitlesWidget: (value, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(
                        format.compact((value * factor).round()),
                        style: labelStyle,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    reservedSize: 24,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= data.length || value != i.toDouble()) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(data[i].label, style: labelStyle),
                      );
                    },
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (var i = 0; i < data.length; i++)
                      FlSpot(i.toDouble(), data[i].valueMinor / factor),
                  ],
                  color: app.chartBar,
                  barWidth: 2,
                  isCurved: false,
                  dotData: FlDotData(
                    getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                      radius: 4,
                      color: app.chartBar,
                      strokeWidth: 2,
                      strokeColor:
                          context.theme.cardTheme.color ?? colors.surface,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: app.chartBar.withValues(alpha: 0.08),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A category slice; [category] is null for the folded "Other" slice.
class _Slice {
  const _Slice(this.category, this.totalMinor, this.shareBasisPoints);
  final ExpenseCategory? category;
  final int totalMinor;
  final int shareBasisPoints;
}

/// Category donut with a legend list. Shows the top [maxSlices] categories
/// and folds the rest into a neutral "Other categories" slice so colour never
/// has to distinguish more than a handful of hues. Legend text uses ink
/// colours; the swatch + icon carry identity.
class CategoryBreakdown extends StatelessWidget {
  const CategoryBreakdown({
    super.key,
    required this.totals,
    required this.resolve,
    required this.format,
    this.maxSlices = 5,
    this.horizontal = false,
    this.onCategoryTap,
  });

  final List<CategoryTotal> totals;
  final ExpenseCategory Function(String id) resolve;
  final AppFormat format;
  final int maxSlices;
  final bool horizontal;
  final ValueChanged<String>? onCategoryTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final grand = totals.fold<int>(0, (s, t) => s + t.totalMinor);
    final slices = <_Slice>[
      for (final t in totals.take(maxSlices))
        _Slice(resolve(t.categoryId), t.totalMinor, t.shareBasisPoints),
    ];
    if (totals.length > maxSlices) {
      final rest = totals.skip(maxSlices);
      final restTotal = rest.fold<int>(0, (s, t) => s + t.totalMinor);
      final restShare = rest.fold<int>(0, (s, t) => s + t.shareBasisPoints);
      slices.add(_Slice(null, restTotal, restShare));
    }
    Color colorOf(_Slice s) =>
        s.category?.color(context) ?? colors.outline.withValues(alpha: 0.6);

    final summary = slices
        .map(
          (s) =>
              '${s.category?.name ?? 'Other categories'} '
              '${format.amount(s.totalMinor)}, '
              '${(s.shareBasisPoints / 100).toStringAsFixed(0)} percent',
        )
        .join('; ');

    final donut = Semantics(
      label: 'Category breakdown. $summary',
      child: ExcludeSemantics(
        child: SizedBox(
          width: 168,
          height: 168,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 54,
                  startDegreeOffset: -90,
                  sections: [
                    for (final s in slices)
                      PieChartSectionData(
                        value: s.totalMinor.toDouble(),
                        color: colorOf(s),
                        radius: 24,
                        showTitle: false,
                      ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Total', style: context.text.labelSmall),
                  FittedBox(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        format.compact(grand),
                        style: context.text.titleMedium!.tabular,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    final legend = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final s in slices)
          InkWell(
            borderRadius: BorderRadius.circular(Radii.sm),
            onTap: s.category == null || onCategoryTap == null
                ? null
                : () => onCategoryTap!(s.category!.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colorOf(s),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Icon(
                    s.category?.icon ?? Icons.more_horiz_rounded,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      s.category?.name ?? 'Other categories',
                      style: context.text.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Text(
                    '${(s.shareBasisPoints / 100).round()}%',
                    style: context.text.bodySmall!.tabular,
                  ),
                  const SizedBox(width: Space.md),
                  Text(
                    format.amount(s.totalMinor),
                    style: context.text.labelLarge!.tabular,
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    if (horizontal) {
      return LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < 520
            ? Column(
                children: [
                  donut,
                  const SizedBox(height: Space.lg),
                  legend,
                ],
              )
            : Row(
                children: [
                  donut,
                  const SizedBox(width: Space.xxl),
                  Expanded(child: legend),
                ],
              ),
      );
    }
    return Column(
      children: [
        donut,
        const SizedBox(height: Space.lg),
        legend,
      ],
    );
  }
}
