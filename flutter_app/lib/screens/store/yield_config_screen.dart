import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/inventory_item.dart';
import '../../models/pos_product.dart';
import '../../models/yield_config.dart';
import '../../services/api.dart';

class YieldConfigScreen extends StatefulWidget {
  const YieldConfigScreen({super.key});

  @override
  State<YieldConfigScreen> createState() => _YieldConfigScreenState();
}

class _YieldConfigScreenState extends State<YieldConfigScreen> {
  List<YieldConfig>    _configs    = [];
  List<InventoryItem>  _inventory  = [];
  List<PosProduct>     _products   = [];
  bool _loading = true;
  bool _posError = false; // true if POS products couldn't be loaded

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      // Load all three in parallel; POS products may fail if DB has no data yet
      final results = await Future.wait([
        ApiService.instance.getYieldConfigs(),
        ApiService.instance.getInventory(),
        ApiService.instance.getPosProducts().catchError((_) => <PosProduct>[]),
      ]);
      setState(() {
        _configs   = results[0] as List<YieldConfig>;
        _inventory = results[1] as List<InventoryItem>;
        _products  = results[2] as List<PosProduct>;
        _posError  = _products.isEmpty;
        _loading   = false;
      });
    } catch (e) {
      setState(() => _loading = false);
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

  Future<void> _showAddDialog() async {
    if (_inventory.isEmpty) {
      _showError('Add inventory items first before creating yield configs.');
      return;
    }
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _YieldFormDialog(
        inventory: _inventory,
        products:  _products,
        posError:  _posError,
      ),
    );
    if (result == true) {
      await _loadAll();
      _showSuccess('Yield config saved.');
    }
  }

  Future<void> _editConfig(YieldConfig cfg) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _YieldFormDialog(
        inventory:  _inventory,
        products:   _products,
        posError:   _posError,
        existing:   cfg,
      ),
    );
    if (result == true) {
      await _loadAll();
      _showSuccess('Yield config updated.');
    }
  }

  Future<void> _deleteConfig(YieldConfig cfg) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Yield Config'),
        content: Text('Delete the mapping for "${cfg.inventoryItemName}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.debtRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ApiService.instance.deleteYieldConfig(cfg.id);
      await _loadAll();
      _showSuccess('Config deleted.');
    } catch (e) {
      _showError(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ────────────────────────────────────────────
        Container(
          color: AppTheme.surface,
          padding: const EdgeInsets.fromLTRB(24, 16, 16, 12),
          child: Row(
            children: [
              const Text('Yield Configuration',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _loadAll,
                tooltip: 'Refresh',
                color: AppTheme.primary,
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _showAddDialog,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Mapping'),
              ),
            ],
          ),
        ),

        // ── Explainer banner ──────────────────────────────────
        _ExplainerBanner(posError: _posError),

        const Divider(height: 1),

        // ── Config grid / list ────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _configs.isEmpty
                  ? _EmptyYieldState(onAdd: _showAddDialog)
                  : _ConfigGrid(
                      configs:   _configs,
                      onEdit:    _editConfig,
                      onDelete:  _deleteConfig,
                    ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Explainer Banner
// ─────────────────────────────────────────────────────────────────────────────

class _ExplainerBanner extends StatelessWidget {
  final bool posError;
  const _ExplainerBanner({required this.posError});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF0F7F4),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  color: AppTheme.primary, size: 18),
              const SizedBox(width: 8),
              const Text('How Yield Config works',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary,
                      fontSize: 13)),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Map each bulk store ingredient to a POS menu item with a portion multiplier. '
            'The system then calculates: "We sold X Chicken Portions today, '
            'so we should have used X ÷ 8 = Y kg of Whole Chicken from the store." '
            'Compare Y to actual issues to spot wastage or theft.',
            style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.5),
          ),
          if (posError) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppTheme.secondary, size: 16),
                const SizedBox(width: 6),
                const Text(
                  'POS products could not be loaded. '
                  'Ensure the POS database has products and the DB connection is active.',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.secondary,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Config Grid
// ─────────────────────────────────────────────────────────────────────────────

class _ConfigGrid extends StatelessWidget {
  final List<YieldConfig> configs;
  final void Function(YieldConfig) onEdit;
  final void Function(YieldConfig) onDelete;

  const _ConfigGrid(
      {required this.configs, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: configs.map((c) => _ConfigCard(
          config:   c,
          onEdit:   () => onEdit(c),
          onDelete: () => onDelete(c),
        )).toList(),
      ),
    );
  }
}

