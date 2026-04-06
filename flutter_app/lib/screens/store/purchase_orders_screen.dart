import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/theme.dart';
import '../../models/staff.dart';
import '../../models/inventory_item.dart';
import '../../services/api.dart';

final _kesPo  = NumberFormat.currency(locale: 'en_KE', symbol: 'KES ', decimalDigits: 2);
final _numFmt = NumberFormat('0.###');

// ─────────────────────────────────────────────────────────────────────────────
// Screen root
// ─────────────────────────────────────────────────────────────────────────────

class PurchaseOrdersScreen extends StatefulWidget {
  final Staff staff;
  const PurchaseOrdersScreen({super.key, required this.staff});

  @override
  State<PurchaseOrdersScreen> createState() => _PurchaseOrdersScreenState();
}

class _PurchaseOrdersScreenState extends State<PurchaseOrdersScreen> {
  List<Map<String, dynamic>> _allPOs = [];
  Map<String, dynamic>?      _selectedPO;
  bool   _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── Data loading ────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final pos = await ApiService.instance.getPurchaseOrders();
      Map<String, dynamic>? refreshed;
      if (_selectedPO != null) {
        try { refreshed = await ApiService.instance.getPurchaseOrder(_selectedPO!['id'] as String); }
        catch (_) {}
      }
      setState(() {
        _allPOs     = pos;
        _selectedPO = refreshed ?? (pos.isNotEmpty ? null : null);
        _loading    = false;
      });
      // Auto-open first PO if none selected
      if (_selectedPO == null && pos.isNotEmpty) {
        await _openPO(pos.first['id'] as String);
      }
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _openPO(String id) async {
    try {
      final po = await ApiService.instance.getPurchaseOrder(id);
      setState(() => _selectedPO = po);
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    }
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  Future<void> _autoDraft() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Auto-Calculate Purchase Order?'),
        content: const Text(
            'The system will scan your inventory and include any item whose current stock '
            'is at or below its minimum (reorder) level.\n\n'
            'Suggested order quantities are calculated based on each item\'s reorder level '
            'and supplier lead time — so you have enough stock to last until the next '
            'delivery arrives.\n\n'
            'You can review and edit quantities before submitting for approval.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.pinTeal),
            child: const Text('Create Draft'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final po = await ApiService.instance.autoDraftPO(widget.staff.name);
      _snack('Draft PO created.');
      await _load();
      await _openPO(po['id'] as String);
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    }
  }

  Future<void> _addItem() async {
    if (_selectedPO == null) return;
    // Load inventory for picker
    List<InventoryItem> items = [];
    try {
      items = await ApiService.instance.getInventory();
    } catch (_) {}

    if (!mounted) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AddItemDialog(items: items),
    );
    if (result == null) return;
    try {
      await ApiService.instance.addPoDetail(_selectedPO!['id'] as String, result);
      await _openPO(_selectedPO!['id'] as String);
      _load();
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    }
  }

