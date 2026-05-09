import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/theme.dart';
import '../../models/staff.dart';
import '../../models/station.dart' hide Station;
import '../../services/api.dart';
import '../kitchen/kitchen_closing_count.dart';
import '../kitchen/kitchen_opening_count.dart';

/// Storekeeper Kitchen Ledger Screen.
/// Date-filterable audit table showing the full chronological shift picture:
/// Item | Location | Opening | Morning Count | Handover Variance |
/// Transfers | Waste | Closing | Expected Closing
class KitchenLedgerScreen extends StatefulWidget {
  final Staff staff;
  const KitchenLedgerScreen({super.key, required this.staff});

  @override
  State<KitchenLedgerScreen> createState() => _KitchenLedgerScreenState();
}

// Mirror the server's todayBusinessDate(): local EAT time − 7 h.
// Business day runs 07:00 EAT → 07:00 EAT (7 AM - 7h = midnight of same day).
DateTime _businessDate() {
  final shifted = DateTime.now().subtract(const Duration(hours: 7));
  return DateTime(shifted.year, shifted.month, shifted.day);
}

class _KitchenLedgerScreenState extends State<KitchenLedgerScreen> {
  List<KitchenLedgerRow> _rows = [];
  List<Map<String, dynamic>> _stations = [];
  List<StationSummary> _stationSummaries = [];
  bool _loading = true;
  String? _error;

