import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/theme.dart';
import '../../models/staff.dart';
import '../../models/supplier.dart';
import '../../models/ledger_entry.dart';
import '../../services/api.dart';

final _kes = NumberFormat.currency(locale: 'en_KE', symbol: 'KES ', decimalDigits: 2);
final _dateFmt = DateFormat('dd MMM yyyy');

// ── Ledger period filter ───────────────────────────────────────────────────────

enum _LedgerPeriod { thisMonth, lastMonth, last90, allTime, custom }

extension _LedgerPeriodLabel on _LedgerPeriod {
  String get label {
    switch (this) {
      case _LedgerPeriod.thisMonth:  return 'This Month';
      case _LedgerPeriod.lastMonth:  return 'Last Month';
      case _LedgerPeriod.last90:     return 'Last 90 Days';
      case _LedgerPeriod.allTime:    return 'All Time';
      case _LedgerPeriod.custom:     return 'Custom';
    }
  }
}

String _fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// Returns (from, to) strings for the given period, or (null, null) for all time.
({String? from, String? to, String label}) _ledgerPeriodDates(
    _LedgerPeriod period, DateTimeRange? custom) {
  final now = DateTime.now();
  switch (period) {
    case _LedgerPeriod.thisMonth:
      return (
        from:  _fmtDate(DateTime(now.year, now.month, 1)),
        to:    _fmtDate(now),
        label: DateFormat('MMM yyyy').format(now),
      );
    case _LedgerPeriod.lastMonth:
      final first = DateTime(now.year, now.month - 1, 1);
      final last  = DateTime(now.year, now.month, 0);
      return (
        from:  _fmtDate(first),
        to:    _fmtDate(last),
        label: DateFormat('MMM yyyy').format(first),
      );
    case _LedgerPeriod.last90:
      return (
        from:  _fmtDate(now.subtract(const Duration(days: 89))),
        to:    _fmtDate(now),
        label: 'Last 90 Days',
      );
    case _LedgerPeriod.allTime:
      return (from: null, to: null, label: 'All Time');
    case _LedgerPeriod.custom:
      if (custom == null) {
        return (from: null, to: null, label: 'Custom');
      }
      final display = DateFormat('d MMM');
      return (
        from:  _fmtDate(custom.start),
        to:    _fmtDate(custom.end),
        label: '${display.format(custom.start)} – ${display.format(custom.end)}',
      );
  }
}

class SupplierLedgerScreen extends StatefulWidget {
  final Staff staff;
  const SupplierLedgerScreen({super.key, required this.staff});

  @override
  State<SupplierLedgerScreen> createState() => _SupplierLedgerScreenState();
}

