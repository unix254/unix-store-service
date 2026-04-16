import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/theme.dart';
import '../../models/staff.dart';
import '../../services/api.dart';

final _kes = NumberFormat.currency(locale: 'en_KE', symbol: 'KES ', decimalDigits: 2);

class PayRunsScreen extends StatefulWidget {
  final Staff staff;
  const PayRunsScreen({super.key, required this.staff});

  @override
  State<PayRunsScreen> createState() => _PayRunsScreenState();
}

class _PayRunsScreenState extends State<PayRunsScreen> {
  // ── State ─────────────────────────────────────────────────────────────────
  Map<String, dynamic>? _todayRun;
  List<Map<String, dynamic>> _allRuns = [];
  bool _loading = true;
  String? _error;

  // Current detail view
  Map<String, dynamic>? _selectedRun;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        ApiService.instance.getTodayPayRun(),
        ApiService.instance.getPayRuns(),
      ]);
      final today = results[0] as Map<String, dynamic>;
      final all   = results[1] as List<Map<String, dynamic>>;
      // Refresh selected run if open
      Map<String, dynamic>? refreshedSelected;
      if (_selectedRun != null) {
        try {
          refreshedSelected = await ApiService.instance.getPayRun(_selectedRun!['id'] as String);
        } catch (_) {}
      }
      setState(() {
        _todayRun     = today;
        _allRuns      = all;
        _selectedRun  = refreshedSelected ?? (today);
        _loading      = false;
      });
    } on ApiException catch (e) {
      setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _openRun(String id) async {
    try {
      final run = await ApiService.instance.getPayRun(id);
      setState(() => _selectedRun = run);
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    }
  }

  Future<void> _autoPopulate() async {
    if (_selectedRun == null) return;
    try {
      final added = await ApiService.instance.autoPopulatePayRun(_selectedRun!['id'] as String);
      _snack('$added supplier${added == 1 ? '' : 's'} added from outstanding debt.');
      _openRun(_selectedRun!['id'] as String);
      _load();
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    }
  }

  Future<void> _togglePostpone(Map<String, dynamic> detail) async {
    if (_selectedRun == null) return;
    final newStatus = detail['status'] == 'Postponed' ? 'Included' : 'Postponed';
    try {
      await ApiService.instance.updatePayRunDetail(
        _selectedRun!['id'] as String,
        detail['id'] as String,
        {'status': newStatus},
      );
      _openRun(_selectedRun!['id'] as String);
      _load();
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    }
  }

  Future<void> _editAmount(Map<String, dynamic> detail) async {
    final ctrl = TextEditingController(
        text: (detail['approved_amount'] ?? detail['requested_amount']).toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Edit Amount: ${detail['supplier_name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Requested: ${_kes.format(num.parse(detail['requested_amount'].toString()))}',
                style: const TextStyle(color: AppTheme.pinMuted, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Approved Amount (KES)',
                prefixText: 'KES ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.pinTeal),
            child: const Text('Update'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final amount = double.tryParse(ctrl.text.trim());
    if (amount == null || amount < 0) {
      _snack('Enter a valid amount', error: true);
      return;
    }
    try {
      await ApiService.instance.updatePayRunDetail(
        _selectedRun!['id'] as String,
        detail['id'] as String,
        {'approved_amount': amount},
      );
      _openRun(_selectedRun!['id'] as String);
      _load();
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    }
  }

  Future<void> _removeDetail(Map<String, dynamic> detail) async {
    if (_selectedRun == null) return;
    try {
      await ApiService.instance.removePayRunDetail(
        _selectedRun!['id'] as String,
        detail['id'] as String,
      );
      _openRun(_selectedRun!['id'] as String);
      _load();
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    }
  }

  // Phase 7: Replaced Submit + WhatsApp + Approve with a single Finalize action.
  // The manager now takes full ownership of pay runs without owner sign-off.
  Future<void> _finalize([List<String> toPostponeIds = const []]) async {
    if (_selectedRun == null) return;
    final included = ((_selectedRun!['details'] as List?) ?? [])
        .cast<Map<String, dynamic>>()
        .where((d) => d['status'] == 'Included')
        .toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Finalize & Start Paying?'),
        content: Text(
            'This will approve the run immediately and unlock disburse buttons for '
            '${included.length} supplier${included.length == 1 ? '' : 's'}. '
            'You can begin disbursing right away.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.pinTeal),
            child: const Text('Finalize & Start Paying'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      // Postpone any unchecked suppliers before finalizing
      for (final id in toPostponeIds) {
        await ApiService.instance.updatePayRunDetail(
            _selectedRun!['id'] as String, id, {'status': 'Postponed'});
      }
      await ApiService.instance.finalizePayRun(_selectedRun!['id'] as String);
      _snack('Pay run approved. You can now disburse payments.');
      _load();
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    }
  }

  Future<void> _disburseDetail(Map<String, dynamic> detail) async {
    if (_selectedRun == null) return;
    final runId    = _selectedRun!['id'] as String;
    final detailId = detail['id'] as String;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DisburseDetailDialog(
        supplierName: detail['supplier_name']?.toString() ?? 'Supplier',
        amount: num.tryParse(detail['approved_amount']?.toString() ?? '0') ?? 0,
        staffName: widget.staff.name,
      ),
    );
    if (result == null) return;

    try {
      final res = await ApiService.instance.disbursePayRunDetail(
        runId, detailId,
        disbursedBy: widget.staff.name,
        paymentSourceId: result['payment_source_id'] as String?,
        paymentReference: result['payment_reference'] as String?,
      );
      _snack(res['run_closed'] == true
          ? 'All payments disbursed. Run closed.'
          : '${detail['supplier_name']} payment posted to ledger.');
      _load();
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppTheme.debtRed : AppTheme.paidGreen,
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline_rounded, size: 48, color: AppTheme.debtRed),
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppTheme.debtRed)),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: _load,
              icon: const Icon(Icons.refresh_rounded), label: const Text('Retry')),
        ]),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 800;

        if (isMobile) {
          if (_selectedRun == null) {
            return SizedBox(
              width: double.infinity,
              child: _RunListPanel(
                runs: _allRuns,
                selectedId: null,
                onSelect: _openRun,
                onRefresh: _load,
              ),
            );
          } else {
            return Column(
              children: [
                Container(
                  color: AppTheme.surface,
                  padding: const EdgeInsets.only(top: 8, bottom: 8, left: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded),
                        onPressed: () => setState(() => _selectedRun = null),
                      ),
                      const SizedBox(width: 8),
                      const Text('Back to Pay Runs', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    ],
                  ),
                ),
                Expanded(
                  child: _RunDetailPanel(
                    run: _selectedRun!,
                    staff: widget.staff,
                    onAutoPopulate: _autoPopulate,
                    onEditAmount: _editAmount,
                    onTogglePostpone: _togglePostpone,
                    onRemove: _removeDetail,
                    onFinalize: _finalize,
                    onDisburseDetail: _disburseDetail,
                    onRefresh: () => _openRun(_selectedRun!['id'] as String),
                  ),
                ),
              ],
            );
          }
        }

        return Row(
          children: [
            // ── Left: Run history list ─────────────────────────────
            SizedBox(
              width: 260,
              child: _RunListPanel(
                runs: _allRuns,
                selectedId: _selectedRun?['id'] as String?,
                onSelect: _openRun,
                onRefresh: _load,
              ),
            ),

            // ── Right: Detail panel ────────────────────────────────
            Expanded(
              child: _selectedRun == null
                  ? const Center(child: Text('Select a pay run',
                      style: TextStyle(color: AppTheme.pinMuted)))
                  : _RunDetailPanel(
                      run: _selectedRun!,
                      staff: widget.staff,
                      onAutoPopulate: _autoPopulate,
                      onEditAmount: _editAmount,
                      onTogglePostpone: _togglePostpone,
                      onRemove: _removeDetail,
                      onFinalize: _finalize,
                      onDisburseDetail: _disburseDetail,
                      onRefresh: () => _openRun(_selectedRun!['id'] as String),
                    ),
            ),
          ],
        );
      },
    );
  }
}