  DateTime _selectedDate = _businessDate();
  String? _filterStationId;
  String? _filterStationName;

  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _loadStations();
    _load();
  }

  String get _dateStr {
    return '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadStations() async {
    try {
      final data = await ApiService.instance.getStations();
      if (!mounted) return;
      setState(() => _stations = data);
    } catch (_) {}
  }

  Future<void> _loadSummaries() async {
    try {
      final data = await ApiService.instance.getStationsSummary();
      final summaries = data.map((j) => StationSummary.fromJson(j)).toList();
      if (!mounted) return;
      setState(() => _stationSummaries = summaries);
    } catch (_) {}
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        ApiService.instance.getKitchenLedger(_dateStr, stationId: _filterStationId),
        ApiService.instance.getStationsSummary(),
      ]);
      final ledgerData = results[0] as Map<String, dynamic>;
      final summaryData = results[1] as List<Map<String, dynamic>>;
      final rows = (ledgerData['rows'] as List)
          .map((j) => KitchenLedgerRow.fromJson(j as Map<String, dynamic>))
          .toList();
      final summaries = summaryData.map((j) => StationSummary.fromJson(j)).toList();
      if (!mounted) return;
      setState(() { _rows = rows; _stationSummaries = summaries; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2026),
      lastDate: _businessDate(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppTheme.pinTeal),
        ),
        child: child!,
      ),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _load();
    }
  }

  Future<void> _confirmSnapshot(String snapshotId, String stationName, String type) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Confirm $type Count'),
        content: Text(
          'Lock the $stationName $type count as the operational truth? '
          'This cannot be undone without contacting ICT admin.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.pinTeal),
            child: const Text('Confirm & Lock'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _confirming = true);
    try {
      await ApiService.instance.confirmSnapshot(snapshotId, widget.staff.name);
      if (!mounted) return;
      setState(() => _confirming = false);
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _confirming = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.debtRed),
      );
    }
  }

  void _goTakeCount(StationSummary station, String type) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => type == 'Closing'
            ? KitchenClosingCountScreen(staff: widget.staff)
            : KitchenOpeningCountScreen(staff: widget.staff),
      ),
    );
    // Refresh after returning so any newly submitted count appears
    _load();
  }

  List<Widget> _buildPendingPanel() {
    if (_stationSummaries.isEmpty) return [];

    final today = DateFormat('d MMM').format(_businessDate());

    // Compact card per station — name on top, action below, laid out in a Wrap
    Widget _stationCard(StationSummary s, String type, _CountState state,
        {VoidCallback? onConfirm, VoidCallback? onTakeCount}) {
      Widget action;
      switch (state) {
        case _CountState.confirmed:
          action = Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.paidGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text('Confirmed',
                style: TextStyle(fontSize: 11, color: AppTheme.paidGreen,
                    fontWeight: FontWeight.w700)),
          );
        case _CountState.submitted:
          action = SizedBox(
            height: 28,
            child: FilledButton(
              onPressed: _confirming ? null : onConfirm,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.pinTeal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              ),
              child: const Text('Confirm & Lock'),
            ),
          );
        case _CountState.notDone:
          action = SizedBox(
            height: 28,
            child: OutlinedButton(
              onPressed: onTakeCount,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.pinTeal,
                side: const BorderSide(color: AppTheme.pinTeal),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
              child: const Text('Take Count'),
            ),
          );
      }

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.name,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: Color(0xFF263238))),
            const SizedBox(height: 6),
            action,
          ],
        ),
      );
    }

    Widget _panel(IconData icon, String title, List<Widget> cards) => Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: AppTheme.pinTeal, size: 14),
            const SizedBox(width: 6),
            Text(title,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: cards),
        ],
      ),
    );

    final openingCards = _stationSummaries.map((s) {
      if (s.openingConfirmed) {
        return _stationCard(s, 'Opening', _CountState.confirmed);
      } else if (s.openingPendingConfirm && s.openingSnapshotId != null) {
        return _stationCard(s, 'Opening', _CountState.submitted,
            onConfirm: () => _confirmSnapshot(s.openingSnapshotId!, s.name, 'Opening'));
      } else {
        return _stationCard(s, 'Opening', _CountState.notDone,
            onTakeCount: () => _goTakeCount(s, 'Opening'));
      }
    }).toList();

    final closingCards = _stationSummaries.map((s) {
      if (s.closingConfirmed) {
        return _stationCard(s, 'Closing', _CountState.confirmed);
      } else if (s.closingPendingConfirm && s.closingSnapshotId != null) {
        return _stationCard(s, 'Closing', _CountState.submitted,
            onConfirm: () => _confirmSnapshot(s.closingSnapshotId!, s.name, 'Closing'));
      } else {
        return _stationCard(s, 'Closing', _CountState.notDone,
            onTakeCount: () => _goTakeCount(s, 'Closing'));
      }
    }).toList();

    return [
      _panel(Icons.wb_sunny_rounded, "Today's Opening Count — $today", openingCards),
      _panel(Icons.nights_stay_rounded, "Today's Closing Counts — $today", closingCards),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('EEE, d MMM yyyy');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ─────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.receipt_long_rounded,
                      color: AppTheme.pinTeal, size: 26),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Kitchen Ledger',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  FilledButton.icon(
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Refresh'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.pinTeal,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Date + station filters
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Date picker chip
                  GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F8FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.pinTeal.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_today_rounded,
                              color: AppTheme.pinTeal, size: 16),
                          const SizedBox(width: 6),
                          Text(fmt.format(_selectedDate),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, color: AppTheme.pinTeal)),
                        ],
                      ),
                    ),
                  ),
                  // Station filter
                  DropdownButton<String?>(
                    value: _filterStationId,
                    underline: const SizedBox(),
                    hint: const Text('All Stations',
                        style: TextStyle(fontSize: 13, color: AppTheme.pinMuted)),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All Stations', style: TextStyle(fontSize: 13)),
                      ),
                      ..._stations.map((s) => DropdownMenuItem<String?>(
                        value: s['id'] as String,
                        child: Text(s['name'] as String, style: const TextStyle(fontSize: 13)),
                      )),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _filterStationId   = val;
                        _filterStationName = val == null ? null
                            : _stations.firstWhere((s) => s['id'] == val)['name'] as String;
                      });
                      _load();
                    },
                  ),
                  const Text(
                    'Business day: 07:00 AM → 07:00 AM',
                    style: TextStyle(fontSize: 11, color: AppTheme.pinMuted),
                  ),
                ],
              ),
            ],
          ),
        ),

        // ── Pending Confirmations ───────────────────────────────
        ..._buildPendingPanel(),

        if (_error != null)
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.debtRed.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_error!, style: const TextStyle(color: AppTheme.debtRed)),
          ),

        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
                  ? _EmptyState(date: fmt.format(_selectedDate))
                  : _LedgerTable(rows: _rows),
        ),
      ],
    );
  }
}

// ── Ledger Table ───────────────────────────────────────────────────────────────

class _LedgerTable extends StatelessWidget {
  final List<KitchenLedgerRow> rows;