class _SupplierLedgerScreenState extends State<SupplierLedgerScreen> {
  List<Supplier> _suppliers = [];
  Supplier? _selected;
  bool _loadingSuppliers = true;

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  Future<void> _loadSuppliers() async {
    setState(() => _loadingSuppliers = true);
    try {
      final list = await ApiService.instance.getSuppliers();
      setState(() {
        _suppliers = list;
        _selected ??= list.isNotEmpty ? list.first : null;
        _loadingSuppliers = false;
      });
    } catch (e) {
      setState(() => _loadingSuppliers = false);
      _showError(e.toString());
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppTheme.debtRed));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppTheme.paidGreen));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 800;

        // Mobile View
        if (isMobile) {
          if (_selected == null) {
            return SizedBox(
              width: double.infinity,
              child: _SupplierList(
                suppliers: _suppliers,
                selected: _selected,
                loading: _loadingSuppliers,
                onSelect: (s) => setState(() => _selected = s),
                onAdd: _showAddSupplierDialog,
                onRefresh: _loadSuppliers,
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
                        onPressed: () => setState(() => _selected = null),
                      ),
                      const SizedBox(width: 8),
                      const Text('Back to Suppliers', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    ],
                  ),
                ),
                Expanded(
                  child: _SupplierDetail(
                    key: ValueKey(_selected!.id),
                    supplier: _selected!,
                    staff: widget.staff,
                    onUpdated: _loadSuppliers,
                    onError: _showError,
                    onSuccess: _showSuccess,
                  ),
                ),
              ],
            );
          }
        }

        // Desktop View
        return Row(
          children: [
            // ── Left: Supplier List ──────────────────────────────
            SizedBox(
              width: 300,
              child: _SupplierList(
                suppliers: _suppliers,
                selected: _selected,
                loading: _loadingSuppliers,
                onSelect: (s) => setState(() => _selected = s),
                onAdd: _showAddSupplierDialog,
                onRefresh: _loadSuppliers,
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            // ── Right: Detail Panel ──────────────────────────────
            Expanded(
              child: _selected == null
                  ? const _EmptyDetail()
                  : _SupplierDetail(
                      key: ValueKey(_selected!.id),
                      supplier: _selected!,
                      staff: widget.staff,
                      onUpdated: _loadSuppliers,
                      onError: _showError,
                      onSuccess: _showSuccess,
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAddSupplierDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => const _SupplierFormDialog(),
    );
    if (result == true) _loadSuppliers();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LEFT PANEL: Supplier List
// ─────────────────────────────────────────────────────────────────────────────

class _SupplierList extends StatefulWidget {
  final List<Supplier> suppliers;
  final Supplier? selected;
  final bool loading;
  final void Function(Supplier) onSelect;
  final VoidCallback onAdd;
  final VoidCallback onRefresh;

  const _SupplierList({
    required this.suppliers,
    required this.selected,
    required this.loading,
    required this.onSelect,
    required this.onAdd,
    required this.onRefresh,
  });

  @override
  State<_SupplierList> createState() => _SupplierListState();
}

class _SupplierListState extends State<_SupplierList> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _search.isEmpty
        ? widget.suppliers
        : widget.suppliers
            .where((s) =>
                s.name.toLowerCase().contains(_search.toLowerCase()) ||
                (s.location ?? '').toLowerCase().contains(_search.toLowerCase()))
            .toList();

    return Scaffold(
        backgroundColor: AppTheme.surface,
        appBar: AppBar(
          title: const Text('Suppliers'),
          actions: [
            IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: widget.onRefresh,
                tooltip: 'Refresh'),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: widget.onAdd,
          backgroundColor: AppTheme.primary,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('Add Supplier',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        body: Column(
          children: [
            // ── Search bar ───────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
              child: TextField(
                onChanged: (v) => setState(() => _search = v),
                decoration: InputDecoration(
                  hintText: 'Search suppliers…',
                  hintStyle: const TextStyle(fontSize: 13),
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon: _search.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 16),
                          onPressed: () => setState(() => _search = ''),
                        )
                      : null,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                ),
              ),
            ),
            // ── List ─────────────────────────────────────────
            Expanded(
              child: widget.loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? Center(
                          child: Text(
                            _search.isNotEmpty
                                ? 'No matches for "$_search"'
                                : 'No suppliers yet.\nTap + to add one.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey),
                          ))
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 80),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, indent: 16),
                          itemBuilder: (_, i) {
                            final s = filtered[i];
                            final isSelected = widget.selected?.id == s.id;
                            return InkWell(
                              onTap: () => widget.onSelect(s),
                              child: Container(
                                color: isSelected
                                    ? AppTheme.primary.withOpacity(0.08)
                                    : s.isInternal
                                        ? const Color(0xFFFFF8E1)
                                        : null,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: isSelected
                                          ? AppTheme.primary
                                          : AppTheme.scaffold,
                                      child: Text(
                                        s.name.substring(0, 1).toUpperCase(),
                                        style: TextStyle(
                                          color: isSelected
                                              ? Colors.white
                                              : AppTheme.primary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  s.name,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 14),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (s.isInternal) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        const Color(0xFFFF8F00),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4),
                                                  ),
                                                  child: const Text('Internal',
                                                      style: TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.w700)),
                                                ),
                                              ],
                                            ],
                                          ),
                                          Text(s.location ?? 'No location',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade600)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    _BalanceChip(amount: s.balanceDue),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RIGHT PANEL: Supplier Detail
// ─────────────────────────────────────────────────────────────────────────────

class _SupplierDetail extends StatefulWidget {
  final Supplier supplier;
  final Staff staff;
  final VoidCallback onUpdated;
  final void Function(String) onError;
  final void Function(String) onSuccess;

  const _SupplierDetail({
    super.key,
    required this.supplier,
    required this.staff,
    required this.onUpdated,
    required this.onError,
    required this.onSuccess,
  });

  @override
  State<_SupplierDetail> createState() => _SupplierDetailState();
}

class _SupplierDetailState extends State<_SupplierDetail> {
  List<LedgerEntry> _entries = [];
  bool _loadingLedger = true;

  _LedgerPeriod _ledgerPeriod = _LedgerPeriod.allTime;
  DateTimeRange? _customLedgerRange;

  @override
  void initState() {
    super.initState();
    _loadLedger();
  }

  Future<void> _loadLedger() async {
    setState(() => _loadingLedger = true);
    try {
      final pd = _ledgerPeriodDates(_ledgerPeriod, _customLedgerRange);
      final list = await ApiService.instance
          .getSupplierLedger(widget.supplier.id, from: pd.from, to: pd.to);
      setState(() {
        _entries = list;
        _loadingLedger = false;
      });
    } catch (e) {
      setState(() => _loadingLedger = false);
      widget.onError(e.toString());
    }
  }

  Future<void> _addEntry(String type) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _AddEntryDialog(
          supplierId: widget.supplier.id, type: type),
    );
    if (result == true) {
      await _loadLedger();
      widget.onUpdated();
    }
  }

  Future<void> _sendOrder() async {
    await showDialog(
      context: context,
      builder: (_) => _OrderDialog(supplier: widget.supplier),
    );
  }

  Future<void> _sendMiniStatement() async {
    try {
      final pd = _ledgerPeriodDates(_ledgerPeriod, _customLedgerRange);
      final result = await ApiService.instance.getSupplierStatementWhatsApp(
        widget.supplier.id,
        from: pd.from,
        to:   pd.to,
      );
      final url = result['whatsapp_url'] as String?;
      if (url != null) {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          widget.onError('Could not open WhatsApp');
        }
      }
    } catch (e) {
      widget.onError(e.toString());
    }
  }

  Future<void> _editSupplier() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _SupplierFormDialog(existing: widget.supplier),
    );
    if (result == true) widget.onUpdated();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.supplier;
    final balance = s.balanceDue;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Supplier Header ──────────────────────────────────
            Container(
              color: AppTheme.surface,
              padding: EdgeInsets.fromLTRB(isMobile ? 16 : 24, 16, isMobile ? 16 : 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isMobile) ...[
                    Text(s.name,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    _BalanceSummaryCard(balance: balance),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        if (s.phone != null)
                          _InfoChip(icon: Icons.phone_rounded, label: s.phone!),
                        if (s.location != null)
                          _InfoChip(
                              icon: Icons.location_on_rounded,
                              label: s.location!),
                        if (s.paymentDay != null)
                          _InfoChip(
                              icon: Icons.calendar_today_rounded,
                              label: 'Pays: ${s.paymentDay}'),
                        if (s.leadTimeDays > 0)
                          _InfoChip(
                              icon: Icons.local_shipping_rounded,
                              label: '${s.leadTimeDays}d lead time'),
                      ],
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.name,
                                  style: const TextStyle(
                                      fontSize: 22, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 16,
                                children: [
                                  if (s.phone != null)
                                    _InfoChip(
                                        icon: Icons.phone_rounded,
                                        label: s.phone!),
                                  if (s.location != null)
                                    _InfoChip(
                                        icon: Icons.location_on_rounded,
                                        label: s.location!),
                                  if (s.paymentDay != null)
                                    _InfoChip(
                                        icon: Icons.calendar_today_rounded,
                                        label: 'Pays: ${s.paymentDay}'),
                                  if (s.leadTimeDays > 0)
                                    _InfoChip(
                                        icon: Icons.local_shipping_rounded,
                                        label: '${s.leadTimeDays}d lead time'),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        _BalanceSummaryCard(balance: balance),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
              // Action buttons
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _addEntry('PURCHASE'),
                    icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                    label: const Text('Record Purchase'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.debtRed),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _addEntry('PAYMENT'),
                    icon: const Icon(Icons.payments_rounded, size: 18),
                    label: const Text('Record Payment'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.paidGreen),
                  ),
                  // Cash-In is managed in the dedicated Expense Accounts screen.
                  OutlinedButton.icon(
                    onPressed: _sendOrder,
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text('Send Order'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _editSupplier,
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('Edit'),
                  ),
                  // ── Statement actions
                  OutlinedButton.icon(
                    onPressed: _sendMiniStatement,
                    icon: const Icon(Icons.chat_rounded, size: 18, color: Color(0xFF25D366)),
                    label: const Text('Send Statement via WhatsApp'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF25D366),
                      side: const BorderSide(color: Color(0xFF25D366)),
                    ),
                  ),
                  Tooltip(
                    message: 'PDF statement – coming soon',
                    child: OutlinedButton.icon(
                      onPressed: null, // disabled – foundation for future PDF
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                      label: const Text('Print Full Statement'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // ── Period filter & Transaction List header ───────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Period chips
              _LedgerPeriodSelector(
                selected: _ledgerPeriod,
                onChanged: (p) async {
                  if (p == _LedgerPeriod.custom) {
                    final range = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      initialDateRange: _customLedgerRange,
                    );
                    if (range == null) return;
                    setState(() {
                      _ledgerPeriod = _LedgerPeriod.custom;
                      _customLedgerRange = range;
                    });
                  } else {
                    setState(() {
                      _ledgerPeriod = p;
                      _customLedgerRange = null;
                    });
                  }
                  _loadLedger();
                },
                customRange: _customLedgerRange,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text('Transaction History',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text('${_entries.length} entries',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: _loadLedger,
                    tooltip: 'Refresh',
                    iconSize: 20,
                  ),
                ],
              ),
            ],
          ),
        ),

        Expanded(
          child: _loadingLedger
              ? const Center(child: CircularProgressIndicator())
              : _entries.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.receipt_long_rounded,
                              size: 56, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text('No transactions yet',
                              style: TextStyle(color: Colors.grey.shade500)),
                        ],
                      ),
                    )
                  : _LedgerTable(entries: _entries),
        ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LEDGER TABLE
