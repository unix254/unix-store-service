import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/theme.dart';
import '../../models/staff.dart';
import '../../models/requisition.dart';
import '../../models/supplier.dart';
import '../../services/api.dart';
import 'requisition_timeline_sheet.dart';

final _timeFmt = DateFormat('HH:mm');
final _dateFmt = DateFormat('dd MMM');

/// Store Desktop – Requisition approval queue with 30-second auto-poll.
class RequisitionApprovalScreen extends StatefulWidget {
  final Staff staff;
  const RequisitionApprovalScreen({super.key, required this.staff});

  @override
  State<RequisitionApprovalScreen> createState() =>
      _RequisitionApprovalScreenState();
}

class _RequisitionApprovalScreenState
    extends State<RequisitionApprovalScreen> {
  List<Requisition> _all = [];
  String _filter = 'Pending'; // Pending | All | Issued | Rejected
  bool _loading = true;
  DateTime? _lastRefresh;
  Timer? _pollTimer;
  int _pollCountdown = 30;
  Timer? _countdownTimer;

  // KPI: total KES value of all issued items in today's 7 AM business day.
  double _issuedCostToday = 0.0;
  int _issuedCountToday = 0;

  static const _filters = ['Pending', 'All', 'Issued', 'Rejected'];

  @override
  void initState() {
    super.initState();
    _loadRequisitions();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    // Reduced from 30 s → 30 min: requisitions are infrequent events.
    _pollTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      if (mounted) _backgroundPoll();
    });
    // Countdown ticks every minute — shows minutes remaining until next auto-refresh.
    _countdownTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() {
        _pollCountdown = 30 - (DateTime.now().minute % 30);
      });
    });
  }

  // User-triggered refresh: shows loading spinner and error snackbars.
  Future<void> _loadRequisitions() async {
    setState(() => _loading = true);
    try {
      await _fetchAndApply();
    } catch (e) {
      setState(() => _loading = false);
      _showError(e.toString());
    }
  }

  // Background timer refresh: silent on network errors so a brief dropout
  // doesn't disrupt the UI with a red error banner.
  Future<void> _backgroundPoll() async {
    try {
      await _fetchAndApply(background: true);
    } catch (_) {
      // Silently swallow network/socket errors from background polling.
    }
  }

  Future<void> _fetchAndApply({bool background = false}) async {
    final results = await Future.wait([
      ApiService.instance.getRequisitions(),
      ApiService.instance.getIssuedCostToday(),
    ]);
    final list = results[0] as List<Requisition>;
    final cost = results[1] as Map<String, dynamic>;
    if (!mounted) return;
    setState(() {
      _all = list;
      _issuedCostToday  = double.tryParse(
              cost['total_cost_kes']?.toString() ?? '0') ?? 0.0;
      _issuedCountToday = int.tryParse(
              cost['total_issues']?.toString() ?? '0') ?? 0;
      _loading       = false;
      _lastRefresh   = DateTime.now();
      _pollCountdown = 30;
    });
  }

  List<Requisition> get _filtered {
    if (_filter == 'All') return _all;
    return _all.where((r) => r.status == _filter).toList();
  }

  int get _pendingCount => _all.where((r) => r.isPending).length;

  // Phase 8 / M14: Issue dialog — branches on requisition type.
  Future<void> _issue(Requisition req) async {
    // ── New Item Request: custom add-to-inventory flow ──────────
    if (req.isNewItemRequest) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => _AddNewItemFromRequestDialog(
          req:       req,
          staffName: widget.staff.name,
        ),
      );
      if (ok == true) {
        _showSuccess('Item added to inventory and request approved.');
        _loadRequisitions();
      }
      return;
    }

    // ── Standard requisition: quantity-adjust issue dialog ──────
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _IssueDialog(req: req),
    );
    if (result == null) return;

    try {
      await ApiService.instance.issueRequisition(
        req.id,
        widget.staff.name,
        issuedQuantity: result['qty'] as double?,
        issueNotes:     result['notes'] as String?,
      );
      _showSuccess('Issued: ${req.itemName}');
      _loadRequisitions();
    } on ApiException catch (e) {
      _showError(e.message);
    }
  }

  // Phase 8: Reject dialog — lets storekeeper provide a reason.
  Future<void> _reject(Requisition req) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _RejectDialog(itemName: req.itemName),
    );
    if (reason == null) return; // cancelled
    try {
      await ApiService.instance.rejectRequisition(
        req.id,
        reason: reason,
        rejectedBy: widget.staff.name,
      );
      _showSuccess('Rejected: ${req.itemName}');
      _loadRequisitions();
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _openTimeline(Requisition req) async {
    await showRequisitionTimeline(
      context,
      req:             req,
      currentUserName: widget.staff.name,
    );
    // Refresh counts after the sheet closes (a comment may have been added).
    _loadRequisitions();
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppTheme.debtRed));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppTheme.paidGreen));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Top Bar ─────────────────────────────────────────
        _TopBar(
          pendingCount:   _pendingCount,
          lastRefresh:    _lastRefresh,
          pollCountdown:  _pollCountdown,
          onRefresh:      _loadRequisitions,
        ),
        // ── KPI Card ─────────────────────────────────────────
        if (!_loading)
          _IssuedCostKpiCard(
            totalCostKes:  _issuedCostToday,
            issuedCount:   _issuedCountToday,
          ),

        // ── Filter Tabs ──────────────────────────────────────
        _FilterTabs(
          filters:  _filters,
          selected: _filter,
          counts:   {
            'Pending':  _all.where((r) => r.status == 'Pending').length,
            'All':      _all.length,
            'Issued':   _all.where((r) => r.status == 'Issued').length,
            'Rejected': _all.where((r) => r.status == 'Rejected').length,
          },
          onSelect: (f) => setState(() => _filter = f),
        ),
        const Divider(height: 1),
        // ── List ─────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _filtered.isEmpty
                  ? _EmptyState(filter: _filter)
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _RequisitionCard(
                        req:        _filtered[i],
                        onIssue:    _filtered[i].isPending
                            ? () => _issue(_filtered[i])
                            : null,
                        onReject:   _filtered[i].isPending
                            ? () => _reject(_filtered[i])
                            : null,
                        onTimeline: () => _openTimeline(_filtered[i]),
                      ),
                    ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Issued Cost KPI Card
