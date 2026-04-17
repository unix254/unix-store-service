import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/theme.dart';
import '../../services/api.dart';

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
  Timer? _autoRefresh;

  @override
  void initState() {
    super.initState();
    _load();
    // Auto-refresh every 60 seconds
    _autoRefresh = Timer.periodic(const Duration(seconds: 60), (_) => _load());
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      _rows = await ApiService.instance.getVarianceToday();
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

  double _v(Map<String, dynamic> r, String key) =>
      double.tryParse(r[key]?.toString() ?? '0') ?? 0.0;

  @override
  Widget build(BuildContext context) {
    final overIssued  = _rows.where((r) => _v(r, 'variance_qty') > 0.05).length;
    final underIssued = _rows.where((r) => _v(r, 'variance_qty') < -0.05).length;
    final onTrack     = _rows.length - overIssued - underIssued;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ────────────────────────────────────────────────
        _VarianceHeader(
          lastRefreshed: _lastRefreshed,
          loading: _loading,
          onRefresh: _load,
        ),

        // ── Summary bar ───────────────────────────────────────────
        if (!_loading && _error == null && _rows.isNotEmpty)
          _SummaryBar(
            total: _rows.length,
            overIssued: overIssued,
            underIssued: underIssued,
            onTrack: onTrack,
          ),

        // ── Content ────────────────────────────────────────────────
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

// ── Header ─────────────────────────────────────────────────────────────────

class _VarianceHeader extends StatelessWidget {
  final DateTime? lastRefreshed;
  final bool loading;
  final VoidCallback onRefresh;

  const _VarianceHeader({
    required this.lastRefreshed,
    required this.loading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('HH:mm:ss');
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 24, 24, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      child: Row(
        children: [
          const Icon(Icons.analytics_rounded,
              color: AppTheme.pinTeal, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Usage Variance — Today',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                if (lastRefreshed != null)
                  Text('Last refreshed: ${fmt.format(lastRefreshed!)}  ·  Auto-refresh every 60s',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.pinMuted)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Legend chips
          _LegendChip(color: AppTheme.debtRed,   label: 'Over-Issued (loss risk)'),
          const SizedBox(width: 8),
          _LegendChip(color: AppTheme.paidGreen, label: 'Under-Issued (saved)'),
          const SizedBox(width: 16),
          FilledButton.icon(
            onPressed: loading ? null : onRefresh,
            icon: loading
                ? const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2,
                        color: Colors.white))
                : const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Refresh'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.pinTeal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ],
      ),
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
          Container(width: 12, height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.pinMuted)),
        ],
      );
}

// ── Summary Bar ────────────────────────────────────────────────────────────

class _SummaryBar extends StatelessWidget {
  final int total;
  final int overIssued;
  final int underIssued;
  final int onTrack;
  const _SummaryBar({
    required this.total,
    required this.overIssued,
    required this.underIssued,
    required this.onTrack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
      color: const Color(0xFFF5F5F5),
      child: Row(
        children: [
          _StatChip(label: 'Items Tracked', value: total.toString(),
              color: AppTheme.pinTeal),
          const SizedBox(width: 12),
          _StatChip(label: 'Over-Issued', value: overIssued.toString(),
              color: overIssued > 0 ? AppTheme.debtRed : Colors.grey),
          const SizedBox(width: 12),
          _StatChip(label: 'Under-Issued', value: underIssued.toString(),
              color: underIssued > 0 ? AppTheme.paidGreen : Colors.grey),
          const SizedBox(width: 12),
          _StatChip(label: 'On Track', value: onTrack.toString(),
              color: Colors.blueGrey),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
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

// ── Variance Table ─────────────────────────────────────────────────────────

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
            child: Row(
              children: const [
                Icon(Icons.info_outline_rounded, color: Colors.blue, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Variance = Actual Issues − Expected Issues.  '
                    'Positive (red) = more stock issued than POS sales justify — possible waste or loss.  '
                    'Negative (green) = less issued than expected — possible under-portioning or carry-over stock.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF1565C0)),
                  ),
                ),
              ],
            ),
          ),

          // Table
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Table(
              border: TableBorder.all(
                color: const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(12),
              ),
              columnWidths: const {
                0: FlexColumnWidth(2.2),   // POS Product
                1: FlexColumnWidth(2.0),   // Store Item
                2: FlexColumnWidth(1.2),   // Expected Issues
                3: FlexColumnWidth(1.2),   // Actual Issues
                4: FlexColumnWidth(1.2),   // Variance
                5: FlexColumnWidth(0.9),   // UOM
              },
              children: [
                // Header row
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
                // Data rows
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
                          : (i.isEven ? Colors.white : const Color(0xFFFAFAFA));

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
        ],
      ),
    );
  }
}

// ── Table cell helpers ─────────────────────────────────────────────────────

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

// ── Empty / Error states ───────────────────────────────────────────────────

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