// ─────────────────────────────────────────────────────────────────────────────

class _LedgerTable extends StatelessWidget {
  final List<LedgerEntry> entries;
  const _LedgerTable({required this.entries});

  @override
  Widget build(BuildContext context) {
    // Show "Paid To" column only when any entry links back to an external supplier
    // (i.e. SUPPLIER_PAYMENT rows on manager/internal accounts).
    final hasRelated = entries.any((e) => e.relatedSupplierName != null);

    // Column indices & widths — kept narrow so the row fits without horizontal scroll
    // when hasRelated is false. When true, a horizontal scroll view handles overflow.
    final colWidths = <int, TableColumnWidth>{
      0: const FixedColumnWidth(100), // Date
      1: const FixedColumnWidth(130), // Type badge
      2: const FixedColumnWidth(120), // Amount
      3: const FixedColumnWidth(200), // Description (fixed, not flex — avoids layout flicker)
      if (hasRelated) 4: const FixedColumnWidth(140), // Paid To
      if (hasRelated) 5: const FixedColumnWidth(80) else 4: const FixedColumnWidth(80),   // Ref
      if (hasRelated) 6: const FixedColumnWidth(130) else 5: const FixedColumnWidth(130), // Balance
    };

    final headers = [
      'Date', 'Type', 'Amount', 'Description',
      if (hasRelated) 'Paid To', // short, readable, no typo
      'Ref', 'Balance',
    ];

    final reversedEntries = entries.reversed.toList();

    // Wrap in horizontal scroll so wide rows never clip outside the panel.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        padding: const EdgeInsets.only(bottom: 24),
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          columnWidths: colWidths,
        children: [
          // Header
          TableRow(
            decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: Colors.grey.shade200, width: 2)),
            ),
            children: headers
                .map((h) => Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 8),
                      child: Text(h,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade600)),
                    ))
                .toList(),
          ),
          // Rows (newest first)
          ...reversedEntries.map((e) => TableRow(
                decoration: BoxDecoration(
                  color: reversedEntries.indexOf(e).isEven
                      ? Colors.transparent
                      : AppTheme.scaffold,
                  border: Border(
                      bottom: BorderSide(
                          color: Colors.grey.shade100, width: 1)),
                ),
                children: [
                  // Date
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 8),
                    child: Text(
                      _dateFmt.format(DateTime.tryParse(e.transactionDate) ??
                          DateTime.now()),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  // Type chip
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 8, horizontal: 8),
                    child: _TypeBadge(type: e.transactionType),
                  ),
                  // Amount
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 8),
                    child: Text(
                      _kes.format(e.amount),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        // CASH_IN shows in blue (bank withdrawal credit)
                        color: e.isCashIn
                            ? const Color(0xFF1565C0)
                            : e.isDebit
                                ? AppTheme.debtRed
                                : AppTheme.paidGreen,
                      ),
                    ),
                  ),
                  // Description
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 8),
                    child: Text(e.description ?? '–',
                        style:
                            const TextStyle(fontSize: 13, color: Colors.black87),
                        overflow: TextOverflow.ellipsis),
                  ),
                  // Related Supplier (only if column shown)
                  if (hasRelated)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 8),
                      child: e.relatedSupplierName != null
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.link_rounded,
                                    size: 13, color: Colors.deepPurple),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(e.relatedSupplierName!,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.deepPurple,
                                          fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            )
                          : const Text('–',
                              style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ),
                  // Ref
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 8),
                    child: Text(e.referenceDoc ?? '–',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey)),
                  ),
                  // Running Balance
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 8),
                    child: e.runningBalance != null
                        ? Text(
                            _kes.format(e.runningBalance),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: (e.runningBalance! > 0)
                                  ? AppTheme.debtRed
                                  : AppTheme.paidGreen,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              )),
        ],
        ), // Closes Table
      ),   // Closes inner SingleChildScrollView
    );     // Closes outer SingleChildScrollView
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DIALOGS
// ─────────────────────────────────────────────────────────────────────────────

