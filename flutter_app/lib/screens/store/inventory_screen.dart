import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/theme.dart';
import '../../models/inventory_item.dart';
import '../../models/staff.dart';
import '../../models/supplier.dart';
import '../../services/api.dart';
import 'cycle_count_screen.dart';

final _kes = NumberFormat.currency(locale: 'en_KE', symbol: 'KES ', decimalDigits: 0);

// Common UOM options for the form dropdown
const _uomOptions = ['kg', 'g', 'L', 'ml', 'pcs', 'dozen', 'bag', 'box', 'litre', 'bunch'];

class InventoryScreen extends StatefulWidget {
  final Staff staff;
  const InventoryScreen({super.key, required this.staff});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<InventoryItem> _items = [];
  List<Supplier> _suppliers = [];
  bool _loading = true;
  String _search = '';
  String? _categoryFilter;
  bool _reorderFilterActive = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.instance.getInventory(),
        ApiService.instance.getSuppliers(),
      ]);
      setState(() {
        _items     = results[0] as List<InventoryItem>;
        _suppliers = results[1] as List<Supplier>;
        _loading   = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      _showError(e.toString());
    }
  }

  List<InventoryItem> get _filtered {
    return _items.where((item) {
      final matchSearch = _search.isEmpty ||
          item.name.toLowerCase().contains(_search.toLowerCase()) ||
          (item.category?.toLowerCase().contains(_search.toLowerCase()) ?? false);
      final matchCat = _categoryFilter == null ||
          item.category == _categoryFilter;
      final matchReorder = !_reorderFilterActive || item.needsReorder;
      return matchSearch && matchCat && matchReorder;
    }).toList();
  }

  List<String> get _categories {
    final cats = _items.map((i) => i.category).whereType<String>().toSet().toList();
    cats.sort();
    return cats;
  }

  int get _reorderCount => _items.where((i) => i.needsReorder).length;

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

  Future<void> _showItemDialog({InventoryItem? item}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _ItemFormDialog(
        existing:  item,
        suppliers: _suppliers,
      ),
    );
    if (result == true) {
      _loadData();
      _showSuccess(item == null ? 'Item added.' : 'Item updated.');
    }
  }

  Future<void> _startCycleCount() async {
    final refreshed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CycleCountScreen()),
    );
    if (refreshed == true) _loadData();
  }

  Future<void> _showAdjustDialog(InventoryItem item) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _AdjustStockDialog(item: item, suppliers: _suppliers),
    );
    if (result == true) {
      _loadData();
      _showSuccess('Stock updated for ${item.name}.');
    }
  }

  // Phase 8: Log store-side waste / write-off for an item.
  Future<void> _showLogWasteDialog(InventoryItem item) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _LogWasteDialog(item: item, staff: widget.staff),
    );
    if (result == true) {
      _loadData();
      _showSuccess('Waste logged for ${item.name}.');
    }
  }

  Future<void> _deleteItem(InventoryItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Item'),
        content: Text('Delete "${item.name}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.debtRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ApiService.instance.deleteInventoryItem(item.id);
      _loadData();
      _showSuccess('${item.name} deleted.');
    } catch (e) {
      _showError(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ────────────────────────────────────────────
        _InventoryHeader(
          totalItems:           _items.length,
          reorderCount:         _reorderCount,
          reorderFilterActive:  _reorderFilterActive,
          onToggleReorderFilter: () => setState(() {
            _reorderFilterActive = !_reorderFilterActive;
          }),
          onAdd:                () => _showItemDialog(),
          onRefresh:            _loadData,
          canManageCycleCount:  widget.staff.canManageCycleCount,
          onCycleCount:         _startCycleCount,
        ),

        // ── Search + Filter bar ────────────────────────────────
        _FilterBar(
          categories:       _categories,
          selectedCategory: _categoryFilter,
          onSearch:         (v) => setState(() => _search = v),
          onCategoryFilter: (c) => setState(() => _categoryFilter = c),
        ),
        const Divider(height: 1),

        // ── Table ──────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? const _EmptyState()
                  : _InventoryTable(
                      items:      filtered,
                      onEdit:     _showItemDialog,
                      onAdjust:   _showAdjustDialog,
                      onLogWaste: _showLogWasteDialog,
                      onDelete:   _deleteItem,
                      canDelete:  widget.staff.canDeleteInventory,
                    ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _InventoryHeader extends StatelessWidget {
  final int totalItems;
  final int reorderCount;
  final bool reorderFilterActive;
  final VoidCallback onToggleReorderFilter;
  final VoidCallback onAdd;
  final VoidCallback onRefresh;
  final bool canManageCycleCount;
  final VoidCallback onCycleCount;

  const _InventoryHeader({
    required this.totalItems,
    required this.reorderCount,
    required this.reorderFilterActive,
    required this.onToggleReorderFilter,
    required this.onAdd,
    required this.onRefresh,
    required this.canManageCycleCount,
    required this.onCycleCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(24, 16, 16, 12),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          const Text('Inventory',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(width: 4),
          // Total items chip (static)
          _StatChip(
              label: '$totalItems items',
              color: AppTheme.primary,
              icon: Icons.inventory_2_rounded),
          // Reorder alert chip — clickable to toggle filter
          if (reorderCount > 0)
            Tooltip(
              message: reorderFilterActive
                  ? 'Showing only items needing reorder — click to clear'
                  : 'Click to filter items needing reorder',
              child: InkWell(
                onTap: onToggleReorderFilter,
                borderRadius: BorderRadius.circular(20),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: reorderFilterActive
                        ? AppTheme.debtRed
                        : AppTheme.debtRed.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: reorderFilterActive
                        ? Border.all(color: AppTheme.debtRed, width: 1.5)
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 14,
                        color: reorderFilterActive
                            ? Colors.white
                            : AppTheme.debtRed,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$reorderCount need reorder',
                        style: TextStyle(
                          color: reorderFilterActive
                              ? Colors.white
                              : AppTheme.debtRed,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (reorderFilterActive) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.close_rounded,
                            size: 14, color: Colors.white),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: onRefresh,
            tooltip: 'Refresh',
            color: AppTheme.primary,
          ),
          // Cycle count — gated by canManageCycleCount capability
          if (canManageCycleCount) ...[
            OutlinedButton.icon(
              onPressed: onCycleCount,
              icon: const Icon(Icons.fact_check_rounded, size: 18),
              label: const Text('Start Cycle Count'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF7B1FA2),
                side: const BorderSide(color: Color(0xFF7B1FA2)),
              ),
            ),
          ],
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Item'),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _StatChip({required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter bar
// ─────────────────────────────────────────────────────────────────────────────

class _FilterBar extends StatefulWidget {
  final List<String> categories;
  final String? selectedCategory;
  final void Function(String) onSearch;
  final void Function(String?) onCategoryFilter;

  const _FilterBar({
    required this.categories,
    required this.selectedCategory,
    required this.onSearch,
    required this.onCategoryFilter,
  });

  @override
  State<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<_FilterBar> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          // Search
          SizedBox(
            width: 280,
            child: TextField(
              controller: _ctrl,
              onChanged: widget.onSearch,
              decoration: InputDecoration(
                hintText: 'Search items…',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _ctrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _ctrl.clear();
                          widget.onSearch('');
                        })
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    vertical: 10, horizontal: 12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Category filter chips
          if (widget.categories.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: widget.selectedCategory == null,
                  onSelected: (_) => widget.onCategoryFilter(null),
                ),
                ...widget.categories.map((c) => FilterChip(
                      label: Text(c),
                      selected: widget.selectedCategory == c,
                      onSelected: (_) => widget.onCategoryFilter(
                          widget.selectedCategory == c ? null : c),
                    )),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Inventory Table
// ─────────────────────────────────────────────────────────────────────────────

class _InventoryTable extends StatelessWidget {
  final List<InventoryItem> items;
  final void Function({InventoryItem? item}) onEdit;
  final void Function(InventoryItem) onAdjust;
  final void Function(InventoryItem) onLogWaste;
  final void Function(InventoryItem) onDelete;
  final bool canDelete;

  const _InventoryTable({
    required this.items,
    required this.onEdit,
    required this.onAdjust,
    required this.onLogWaste,
    required this.onDelete,
    required this.canDelete,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 20,
          headingRowColor: WidgetStateProperty.all(AppTheme.scaffold),
          headingTextStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: Colors.black54,
          ),
          dataRowMinHeight: 52,
          dataRowMaxHeight: 60,
          columns: const [
            DataColumn(label: Text('ITEM')),
            DataColumn(label: Text('CATEGORY')),
            DataColumn(label: Text('IN STOCK'), numeric: true),
            DataColumn(label: Text('MIN STOCK'), numeric: true),
            DataColumn(label: Text('UOM')),
            DataColumn(label: Text('COST / UNIT'), numeric: true),
            DataColumn(label: Text('SUPPLIER')),
            DataColumn(label: Text('ACTIONS')),
          ],
          rows: items.asMap().entries.map((entry) {
            final i    = entry.key;
            final item = entry.value;
            final isLow = item.needsReorder;

            return DataRow(
              color: WidgetStateProperty.resolveWith((states) {
                if (isLow) return AppTheme.debtRed.withOpacity(0.05);
                return i.isEven ? Colors.white : AppTheme.scaffold;
              }),
              cells: [
                // Item name
                DataCell(Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isLow) ...[
                      const Icon(Icons.warning_amber_rounded,
                          color: AppTheme.debtRed, size: 16),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      item.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isLow ? AppTheme.debtRed : Colors.black87,
                      ),
                    ),
                  ],
                )),

                // Category
                DataCell(Text(item.category ?? '—',
                    style: const TextStyle(fontSize: 13))),

                // In Stock
                DataCell(Text(
                  item.quantityInStock.toStringAsFixed(
                      item.quantityInStock % 1 == 0 ? 0 : 1),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: isLow ? AppTheme.debtRed : AppTheme.paidGreen,
                  ),
                )),

                // Min Stock
                DataCell(Text(
                  item.reorderLevel != null
                      ? item.reorderLevel!.toStringAsFixed(
                          item.reorderLevel! % 1 == 0 ? 0 : 1)
                      : '—',
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                )),

                // UOM
                DataCell(Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(item.unitOfMeasure,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary)),
                )),

                // Cost
                DataCell(Text(
                  item.costPerUnit != null
                      ? _kes.format(item.costPerUnit)
                      : '—',
                  style: const TextStyle(fontSize: 13),
                )),

                // Supplier
                DataCell(Text(item.supplierName ?? '—',
                    style: const TextStyle(fontSize: 13))),

                // Actions
                DataCell(Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Edit
                    _ActionBtn(
                      icon: Icons.edit_rounded,
                      tooltip: 'Edit item',
                      color: Colors.blueGrey,
                      onTap: () => onEdit(item: item),
                    ),
                    // Receive Stock
                    _ActionBtn(
                      icon: Icons.add_circle_rounded,
                      tooltip: 'Adjust Stock / Receive Delivery',
                      color: AppTheme.paidGreen,
                      onTap: () => onAdjust(item),
                    ),
                    // Log Waste (Phase 8)
                    _ActionBtn(
                      icon: Icons.delete_sweep_rounded,
                      tooltip: 'Log Waste / Write-off',
                      color: Colors.orange.shade700,
                      onTap: () => onLogWaste(item),
                    ),
                    // Delete (gated by canDeleteInventory)
                    if (canDelete)
                      _ActionBtn(
                        icon: Icons.delete_outline_rounded,
                        tooltip: 'Delete item',
                        color: AppTheme.debtRed,
                        onTap: () => onDelete(item),
                      ),
                  ],
                )),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn(
      {required this.icon,
      required this.tooltip,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialogs
// ─────────────────────────────────────────────────────────────────────────────

class _ItemFormDialog extends StatefulWidget {
  final InventoryItem? existing;
  final List<Supplier> suppliers;
  const _ItemFormDialog({this.existing, required this.suppliers});

  @override
  State<_ItemFormDialog> createState() => _ItemFormDialogState();
}

class _ItemFormDialogState extends State<_ItemFormDialog> {
  final _formKey   = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _categoryCtrl;
  late TextEditingController _qtyCtrl;
  late TextEditingController _reorderCtrl;
  late TextEditingController _costCtrl;
  late TextEditingController _notesCtrl;
  String _uom = 'kg';
  String? _supplierId;
  String? _defaultPurchaserId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    _nameCtrl     = TextEditingController(text: s?.name ?? '');
    _categoryCtrl = TextEditingController(text: s?.category ?? '');
    _qtyCtrl      = TextEditingController(
        text: s != null ? s.quantityInStock.toStringAsFixed(
            s.quantityInStock % 1 == 0 ? 0 : 1) : '0');
    _reorderCtrl  = TextEditingController(
        text: s?.reorderLevel?.toStringAsFixed(
            (s.reorderLevel ?? 0) % 1 == 0 ? 0 : 1) ?? '');
    _costCtrl     = TextEditingController(
        text: s?.costPerUnit?.toStringAsFixed(2) ?? '');
    _notesCtrl    = TextEditingController(text: s?.notes ?? '');
    _uom                 = s?.unitOfMeasure ?? 'kg';
    _supplierId          = s?.supplierId;
    _defaultPurchaserId  = s?.defaultPurchaserId;
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl, _categoryCtrl, _qtyCtrl,
      _reorderCtrl, _costCtrl, _notesCtrl
    ]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final body = {
      'name':             _nameCtrl.text.trim(),
      'category':         _categoryCtrl.text.trim().isEmpty ? null : _categoryCtrl.text.trim(),
      'unit_of_measure':  _uom,
      'quantity_in_stock': double.tryParse(_qtyCtrl.text.trim()) ?? 0,
      'reorder_level':    _reorderCtrl.text.trim().isEmpty ? null : double.tryParse(_reorderCtrl.text.trim()),
      'cost_per_unit':    _costCtrl.text.trim().isEmpty ? null : double.tryParse(_costCtrl.text.trim()),
      'supplier_id':           _supplierId,
      'default_purchaser_id':  _defaultPurchaserId,
      'notes':                 _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    };

    try {
      if (widget.existing == null) {
        await ApiService.instance.createInventoryItem(body);
      } else {
        await ApiService.instance.updateInventoryItem(widget.existing!.id, body);
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
      title: Row(
        children: [
          Icon(isEdit ? Icons.edit_rounded : Icons.add_circle_rounded,
              color: AppTheme.primary),
          const SizedBox(width: 10),
          Text(isEdit ? 'Edit Inventory Item' : 'Add Inventory Item'),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Name
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Item Name *',
                      prefixIcon: Icon(Icons.inventory_2_rounded)),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Name is required' : null,
                ),
                const SizedBox(height: 12),
                // Category
                TextFormField(
                  controller: _categoryCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Category',
                      hintText: 'e.g. Poultry, Produce, Dry Goods',
                      prefixIcon: Icon(Icons.label_rounded)),
                ),
                const SizedBox(height: 12),
                // UOM row
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: _uom,
                        decoration: const InputDecoration(
                            labelText: 'Unit of Measure *',
                            prefixIcon: Icon(Icons.straighten_rounded)),
                        items: _uomOptions
                            .map((u) => DropdownMenuItem(
                                value: u, child: Text(u)))
                            .toList(),
                        onChanged: (v) => setState(() => _uom = v!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Current qty
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _qtyCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Current Quantity',
                            prefixIcon: Icon(Icons.numbers_rounded)),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    // Min stock / Reorder level
                    Expanded(
                      child: TextFormField(
                        controller: _reorderCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Min Stock (Reorder Level)',
                            hintText: 'Alert below this',
                            prefixIcon: Icon(Icons.warning_amber_rounded)),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Cost per unit
                    Expanded(
                      child: TextFormField(
                        controller: _costCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Cost per Unit (KES)',
                            prefixIcon: Icon(Icons.attach_money_rounded)),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Supplier dropdown (external suppliers)
                DropdownButtonFormField<String?>(
                  value: _supplierId,
                  decoration: const InputDecoration(
                      labelText: 'Supplier (optional)',
                      prefixIcon: Icon(Icons.people_alt_rounded)),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('No supplier')),
                    ...widget.suppliers
                        .where((s) => !s.isInternal)
                        .map((s) => DropdownMenuItem(
                            value: s.id, child: Text(s.name))),
                  ],
                  onChanged: (v) => setState(() => _supplierId = v),
                ),
                const SizedBox(height: 12),
                // Default Purchaser dropdown (internal suppliers only)
                DropdownButtonFormField<String?>(
                  value: _defaultPurchaserId,
                  decoration: const InputDecoration(
                      labelText: 'Default Purchaser (who buys this item)',
                      hintText: 'Assign to a manager expense account',
                      prefixIcon: Icon(Icons.account_balance_wallet_rounded)),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('— Unassigned —')),
                    ...widget.suppliers
                        .where((s) => s.isInternal)
                        .map((s) => DropdownMenuItem(
                            value: s.id, child: Text(s.name))),
                  ],
                  onChanged: (v) => setState(() => _defaultPurchaserId = v),
                ),
                const SizedBox(height: 12),
                // Notes
                TextFormField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
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
                  width: 20, height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(isEdit ? 'Update' : 'Add Item'),
        ),
      ],
    );
  }
}

// ── Adjust Stock Dialog ──────────────────────────────────────────────────────

class _AdjustStockDialog extends StatefulWidget {
  final InventoryItem item;
  final List<Supplier> suppliers;
  const _AdjustStockDialog({required this.item, required this.suppliers});

  @override
  State<_AdjustStockDialog> createState() => _AdjustStockDialogState();
}

class _AdjustStockDialogState extends State<_AdjustStockDialog> {
  final _amountCtrl    = TextEditingController();
  final _reasonCtrl    = TextEditingController();
  final _totalCostCtrl = TextEditingController();
  bool    _isDelivery  = true;
  String? _supplierId;
  bool    _saving      = false;

  @override
  void initState() {
    super.initState();
    // Pre-select the item's default supplier
    _supplierId = widget.item.supplierId;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _reasonCtrl.dispose();
    _totalCostCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amt = double.tryParse(_amountCtrl.text.trim());
    if (amt == null || amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enter a valid positive amount')));
      return;
    }
    // If delivery mode, validate invoice cost is provided
    double? totalCost;
    if (_isDelivery) {
      totalCost = double.tryParse(_totalCostCtrl.text.trim());
      if (totalCost == null || totalCost <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Enter the total invoice cost (KES) for this delivery')));
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final delta = _isDelivery ? amt : -amt;

      // Compute new cost per unit from invoice total ÷ quantity received.
      // This lets the backend detect price changes and advise on POS margin impact.
      double? newCostPerUnit;
      if (_isDelivery && totalCost != null && amt > 0) {
        newCostPerUnit = totalCost / amt;
      }

      await ApiService.instance.adjustStock(
        widget.item.id,
        delta,
        reason:         _reasonCtrl.text.trim(),
        supplierId:     _isDelivery ? _supplierId : null,
        totalCost:      _isDelivery ? totalCost   : null,
        newCostPerUnit: newCostPerUnit,
      );

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.debtRed));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentStock = widget.item.quantityInStock;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.move_to_inbox_rounded, color: AppTheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Adjust Stock: ${widget.item.name}',
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Current stock indicator
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.scaffold,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.inventory_2_rounded,
                        color: Colors.grey.shade600, size: 18),
                    const SizedBox(width: 8),
                    Text('Current stock:  ',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                    Text(
                      '${currentStock.toStringAsFixed(currentStock % 1 == 0 ? 0 : 1)} '
                      '${widget.item.unitOfMeasure}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Type toggle
              Row(
                children: [
                  Expanded(
                    child: _TypeToggle(
                      label:    'Receive Delivery',
                      icon:     Icons.add_circle_rounded,
                      selected: _isDelivery,
                      color:    AppTheme.paidGreen,
                      onTap:    () => setState(() => _isDelivery = true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TypeToggle(
                      label:    'Correction / Removal',
                      icon:     Icons.remove_circle_rounded,
                      selected: !_isDelivery,
                      color:    AppTheme.debtRed,
                      onTap:    () => setState(() => _isDelivery = false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Amount field
              TextFormField(
                controller: _amountCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText:  'Amount (${widget.item.unitOfMeasure})',
                  prefixIcon: Icon(
                    _isDelivery ? Icons.add_rounded : Icons.remove_rounded,
                    color: _isDelivery ? AppTheme.paidGreen : AppTheme.debtRed,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: _isDelivery ? AppTheme.paidGreen : AppTheme.debtRed,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),

              // ── Delivery-only fields ────────────────────────────
              if (_isDelivery) ...[
                // Supplier dropdown
                DropdownButtonFormField<String?>(
                  value: _supplierId,
                  decoration: const InputDecoration(
                    labelText: 'Supplier (for debt tracking)',
                    prefixIcon: Icon(Icons.people_alt_rounded),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('— No supplier / cash purchase —',
                            style: TextStyle(color: Colors.grey))),
                    ...widget.suppliers.map((s) =>
                        DropdownMenuItem<String?>(value: s.id, child: Text(s.name))),
                  ],
                  onChanged: (v) => setState(() => _supplierId = v),
                ),
                const SizedBox(height: 12),
                // Invoice cost
                TextFormField(
                  controller: _totalCostCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Total Invoice Cost (KES) *',
                    hintText: 'e.g. 4500',
                    prefixIcon: Icon(Icons.receipt_long_rounded),
                    prefixText: 'KES ',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 6),
                // Explainer
                if (_supplierId != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: const [
                      Icon(Icons.link_rounded, size: 14, color: AppTheme.paidGreen),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Invoice cost will be added to the supplier\'s debt automatically.',
                          style: TextStyle(fontSize: 11, color: Color(0xFF2E7D32)),
                        ),
                      ),
                    ]),
                  ),
                const SizedBox(height: 12),
              ],

              // Reason / reference
              TextFormField(
                controller: _reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Invoice Ref / Notes (optional)',
                  hintText: 'e.g. Invoice #1234, Morning delivery',
                  prefixIcon: Icon(Icons.notes_rounded),
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
          style: ElevatedButton.styleFrom(
            backgroundColor: _isDelivery ? AppTheme.paidGreen : AppTheme.debtRed,
          ),
          child: _saving
              ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(_isDelivery ? 'Add to Stock' : 'Deduct Stock'),
        ),
      ],
    );
  }
}

class _TypeToggle extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _TypeToggle({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.1) : AppTheme.scaffold,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? color : Colors.grey, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.normal,
                  color: selected ? color : Colors.grey,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_rounded, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No inventory items yet.',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade500)),
          const SizedBox(height: 8),
          Text('Click "Add Item" to get started.',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade400)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Phase 8: Log Waste Dialog (Store-side)
// Records expired / spoiled / ruined stock and deducts it from inventory.
// ─────────────────────────────────────────────────────────────────────────────

class _LogWasteDialog extends StatefulWidget {
  final InventoryItem item;
  final Staff staff;
  const _LogWasteDialog({required this.item, required this.staff});

  @override
  State<_LogWasteDialog> createState() => _LogWasteDialogState();
}

class _LogWasteDialogState extends State<_LogWasteDialog> {
  final _formKey  = GlobalKey<FormState>();
  final _qtyCtrl  = TextEditingController(text: '1');
  final _noteCtrl = TextEditingController();
  bool _saving    = false;

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final qty = double.parse(_qtyCtrl.text.trim());
    if (qty > widget.item.quantityInStock) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Cannot write off more than in stock '
            '(${widget.item.quantityInStock.toStringAsFixed(1)} ${widget.item.unitOfMeasure}).'),
        backgroundColor: AppTheme.debtRed,
      ));
      return;
    }
    setState(() => _saving = true);
    try {
      await ApiService.instance.logWaste(
        inventoryItemId:   widget.item.id,
        quantity:          qty,
        loggedBy:          widget.staff.name,
        notes:             _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        requesterLocation: widget.staff.locationName,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: AppTheme.debtRed,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final item   = widget.item;
    final inStock = item.quantityInStock;

    return AlertDialog(
      title: Row(children: [
        Icon(Icons.delete_sweep_rounded, color: Colors.orange.shade700),
        const SizedBox(width: 10),
        Expanded(child: Text('Log Waste: ${item.name}',
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
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(children: [
                  Icon(Icons.inventory_2_rounded,
                      size: 16, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Text(
                    'In Stock: ${inStock.toStringAsFixed(inStock % 1 == 0 ? 0 : 1)} ${item.unitOfMeasure}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange.shade800),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _qtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Waste Quantity (${item.unitOfMeasure})',
                  prefixIcon: const Icon(Icons.remove_circle_outline_rounded),
                  focusedBorder: OutlineInputBorder(
                    borderSide:
                        BorderSide(color: Colors.orange.shade700, width: 2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  final n = double.tryParse(v);
                  if (n == null || n <= 0) return 'Enter a positive number';
                  if (n > inStock) return 'Cannot exceed stock (${inStock.toStringAsFixed(1)})';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Reason / Notes (optional)',
                  prefixIcon: Icon(Icons.notes_rounded),
                  hintText: 'e.g. Expired, Spilled, Damaged',
                ),
                maxLines: 2,
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
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Log Waste'),
        ),
      ],
    );
  }
}
