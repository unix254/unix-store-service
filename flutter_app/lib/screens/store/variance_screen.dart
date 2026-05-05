import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/theme.dart';
import '../../services/api.dart';

// ── Period enum ────────────────────────────────────────────────────────────────

enum _Period { today, yesterday, thisWeek, lastWeek, custom }

extension _PeriodLabel on _Period {
  String get label {
    switch (this) {
      case _Period.today:     return 'Today';
      case _Period.yesterday: return 'Yesterday';
      case _Period.thisWeek:  return 'This Week';
      case _Period.lastWeek:  return 'Last Week';
      case _Period.custom:    return 'Custom';
    }
  }
}

// ── Business-day helpers ───────────────────────────────────────────────────────

// Shift by 7 hours so that 2 AM Wednesday counts as Tuesday's business day.
DateTime _businessDay(DateTime dt) {
  final shifted = dt.subtract(const Duration(hours: 7));
  return DateTime(shifted.year, shifted.month, shifted.day);
}

String _fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// Returns (from, to) business-date strings for the given period.
({String from, String to, String title}) _periodDates(
    _Period period, DateTimeRange? custom) {
  final today = _businessDay(DateTime.now());

  switch (period) {
    case _Period.today:
      return (from: _fmtDate(today), to: _fmtDate(today), title: 'Today');
    case _Period.yesterday:
      final y = today.subtract(const Duration(days: 1));
      return (from: _fmtDate(y), to: _fmtDate(y), title: 'Yesterday');
    case _Period.thisWeek:
      final start = today.subtract(Duration(days: today.weekday - 1));
      return (
        from:  _fmtDate(start),
        to:    _fmtDate(today),
        title: 'This Week',
      );
    case _Period.lastWeek:
      final thisMonday = today.subtract(Duration(days: today.weekday - 1));
      final lastMonday = thisMonday.subtract(const Duration(days: 7));
      final lastSunday = thisMonday.subtract(const Duration(days: 1));
      return (
        from:  _fmtDate(lastMonday),
        to:    _fmtDate(lastSunday),
        title: 'Last Week',
      );
    case _Period.custom:
      if (custom == null) {
        return (from: _fmtDate(today), to: _fmtDate(today), title: 'Custom');
      }
      final f = _businessDay(custom.start);
      final t = _businessDay(custom.end);
      final display = DateFormat('d MMM');
      return (
        from:  _fmtDate(f),
        to:    _fmtDate(t),
        title: '${display.format(f)} – ${display.format(t)}',
      );
  }
}

// ── Screen ─────────────────────────────────────────────────────────────────────

class VarianceScreen extends StatefulWidget {
  const VarianceScreen({super.key});

  @override
  State<VarianceScreen> createState() => _VarianceScreenState();
}

class _VarianceScreenState extends State<VarianceScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  DateTime? _lastRefreshed;

  _Period _period = _Period.today;
  DateTimeRange? _customRange;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final pd = _periodDates(_period, _customRange);
      _rows = await ApiService.instance.getVarianceRange(pd.from, pd.to);
      if (!mounted) return;
      setState(() {
        _lastRefreshed = DateTime.now();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _pickCustomRange() async {
    final initial = _customRange ??
        DateTimeRange(
          start: DateTime.now().subtract(const Duration(days: 6)),
          end:   DateTime.now(),
        );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate:  DateTime.now(),
      initialDateRange: initial,
      helpText: 'Select variance date range',
      saveText: 'Apply',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppTheme.pinTeal),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      _customRange = picked;
      _period = _Period.custom;
    });
    _load();
  }

  void _selectPeriod(_Period p) {
    if (p == _Period.custom) {
      _pickCustomRange();
      return;
    }
    setState(() => _period = p);
    _load();
  }

  double _v(Map<String, dynamic> r, String key) =>
      double.tryParse(r[key]?.toString() ?? '0') ?? 0.0;

  @override
  Widget build(BuildContext context) {
    final overIssued  = _rows.where((r) => _v(r, 'variance_qty') > 0.05).length;
    final underIssued = _rows.where((r) => _v(r, 'variance_qty') < -0.05).length;
    final onTrack     = _rows.length - overIssued - underIssued;
    final pd          = _periodDates(_period, _customRange);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _VarianceHeader(
          periodTitle:   pd.title,
          lastRefreshed: _lastRefreshed,
          loading:       _loading,
          onRefresh:     _load,
          selectedPeriod: _period,
          onPeriodChange: _selectPeriod,
        ),

        if (!_loading && _error == null && _rows.isNotEmpty)
          _SummaryBar(
            total:       _rows.length,
            overIssued:  overIssued,
            underIssued: underIssued,
            onTrack:     onTrack,
          ),

        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _ErrorState(error: _error!, onRetry: _load)
                  : _rows.isEmpty
                      ? const _EmptyState()
                      : _VarianceTable(rows: _rows, vFn: _v),
        ),
      ],
    );
  }
}