class _AddEntryDialog extends StatefulWidget {
  final String supplierId;
  final String type;
  const _AddEntryDialog({required this.supplierId, required this.type});

  @override
  State<_AddEntryDialog> createState() => _AddEntryDialogState();
}

class _AddEntryDialogState extends State<_AddEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  bool _saving = false;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ApiService.instance.addLedgerEntry(widget.supplierId, {
        'transaction_type': widget.type,
        'amount': double.parse(_amountCtrl.text.trim()),
        'description': _descCtrl.text.trim(),
        'reference_doc': _refCtrl.text.trim(),
        'transaction_date': DateFormat('yyyy-MM-dd').format(_date),
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.debtRed));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPurchase = widget.type == 'PURCHASE';
    final isCashIn   = widget.type == 'CASH_IN';

    // Colour + label per transaction type
    final accentColor = isPurchase
        ? AppTheme.debtRed
        : isCashIn
            ? const Color(0xFF1565C0)   // deep blue for bank cash-in
            : AppTheme.paidGreen;

    final titleIcon = isPurchase
        ? Icons.add_shopping_cart_rounded
        : isCashIn
            ? Icons.account_balance_rounded
            : Icons.payments_rounded;

    final titleText = isPurchase
        ? 'Record Purchase'
        : isCashIn
            ? 'Record Cash-In (Bank Withdrawal)'
            : 'Record Payment';

    final saveLabel = isPurchase
        ? 'Save Purchase'
        : isCashIn
            ? 'Save Cash-In'
            : 'Save Payment';

    final refLabel = isCashIn
        ? 'Bank Ref / Cheque No. (optional)'
        : 'Invoice / Receipt Ref (optional)';

    return AlertDialog(
      title: Row(
        children: [
          Icon(titleIcon, color: accentColor),
          const SizedBox(width: 10),
          Text(titleText),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _amountCtrl,
                decoration: InputDecoration(
                  labelText: 'Amount (KES)',
                  prefixIcon: const Icon(Icons.attach_money_rounded),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: accentColor, width: 2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Amount is required';
                  if (double.tryParse(v) == null) return 'Enter a valid number';
                  if (double.parse(v) <= 0) return 'Amount must be positive';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date',
                    prefixIcon: Icon(Icons.calendar_today_rounded),
                  ),
                  child: Text(_dateFmt.format(_date)),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _refCtrl,
                decoration: InputDecoration(
                  labelText: refLabel,
                  prefixIcon: const Icon(Icons.receipt_rounded),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(backgroundColor: accentColor),
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(saveLabel),
        ),
      ],
    );
  }
}

