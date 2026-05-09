import 'dart:convert';
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

DateTime _businessDay(DateTime dt) {
  final shifted = dt.subtract(const Duration(hours: 7));
  return DateTime(shifted.year, shifted.month, shifted.day);
}

String _fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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
      return (from: _fmtDate(start), to: _fmtDate(today), title: 'This Week');
    case _Period.lastWeek:
      final thisMonday = today.subtract(Duration(days: today.weekday - 1));
      final lastMonday = thisMonday.subtract(const Duration(days: 7));
      final lastSunday = thisMonday.subtract(const Duration(days: 1));
      return (from: _fmtDate(lastMonday), to: _fmtDate(lastSunday), title: 'Last Week');
    case _Period.custom:
      if (custom == null) {
        return (from: _fmtDate(today), to: _fmtDate(today), title: 'Custom');
      }
      final f = _businessDay(custom.start);
      final t = _businessDay(custom.end);
      return (
        from:  _fmtDate(f),
        to:    _fmtDate(t),
        title: '${DateFormat('d MMM').format(f)} – ${DateFormat('d MMM').format(t)}',
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
  String _mode = 'estimate'; // 'estimate' | 'verified'
  bool _loading = true;
  String? _error;
  DateTime? _lastRefreshed;

  _Period _period = _Period.today;
  DateTimeRange? _customRange;
  String? _stationId;
  bool _paretoMode = false; // false = All Items, true = Top Offenders
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _stations = [];

  @override
  void initState() {
    super.initState();
    _loadStations();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStations() async {
    try {
      _stations = await ApiService.instance.getStations();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final pd = _periodDates(_period, _customRange);
      final result = await ApiService.instance.getVarianceRangeV2(
        pd.from, pd.to, stationId: _stationId);
      final rows = (result['rows'] as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _rows          = rows;
        _mode          = result['mode'] as String? ?? 'estimate';
        _lastRefreshed = DateTime.now();
        _loading       = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _pickCustomRange() async {
    final initial = _customRange ??
        DateTimeRange(start: DateTime.now().subtract(const Duration(days: 6)), end: DateTime.now());
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
    setState(() { _customRange = picked; _period = _Period.custom; });
    _load();
  }

  void _selectPeriod(_Period p) {
    if (p == _Period.custom) { _pickCustomRange(); return; }
    setState(() => _period = p);
    _load();
  }

  double _v(Map<String, dynamic> r, String key) =>
      double.tryParse(r[key]?.toString() ?? '0') ?? 0.0;

  List<Map<String, dynamic>> get _displayRows {
    // Step 1: pareto filter
    List<Map<String, dynamic>> rows;
    if (_paretoMode) {
      final sorted = List<Map<String, dynamic>>.from(_rows)
        ..sort((a, b) => _v(b, 'variance_kes').abs().compareTo(_v(a, 'variance_kes').abs()));
      rows = sorted.take(5).toList();
    } else {
      rows = _rows;
    }
    // Step 2: search filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      rows = rows.where((r) =>
        (r['inventory_item_name']?.toString().toLowerCase().contains(q) ?? false) ||
        (r['pos_product_name']?.toString().toLowerCase().contains(q) ?? false),
      ).toList();
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final displayed   = _displayRows;
    final overIssued  = displayed.where((r) => _v(r, 'variance_qty') > 0.05).length;
    final underIssued = displayed.where((r) => _v(r, 'variance_qty') < -0.05).length;
    final onTrack     = displayed.length - overIssued - underIssued;
    final pd          = _periodDates(_period, _customRange);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _VarianceHeader(
          periodTitle:    pd.title,
          lastRefreshed:  _lastRefreshed,
          loading:        _loading,
          mode:           _mode,
          onRefresh:      _load,
          selectedPeriod: _period,
          onPeriodChange: _selectPeriod,
          stations:       _stations,
          selectedStation: _stationId,
          onStationChange: (val) { setState(() => _stationId = val); _load(); },
          paretoMode:     _paretoMode,
          onParetoToggle: () => setState(() => _paretoMode = !_paretoMode),
        ),

        if (!_loading && _error == null && _rows.isNotEmpty)
          _SummaryBar(
            total: displayed.length, overIssued: overIssued,
            underIssued: underIssued, onTrack: onTrack, mode: _mode,
            searchController: _searchCtrl,
            onSearchChanged: (q) => setState(() => _searchQuery = q),
          ),

        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _ErrorState(error: _error!, onRetry: _load)
                  : displayed.isEmpty
                      ? const _EmptyState()
                      : _VarianceTable(rows: displayed, vFn: _v, mode: _mode,
                          paretoMode: _paretoMode),
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
  final String mode;
  final VoidCallback onRefresh;
  final _Period selectedPeriod;
  final void Function(_Period) onPeriodChange;
  final List<Map<String, dynamic>> stations;
  final String? selectedStation;
  final void Function(String?) onStationChange;
  final bool paretoMode;
  final VoidCallback onParetoToggle;

  const _VarianceHeader({
    required this.periodTitle,
    required this.lastRefreshed,
    required this.loading,
    required this.mode,
    required this.onRefresh,
    required this.selectedPeriod,
    required this.onPeriodChange,
    required this.stations,
    required this.selectedStation,
    required this.onStationChange,
    required this.paretoMode,
    required this.onParetoToggle,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('HH:mm:ss');
    final isVerified = mode == 'verified';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics_rounded, color: AppTheme.pinTeal, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Usage Variance — $periodTitle',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        // Mode badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isVerified
                                ? AppTheme.paidGreen.withValues(alpha: 0.12)
                                : Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isVerified
                                  ? AppTheme.paidGreen.withValues(alpha: 0.4)
                                  : Colors.amber.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            isVerified ? 'Verified' : 'Estimated',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isVerified ? AppTheme.paidGreen : Colors.amber.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (lastRefreshed != null)
                      Text('Last refreshed: ${fmt.format(lastRefreshed!)}',
                          style: const TextStyle(fontSize: 12, color: AppTheme.pinMuted)),
                  ],
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  IconButton(
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Row(children: [
                          Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 18),
                          SizedBox(width: 10),
                          Text('PDF Report generation coming soon.',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                        ]),
                        backgroundColor: AppTheme.pinTeal,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        duration: const Duration(seconds: 3),
                      ),
                    ),
                    icon: const Icon(Icons.picture_as_pdf_rounded, color: AppTheme.pinTeal),
                    tooltip: 'Download PDF (coming soon)',
                  ),
                  FilledButton.icon(
                    onPressed: loading ? null : onRefresh,
                    icon: loading
                        ? const SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Refresh'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.pinTeal,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Period selector + station filter
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ..._Period.values.map((p) {
                final isSelected = selectedPeriod == p;
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
                  side: BorderSide(color: isSelected ? AppTheme.pinTeal : const Color(0xFFDDDDDD)),
                  onSelected: (_) => onPeriodChange(p),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                );
              }),
              if (stations.isNotEmpty) ...[
                const SizedBox(width: 8),
                DropdownButton<String?>(
                  value: selectedStation,
                  underline: const SizedBox(),
                  isDense: true,
                  hint: const Text('All Stations',
                      style: TextStyle(fontSize: 12, color: AppTheme.pinMuted)),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('All Stations', style: TextStyle(fontSize: 12))),
                    ...stations.map((s) => DropdownMenuItem<String?>(
                        value: s['id'] as String,
                        child: Text(s['name'] as String, style: const TextStyle(fontSize: 12)))),
                  ],
                  onChanged: onStationChange,
                ),
              ],
              OutlinedButton.icon(
                onPressed: onParetoToggle,
                icon: Icon(paretoMode ? Icons.list_rounded : Icons.bar_chart_rounded, size: 16),
                label: Text(paretoMode ? 'All Items' : 'Top Offenders',
                    style: const TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.pinTeal,
                  side: const BorderSide(color: AppTheme.pinTeal),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Summary Bar ────────────────────────────────────────────────────────────────

class _SummaryBar extends StatelessWidget {
  final int total, overIssued, underIssued, onTrack;
  final String mode;
  final TextEditingController searchController;
  final void Function(String) onSearchChanged;

  const _SummaryBar({
    required this.total, required this.overIssued,
    required this.underIssued, required this.onTrack, required this.mode,
    required this.searchController, required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFFF5F5F5),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 10, runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _StatChip(label: 'Items Tracked', value: total.toString(), color: AppTheme.pinTeal),
                _StatChip(label: 'Over-Consumed', value: overIssued.toString(),
                    color: overIssued > 0 ? AppTheme.debtRed : Colors.grey),
                _StatChip(label: 'Under-Consumed', value: underIssued.toString(),
                    color: underIssued > 0 ? AppTheme.paidGreen : Colors.grey),
                _StatChip(label: 'On Track', value: onTrack.toString(), color: Colors.blueGrey),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Search field
          SizedBox(
            width: 210,
            child: TextField(
              controller: searchController,
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search items…',
                hintStyle: const TextStyle(fontSize: 12, color: AppTheme.pinMuted),
                prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppTheme.pinMuted),
                suffixIcon: searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 16),
                        onPressed: () {
                          searchController.clear();
                          onSearchChanged('');
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppTheme.pinTeal),
                ),
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
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
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.pinMuted)),
        ],
      ),
    );
  }
}

