import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/theme.dart';
import '../../models/staff.dart';
import '../../services/api.dart';

final _kespo = NumberFormat.currency(locale: 'en_KE', symbol: 'KES ', decimalDigits: 2);
final _numFmt = NumberFormat('0.###');

/// Purchase Orders screen — shows auto-drafted PO items and lets the
/// Store Keeper submit / Manager approve them for WhatsApp ordering.
class PurchaseOrdersScreen extends StatefulWidget {
  final Staff staff;
  const PurchaseOrdersScreen({super.key, required this.staff});

  @override
  State<PurchaseOrdersScreen> createState() => _PurchaseOrdersScreenState();
}

class _PurchaseOrdersScreenState extends State<PurchaseOrdersScreen> {
  List<Map<String, dynamic>> _items = [];
  final Map<String, bool> _selected = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await ApiService.instance.getDraftPO();
      setState(() {
        _items = data;
        // Default-select all
        for (final item in data) {
          _selected[item['id'] as String] = true;
        }
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // Group selected items by supplier
  Map<String, List<Map<String, dynamic>>> get _bySupplier {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final item in _items) {
      if (_selected[item['id'] as String] != true) continue;
      final supplierId   = item['supplier_id'] as String? ?? 'no_supplier';
      final supplierName = item['supplier_name'] as String? ?? 'No Supplier';
      grouped.putIfAbsent(supplierId, () => []).add(item);
    }
    return grouped;
  }

  Future<void> _sendOrderForSupplier(
      String supplierId, String supplierName, List<Map<String, dynamic>> items) async {
    try {
      final orderItems = items.map((item) => {
        'name':     item['name'],
        'quantity': _numFmt.format(num.tryParse(item['suggested_order_qty']?.toString() ?? '0') ?? 0),
        'unit':     item['unit_of_measure'],
      }).toList();

      final data = await ApiService.instance.getOrderMessage(supplierId, orderItems,
          note: 'Auto-generated Purchase Order — Lead Time: ${_leadLabel(items.first)}');

      final url = data['whatsapp_url'] as String?;
      if (url != null && await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    }
  }

  String _leadLabel(Map<String, dynamic> item) {
    final lt = item['lead_time_days'];
    if (lt == null) return 'N/A';
    return '${lt} day${lt == 1 ? '' : 's'}';
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppTheme.debtRed : AppTheme.paidGreen,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _selected.values.where((v) => v).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(28, 20, 20, 16),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
          ),
          child: Row(
            children: [
              const Icon(Icons.shopping_cart_rounded,
                  color: AppTheme.pinTeal, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Purchase Orders',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    Text(
                      _loading
                          ? 'Computing auto-draft…'
                          : '${_items.length} item${_items.length == 1 ? '' : 's'} need restocking · $selectedCount selected',
                      style: const TextStyle(fontSize: 12, color: AppTheme.pinMuted),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Recalculate'),
              ),
              if (selectedCount > 0) ...[
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _sendAllWhatsApp,
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: Text('Send Orders ($selectedCount items)'),
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.pinTeal),
                ),
              ],
            ],
          ),
        ),

        // ── Explainer ─────────────────────────────────────────
        if (!_loading && _error == null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
            color: const Color(0xFFF3E5F5),
            child: Row(children: const [
              Icon(Icons.auto_awesome_rounded, color: Color(0xFF7B1FA2), size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Items appear here when: Current Stock ≤ Reorder Level + (Daily Usage × Lead Time Days). '
                  'Check boxes to include in WhatsApp orders, grouped by supplier.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF4A148C)),
                ),
              ),
            ]),
          ),

        // ── Content ───────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _ErrorView(error: _error!, onRetry: _load)
                  : _items.isEmpty
                      ? _EmptyView()
                      : _PoTable(
                          items: _items,
                          selected: _selected,
                          onToggle: (id, val) =>
                              setState(() => _selected[id] = val),
                          onSelectAll: (val) => setState(() {
                            for (final item in _items) {
                              _selected[item['id'] as String] = val;
                            }
                          }),
                        ),
        ),

        // ── Per-supplier Send buttons ──────────────────────────
        if (!_loading && _error == null && _bySupplier.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
            ),
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              children: _bySupplier.entries.map((e) {
                final supplierId   = e.key;
                final supplierName = e.value.first['supplier_name'] as String? ?? 'No Supplier';
                return OutlinedButton.icon(
                  onPressed: () =>
                      _sendOrderForSupplier(supplierId, supplierName, e.value),
                  icon: const Icon(Icons.chat_rounded, size: 14),
                  label: Text('Order from $supplierName (${e.value.length})',
                      style: const TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF25D366),
                    side: const BorderSide(color: Color(0xFF25D366)),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Future<void> _sendAllWhatsApp() async {
    final grouped = _bySupplier;
    if (grouped.isEmpty) return;

    for (final entry in grouped.entries) {
      await _sendOrderForSupplier(entry.key,
          entry.value.first['supplier_name'] as String? ?? 'Supplier',
          entry.value);
      // Small delay between multiple WhatsApp opens
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }
}

// ── PO Table ───────────────────────────────────────────────────────────────

class _PoTable extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final Map<String, bool> selected;
  final void Function(String, bool) onToggle;
  final void Function(bool) onSelectAll;

  const _PoTable({
    required this.items,
    required this.selected,
    required this.onToggle,
    required this.onSelectAll,
  });

  @override
  Widget build(BuildContext context) {
    final allSelected = items.every((i) => selected[i['id'] as String] == true);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Table(
          border: TableBorder.all(
            color: const Color(0xFFE0E0E0),
            borderRadius: BorderRadius.circular(12),
          ),
          columnWidths: const {
            0: FixedColumnWidth(48),    // checkbox
            1: FlexColumnWidth(2.5),   // item
            2: FlexColumnWidth(1.2),   // supplier
            3: FlexColumnWidth(0.9),   // uom
            4: FlexColumnWidth(1.0),   // current stock
            5: FlexColumnWidth(1.0),   // reorder level
            6: FlexColumnWidth(1.0),   // daily usage
            7: FlexColumnWidth(0.9),   // lead time
            8: FlexColumnWidth(1.2),   // order qty
          },
          children: [
            // Header
            TableRow(
              decoration: const BoxDecoration(color: Color(0xFF37474F)),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Checkbox(
                    value: allSelected,
                    onChanged: (v) => onSelectAll(v ?? false),
                    fillColor: WidgetStateProperty.all(AppTheme.pinTeal),
                  ),
                ),
                _TH('Item'),
                _TH('Supplier'),
                _TH('UOM'),
                _TH('In Stock'),
                _TH('Min Level'),
                _TH('Daily Use'),
                _TH('Lead (days)'),
                _TH('Order Qty'),
              ],
            ),
            // Data rows
            ...items.asMap().entries.map((entry) {
              final i    = entry.key;
              final item = entry.value;
              final id   = item['id'] as String;
              final isSelected = selected[id] == true;
              final currentStock = num.tryParse(item['quantity_in_stock']?.toString() ?? '0') ?? 0;
              final reorderLevel = num.tryParse(item['reorder_level']?.toString() ?? '0') ?? 0;
              final dailyUsage   = num.tryParse(item['daily_usage']?.toString() ?? '0') ?? 0;
              final leadTime     = item['lead_time_days'];
              final orderQty     = num.tryParse(item['suggested_order_qty']?.toString() ?? '0') ?? 0;

              final rowBg = isSelected
                  ? AppTheme.pinTeal.withOpacity(0.04)
                  : (i.isEven ? Colors.white : const Color(0xFFFAFAFA));

              return TableRow(
                decoration: BoxDecoration(color: rowBg),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Checkbox(
                      value: isSelected,
                      onChanged: (v) => onToggle(id, v ?? false),
                      fillColor: WidgetStateProperty.all(AppTheme.pinTeal),
                    ),
                  ),
                  _TC(item['name']?.toString() ?? '—', bold: true),
                  _TC(item['supplier_name']?.toString() ?? '—', muted: true),
                  _TC(item['unit_of_measure']?.toString() ?? '—', muted: true),
                  _TC(_numFmt.format(currentStock),
                      color: currentStock <= 0 ? AppTheme.debtRed : null),
                  _TC(_numFmt.format(reorderLevel)),
                  _TC(_numFmt.format(dailyUsage), muted: true),
                  _TC(leadTime?.toString() ?? '—', muted: true),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.pinTeal.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(_numFmt.format(orderQty),
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.pinTeal)),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}

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

// ── Empty / Error ──────────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_rounded, size: 72, color: Colors.green.shade200),
          const SizedBox(height: 16),
          Text('All stock levels are healthy!',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade500)),
          const SizedBox(height: 8),
          Text('No items are currently below their reorder threshold.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded, size: 56, color: AppTheme.debtRed),
          const SizedBox(height: 12),
          Text(error, style: const TextStyle(color: AppTheme.debtRed)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry')),
        ],
      ),
    );
  }
}