// ── Supplier Form Dialog ──────────────────────────────────────────────────────

class _SupplierFormDialog extends StatefulWidget {
  final Supplier? existing;
  const _SupplierFormDialog({this.existing});

  @override
  State<_SupplierFormDialog> createState() => _SupplierFormDialogState();
}

const _kPaymentDays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday',
  'Friday', 'Saturday', 'Sunday', 'Daily',
];

class _SupplierFormDialogState extends State<_SupplierFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _locationCtrl;
  late TextEditingController _leadTimeCtrl;
  late TextEditingController _notesCtrl;
  String? _payDay;
  bool _isInternal = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    _nameCtrl     = TextEditingController(text: s?.name ?? '');
    _phoneCtrl    = TextEditingController(text: s?.phone ?? '');
    _locationCtrl = TextEditingController(text: s?.location ?? '');
    _leadTimeCtrl = TextEditingController(text: s?.leadTimeDays.toString() ?? '1');
    _notesCtrl    = TextEditingController(text: s?.notes ?? '');
    _payDay = (s?.paymentDay != null && _kPaymentDays.contains(s!.paymentDay))
        ? s.paymentDay
        : null;
    _isInternal = s?.isInternal ?? false;
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _phoneCtrl, _locationCtrl, _leadTimeCtrl, _notesCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final body = {
      'name':          _nameCtrl.text.trim(),
      'phone':         _phoneCtrl.text.trim(),
      'location':      _locationCtrl.text.trim(),
      'payment_day':   _payDay ?? '',
      'lead_time_days': int.tryParse(_leadTimeCtrl.text.trim()) ?? 1,
      'notes':         _notesCtrl.text.trim(),
      'is_internal':   _isInternal,
    };

    try {
      if (widget.existing == null) {
        await ApiService.instance.createSupplier(body);
      } else {
        await ApiService.instance.updateSupplier(widget.existing!.id, body);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.debtRed));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Supplier' : 'Add New Supplier'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Internal account toggle
                Container(
                  decoration: BoxDecoration(
                    color: _isInternal
                        ? const Color(0xFFFFF8E1)
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isInternal
                          ? const Color(0xFFFF8F00)
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: SwitchListTile(
                    dense: true,
                    value: _isInternal,
                    activeColor: const Color(0xFFFF8F00),
                    title: const Text('Internal Expense Account',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      _isInternal
                          ? 'This supplier represents a manager who holds business cash.'
                          : 'Toggle on if this is a manager cash account, not an external vendor.',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                    onChanged: (v) => setState(() => _isInternal = v),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                      labelText: _isInternal ? 'Account Name *' : 'Supplier Name *',
                      hintText: _isInternal ? 'e.g. Nairobi Manager – John' : '',
                      prefixIcon: Icon(_isInternal
                          ? Icons.account_balance_wallet_rounded
                          : Icons.business_rounded)),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneCtrl,
                  decoration: InputDecoration(
                      labelText: _isInternal
                          ? 'Manager Phone (WhatsApp)'
                          : 'Phone (for WhatsApp/SMS)',
                      prefixIcon: const Icon(Icons.phone_rounded)),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _locationCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Location / Town',
                      prefixIcon: Icon(Icons.location_on_rounded)),
                ),
                if (!_isInternal) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          value: _payDay,
                          decoration: const InputDecoration(
                            labelText: 'Payment Day',
                            prefixIcon: Icon(Icons.calendar_today_rounded),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('— Not scheduled —',
                                    style: TextStyle(color: Colors.grey))),
                            ..._kPaymentDays.map((d) =>
                                DropdownMenuItem<String?>(value: d, child: Text(d))),
                          ],
                          onChanged: (v) => setState(() => _payDay = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _leadTimeCtrl,
                          decoration: const InputDecoration(
                              labelText: 'Lead Time (days)',
                              prefixIcon: Icon(Icons.local_shipping_rounded)),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Notes',
                      prefixIcon: Icon(Icons.notes_rounded)),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(isEdit ? 'Update' : 'Add Supplier'),
        ),
      ],
    );
  }
}