  Future<void> _editQty(Map<String, dynamic> detail) async {
    if (_selectedPO == null) return;
    final ctrl = TextEditingController(
        text: (detail['approved_qty'] ?? detail['suggested_qty'] ?? '0').toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Edit Quantity: ${detail['item_name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Suggested: ${_numFmt.format(num.tryParse(detail['suggested_qty']?.toString() ?? '0') ?? 0)} '
              '${detail['unit_of_measure'] ?? ''}',
              style: const TextStyle(color: AppTheme.pinMuted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Approved Order Quantity',
                suffixText: detail['unit_of_measure']?.toString() ?? '',
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
    final qty = double.tryParse(ctrl.text.trim());
    if (qty == null || qty < 0) { _snack('Enter a valid quantity', error: true); return; }
    try {
      await ApiService.instance.updatePoDetail(
          _selectedPO!['id'] as String, detail['id'] as String, {'approved_qty': qty});
      await _openPO(_selectedPO!['id'] as String);
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    }
  }

  Future<void> _removeDetail(Map<String, dynamic> detail) async {
    if (_selectedPO == null) return;
    try {
      await ApiService.instance.removePoDetail(
          _selectedPO!['id'] as String, detail['id'] as String);
      await _openPO(_selectedPO!['id'] as String);
      _load();
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    }
  }

  Future<void> _submit() async {
    if (_selectedPO == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Submit for Approval?'),
        content: const Text(
            'This will lock quantities and send the PO to the Manager for approval. '
            'WhatsApp order links are only available after approval.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.pinTeal),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.instance.submitPO(_selectedPO!['id'] as String);
      _snack('PO submitted for approval.');
      _load();
      await _openPO(_selectedPO!['id'] as String);
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    }
  }

  Future<void> _approve() async {
    if (_selectedPO == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Approve Purchase Order?'),
        content: const Text(
            'Approving unlocks the WhatsApp send buttons so the Storekeeper '
            'can dispatch orders directly to suppliers.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.paidGreen),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.instance.approvePO(_selectedPO!['id'] as String, widget.staff.name);
      _snack('PO approved. WhatsApp ordering is now enabled.');
      _load();
      await _openPO(_selectedPO!['id'] as String);
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    }
  }

  Future<void> _sendWhatsApp(String supplierId, String supplierName,
      List<Map<String, dynamic>> items) async {
    try {
      final orderItems = items.map((d) => {
        'name':     d['item_name'],
        'quantity': _numFmt.format(num.tryParse(d['approved_qty']?.toString() ?? '0') ?? 0),
        'unit':     d['unit_of_measure'],
      }).toList();
      final data = await ApiService.instance.getOrderMessage(supplierId, orderItems,
          note: 'Approved Purchase Order');
      final url = data['whatsapp_url'] as String?;
      if (url != null && await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
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

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded, size: 48, color: AppTheme.debtRed),
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppTheme.debtRed)),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: _load,
              icon: const Icon(Icons.refresh_rounded), label: const Text('Retry')),
        ],
      ));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 800;

        if (isMobile) {
          if (_selectedPO == null) {
            return _PoListPanel(
              pos: _allPOs,
              selectedId: null,
              onSelect: _openPO,
              onRefresh: _load,
              onAutoDraft: _autoDraft,
            );
          }
          return Column(children: [
            Container(
              color: AppTheme.surface,
              padding: const EdgeInsets.only(top: 8, bottom: 8, left: 8),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => setState(() => _selectedPO = null),
                ),
                const SizedBox(width: 8),
                const Text('Back to Purchase Orders',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              ]),
            ),
            Expanded(child: _PoDetailPanel(
              po: _selectedPO!,
              staff: widget.staff,
              onAddItem: _addItem,
              onEditQty: _editQty,
              onRemove: _removeDetail,
              onSubmit: _submit,
              onApprove: _approve,
              onSendWhatsApp: _sendWhatsApp,
              onRefresh: () => _openPO(_selectedPO!['id'] as String),
            )),
          ]);
        }

        return Row(children: [
          // ── Left sidebar ──────────────────────────────────────
          SizedBox(
            width: 260,
            child: _PoListPanel(
              pos: _allPOs,
              selectedId: _selectedPO?['id'] as String?,
              onSelect: _openPO,
              onRefresh: _load,
              onAutoDraft: _autoDraft,
            ),
          ),
          // ── Detail panel ──────────────────────────────────────
          Expanded(
            child: _selectedPO == null
                ? _EmptyDetail(onAutoDraft: _autoDraft)
                : _PoDetailPanel(
                    po: _selectedPO!,
                    staff: widget.staff,
                    onAddItem: _addItem,
                    onEditQty: _editQty,
                    onRemove: _removeDetail,
                    onSubmit: _submit,
                    onApprove: _approve,
                    onSendWhatsApp: _sendWhatsApp,
                    onRefresh: () => _openPO(_selectedPO!['id'] as String),
                  ),
          ),
        ]);
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PO List Panel (left sidebar)
// ─────────────────────────────────────────────────────────────────────────────

class _PoListPanel extends StatelessWidget {
  final List<Map<String, dynamic>> pos;
  final String? selectedId;
  final void Function(String) onSelect;
  final VoidCallback onRefresh;
  final VoidCallback onAutoDraft;

  const _PoListPanel({
    required this.pos,
    required this.selectedId,
    required this.onSelect,
    required this.onRefresh,
    required this.onAutoDraft,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.sidebar,
      child: Column(children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 12, 12),
          child: Row(children: [
            const Icon(Icons.shopping_cart_rounded, color: AppTheme.pinTeal, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Purchase Orders',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: AppTheme.pinMuted, size: 18),
              onPressed: onRefresh,
              tooltip: 'Refresh',
            ),
          ]),
        ),
        // New PO button
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onAutoDraft,
              icon: const Icon(Icons.auto_awesome_rounded, size: 16),
              label: const Text('New Auto-Draft PO', style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.pinTeal,
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ),
        const Divider(color: Color(0xFF263238), height: 1),
        // PO list
        Expanded(
          child: pos.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No purchase orders yet.\nTap "New Auto-Draft PO" to get started.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.pinMuted, fontSize: 12),
                    ),
                  ))
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 4),
                  itemCount: pos.length,
                  itemBuilder: (_, i) {
                    final po = pos[i];
                    final isSelected = po['id'] == selectedId;
                    return _PoTile(po: po, selected: isSelected,
                        onTap: () => onSelect(po['id'] as String));
                  },
                ),
        ),
      ]),
    );
  }
}