// ── Header ─────────────────────────────────────────────────────────────────────

class _VarianceHeader extends StatelessWidget {
  final String periodTitle;
  final DateTime? lastRefreshed;
  final bool loading;
  final VoidCallback onRefresh;
  final _Period selectedPeriod;
  final void Function(_Period) onPeriodChange;

  const _VarianceHeader({
    required this.periodTitle,
    required this.lastRefreshed,
    required this.loading,
    required this.onRefresh,
    required this.selectedPeriod,
    required this.onPeriodChange,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('HH:mm:ss');
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            children: [
              const Icon(Icons.analytics_rounded,
                  color: AppTheme.pinTeal, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Usage Variance — $periodTitle',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    if (lastRefreshed != null)
                      Text(
                        'Last refreshed: ${fmt.format(lastRefreshed!)}',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.pinMuted),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Wrap(
                spacing: 8,
                children: [
                  _LegendChip(color: AppTheme.debtRed,   label: 'Over-Issued'),
                  _LegendChip(color: AppTheme.paidGreen, label: 'Under-Issued'),
                  IconButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Row(
                            children: [
                              Icon(Icons.picture_as_pdf_rounded,
                                  color: Colors.white, size: 18),
                              SizedBox(width: 10),
                              Text('PDF Report generation coming soon.',
                                  style: TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ),
                          backgroundColor: AppTheme.pinTeal,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    },
                    icon: const Icon(Icons.picture_as_pdf_rounded,
                        color: AppTheme.pinTeal),
                    tooltip: 'Download PDF (coming soon)',
                  ),
                  FilledButton.icon(
                    onPressed: loading ? null : onRefresh,
                    icon: loading
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Refresh'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.pinTeal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Period selector
          _PeriodSelector(
            selected:  selectedPeriod,
            onChange:  onPeriodChange,
          ),
        ],
      ),
    );
  }
}

// ── Period selector ─────────────────────────────────────────────────────────────

class _PeriodSelector extends StatelessWidget {
  final _Period selected;
  final void Function(_Period) onChange;

  const _PeriodSelector({required this.selected, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: _Period.values.map((p) {
        final isSelected = selected == p;
        return ChoiceChip(
          label: Text(p.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : AppTheme.pinMuted,
              )),
          selected: isSelected,
          selectedColor: AppTheme.pinTeal,
          backgroundColor: const Color(0xFFF5F5F5),
          side: BorderSide(
            color: isSelected ? AppTheme.pinTeal : const Color(0xFFDDDDDD),
          ),
          onSelected: (_) => onChange(p),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        );
      }).toList(),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendChip({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
              width: 12, height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(fontSize: 11, color: AppTheme.pinMuted)),
        ],
      );
}

// ── Summary Bar ────────────────────────────────────────────────────────────────

class _SummaryBar extends StatelessWidget {
  final int total, overIssued, underIssued, onTrack;
  const _SummaryBar({
    required this.total,
    required this.overIssued,
    required this.underIssued,
    required this.onTrack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFFF5F5F5),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _StatChip(label: 'Items Tracked', value: total.toString(),
              color: AppTheme.pinTeal),
          _StatChip(label: 'Over-Issued', value: overIssued.toString(),
              color: overIssued > 0 ? AppTheme.debtRed : Colors.grey),
          _StatChip(label: 'Under-Issued', value: underIssued.toString(),
              color: underIssued > 0 ? AppTheme.paidGreen : Colors.grey),
          _StatChip(label: 'On Track', value: onTrack.toString(),
              color: Colors.blueGrey),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(fontSize: 12, color: AppTheme.pinMuted)),
        ],
      ),
    );
  }
}