// ── Order Dialog ──────────────────────────────────────────────────────────────

class _OrderDialog extends StatefulWidget {
  final Supplier supplier;
  const _OrderDialog({required this.supplier});

  @override
  State<_OrderDialog> createState() => _OrderDialogState();
}

class _OrderDialogState extends State<_OrderDialog> {
  final List<Map<String, TextEditingController>> _items = [];
  final _noteCtrl = TextEditingController();
  String? _message;
  String? _waUrl;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _addItem();
  }

  void _addItem() {
    setState(() => _items.add({
          'name': TextEditingController(),
          'quantity': TextEditingController(),
          'unit': TextEditingController(text: 'kg'),
        }));
  }

  void _removeItem(int i) {
    if (_items.length > 1) {
      final item = _items.removeAt(i);
      for (final c in item.values) c.dispose();
      setState(() {});
    }
  }

  Future<void> _preview() async {
    final items = _items
        .map((m) => {
              'name': m['name']!.text.trim(),
              'quantity': m['quantity']!.text.trim(),
              'unit': m['unit']!.text.trim(),
            })
        .where((m) => m['name']!.isNotEmpty)
        .toList();

    if (items.isEmpty) return;

    setState(() => _loading = true);
    try {
      final result = await ApiService.instance.getOrderMessage(
        widget.supplier.id,
        items,
        note: _noteCtrl.text.trim(),
      );
      setState(() {
        _message = result['message'] as String?;
        _waUrl = result['whatsapp_url'] as String?;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())));
    }
  }

  @override
  void dispose() {
    for (final item in _items) {
      for (final c in item.values) c.dispose();
    }
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.send_rounded, color: AppTheme.primary),
          const SizedBox(width: 10),
          Text('Send Order to ${widget.supplier.name}'),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Order items
              ...List.generate(
                _items.length,
                (i) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: TextFormField(
                          controller: _items[i]['name'],
                          decoration: InputDecoration(
                              labelText: 'Item ${i + 1}',
                              hintText: 'e.g. Whole Chicken'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 80,
                        child: TextFormField(
                          controller: _items[i]['quantity'],
                          decoration: const InputDecoration(labelText: 'Qty'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 70,
                        child: TextFormField(
                          controller: _items[i]['unit'],
                          decoration: const InputDecoration(labelText: 'Unit'),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline_rounded,
                            color: AppTheme.debtRed),
                        onPressed: () => _removeItem(i),
                      ),
                    ],
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _addItem,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add Item'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                    labelText: 'Additional Note (optional)'),
                maxLines: 2,
              ),

              // Message preview
              if (_message != null) ...[
                const SizedBox(height: 20),
                const Text('Message Preview:',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.paidGreen),
                  ),
                  child: SelectableText(_message!,
                      style: const TextStyle(fontSize: 13, height: 1.5)),
                ),
                if (_waUrl != null) ...[
                  const SizedBox(height: 12),
                  const Text(
                    '💡 Click "Open WhatsApp" to send this message directly.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close')),
        ElevatedButton.icon(
          onPressed: _loading ? null : _preview,
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF37474F)),
          icon: const Icon(Icons.preview_rounded, size: 18),
          label: const Text('Preview Message'),
        ),
        if (_waUrl != null)
          ElevatedButton.icon(
            onPressed: () async {
              final uri = Uri.parse(_waUrl!);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366)),
            icon: const Icon(Icons.chat_rounded, size: 18),
            label: const Text('Open WhatsApp'),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SMALL WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _LedgerPeriodSelector extends StatelessWidget {
  final _LedgerPeriod selected;
  final void Function(_LedgerPeriod) onChanged;
  final DateTimeRange? customRange;

  const _LedgerPeriodSelector({
    required this.selected,
    required this.onChanged,
    this.customRange,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _LedgerPeriod.values.map((p) {
          String label = p.label;
          if (p == _LedgerPeriod.custom && customRange != null) {
            final fmt = DateFormat('d MMM');
            label = '${fmt.format(customRange!.start)} – ${fmt.format(customRange!.end)}';
          }
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(label, style: const TextStyle(fontSize: 12)),
              selected: selected == p,
              onSelected: (_) => onChanged(p),
              selectedColor: AppTheme.primary.withOpacity(0.15),
              labelStyle: TextStyle(
                color: selected == p ? AppTheme.primary : Colors.grey.shade700,
                fontWeight: selected == p ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _BalanceChip extends StatelessWidget {
  final double amount;
  const _BalanceChip({required this.amount});

  @override
  Widget build(BuildContext context) {
    final isDebt = amount > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDebt
            ? AppTheme.debtRed.withOpacity(0.1)
            : AppTheme.paidGreen.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _kes.format(amount),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: isDebt ? AppTheme.debtRed : AppTheme.paidGreen,
        ),
      ),
    );
  }
}

class _BalanceSummaryCard extends StatelessWidget {
  final double balance;
  const _BalanceSummaryCard({required this.balance});

  @override
  Widget build(BuildContext context) {
    final isDebt = balance > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: isDebt
            ? AppTheme.debtRed.withOpacity(0.07)
            : AppTheme.paidGreen.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDebt ? AppTheme.debtRed : AppTheme.paidGreen,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            isDebt ? 'BALANCE DUE' : 'FULLY PAID',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: isDebt ? AppTheme.debtRed : AppTheme.paidGreen,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _kes.format(balance.abs()),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: isDebt ? AppTheme.debtRed : AppTheme.paidGreen,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
      ],
    );
  }
}

// _TypeBadge – handles PURCHASE, PAYMENT, SUPPLIER_PAYMENT, and CASH_IN.
class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final String label;
    final IconData icon;

    switch (type) {
      case 'SUPPLIER_PAYMENT':
        bg = Colors.deepPurple.withOpacity(0.1);
        fg = Colors.deepPurple;
        label = 'SUPP. PAYMENT';
        icon = Icons.swap_horiz_rounded;
        break;
      case 'PAYMENT':
        bg = AppTheme.paidGreen.withOpacity(0.1);
        fg = AppTheme.paidGreen;
        label = 'PAYMENT';
        icon = Icons.check_circle_outline_rounded;
        break;
      case 'CASH_IN':
        bg = const Color(0xFF1565C0).withOpacity(0.1);
        fg = const Color(0xFF1565C0);
        label = 'CASH IN';
        icon = Icons.account_balance_rounded;
        break;
      default: // PURCHASE
        bg = AppTheme.debtRed.withOpacity(0.1);
        fg = AppTheme.debtRed;
        label = 'PURCHASE';
        icon = Icons.shopping_cart_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_alt_rounded, size: 72, color: Colors.grey.shade200),
          const SizedBox(height: 16),
          Text(
            'Select a supplier to view their ledger',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }
}