// ── Run List Panel ─────────────────────────────────────────────────────────

class _RunListPanel extends StatelessWidget {
  final List<Map<String, dynamic>> runs;
  final String? selectedId;
  final void Function(String) onSelect;
  final VoidCallback onRefresh;

  const _RunListPanel({
    required this.runs,
    required this.selectedId,
    required this.onSelect,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.sidebar,
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 12, 12),
            child: Row(
              children: [
                const Icon(Icons.payments_rounded, color: AppTheme.pinTeal, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Pay Runs',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: AppTheme.pinMuted, size: 18),
                  onPressed: onRefresh,
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF263238), height: 1),
          Expanded(
            child: runs.isEmpty
                ? const Center(
                    child: Text('No pay runs yet',
                        style: TextStyle(color: AppTheme.pinMuted, fontSize: 12)))
                : ListView.builder(
                    itemCount: runs.length,
                    padding: const EdgeInsets.only(top: 4),
                    itemBuilder: (_, i) {
                      final r = runs[i];
                      final isSelected = r['id'] == selectedId;
                      final status = r['status'] as String;
                      return _RunTile(
                        run: r,
                        selected: isSelected,
                        onTap: () => onSelect(r['id'] as String),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _RunTile extends StatelessWidget {
  final Map<String, dynamic> run;
  final bool selected;
  final VoidCallback onTap;
  const _RunTile({required this.run, required this.selected, required this.onTap});

  static const _statusColors = {
    'Draft':     Color(0xFF90A4AE),
    'Submitted': Color(0xFFFFA000),
    'Approved':  Color(0xFF66BB6A),
    'Disbursed': Color(0xFF26A69A),
  };

  @override
  Widget build(BuildContext context) {
    final status = run['status'] as String;
    final color  = _statusColors[status] ?? Colors.grey;
    final total  = num.tryParse(run['total_approved']?.toString() ?? '0') ?? 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: selected ? AppTheme.pinTeal.withOpacity(0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        dense: true,
        onTap: onTap,
        title: Text(run['run_date']?.toString() ?? '—',
            style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text(_kes.format(total),
            style: const TextStyle(color: AppTheme.pinMuted, fontSize: 11)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(status,
              style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

// ── Run Detail Panel ───────────────────────────────────────────────────────

class _RunDetailPanel extends StatefulWidget {
  final Map<String, dynamic> run;
  final Staff staff;
  final VoidCallback onAutoPopulate;
  final void Function(Map<String, dynamic>) onEditAmount;
  final void Function(Map<String, dynamic>) onTogglePostpone;
  final void Function(Map<String, dynamic>) onRemove;
  /// Phase 7: single manager-led action — transitions Draft → Approved immediately.
  final Future<void> Function(List<String> toPostponeIds) onFinalize;
  final Future<void> Function(Map<String, dynamic> detail) onDisburseDetail;
  final VoidCallback onRefresh;

  const _RunDetailPanel({
    required this.run,
    required this.staff,
    required this.onAutoPopulate,
    required this.onEditAmount,
    required this.onTogglePostpone,
    required this.onRemove,
    required this.onFinalize,
    required this.onDisburseDetail,
    required this.onRefresh,
  });

  @override
  State<_RunDetailPanel> createState() => _RunDetailPanelState();
}

class _RunDetailPanelState extends State<_RunDetailPanel> {
  Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _initSelection();
  }

  @override
  void didUpdateWidget(_RunDetailPanel old) {
    super.didUpdateWidget(old);
    // Re-seed checkboxes when run or its details change
    if (old.run['id'] != widget.run['id']) {
      _initSelection();
    } else {
      final oldLen = (old.run['details'] as List?)?.length ?? 0;
      final newLen = (widget.run['details'] as List?)?.length ?? 0;
      if (oldLen != newLen) _initSelection();
    }
  }

  void _initSelection() {
    final details = (widget.run['details'] as List?)
        ?.map((e) => e as Map<String, dynamic>)
        .toList() ?? [];
    final included = details.where((d) => d['status'] == 'Included').toList();
    setState(() {
      _selectedIds = included.map((d) => d['id'] as String).toSet();
    });
  }

  Future<void> _handleFinalize(List<Map<String, dynamic>> included) async {
    final allIds = included.map((d) => d['id'] as String).toSet();
    final toPostpone = allIds.difference(_selectedIds).toList();
    await widget.onFinalize(toPostpone);
  }

  @override
  Widget build(BuildContext context) {
    final status      = widget.run['status'] as String;
    final isDraft     = status == 'Draft';
    final isSubmit    = status == 'Submitted';
    final isApproved  = status == 'Approved';
    final isDisbursed = status == 'Disbursed';
    final details = (widget.run['details'] as List?)
        ?.map((e) => e as Map<String, dynamic>)
        .toList() ?? [];
    final included  = details.where((d) => d['status'] == 'Included').toList();
    final postponed = details.where((d) => d['status'] == 'Postponed').toList();
    final totalApproved = included.fold<double>(0, (s, d) =>
        s + (num.tryParse(d['approved_amount']?.toString() ?? '0') ?? 0).toDouble());

    return Column(
      children: [
        // ── Header ─────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 20, 14),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: title + status badge
              Row(children: [
                Text('Pay Run: ${widget.run['run_date']}',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(width: 12),
                _StatusBadge(status: status),
              ]),
              const SizedBox(height: 4),
              Text('${included.length} suppliers · ${_kes.format(totalApproved)}',
                  style: const TextStyle(color: AppTheme.pinMuted, fontSize: 13)),
              // Row 2: action buttons (wrap so they never overflow)
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  // Phase 7: Draft → Approved in one step, no owner WhatsApp sign-off.
                  if (isDraft) ...[
                    OutlinedButton.icon(
                      onPressed: widget.onAutoPopulate,
                      icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                      label: const Text('Auto-Populate'),
                    ),
                    FilledButton.icon(
                      onPressed: included.isEmpty
                          ? null
                          : () => _handleFinalize(included),
                      icon: const Icon(Icons.rocket_launch_rounded, size: 16),
                      label: Text(_selectedIds.length < included.length
                          ? 'Finalize ${_selectedIds.length}/${included.length} & Start Paying'
                          : 'Finalize & Start Paying'),
                      style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.pinTeal),
                    ),
                  ],
                  // Legacy: runs already in Submitted state can still be approved manually.
                  if (isSubmit)
                    FilledButton.icon(
                      onPressed: () async {
                        try {
                          await ApiService.instance.approvePayRun(
                              widget.run['id'] as String);
                          widget.onRefresh();
                        } catch (_) {}
                      },
                      icon: const Icon(Icons.check_circle_rounded, size: 16),
                      label: const Text('Mark Approved'),
                      style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.paidGreen),
                    ),
                  if (isApproved) (() {
                    final paid = details.where((d) => d['status'] == 'Paid').length;
                    return Chip(
                      avatar: const Icon(Icons.account_balance_rounded,
                          color: Colors.white, size: 14),
                      label: Text(
                        paid == included.length
                            ? 'All paid — closing…'
                            : 'Disburse per row below ($paid/${included.length} paid)',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      backgroundColor: paid == included.length
                          ? AppTheme.paidGreen
                          : AppTheme.debtRed,
                    );
                  })(),
                  if (isDisbursed)
                    const Chip(
                      label: Text('Payments disbursed ✓',
                          style: TextStyle(color: Colors.white)),
                      backgroundColor: AppTheme.paidGreen,
                    ),
                ],
              ),
            ],
          ),
        ),

        // ── Supplier table ─────────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (included.isNotEmpty) ...[
                  _SectionHeader(
                      icon: Icons.check_circle_outline_rounded,
                      label: isDraft
                          ? 'To Pay (${included.length}) — tick to include'
                          : 'To Pay (${included.length})',
                      color: AppTheme.paidGreen),
                  const SizedBox(height: 12),
                  // Group included suppliers by payment_day with optional checkboxes
                  ..._buildDayGroups(
                    included,
                    isDraft || isSubmit,          // canEdit
                    onEditAmount: widget.onEditAmount,
                    onTogglePostpone: widget.onTogglePostpone,
                    onRemove: widget.onRemove,
                    selectedIds: isDraft ? _selectedIds : null,
                    onToggleSelect: isDraft
                        ? (id, val) => setState(() {
                              if (val) {
                                _selectedIds = {..._selectedIds, id};
                              } else {
                                _selectedIds = _selectedIds.difference({id});
                              }
                            })
                        : null,
                    onDisburseDetail: isApproved ? widget.onDisburseDetail : null,
                  ),
                  const SizedBox(height: 24),
                ],
                if (postponed.isNotEmpty) ...[
                  _SectionHeader(
                      icon: Icons.schedule_rounded,
                      label: 'Postponed (${postponed.length})',
                      color: Colors.orange),
                  const SizedBox(height: 8),
                  _SupplierTable(
                    details: postponed,
                    canEdit: isDraft,
                    onEditAmount: widget.onEditAmount,
                    onTogglePostpone: widget.onTogglePostpone,
                    onRemove: widget.onRemove,
                  ),
                ],
                if (included.isEmpty && postponed.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(48),
                      child: Column(children: [
                        Icon(Icons.inbox_rounded,
                            size: 56, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text('No suppliers added yet.',
                            style: TextStyle(color: Colors.grey.shade500)),
                        if (isDraft) ...[
                          const SizedBox(height: 8),
                          Text(
                              'Tap "Auto-Populate" to add suppliers with outstanding debt.',
                              style: TextStyle(
                                  color: Colors.grey.shade400, fontSize: 12)),
                        ],
                      ]),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Day-grouping helper ────────────────────────────────────────────────────

const _kDayOrder = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday',
  'Friday', 'Saturday', 'Sunday', 'Daily',
];

List<Widget> _buildDayGroups(
  List<Map<String, dynamic>> details,
  bool canEdit, {
  required void Function(Map<String, dynamic>) onEditAmount,
  required void Function(Map<String, dynamic>) onTogglePostpone,
  required void Function(Map<String, dynamic>) onRemove,
  Set<String>? selectedIds,
  void Function(String id, bool selected)? onToggleSelect,
  Future<void> Function(Map<String, dynamic>)? onDisburseDetail,
}) {
  // Group by payment_day; null/empty → 'Unscheduled'
  final Map<String, List<Map<String, dynamic>>> groups = {};
  for (final d in details) {
    final day = (d['payment_day'] as String?)?.trim();
    final key = (day != null && day.isNotEmpty) ? day : 'Unscheduled';
    groups.putIfAbsent(key, () => []).add(d);
  }

  // Sort groups: known days first (Mon-Sun/Daily), then Unscheduled
  final sortedKeys = groups.keys.toList()
    ..sort((a, b) {
      final ia = _kDayOrder.indexOf(a);
      final ib = _kDayOrder.indexOf(b);
      if (ia == -1 && ib == -1) return a.compareTo(b);
      if (ia == -1) return 1;
      if (ib == -1) return -1;
      return ia.compareTo(ib);
    });

  final widgets = <Widget>[];
  for (final key in sortedKeys) {
    final group = groups[key]!;
    final groupTotal = group.fold<double>(
        0, (s, d) => s + (num.tryParse(d['approved_amount']?.toString() ?? '0') ?? 0).toDouble());

    widgets.add(
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF90CAF9)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.calendar_today_rounded,
                  size: 13, color: Color(0xFF1565C0)),
              const SizedBox(width: 5),
              Text(key,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1565C0))),
              const SizedBox(width: 6),
              Text('(${group.length})',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF1565C0))),
            ]),
          ),
          const SizedBox(width: 10),
          Text(_kes.format(groupTotal),
              style: const TextStyle(fontSize: 12, color: AppTheme.pinMuted)),
        ]),
      ),
    );
    widgets.add(
      _SupplierTable(
        details: group,
        canEdit: canEdit,
        onEditAmount: onEditAmount,
        onTogglePostpone: onTogglePostpone,
        onRemove: onRemove,
        selectedIds: selectedIds,
        onToggleSelect: onToggleSelect,
        onDisburseDetail: onDisburseDetail,
      ),
    );
    widgets.add(const SizedBox(height: 16));
  }
  return widgets;
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  static const _colors = {
    'Draft':     Color(0xFF90A4AE),
    'Submitted': Color(0xFFFFA000),
    'Approved':  Color(0xFF66BB6A),
    'Disbursed': Color(0xFF26A69A),
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[status] ?? Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color),
      ),
      child: Text(status,
          style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w700)),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _SectionHeader({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w700, fontSize: 14)),
      ]);
}

