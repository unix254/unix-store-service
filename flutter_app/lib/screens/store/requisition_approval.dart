import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/theme.dart';
import '../../models/staff.dart';
import '../../models/requisition.dart';
import '../../services/api.dart';

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
    // Auto-refresh every 30 seconds
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _loadRequisitions();
    });
    // Countdown ticker for UI indicator
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _pollCountdown =
            30 - (DateTime.now().second % 30);
      });
    });
  }

  Future<void> _loadRequisitions() async {
    setState(() => _loading = true);
    try {
      final list = await ApiService.instance.getRequisitions();
      setState(() {
        _all = list;
        _loading = false;
        _lastRefresh = DateTime.now();
        _pollCountdown = 30;
      });
    } catch (e) {
      setState(() => _loading = false);
      _showError(e.toString());
    }
  }

  List<Requisition> get _filtered {
    if (_filter == 'All') return _all;
    return _all.where((r) => r.status == _filter).toList();
  }

  int get _pendingCount => _all.where((r) => r.isPending).length;

  Future<void> _issue(Requisition req) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Issue'),
        content: Text(
          'Issue ${req.quantity.toStringAsFixed(req.quantity % 1 == 0 ? 0 : 1)} '
          '${req.unitOfMeasure ?? req.itemUom ?? ''} of ${req.itemName}?\n\n'
          'This will deduct the quantity from stock.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.paidGreen),
            child: const Text('Yes, Issue'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await ApiService.instance.issueRequisition(req.id, widget.staff.name);
      _showSuccess('Issued: ${req.itemName}');
      _loadRequisitions();
    } on ApiException catch (e) {
      _showError(e.message);
    }
  }

  Future<void> _reject(Requisition req) async {
    try {
      await ApiService.instance.rejectRequisition(req.id);
      _showSuccess('Rejected: ${req.itemName}');
      _loadRequisitions();
    } catch (e) {
      _showError(e.toString());
    }
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
                        req:     _filtered[i],
                        onIssue: _filtered[i].isPending
                            ? () => _issue(_filtered[i])
                            : null,
                        onReject: _filtered[i].isPending
                            ? () => _reject(_filtered[i])
                            : null,
                      ),
                    ),
        ),
      ],
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
            '$countdown',
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
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

  const _RequisitionCard(
      {required this.req, this.onIssue, this.onReject});

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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Purpose icon block ─────────────────────────────
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: req.isSales
                    ? AppTheme.pinTeal.withOpacity(0.12)
                    : AppTheme.secondary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  req.isSales ? '📦' : '🍽️',
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
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87),
                      children: [
                        TextSpan(text: req.itemName),
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
                  const SizedBox(height: 6),
                  // Meta row
                  Wrap(
                    spacing: 14,
                    children: [
                      _MetaChip(
                        icon: Icons.person_rounded,
                        label: req.requestedBy,
                      ),
                      _MetaChip(
                        icon: Icons.access_time_rounded,
                        label: _formatTime(req.requestedAt),
                      ),
                      _PurposeBadge(purpose: req.purpose),
                      if (req.notes != null && req.notes!.isNotEmpty)
                        _MetaChip(
                          icon: Icons.notes_rounded,
                          label: req.notes!,
                        ),
                    ],
                  ),
                  // Issued by info
                  if (req.isIssued && req.issuedBy != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Issued by ${req.issuedBy}'
                        '${req.issuedAt != null ? ' at ${_formatTime(req.issuedAt!)}' : ''}',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.paidGreen.withOpacity(0.8)),
                      ),
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
                const SizedBox(height: 12),
                if (isPending) ...[
                  SizedBox(
                    width: 120,
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: onIssue,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.paidGreen,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10))),
                      icon: const Icon(Icons.check_rounded,
                          size: 18, color: Colors.white),
                      label: const Text('Issue',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 120,
                    height: 40,
                    child: OutlinedButton.icon(
                      onPressed: onReject,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.debtRed,
                        side: const BorderSide(color: AppTheme.debtRed),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: const Text('Reject',
                          style:
                              TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String raw) {
    final dt = DateTime.tryParse(raw);
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
  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.grey.shade500),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
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