class _ConfigCard extends StatelessWidget {
  final YieldConfig config;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ConfigCard({
    required this.config,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: SizedBox(
        width: 320,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Store item → POS product arrow ────────────
              Row(
                children: [
                  // Store ingredient
                  Expanded(
                    child: _ItemPill(
                      label: config.inventoryItemName,
                      sub:   '1 ${config.unitOfMeasure}',
                      color: AppTheme.primary,
                      icon:  Icons.inventory_2_rounded,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Icon(Icons.arrow_forward_rounded,
                        color: Colors.grey.shade400, size: 20),
                  ),
                  // POS product
                  Expanded(
                    child: _ItemPill(
                      label: config.posProductName ?? 'POS Product',
                      sub:   '× ${config.portionsPerUnit % 1 == 0 ? config.portionsPerUnit.toInt() : config.portionsPerUnit} portions',
                      color: AppTheme.secondary,
                      icon:  Icons.restaurant_menu_rounded,
                    ),
                  ),
                ],
              ),

              // ── Summary sentence ──────────────────────────
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.scaffold,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  config.summary,
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      fontStyle: FontStyle.italic),
                ),
              ),

              if (config.notes != null && config.notes!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(config.notes!,
                    style: const TextStyle(
                        fontSize: 11, color: Colors.black45)),
              ],

              // ── Actions ────────────────────────────────────
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    label: const Text('Edit'),
                    style: TextButton.styleFrom(
                        foregroundColor: AppTheme.primary),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    label: const Text('Delete'),
                    style: TextButton.styleFrom(
                        foregroundColor: AppTheme.debtRed),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemPill extends StatelessWidget {
  final String label;
  final String sub;
  final Color color;
  final IconData icon;

  const _ItemPill({
    required this.label,
    required this.sub,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: Colors.black87),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          Text(sub,
              style: TextStyle(fontSize: 11, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Yield Form Dialog (Add / Edit)
// ─────────────────────────────────────────────────────────────────────────────

class _YieldFormDialog extends StatefulWidget {
  final List<InventoryItem> inventory;
  final List<PosProduct>    products;
  final bool                posError;
  final YieldConfig?        existing;

  const _YieldFormDialog({
    required this.inventory,
    required this.products,
    required this.posError,
    this.existing,
  });

  @override
  State<_YieldFormDialog> createState() => _YieldFormDialogState();
}

class _YieldFormDialogState extends State<_YieldFormDialog> {
  final _formKey        = GlobalKey<FormState>();
  final _portionsCtrl   = TextEditingController();
  final _notesCtrl      = TextEditingController();
  final _manualProdCtrl = TextEditingController(); // fallback if POS empty

  String? _selectedInventoryId;
  String? _selectedProductId;
  bool    _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _selectedInventoryId = e.inventoryItemId;
      _selectedProductId   = e.unicentaProductId;
      _portionsCtrl.text   = e.portionsPerUnit
          .toStringAsFixed(e.portionsPerUnit % 1 == 0 ? 0 : 1);
      _notesCtrl.text      = e.notes ?? '';
      if (widget.posError) _manualProdCtrl.text = e.unicentaProductId;
    }
  }

  @override
  void dispose() {
    _portionsCtrl.dispose();
    _notesCtrl.dispose();
    _manualProdCtrl.dispose();
    super.dispose();
  }

  // Selected inventory item for preview
  InventoryItem? get _pickedItem => _selectedInventoryId == null
      ? null
      : widget.inventory.where((i) => i.id == _selectedInventoryId).firstOrNull;

  // Selected POS product for preview
  PosProduct? get _pickedProduct => _selectedProductId == null
      ? null
      : widget.products.where((p) => p.id == _selectedProductId).firstOrNull;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final productId = widget.posError
        ? _manualProdCtrl.text.trim()
        : _selectedProductId;
    if (_selectedInventoryId == null || (productId == null || productId.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Select both a store item and a POS product.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final body = {
        'inventory_item_id':   _selectedInventoryId,
        'unicenta_product_id': productId,
        'portions_per_unit':   double.parse(_portionsCtrl.text.trim()),
        'notes':               _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      };
      if (widget.existing == null) {
        await ApiService.instance.createYieldConfig(body);
      } else {
        await ApiService.instance.updateYieldConfig(widget.existing!.id, body);
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
          const Icon(Icons.tune_rounded, color: AppTheme.primary),
          const SizedBox(width: 10),
          Text(isEdit ? 'Edit Yield Mapping' : 'Add Yield Mapping'),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Step 1: Store Ingredient ───────────────────
                const _StepLabel(step: '1', label: 'Bulk Store Ingredient'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedInventoryId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Select store item',
                    prefixIcon: Icon(Icons.inventory_2_rounded),
                  ),
                  items: widget.inventory.map((item) => DropdownMenuItem(
                    value: item.id,
                    child: Text('${item.name}  (${item.unitOfMeasure})',
                        overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: (v) => setState(() => _selectedInventoryId = v),
                  validator: (v) => v == null ? 'Required' : null,
                ),
                const SizedBox(height: 16),

                // ── Step 2: POS Menu Item ──────────────────────
                const _StepLabel(step: '2', label: 'POS Menu Item (sold to customers)'),
                const SizedBox(height: 8),
                if (widget.posError)
                  TextFormField(
                    controller: _manualProdCtrl,
                    decoration: const InputDecoration(
                      labelText: 'POS Product UUID (manual entry)',
                      hintText: 'Copy from uniCenta products table',
                      prefixIcon: Icon(Icons.restaurant_menu_rounded),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Required' : null,
                  )
                else
                  // Autocomplete for large POS product lists
                  Autocomplete<PosProduct>(
                    initialValue: TextEditingValue(
                      text: _pickedProduct?.displayLabel ?? '',
                    ),
                    optionsBuilder: (TextEditingValue tv) {
                      if (tv.text.isEmpty) return widget.products;
                      final q = tv.text.toLowerCase();
                      return widget.products.where(
                          (p) => p.displayLabel.toLowerCase().contains(q));
                    },
                    displayStringForOption: (p) => p.displayLabel,
                    onSelected: (p) =>
                        setState(() => _selectedProductId = p.id),
                    fieldViewBuilder: (ctx, ctrl, focusNode, onFieldSubmitted) {
                      return TextFormField(
                        controller: ctrl,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          labelText: 'Search POS product…',
                          prefixIcon: Icon(Icons.restaurant_menu_rounded),
                          hintText: 'Type to filter',
                        ),
                        validator: (_) =>
                            _selectedProductId == null ? 'Required' : null,
                      );
                    },
                    optionsViewBuilder: (ctx, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(8),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                                maxHeight: 220, maxWidth: 460),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (_, i) {
                                final p = options.elementAt(i);
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(
                                      Icons.restaurant_menu_rounded,
                                      size: 16),
                                  title: Text(p.displayLabel,
                                      style: const TextStyle(fontSize: 13)),
                                  onTap: () => onSelected(p),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 16),

                // ── Step 3: Portions ───────────────────────────
                const _StepLabel(
                    step: '3', label: 'Portions per unit of store ingredient'),
                const SizedBox(height: 4),
                Text(
                  'How many POS portions does 1 unit of the store item produce?',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _portionsCtrl,
                  autofocus: !isEdit,
                  decoration: InputDecoration(
                    labelText: 'Portions per unit',
                    hintText: 'e.g. 8  (1 whole chicken = 8 portions)',
                    prefixIcon: const Icon(Icons.format_list_numbered_rounded),
                    suffix: _pickedItem != null
                        ? Text('per ${_pickedItem!.unitOfMeasure}',
                            style: TextStyle(
                                color: Colors.grey.shade500, fontSize: 12))
                        : null,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    final n = double.tryParse(v.trim());
                    if (n == null || n <= 0) return 'Enter a positive number';
                    return null;
                  },
                ),

                // ── Live preview ───────────────────────────────
                if (_pickedItem != null ||
                    _pickedProduct != null ||
                    _portionsCtrl.text.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _PreviewBox(
                    itemName:     _pickedItem?.name ?? '…',
                    itemUom:      _pickedItem?.unitOfMeasure ?? '',
                    productName:  _pickedProduct?.name ??
                        (_manualProdCtrl.text.trim().isEmpty ? '…' : _manualProdCtrl.text.trim()),
                    portionsText: _portionsCtrl.text.trim(),
                  ),
                ],

                const SizedBox(height: 14),
                // Notes
                TextFormField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
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
              : Text(isEdit ? 'Update Mapping' : 'Save Mapping'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StepLabel extends StatelessWidget {
  final String step;
  final String label;
  const _StepLabel({required this.step, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 22, height: 22,
          decoration: const BoxDecoration(
              shape: BoxShape.circle, color: AppTheme.primary),
          child: Center(
            child: Text(step,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 13)),
      ],
    );
  }
}

class _PreviewBox extends StatelessWidget {
  final String itemName;
  final String itemUom;
  final String productName;
  final String portionsText;

  const _PreviewBox({
    required this.itemName,
    required this.itemUom,
    required this.productName,
    required this.portionsText,
  });

  @override
  Widget build(BuildContext context) {
    final portions = double.tryParse(portionsText);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome_rounded,
              color: AppTheme.primary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              portions != null && portions > 0
                  ? '1 $itemUom of $itemName  →  '
                    '${portions % 1 == 0 ? portions.toInt() : portions} × $productName'
                  : '1 $itemUom of $itemName  →  ? × $productName',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyYieldState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyYieldState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.tune_rounded, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No yield mappings yet.',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade500)),
          const SizedBox(height: 8),
          Text(
            'Link your store ingredients to POS menu items\nto enable Usage Variance tracking.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add First Mapping'),
          ),
        ],
      ),
    );
  }
}