class _SupplierTable extends StatelessWidget {
  final List<Map<String, dynamic>> details;
  final bool canEdit;
  final void Function(Map<String, dynamic>) onEditAmount;
  final void Function(Map<String, dynamic>) onTogglePostpone;
  final void Function(Map<String, dynamic>) onRemove;
  // Optional checkbox support (Draft mode selection)
  final Set<String>? selectedIds;
  final void Function(String id, bool selected)? onToggleSelect;
  // Optional per-row disburse (Approved mode)
  final Future<void> Function(Map<String, dynamic>)? onDisburseDetail;

  const _SupplierTable({
    required this.details,
    required this.canEdit,
    required this.onEditAmount,
    required this.onTogglePostpone,
    required this.onRemove,
    this.selectedIds,
    this.onToggleSelect,
    this.onDisburseDetail,
  });

  bool get _showCheckboxes => selectedIds != null;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Table(
        border: TableBorder.all(color: const Color(0xFFE0E0E0),
            borderRadius: BorderRadius.circular(10)),
        columnWidths: _showCheckboxes
            ? const {
                0: FixedColumnWidth(46),
                1: FlexColumnWidth(2.5),
                2: FlexColumnWidth(1.8),
                3: FlexColumnWidth(1.8),
                4: FlexColumnWidth(1.5),
              }
            : const {
                0: FlexColumnWidth(2.5),
                1: FlexColumnWidth(1.8),
                2: FlexColumnWidth(1.8),
                3: FlexColumnWidth(1.5),
              },
        children: [
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFF37474F)),
            children: [
              if (_showCheckboxes) _TH(''),
              _TH('Supplier'),
              _TH('Requested'),
              _TH('Approved'),
              _TH('Actions'),
            ],
          ),
          ...details.asMap().entries.map((e) {
            final i = e.key;
            final d = e.value;
            final id = d['id'] as String;
            final isPostponed = d['status'] == 'Postponed';
            final isChecked   = selectedIds?.contains(id) ?? false;
            final requested = num.tryParse(d['requested_amount']?.toString() ?? '0') ?? 0;
            final approved  = num.tryParse(d['approved_amount']?.toString()  ?? '0') ?? 0;
            final isPartial = approved < requested;

            return TableRow(
              decoration: BoxDecoration(
                color: _showCheckboxes && !isChecked
                    ? Colors.grey.shade100
                    : isPostponed
                        ? Colors.grey.shade50
                        : (i.isEven ? Colors.white : const Color(0xFFFAFAFA)),
              ),
              children: [
                // ── Checkbox column (Draft only) ───────────────
                if (_showCheckboxes)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Checkbox(
                      value: isChecked,
                      onChanged: (v) => onToggleSelect?.call(id, v ?? false),
                      activeColor: AppTheme.pinTeal,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                // ── Supplier name ──────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Text(d['supplier_name']?.toString() ?? '—',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: (_showCheckboxes && !isChecked) || isPostponed
                              ? Colors.grey
                              : Colors.black87,
                          decoration: isPostponed ? TextDecoration.lineThrough : null)),
                ),
                // ── Requested ─────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Text(_kes.format(requested),
                      style: const TextStyle(fontSize: 13, color: AppTheme.pinMuted)),
                ),
                // ── Approved ──────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_kes.format(approved),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isPostponed || (_showCheckboxes && !isChecked)
                                  ? Colors.grey
                                  : (isPartial ? Colors.orange : AppTheme.paidGreen))),
                      if (isPartial && !isPostponed) ...[
                        const SizedBox(width: 4),
                        const Tooltip(
                          message: 'Partial payment',
                          child: Icon(Icons.info_outline_rounded,
                              size: 13, color: Colors.orange),
                        ),
                      ],
                    ],
                  ),
                ),
                // ── Actions ───────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: canEdit
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_rounded, size: 16),
                              color: Colors.blueGrey,
                              onPressed: () => onEditAmount(d),
                              tooltip: 'Edit amount',
                            ),
                            IconButton(
                              icon: Icon(
                                isPostponed
                                    ? Icons.undo_rounded
                                    : Icons.schedule_rounded,
                                size: 16,
                              ),
                              color: isPostponed ? AppTheme.paidGreen : Colors.orange,
                              onPressed: () => onTogglePostpone(d),
                              tooltip: isPostponed ? 'Re-include' : 'Postpone',
                            ),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline_rounded,
                                  size: 16),
                              color: AppTheme.debtRed,
                              onPressed: () => onRemove(d),
                              tooltip: 'Remove',
                            ),
                          ],
                        )
                      : onDisburseDetail != null
                          ? (d['status'] == 'Paid'
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8),
                                  child: Icon(Icons.check_circle_rounded,
                                      color: AppTheme.paidGreen, size: 20),
                                )
                              : OutlinedButton.icon(
                                  onPressed: () => onDisburseDetail!(d),
                                  icon: const Icon(Icons.payments_rounded, size: 14),
                                  label: const Text('Pay', style: TextStyle(fontSize: 12)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.debtRed,
                                    side: const BorderSide(color: AppTheme.debtRed),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ))
                          : const SizedBox(),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