  const _LedgerTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('0.###');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 1000),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Table(
              border: TableBorder.all(
                color: const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(12),
              ),
              columnWidths: const {
                0: FlexColumnWidth(2.2),   // Item
                1: FlexColumnWidth(1.5),   // Location
                2: FlexColumnWidth(1.1),   // Opening
                3: FlexColumnWidth(1.2),   // Morning Count
                4: FlexColumnWidth(1.3),   // Handover Var
                5: FlexColumnWidth(1.1),   // Transfers
                6: FlexColumnWidth(1.0),   // Waste
                7: FlexColumnWidth(1.1),   // Closing
                8: FlexColumnWidth(1.3),   // Expected Closing
                9: FlexColumnWidth(0.9),   // UOM
              },
              children: [
                // Header
                TableRow(
                  decoration: const BoxDecoration(color: Color(0xFF37474F)),
                  children: [
                    _TH('Item'),
                    _TH('Station'),
                    _TH('Opening'),
                    _TH('Morning Count'),
                    _TH('Handover Var.'),
                    _TH('Transfers'),
                    _TH('Waste'),
                    _TH('Closing'),
                    _TH('Expected Closing'),
                    _TH('UOM'),
                  ],
                ),
                // Rows
                ...rows.asMap().entries.map((entry) {
                  final i   = entry.key;
                  final row = entry.value;
                  final hv  = row.handoverVariance;
                  final hvSignificant = hv != null && hv.abs() > 0.05;
                  final closingDiff = row.closing != null
                      ? row.closing! - row.expectedClosing
                      : null;
                  final closingBad = closingDiff != null && closingDiff.abs() > 0.1;

                  final rowBg = hvSignificant
                      ? AppTheme.debtRed.withValues(alpha: 0.05)
                      : (i.isEven ? Colors.white : const Color(0xFFFAFAFA));

                  String _f(double? v) => v == null ? '—' : fmt.format(v);
                  String _fSign(double? v) {
                    if (v == null) return '—';
                    return (v >= 0 ? '+' : '') + fmt.format(v);
                  }

                  return TableRow(
                    decoration: BoxDecoration(color: rowBg),
                    children: [
                      // Item name
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        child: Row(
                          children: [
                            if (row.isPeakHours)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Icon(Icons.warning_amber_rounded,
                                    size: 14, color: Colors.amber.shade700),
                              ),
                            Expanded(
                              child: Text(row.itemName,
                                  style: const TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ),
                      // Station
                      _TD(row.stationName, muted: true),
                      // Opening
                      _TD(_f(row.opening)),
                      // Morning Count
                      row.morningCount == null
                          ? _TDMissing('Not counted')
                          : _TD(_f(row.morningCount)),
                      // Handover Variance
                      hv == null
                          ? _TDMissing('—')
                          : Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                              child: Text(_fSign(hv),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: hvSignificant ? FontWeight.w700 : FontWeight.w400,
                                    color: hvSignificant
                                        ? AppTheme.debtRed
                                        : Colors.grey.shade700,
                                  )),
                            ),
                      // Transfers
                      _TD(_f(row.transfers)),
                      // Waste
                      _TD(row.waste > 0 ? _f(row.waste) : '—',
                          color: row.waste > 0 ? Colors.orange.shade700 : null),
                      // Closing
                      row.closing == null
                          ? _TDMissing('Not counted')
                          : Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                              child: Text(_f(row.closing),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: closingBad ? FontWeight.w700 : FontWeight.w400,
                                    color: closingBad ? AppTheme.debtRed : const Color(0xFF263238),
                                  )),
                            ),
                      // Expected Closing
                      _TD(_f(row.expectedClosing), muted: true),
                      // UOM
                      _TD(row.unitOfMeasure, muted: true),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Cell helpers ───────────────────────────────────────────────────────────────

Widget _TH(String text) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
  child: Text(text,
      style: const TextStyle(
          color: Colors.white, fontSize: 11,
          fontWeight: FontWeight.w700, letterSpacing: 0.3)),
);

Widget _TD(String text, {bool muted = false, Color? color}) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
  child: Text(text,
      style: TextStyle(
          fontSize: 13,
          color: color ?? (muted ? AppTheme.pinMuted : const Color(0xFF263238)))),
);

Widget _TDMissing(String text) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
  child: Text(text,
      style: const TextStyle(
          fontSize: 12, color: AppTheme.pinMuted,
          fontStyle: FontStyle.italic)),
);

class _EmptyState extends StatelessWidget {
  final String date;
  const _EmptyState({required this.date});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.receipt_long_rounded, size: 72, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        Text('No kitchen activity on $date',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
        const SizedBox(height: 8),
        const Text('Counts and transfers appear here once kitchen staff submit them.',
            style: TextStyle(fontSize: 13, color: AppTheme.pinMuted),
            textAlign: TextAlign.center),
      ],
    ),
  );
}

enum _CountState { notDone, submitted, confirmed }