// ── Variance Table ─────────────────────────────────────────────────────────────

class _VarianceTable extends StatefulWidget {
  final List<Map<String, dynamic>> rows;
  final double Function(Map<String, dynamic>, String) vFn;
  final String mode;
  final bool paretoMode;

  const _VarianceTable({
    required this.rows, required this.vFn,
    required this.mode, required this.paretoMode,
  });

  @override
  State<_VarianceTable> createState() => _VarianceTableState();
}

class _VarianceTableState extends State<_VarianceTable> {
  // Tracks which rows have their POS product breakdown expanded
  final Set<String> _expanded = {};

  /// Returns a display string for the POS Product(s) column.
  /// Shows up to 2 product names; if there are more it appends "+N more".
  /// Using the already-parsed breakdown rather than the raw concatenated SQL string.
  String _posProductLabel(List<Map<String, dynamic>> breakdown) {
    if (breakdown.isEmpty) return '—';
    const maxShow = 2;
    final names = breakdown
        .map((b) => b['pos_product_name']?.toString() ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    if (names.isEmpty) return '—';
    if (names.length <= maxShow) return names.join(' / ');
    return '${names.take(maxShow).join(' / ')}  +${names.length - maxShow} more';
  }

  List<Map<String, dynamic>> _parsedBreakdown(Map<String, dynamic> row) {
    final raw = row['pos_product_breakdown'];
    if (raw == null) return [];
    try {
      // Backend parses JSON_ARRAYAGG strings before sending, but handle String
      // defensively in case an older cached response or edge case slips through.
      if (raw is List) return raw.cast<Map<String, dynamic>>();
      if (raw is String) {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('0.###');
    final fmtKesInt = NumberFormat('#,##0'); // whole shillings, no decimals
    final isVerified = widget.mode == 'verified';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Explanation banner
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF90CAF9)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Colors.blue, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isVerified
                        ? 'Variance = True Consumption − Expected Consumption (from POS sales). '
                          'True Consumption = Opening Stock + Transfers − Waste − Closing Stock. Business day 7 AM – 7 AM.'
                        : 'Estimated mode — No physical count data found for this period. '
                          'Variance = Transfers Issued − Expected Consumption (from POS sales). '
                          'Start doing daily closing counts to get Verified variance.',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF1565C0)),
                  ),
                ),
              ],
            ),
          ),

          if (widget.paretoMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppTheme.debtRed.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.debtRed.withValues(alpha: 0.25)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.bar_chart_rounded, color: AppTheme.debtRed, size: 16),
                  SizedBox(width: 8),
                  Text('Top Offenders — sorted by KES financial impact (highest loss first)',
                      style: TextStyle(fontSize: 12, color: AppTheme.debtRed,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 900),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Table(
                  border: TableBorder.all(
                    color: const Color(0xFFE0E0E0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  columnWidths: {
                    0: const FlexColumnWidth(0.4), // expand
                    1: const FlexColumnWidth(1.8), // Store Item
                    2: const FlexColumnWidth(2.0), // POS Product(s)
                    3: const FlexColumnWidth(1.2), // Expected Consumption
                    4: const FlexColumnWidth(1.2), // True Consumption
                    5: const FlexColumnWidth(1.2), // Variance
                    6: const FlexColumnWidth(1.0), // KES Impact
                    7: const FlexColumnWidth(0.7), // UOM
                  },
                  children: [
                    // Header
                    TableRow(
                      decoration: const BoxDecoration(color: Color(0xFF37474F)),
                      children: [
                        _TH(''),
                        _TH('Store Item'),
                        _TH('POS Product(s)'),
                        _TH('Expected Consumption\n(from POS sales)'),
                        _TH('True Consumption'),
                        _TH('Variance'),
                        _TH('KES Impact'),
                        _TH('UOM'),
                      ],
                    ),
                    ...widget.rows.asMap().entries.expand((entry) {
                      final i   = entry.key;
                      final r   = entry.value;
                      final itemId    = r['inventory_item_id']?.toString() ?? '';
                      final variance  = widget.vFn(r, 'variance_qty');
                      final isOver    = variance > 0.05;
                      final isUnder   = variance < -0.05;
                      final isExpanded = _expanded.contains(itemId);
                      final breakdown = _parsedBreakdown(r);
                      // Show expand for any item with breakdown data (even single product)
                      // so users can confirm which POS product drives consumption.
                      final hasBreakdown = breakdown.isNotEmpty;

                      final varianceKes = widget.vFn(r, 'variance_kes');

                      final rowBg = i.isEven ? Colors.white : const Color(0xFFFAFAFA);

                      final varianceColor = isOver
                          ? AppTheme.debtRed
                          : isUnder
                              ? AppTheme.paidGreen
                              : Colors.grey.shade600;

                      final trueConsumptionKey = isVerified ? 'true_consumption' : 'true_consumption';

                      return [
                        // Main row
                        TableRow(
                          decoration: BoxDecoration(color: rowBg),
                          children: [
                            // Expand button
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                              child: hasBreakdown
                                  ? IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                      icon: Icon(
                                        isExpanded
                                            ? Icons.expand_less_rounded
                                            : Icons.expand_more_rounded,
                                        size: 18, color: AppTheme.pinTeal,
                                      ),
                                      onPressed: () => setState(() {
                                        if (isExpanded) _expanded.remove(itemId);
                                        else _expanded.add(itemId);
                                      }),
                                    )
                                  : const SizedBox(),
                            ),
                            // col 1: Store Item (now first)
                            _TD(r['inventory_item_name']?.toString() ?? '—', bold: true),
                            // col 2: POS Product(s) — show up to 2, then "+N more"
                            _TD(_posProductLabel(breakdown)),
                            _TD(fmt.format(widget.vFn(r, 'expected_consumption'))),
                            _TD(r[trueConsumptionKey] != null
                                ? fmt.format(widget.vFn(r, trueConsumptionKey))
                                : fmt.format(widget.vFn(r, 'true_consumption'))),
                            _TDColored(
                              value: (variance >= 0 ? '+' : '') + fmt.format(variance),
                              color: varianceColor,
                              bold: isOver || isUnder,
                            ),
                            // KES Impact: whole shillings, no currency prefix
                            _TD(varianceKes > 0
                                ? fmtKesInt.format(varianceKes.round())
                                : '—',
                                color: varianceKes > 50 ? AppTheme.debtRed : null),
                            _TD(r['unit_of_measure']?.toString() ?? '—', muted: true),
                          ],
                        ),
                        // Expanded breakdown rows
                        if (isExpanded && hasBreakdown)
                          ...breakdown.map((b) => TableRow(
                            decoration: const BoxDecoration(color: Color(0xFFF0F7FF)),
                            children: [
                              _TD(''),          // col 0: expand (blank)
                              _TD(''),          // col 1: Store Item (blank — shown on parent row)
                              // col 2: POS product name indented
                              Padding(
                                padding: const EdgeInsets.only(left: 28, top: 8, bottom: 8, right: 14),
                                child: Text(
                                  '↳ ${b['pos_product_name'] ?? '—'}',
                                  style: const TextStyle(
                                      fontSize: 12, color: AppTheme.pinTeal,
                                      fontStyle: FontStyle.italic),
                                ),
                              ),
                              // col 3: expected qty for this POS product
                              _TD(fmt.format(
                                  double.tryParse(b['expected_qty']?.toString() ?? '0') ?? 0)),
                              _TD(''),  // col 4
                              _TD(''),  // col 5
                              _TD(''),  // col 6
                              _TD(''),  // col 7
                            ],
                          )),
                      ];
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

// ── Cell helpers ───────────────────────────────────────────────────────────────

Widget _TH(String text) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  child: Text(text,
      style: const TextStyle(color: Colors.white, fontSize: 11,
          fontWeight: FontWeight.w700, letterSpacing: 0.3)),
);

Widget _TD(String text, {bool muted = false, bool bold = false, Color? color}) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
  child: Text(text,
      style: TextStyle(
          fontSize: 13,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          color: color ?? (muted ? AppTheme.pinMuted : const Color(0xFF263238)))),
);

Widget _TDColored({
  required String value,
  required Color color,
  bool bold = false,
}) =>
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Text(value,
          style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
    );

// ── Empty / Error states ───────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Center(
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

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline_rounded, size: 56, color: AppTheme.debtRed),
        const SizedBox(height: 12),
        Text(error, style: const TextStyle(fontSize: 14, color: AppTheme.debtRed)),
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