class _PoTile extends StatelessWidget {
  final Map<String, dynamic> po;
  final bool selected;
  final VoidCallback onTap;
  const _PoTile({required this.po, required this.selected, required this.onTap});

  static const _statusColors = {
    'DRAFT':            Color(0xFF90A4AE),
    'PENDING_APPROVAL': Color(0xFFFFA000),
    'APPROVED':         Color(0xFF66BB6A),
    'SENT':             Color(0xFF26A69A),
  };
  static const _statusLabels = {
    'DRAFT':            'Draft',
    'PENDING_APPROVAL': 'Pending',
    'APPROVED':         'Approved',
    'SENT':             'Sent',
  };

  @override
  Widget build(BuildContext context) {
    final status     = po['status'] as String;
    final color      = _statusColors[status] ?? Colors.grey;
    final label      = _statusLabels[status] ?? status;
    final createdAt  = po['created_at'] as String? ?? '';
    final dateStr    = createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt;
    final itemCount  = po['item_count'] ?? 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: selected ? AppTheme.pinTeal.withOpacity(0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        dense: true,
        onTap: onTap,
        title: Text(dateStr,
            style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text('$itemCount item${itemCount == 1 ? '' : 's'}',
            style: const TextStyle(color: AppTheme.pinMuted, fontSize: 11)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label,
              style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PO Detail Panel (right)
// ─────────────────────────────────────────────────────────────────────────────

class _PoDetailPanel extends StatelessWidget {
  final Map<String, dynamic> po;
  final Staff staff;
  final VoidCallback onAddItem;
  final void Function(Map<String, dynamic>) onEditQty;
  final void Function(Map<String, dynamic>) onRemove;
  final VoidCallback onSubmit;
  final VoidCallback onApprove;
  final void Function(String, String, List<Map<String, dynamic>>) onSendWhatsApp;
  final VoidCallback onRefresh;

  const _PoDetailPanel({
    required this.po,
    required this.staff,
    required this.onAddItem,
    required this.onEditQty,
    required this.onRemove,
    required this.onSubmit,
    required this.onApprove,
    required this.onSendWhatsApp,
    required this.onRefresh,
  });

  static const _statusColors = {
    'DRAFT':            Color(0xFF90A4AE),
    'PENDING_APPROVAL': Color(0xFFFFA000),
    'APPROVED':         Color(0xFF66BB6A),
    'SENT':             Color(0xFF26A69A),
  };

  @override
  Widget build(BuildContext context) {
    final status      = po['status'] as String;
    final isDraft     = status == 'DRAFT';
    final isPending   = status == 'PENDING_APPROVAL';
    final isApproved  = status == 'APPROVED';
    final isSent      = status == 'SENT';
    final statusColor = _statusColors[status] ?? Colors.grey;

    final details = (po['details'] as List?)
        ?.map((e) => e as Map<String, dynamic>).toList() ?? [];

    // Group by supplier for WhatsApp send buttons
    final Map<String, List<Map<String, dynamic>>> bySupplier = {};
    for (final d in details) {
      final sid  = d['supplier_id'] as String? ?? 'no_supplier';
      final sname = d['supplier_name'] as String? ?? 'No Supplier';
      bySupplier.putIfAbsent(sid, () => []).add(d);
      // Store supplier name as a side-effect key
      bySupplier[sid]!.last['_supplier_display'] = sname;
    }

    final createdAt = po['created_at'] as String? ?? '';
    final dateStr   = createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt;

    return Column(children: [
      // ── Header ──────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.fromLTRB(24, 18, 20, 14),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
        ),
        child: Row(children: [
          const Icon(Icons.shopping_cart_rounded, color: AppTheme.pinTeal, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('PO — $dateStr',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(width: 10),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: statusColor),
                  ),
                  child: Text(status.replaceAll('_', ' '),
                      style: TextStyle(fontSize: 11, color: statusColor,
                          fontWeight: FontWeight.w700)),
                ),
              ]),
              if (po['created_by'] != null)
                Text('Created by ${po['created_by']}  ·  ${details.length} items',
                    style: const TextStyle(fontSize: 12, color: AppTheme.pinMuted)),
            ]),
          ),
          const SizedBox(width: 12),

          // ── Action buttons by status ──────────────
          if (isDraft) ...[
            OutlinedButton.icon(
              onPressed: onAddItem,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add Item'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: details.isEmpty ? null : onSubmit,
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text('Submit for Approval'),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.pinTeal),
            ),
          ],
          if (isPending && staff.canApproveRequisitions) ...[
            FilledButton.icon(
              onPressed: onApprove,
              icon: const Icon(Icons.check_circle_rounded, size: 16),
              label: const Text('Approve PO'),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.paidGreen),
            ),
          ],
          if (isPending && !staff.canApproveRequisitions)
            const Chip(
              label: Text('Awaiting Manager Approval',
                  style: TextStyle(fontSize: 12)),
              avatar: Icon(Icons.hourglass_top_rounded, size: 14),
            ),
          if (isApproved || isSent)
            const Chip(
              label: Text('Approved ✓  —  Send orders below',
                  style: TextStyle(color: Colors.white, fontSize: 12)),
              backgroundColor: AppTheme.paidGreen,
            ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: onRefresh,
            tooltip: 'Refresh',
          ),
        ]),
      ),

      // ── Explainer (Draft only) ───────────────────────────────
      if (isDraft)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          color: const Color(0xFFF3E5F5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.info_outline_rounded,
                    color: Color(0xFF7B1FA2), size: 15),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Items shown were at or below their minimum stock level. '
                  'Suggested quantities are calculated using each item\'s reorder level '
                  'and supplier lead time, so stock arrives before you run out. '
                  'Review and adjust quantities as needed, then submit for approval. '
                  'WhatsApp order links unlock once a Manager approves.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF4A148C)),
                ),
              ),
            ],
          ),
        ),

      // ── Items table ──────────────────────────────────────────
      Expanded(
        child: details.isEmpty
            ? Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.inbox_rounded, size: 56, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text('No items in this PO.',
                      style: TextStyle(color: Colors.grey.shade500)),
                  if (isDraft) ...[
                    const SizedBox(height: 8),
                    Text('Tap "Add Item" to manually add items to this order.',
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                  ],
                ]),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Table(
                    border: TableBorder.all(color: const Color(0xFFE0E0E0),
                        borderRadius: BorderRadius.circular(12)),
                    columnWidths: {
                      0: const FlexColumnWidth(2.5),  // item
                      1: const FlexColumnWidth(1.5),  // supplier
                      2: const FixedColumnWidth(60),  // uom
                      3: const FlexColumnWidth(1.0),  // in stock
                      4: const FlexColumnWidth(1.0),  // suggested qty
                      5: const FlexColumnWidth(1.0),  // approved qty
                      if (isDraft) 6: const FixedColumnWidth(80), // actions
                    },
                    children: [
                      // Header
                      TableRow(
                        decoration: const BoxDecoration(color: Color(0xFF37474F)),
                        children: [
                          _TH('Item'),
                          _TH('Supplier'),
                          _TH('UOM'),
                          _TH('In Stock'),
                          _TH('Suggested'),
                          _TH('Order Qty'),
                          if (isDraft) _TH(''),
                        ],
                      ),
                      // Rows
                      ...details.asMap().entries.map((entry) {
                        final i   = entry.key;
                        final d   = entry.value;
                        final inStock    = num.tryParse(d['quantity_in_stock']?.toString() ?? '0') ?? 0;
                        final suggested  = num.tryParse(d['suggested_qty']?.toString() ?? '0') ?? 0;
                        final approved   = num.tryParse(d['approved_qty']?.toString() ?? '0') ?? 0;

                        return TableRow(
                          decoration: BoxDecoration(
                            color: i.isEven ? Colors.white : const Color(0xFFFAFAFA),
                          ),
                          children: [
                            _TC(d['item_name']?.toString() ?? '—', bold: true),
                            _TC(d['supplier_name']?.toString() ?? '—', muted: true),
                            _TC(d['unit_of_measure']?.toString() ?? '—', muted: true),
                            _TC(_numFmt.format(inStock),
                                color: inStock <= 0 ? AppTheme.debtRed : null),
                            _TC(_numFmt.format(suggested), muted: true),
                            // Approved qty — teal badge
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppTheme.pinTeal.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(_numFmt.format(approved),
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.pinTeal)),
                                  ),
                                  if (isDraft) ...[
                                    const SizedBox(width: 4),
                                    InkWell(
                                      onTap: () => onEditQty(d),
                                      borderRadius: BorderRadius.circular(4),
                                      child: const Padding(
                                        padding: EdgeInsets.all(3),
                                        child: Icon(Icons.edit_rounded,
                                            size: 13, color: AppTheme.pinMuted),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (isDraft)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 6),
                                child: IconButton(
                                  icon: const Icon(Icons.remove_circle_outline_rounded,
                                      size: 16),
                                  color: AppTheme.debtRed,
                                  onPressed: () => onRemove(d),
                                  tooltip: 'Remove',
                                ),
                              ),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ),
      ),

      // ── WhatsApp send footer (APPROVED only) ─────────────────
      if ((isApproved || isSent) && bySupplier.isNotEmpty)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Send approved orders to suppliers via WhatsApp:',
                  style: TextStyle(fontSize: 12, color: AppTheme.pinMuted)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: bySupplier.entries.map((e) {
                  final supplierId   = e.key;
                  final supplierName = e.value.first['supplier_name'] as String? ?? 'No Supplier';
                  final count        = e.value.length;
                  return OutlinedButton.icon(
                    onPressed: supplierId == 'no_supplier'
                        ? null
                        : () => onSendWhatsApp(supplierId, supplierName, e.value),
                    icon: const Icon(Icons.chat_rounded, size: 14),
                    label: Text('$supplierName ($count items)',
                        style: const TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF25D366),
                      side: const BorderSide(color: Color(0xFF25D366)),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty detail placeholder
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyDetail extends StatelessWidget {
  final VoidCallback onAutoDraft;
  const _EmptyDetail({required this.onAutoDraft});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.shopping_cart_outlined, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No purchase order selected.',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
          const SizedBox(height: 8),
          Text('Create a new auto-draft or select one from the list.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onAutoDraft,
            icon: const Icon(Icons.auto_awesome_rounded, size: 16),
            label: const Text('New Auto-Draft PO'),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.pinTeal),
          ),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Add Item Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _AddItemDialog extends StatefulWidget {
  final List<InventoryItem> items;
  const _AddItemDialog({required this.items});

  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<_AddItemDialog> {
  InventoryItem? _picked;
  final _qtyCtrl = TextEditingController(text: '1');
  String _search = '';

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _search.isEmpty
        ? widget.items
        : widget.items
            .where((i) => i.name.toLowerCase().contains(_search.toLowerCase()))
            .toList();

    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.add_shopping_cart_rounded, color: AppTheme.pinTeal),
        SizedBox(width: 10),
        Text('Add Item to PO'),
      ]),
      content: SizedBox(
        width: 460,
        height: 400,
        child: Column(children: [
          // Search
          TextField(
            onChanged: (v) => setState(() => _search = v),
            decoration: const InputDecoration(
              hintText: 'Search inventory items…',
              prefixIcon: Icon(Icons.search_rounded, size: 18),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            ),
          ),
          const SizedBox(height: 8),
          // Item list
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final item = filtered[i];
                final isSelected = _picked?.id == item.id;
                return ListTile(
                  dense: true,
                  selected: isSelected,
                  selectedTileColor: AppTheme.pinTeal.withOpacity(0.08),
                  onTap: () => setState(() => _picked = item),
                  title: Text(item.name,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text('${item.unitOfMeasure}  ·  In stock: '
                      '${_numFmt.format(item.quantityInStock)}',
                      style: const TextStyle(fontSize: 11)),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle_rounded,
                          color: AppTheme.pinTeal, size: 18)
                      : null,
                );
              },
            ),
          ),
          if (_picked != null) ...[
            const Divider(height: 16),
            Row(children: [
              Expanded(
                child: Text('Qty to order (${_picked!.unitOfMeasure}):',
                    style: const TextStyle(fontSize: 13)),
              ),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: _qtyCtrl,
                  textAlign: TextAlign.center,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(isDense: true),
                ),
              ),
            ]),
          ],
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _picked == null ? null : () {
            final qty = double.tryParse(_qtyCtrl.text.trim()) ?? 0;
            Navigator.pop(context, {
              'inventory_item_id': _picked!.id,
              'supplier_id':       _picked!.supplierId,
              'suggested_qty':     qty,
              'approved_qty':      qty,
            });
          },
          style: FilledButton.styleFrom(backgroundColor: AppTheme.pinTeal),
          child: const Text('Add to PO'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Table cell helpers
// ─────────────────────────────────────────────────────────────────────────────

Widget _TH(String text) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
    );

Widget _TC(String text, {bool bold = false, bool muted = false, Color? color}) =>
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(text,
          style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
              color: color ?? (muted ? AppTheme.pinMuted : const Color(0xFF263238)))),
    );