// ─────────────────────────────────────────────────────────────────────────────

class _IssuedCostKpiCard extends StatelessWidget {
  final double totalCostKes;
  final int issuedCount;
  const _IssuedCostKpiCard({
    required this.totalCostKes,
    required this.issuedCount,
  });

  @override
  Widget build(BuildContext context) {
    final kes = NumberFormat.currency(
        locale: 'en_KE', symbol: 'KES ', decimalDigits: 0);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4A148C), Color(0xFF7B1FA2)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7B1FA2).withOpacity(0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.moving_rounded, color: Colors.white70, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total Cost Issued Today',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(
                  kes.format(totalCostKes),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$issuedCount issues',
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              ),
              const Text('7 AM business day',
                  style: TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top Bar
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final int pendingCount;
  final DateTime? lastRefresh;
  final int pollCountdown;
  final VoidCallback onRefresh;

  const _TopBar({
    required this.pendingCount,
    required this.lastRefresh,
    required this.pollCountdown,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(24, 16, 16, 12),
      child: Row(
        children: [
          const Text('Requisitions',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(width: 14),
          // Pending badge
          if (pendingCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.debtRed,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$pendingCount PENDING',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800),
              ),
            ),
          const Spacer(),
          // Poll countdown
          Row(
            children: [
              _PollIndicator(countdown: pollCountdown),
              const SizedBox(width: 6),
              Text(
                lastRefresh != null
                    ? 'Refreshed ${DateFormat('HH:mm:ss').format(lastRefresh!)}'
                    : 'Loading…',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: onRefresh,
                tooltip: 'Refresh now',
                color: AppTheme.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Circular countdown ring
class _PollIndicator extends StatelessWidget {
  final int countdown;
  const _PollIndicator({required this.countdown});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: countdown / 30,
            strokeWidth: 3,
            backgroundColor: Colors.grey.shade200,
            color: AppTheme.primary,
          ),
          Text(
            '${countdown}m',
            style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter Tabs
// ─────────────────────────────────────────────────────────────────────────────

class _FilterTabs extends StatelessWidget {
  final List<String> filters;
  final String selected;
  final Map<String, int> counts;
  final void Function(String) onSelect;

  const _FilterTabs({
    required this.filters,
    required this.selected,
    required this.counts,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        children: filters.map((f) {
          final isSelected = f == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: FilterChip(
              label: Text('$f  ${counts[f] ?? 0}'),
              selected: isSelected,
              onSelected: (_) => onSelect(f),
              selectedColor: AppTheme.primary.withOpacity(0.15),
              checkmarkColor: AppTheme.primary,
              labelStyle: TextStyle(
                color: isSelected ? AppTheme.primary : Colors.grey.shade600,
                fontWeight:
                    isSelected ? FontWeight.w700 : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Requisition Card
// ─────────────────────────────────────────────────────────────────────────────

class _RequisitionCard extends StatelessWidget {
  final Requisition req;
  final VoidCallback? onIssue;
  final VoidCallback? onReject;
  final VoidCallback? onTimeline;

  const _RequisitionCard({
    required this.req,
    this.onIssue,
    this.onReject,
    this.onTimeline,
  });

  @override
  Widget build(BuildContext context) {
    final isPending = req.isPending;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isPending
              ? AppTheme.secondary.withOpacity(0.5)
              : Colors.grey.shade200,
          width: isPending ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Purpose icon block ─────────────────────────────
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: req.isNewItemRequest
                    ? const Color(0xFF00796B).withOpacity(0.12)
                    : req.isSales
                        ? AppTheme.pinTeal.withOpacity(0.12)
                        : AppTheme.secondary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  req.isNewItemRequest ? '🆕' : req.isSales ? '📦' : '🍽️',
                  style: const TextStyle(fontSize: 26),
                ),
              ),
            ),
            const SizedBox(width: 16),

            // ── Details ────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Item + Qty
                  Row(children: [
                    if (req.isNewItemRequest) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00796B),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('NEW ITEM',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5)),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87),
                          children: [
                            TextSpan(
                              text: req.isNewItemRequest
                                  ? (req.newItemName ?? 'New Item')
                                  : req.itemName,
                            ),
                            TextSpan(
                              text:
                                  '  ×  ${req.quantity.toStringAsFixed(req.quantity % 1 == 0 ? 0 : 1)} '
                                  '${req.unitOfMeasure ?? req.itemUom ?? ''}',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  // Meta row
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _MetaChip(
                        icon: Icons.person_rounded,
                        label: req.requestedBy,
                      ),
                      _MetaChip(
                        icon: Icons.access_time_rounded,
                        label: _formatTime(req.requestedAt),
                      ),
                      if (req.requesterLocation != null &&
                          req.requesterLocation!.isNotEmpty)
                        _MetaChip(
                          icon: Icons.store_mall_directory_rounded,
                          label: req.requesterLocation!,
                          color: AppTheme.pinTeal,
                        ),
                      _PurposeBadge(purpose: req.purpose),
                      if (req.notes != null && req.notes!.isNotEmpty)
                        _MetaChip(
                          icon: Icons.notes_rounded,
                          label: req.notes!,
                        ),
                    ],
                  ),
                  // ── Stock Balance Strip ────────────────────────
                  // Only shown for standard requests (not new-item) when
                  // we have store qty. Gives the storekeeper the key
                  // numbers needed to approve without opening inventory.
                  if (!req.isNewItemRequest && req.storeQty != null) ...[
                    const SizedBox(height: 8),
                    _StockBalanceStrip(req: req),
                  ],
                  // Issued / adjusted info
                  if (req.isIssued && req.issuedBy != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.paidGreen.withOpacity(0.85)),
                          children: [
                            TextSpan(text: 'Issued by ${req.issuedBy}'),
                            if (req.issuedAt != null)
                              TextSpan(text: ' at ${_formatTime(req.issuedAt!)}'),
                            // Show adjusted quantity if it differs from requested
                            if (req.issuedQuantity != null &&
                                req.issuedQuantity != req.quantity)
                              TextSpan(
                                text: '  ·  Adjusted: '
                                    '${req.issuedQuantity!.toStringAsFixed(req.issuedQuantity! % 1 == 0 ? 0 : 1)}'
                                    ' ${req.unitOfMeasure ?? req.itemUom ?? ''}'
                                    ' (requested ${req.quantity.toStringAsFixed(req.quantity % 1 == 0 ? 0 : 1)})',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (req.issueNotes != null && req.issueNotes!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.notes_rounded,
                              size: 13, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(req.issueNotes!,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600,
                                  fontStyle: FontStyle.italic)),
                        ]),
                      ),
                  ],
                  // Rejection reason
                  if (req.isRejected && req.issueNotes != null && req.issueNotes!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.info_outline_rounded,
                            size: 13, color: AppTheme.debtRed.withOpacity(0.7)),
                        const SizedBox(width: 4),
                        Text('Reason: ${req.issueNotes!}',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.debtRed.withOpacity(0.8),
                                fontStyle: FontStyle.italic)),
                      ]),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),

            // ── Status / Actions ────────────────────────────────
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _StatusBadge(status: req.status),
                const SizedBox(height: 8),
                // Chat / timeline button with activity count badge
                InkWell(
                  onTap: onTimeline,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 15,
                          color: req.hasActivity
                              ? AppTheme.primary
                              : Colors.grey.shade400,
                        ),
                        if (req.timelineCount > 0) ...[
                          const SizedBox(width: 4),
                          Text(
                            '${req.timelineCount}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ],
        ),
        if (isPending) ...[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.debtRed,
                      side: const BorderSide(color: AppTheme.debtRed),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Reject',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  ElevatedButton.icon(
                    onPressed: onIssue,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: req.isNewItemRequest
                            ? const Color(0xFF00796B)
                            : AppTheme.paidGreen,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    icon: Icon(
                        req.isNewItemRequest
                            ? Icons.add_circle_rounded
                            : Icons.check_rounded,
                        size: 18, color: Colors.white),
                    label: Text(
                        req.isNewItemRequest ? 'Approve' : 'Issue',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTime(String raw) {
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return '–';
    final now = DateTime.now();
    if (dt.day == now.day) return _timeFmt.format(dt);
    return '${_dateFmt.format(dt)} ${_timeFmt.format(dt)}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    switch (status) {
      case 'Issued':
        color = AppTheme.paidGreen;
        icon = Icons.check_circle_rounded;
        break;
      case 'Rejected':
        color = AppTheme.debtRed;
        icon = Icons.cancel_rounded;
        break;
      default:
        color = AppTheme.secondary;
        icon = Icons.hourglass_top_rounded;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(status.toUpperCase(),
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }
}

class _PurposeBadge extends StatelessWidget {
  final String purpose;
  const _PurposeBadge({required this.purpose});

  @override
  Widget build(BuildContext context) {
    final isSales = purpose == 'Sales';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(isSales ? '📦' : '🍽️', style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 4),
        Text(
          purpose.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isSales ? AppTheme.pinTeal : AppTheme.secondary,
          ),
        ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  /// Optional accent color — when set the icon and text use this color instead of grey.
  final Color? color;
  const _MetaChip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.grey.shade500;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: c),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
              fontSize: 12,
              color: color != null ? c : Colors.grey.shade600,
              fontWeight: color != null ? FontWeight.w600 : FontWeight.w400,
            )),
      ],
    );
  }
}

// ── Stock Balance Strip ────────────────────────────────────────────────────────
// Shows current store inventory and station closing stock for a requisition.
// Gives the storekeeper at-a-glance signal before approving.
class _StockBalanceStrip extends StatelessWidget {
  final Requisition req;
  const _StockBalanceStrip({required this.req});

  String _fmt(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final uom        = req.unitOfMeasure ?? req.itemUom ?? '';
    final storeQty   = req.storeQty!;
    final storeOk    = storeQty >= req.quantity;
    final storeColor = storeOk ? AppTheme.paidGreen : AppTheme.debtRed;

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        // Store balance pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: storeColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: storeColor.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_2_rounded, size: 12, color: storeColor),
              const SizedBox(width: 5),
              Text('Store: ',
                  style: TextStyle(
                      fontSize: 11, color: storeColor,
                      fontWeight: FontWeight.w600)),
              Text('${_fmt(storeQty)} $uom',
                  style: TextStyle(
                      fontSize: 11, color: storeColor,
                      fontWeight: FontWeight.w800)),
              if (!storeOk) ...[
                const SizedBox(width: 4),
                Icon(Icons.warning_rounded, size: 11, color: storeColor),
              ],
            ],
          ),
        ),
        // Station balance pill (only when station stock data exists)
        if (req.stationQty != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.pinTeal.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.pinTeal.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.store_mall_directory_rounded,
                    size: 12, color: AppTheme.pinTeal),
                const SizedBox(width: 5),
                Text('${req.requesterLocation ?? 'Station'}: ',
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.pinTeal,
                        fontWeight: FontWeight.w600)),
                Text('${_fmt(req.stationQty!)} $uom',
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.pinTeal,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String filter;
  const _EmptyState({required this.filter});

  @override
  Widget build(BuildContext context) {
    final isPending = filter == 'Pending';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isPending
                ? Icons.check_circle_outline_rounded
                : Icons.assignment_outlined,
            size: 72,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            isPending
                ? 'No pending requests – all clear! ✅'
                : 'No $filter requisitions found',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Phase 8 Dialogs
// ─────────────────────────────────────────────────────────────────────────────

/// Issue dialog: allows the storekeeper to adjust the issued quantity
/// and optionally add a note before confirming.
class _IssueDialog extends StatefulWidget {
  final Requisition req;
  const _IssueDialog({required this.req});

  @override
  State<_IssueDialog> createState() => _IssueDialogState();
}

class _IssueDialogState extends State<_IssueDialog> {
  late final TextEditingController _qtyCtrl;
  final _notesCtrl = TextEditingController();
  final _formKey   = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final qty = widget.req.quantity;
    _qtyCtrl = TextEditingController(
      text: qty.toStringAsFixed(qty % 1 == 0 ? 0 : 1),
    );
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final req    = widget.req;
    final uom    = req.unitOfMeasure ?? req.itemUom ?? '';
    final reqQty = req.quantity;

    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.check_circle_rounded, color: AppTheme.paidGreen),
        const SizedBox(width: 10),
        Expanded(child: Text('Issue: ${req.itemName}',
            overflow: TextOverflow.ellipsis)),
      ]),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Requested: ${reqQty.toStringAsFixed(reqQty % 1 == 0 ? 0 : 1)} $uom',
                style: const TextStyle(color: AppTheme.pinMuted, fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _qtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Issued Quantity ($uom)',
                  prefixIcon: const Icon(Icons.straighten_rounded),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: AppTheme.paidGreen, width: 2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  final n = double.tryParse(v);
                  if (n == null || n <= 0) return 'Enter a positive number';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Note / Reason (optional)',
                  prefixIcon: Icon(Icons.notes_rounded),
                  hintText: 'e.g. Only 2 kg available',
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop({
              'qty':   double.parse(_qtyCtrl.text.trim()),
              'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
            });
          },
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.paidGreen),
          child: const Text('Confirm Issue'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// M14: Add New Item From Request Dialog
// Shown when a storekeeper approves a kitchen "new item request".
// Combines a mini "Add Inventory Item" form with the issue-requisition call.
// ─────────────────────────────────────────────────────────────────────────────

const _kCategories = [
  'Meat', 'Vegetables', 'Dairy', 'Dry Goods',
  'Beverages', 'Cleaning', 'Packaging', 'Other',
];

const _kUomOptions = [
  'kg', 'g', 'L', 'ml', 'pcs', 'dozen', 'bag', 'box', 'litre', 'bunch',
];

class _AddNewItemFromRequestDialog extends StatefulWidget {
  final Requisition req;
  final String staffName;

  const _AddNewItemFromRequestDialog({
    required this.req,
    required this.staffName,
  });

  @override
  State<_AddNewItemFromRequestDialog> createState() =>
      _AddNewItemFromRequestDialogState();
}

class _AddNewItemFromRequestDialogState
    extends State<_AddNewItemFromRequestDialog> {
  final _formKey       = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _reorderCtrl;
  late final TextEditingController _targetQtyCtrl;
  String? _category;
  late String _uom;
  String? _purchaserId;          // default_purchaser_id (internal supplier)
  List<Supplier> _purchasers = []; // internal suppliers for the dropdown
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl      = TextEditingController(text: widget.req.newItemName ?? '');
    _reorderCtrl   = TextEditingController();
    _targetQtyCtrl = TextEditingController();

    // Pre-fill UOM from the requisition; fall back to 'pcs' if not in the list.
    final rawUom = widget.req.unitOfMeasure ?? widget.req.itemUom ?? 'pcs';
    _uom = _kUomOptions.contains(rawUom) ? rawUom : 'pcs';

    _loadPurchasers();
  }

  Future<void> _loadPurchasers() async {
    try {
      final all = await ApiService.instance.getSuppliers();
      if (!mounted) return;
      setState(() => _purchasers = all.where((s) => s.isInternal).toList());
    } catch (_) {
      // Non-critical — purchaser dropdown simply stays empty if load fails
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _reorderCtrl.dispose();
    _targetQtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_category == null) {
      setState(() => _error = 'Please select a category.');
      return;
    }

    setState(() { _saving = true; _error = null; });

    try {
      // Step 1: Create the inventory item (stock starts at 0).
      // Target procure qty has no dedicated DB column — stored in notes.
      final targetQty = double.tryParse(_targetQtyCtrl.text.trim());
      final notesStr  = targetQty != null
          ? 'Target order qty: ${targetQty.toStringAsFixed(targetQty % 1 == 0 ? 0 : 1)} $_uom'
          : null;

      await ApiService.instance.createInventoryItem({
        'name':                _nameCtrl.text.trim(),
        'category':            _category,
        'unit_of_measure':     _uom,
        'quantity_in_stock':   0,
        'reorder_level':       double.parse(_reorderCtrl.text.trim()),
        if (_purchaserId != null) 'default_purchaser_id': _purchaserId,
        if (notesStr != null) 'notes': notesStr,
      });

      // Step 2: Mark the requisition as issued (backend skips stock deduction
      // because inventory_item_id is NULL on new-item requests).
      await ApiService.instance.issueRequisition(
        widget.req.id,
        widget.staffName,
        issueNotes: 'Added to inventory as new item',
      );

      if (!mounted) return;
      Navigator.of(context).pop(true); // signal success to parent
    } on ApiException catch (e) {
      setState(() { _error = e.message; _saving = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.req;

    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.add_circle_rounded,
            color: Color(0xFF00796B), size: 22),
        const SizedBox(width: 8),
        const Expanded(
          child: Text('Add to Inventory & Approve',
              style: TextStyle(fontSize: 15)),
        ),
      ]),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Context banner
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00796B).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color(0xFF00796B).withOpacity(0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 14, color: Color(0xFF00796B)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Requested by ${req.requestedBy}  ·  '
                        '${req.quantity.toStringAsFixed(req.quantity % 1 == 0 ? 0 : 1)} '
                        '${req.unitOfMeasure ?? req.itemUom ?? ''}',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF00796B)),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),

                // Item Name
                TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Item Name *',
                    prefixIcon: Icon(Icons.inventory_2_rounded),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Item name is required'
                      : null,
                ),
                const SizedBox(height: 12),

                // Category
                DropdownButtonFormField<String>(
                  value: _category,
                  decoration: const InputDecoration(
                    labelText: 'Category *',
                    prefixIcon: Icon(Icons.label_rounded),
                    border: OutlineInputBorder(),
                  ),
                  items: _kCategories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _category = v;
                    _error = null;
                  }),
                  validator: (v) =>
                      v == null ? 'Category is required' : null,
                ),
                const SizedBox(height: 12),

                // Unit of Measure
                DropdownButtonFormField<String>(
                  value: _uom,
                  decoration: const InputDecoration(
                    labelText: 'Unit of Measure *',
                    prefixIcon: Icon(Icons.straighten_rounded),
                    border: OutlineInputBorder(),
                  ),
                  items: _kUomOptions
                      .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                      .toList(),
                  onChanged: (v) => setState(() => _uom = v!),
                ),
                const SizedBox(height: 12),

                // Default Purchaser (internal supplier / manager float account)
                DropdownButtonFormField<String?>(
                  value: _purchaserId,
                  decoration: const InputDecoration(
                    labelText: 'Default Purchaser (who buys this item)',
                    prefixIcon: Icon(Icons.account_balance_wallet_rounded),
                    border: OutlineInputBorder(),
                    helperText:
                        'Assign to a manager account so this item appears in their next procurement run.',
                    helperMaxLines: 2,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('— Unassigned —')),
                    ..._purchasers.map((s) =>
                        DropdownMenuItem<String?>(value: s.id, child: Text(s.name))),
                  ],
                  onChanged: (v) => setState(() => _purchaserId = v),
                ),
                const SizedBox(height: 12),

                // Reorder Level
                TextFormField(
                  controller: _reorderCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Min Stock Level (Reorder Level) *',
                    prefixIcon: Icon(Icons.warning_amber_rounded),
                    border: OutlineInputBorder(),
                    helperText:
                        'Set this so the system triggers a purchase in the next procurement run.',
                    helperMaxLines: 2,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if (double.tryParse(v.trim()) == null) return 'Enter a number';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Reorder Quantity
                TextFormField(
                  controller: _targetQtyCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Target Procure Qty (Reorder Quantity) *',
                    prefixIcon: Icon(Icons.add_shopping_cart_rounded),
                    border: OutlineInputBorder(),
                    helperText:
                        'How much to order when stock drops below the min level.',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if (double.tryParse(v.trim()) == null) return 'Enter a number';
                    return null;
                  },
                ),
                const SizedBox(height: 8),

                // Current stock note (locked to 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.scaffold,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    Icon(Icons.lock_outline_rounded,
                        size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 8),
                    Text(
                      'Current Stock: 0  (item not yet received)',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ]),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: const TextStyle(
                          color: AppTheme.debtRed, fontSize: 13)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: _saving ? null : _submit,
          style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00796B)),
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.add_circle_rounded, size: 16),
          label: const Text('Add to Inventory & Approve'),
        ),
      ],
    );
  }
}

/// Reject dialog: lets the storekeeper enter a reason before rejecting.
class _RejectDialog extends StatefulWidget {
  final String itemName;
  const _RejectDialog({required this.itemName});

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.cancel_rounded, color: AppTheme.debtRed),
        const SizedBox(width: 10),
        Expanded(child: Text('Reject: ${widget.itemName}',
            overflow: TextOverflow.ellipsis)),
      ]),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: _ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Rejection Reason (optional)',
            prefixIcon: Icon(Icons.notes_rounded),
            hintText: 'e.g. Out of stock until Thursday',
          ),
          maxLines: 3,
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_ctrl.text.trim()),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.debtRed),
          child: const Text('Reject'),
        ),
      ],
    );
  }
}