Widget _TH(String text) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
    );

// ── Disburse Detail Dialog ────────────────────────────────────────────────────
// Shown when tapping "Pay" on a supplier row in an Approved pay run.
// Returns { payment_source_id?, payment_reference? } or null if cancelled.

class _DisburseDetailDialog extends StatefulWidget {
  final String supplierName;
  final num amount;
  final String staffName;

  const _DisburseDetailDialog({
    required this.supplierName,
    required this.amount,
    required this.staffName,
  });

  @override
  State<_DisburseDetailDialog> createState() => _DisburseDetailDialogState();
}

class _DisburseDetailDialogState extends State<_DisburseDetailDialog> {
  List<Map<String, dynamic>> _internalSuppliers = [];
  String? _selectedSourceId;
  final _refCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadInternalSuppliers();
  }

  @override
  void dispose() {
    _refCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInternalSuppliers() async {
    try {
      final list = await ApiService.instance.getInternalSuppliers();
      setState(() { _internalSuppliers = list; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _confirm() {
    setState(() => _saving = true);
    Navigator.of(context).pop({
      'payment_source_id': _selectedSourceId,
      'payment_reference': _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.payments_rounded, color: AppTheme.debtRed),
        const SizedBox(width: 10),
        Expanded(child: Text('Pay ${widget.supplierName}',
            style: const TextStyle(fontSize: 16))),
      ]),
      content: SizedBox(
        width: 400,
        child: _loading
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Amount: ${_kes.format(widget.amount)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 16),

                  // Payment source
                  DropdownButtonFormField<String?>(
                    value: _selectedSourceId,
                    decoration: const InputDecoration(
                      labelText: 'Payment Source',
                      hintText: 'How is this being paid?',
                      prefixIcon: Icon(Icons.account_balance_wallet_rounded),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Bank Transfer / Direct')),
                      ..._internalSuppliers.map((s) => DropdownMenuItem(
                          value: s['id'] as String,
                          child: Text('Cash via ${s['name']}'))),
                    ],
                    onChanged: (v) => setState(() => _selectedSourceId = v),
                  ),
                  const SizedBox(height: 12),

                  // MPesa / reference
                  TextField(
                    controller: _refCtrl,
                    decoration: const InputDecoration(
                      labelText: 'MPesa / Payment Reference (optional)',
                      hintText: 'e.g. QHX7Y3Z2AB',
                      prefixIcon: Icon(Icons.receipt_rounded),
                      border: OutlineInputBorder(),
                    ),
                  ),

                  if (_selectedSourceId != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFF8F00)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.info_outline_rounded,
                            size: 16, color: Color(0xFFFF8F00)),
                        const SizedBox(width: 8),
                        const Expanded(child: Text(
                          'A double-entry will be posted: PAYMENT to supplier + PURCHASE to the selected manager cash account.',
                          style: TextStyle(fontSize: 11, color: Color(0xFF6D4C41)),
                        )),
                      ]),
                    ),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: _loading || _saving ? null : _confirm,
          icon: const Icon(Icons.check_rounded, size: 16),
          label: const Text('Confirm Payment'),
          style: FilledButton.styleFrom(backgroundColor: AppTheme.debtRed),
        ),
      ],
    );
  }
}