// ── Variance Table ─────────────────────────────────────────────────────────────

class _VarianceTable extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final double Function(Map<String, dynamic>, String) vFn;

  const _VarianceTable({required this.rows, required this.vFn});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('0.###');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Explanation banner
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF90CAF9)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, color: Colors.blue, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Variance = Actual Issues − Expected Issues.  '
                    'Positive (red) = more stock issued than POS sales justify — possible waste or loss.  '
                    'Negative (green) = less issued than expected — possible under-portioning or carry-over stock.  '
                    'Business day runs 7 AM – 7 AM.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF1565C0)),
                  ),
                ),
              ],
            ),
          ),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 800),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Table(
                  border: TableBorder.all(
                    color: const Color(0xFFE0E0E0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  columnWidths: const {
                    0: FlexColumnWidth(2.2),
                    1: FlexColumnWidth(2.0),
                    2: FlexColumnWidth(1.2),
                    3: FlexColumnWidth(1.2),
                    4: FlexColumnWidth(1.2),
                    5: FlexColumnWidth(0.9),
                  },
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(color: Color(0xFF37474F)),
                      children: [
                        _TH('POS Product(s)'),
                        _TH('Store Item'),
                        _TH('Expected Issues'),
                        _TH('Actual Issues'),
                        _TH('Variance'),
                        _TH('UOM'),
                      ],
                    ),
                    ...rows.asMap().entries.map((entry) {
                      final i = entry.key;
                      final r = entry.value;
                      final variance = vFn(r, 'variance_qty');
                      final isOver  = variance > 0.05;
                      final isUnder = variance < -0.05;

                      final rowBg = isOver
                          ? AppTheme.debtRed.withOpacity(0.07)
                          : isUnder
                              ? AppTheme.paidGreen.withOpacity(0.07)
                              : (i.isEven
                                  ? Colors.white
                                  : const Color(0xFFFAFAFA));

                      final varianceColor = isOver
                          ? AppTheme.debtRed
                          : isUnder
                              ? AppTheme.paidGreen
                              : Colors.grey.shade600;

                      return TableRow(
                        decoration: BoxDecoration(color: rowBg),
                        children: [
                          _TD(r['pos_product_name']?.toString() ?? '—'),
                          _TD(r['inventory_item_name']?.toString() ?? '—'),
                          _TD(fmt.format(vFn(r, 'expected_consumption'))),
                          _TD(fmt.format(vFn(r, 'actual_issued'))),
                          _TDColored(
                            value: (variance >= 0 ? '+' : '') +
                                fmt.format(variance),
                            color: varianceColor,
                            bold: isOver || isUnder,
                            icon: isOver
                                ? Icons.arrow_upward_rounded
                                : isUnder
                                    ? Icons.arrow_downward_rounded
                                    : null,
                          ),
                          _TD(r['unit_of_measure']?.toString() ?? '—',
                              muted: true),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Table cell helpers ─────────────────────────────────────────────────────────

Widget _TH(String text) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3)),
    );

Widget _TD(String text, {bool muted = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Text(text,
          style: TextStyle(
              fontSize: 13,
              color: muted ? AppTheme.pinMuted : const Color(0xFF263238))),
    );

Widget _TDColored({
  required String value,
  required Color color,
  bool bold = false,
  IconData? icon,
}) =>
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
          ],
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  color: color,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
        ],
      ),
    );

// ── Empty / Error states ───────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bar_chart_rounded, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No yield configurations found.',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
          const SizedBox(height: 8),
          Text('Add yield configs in the Yield Config tab to start tracking variance.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 56, color: AppTheme.debtRed),
          const SizedBox(height: 12),
          Text(error,
              style: const TextStyle(fontSize: 14, color: AppTheme.debtRed)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
