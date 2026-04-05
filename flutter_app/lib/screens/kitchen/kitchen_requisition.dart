import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../config/theme.dart';
import '../../models/staff.dart';
import '../../models/inventory_item.dart';
import '../../models/requisition.dart';
import '../../services/api.dart';
import '../pin_login.dart';

/// Kitchen Tablet UI – designed for 11-inch Android tablet, large touch targets.
/// Workflow: Pick item → Set quantity → Choose purpose → Submit
class KitchenRequisitionScreen extends StatefulWidget {
  final Staff staff;
  const KitchenRequisitionScreen({super.key, required this.staff});

  @override
  State<KitchenRequisitionScreen> createState() =>
      _KitchenRequisitionScreenState();
}

class _KitchenRequisitionScreenState extends State<KitchenRequisitionScreen> {
  // ── State ───────────────────────────────────────────────────
  List<InventoryItem> _items = [];
  InventoryItem? _picked;
  double _qty = 1.0;
  String _purpose = 'Sales'; // 'Sales' | 'Staff Meal'
  final _notesCtrl = TextEditingController();
  String _search = '';

  List<Requisition> _myRequests = [];
  bool _loadingItems = true;
  bool _loadingRequests = false;
  bool _submitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loadingItems = true);
    try {
      final items = await ApiService.instance.getInventory();
      setState(() {
        _items = items;
        _loadingItems = false;
      });
    } catch (e) {
      setState(() => _loadingItems = false);
    }
    _loadMyRequests();
  }

  Future<void> _loadMyRequests() async {
    setState(() => _loadingRequests = true);
    try {
      final all = await ApiService.instance.getRequisitions();
      final mine = all
          .where((r) => r.requestedBy == widget.staff.name)
          .toList();
      setState(() {
        _myRequests = mine;
        _loadingRequests = false;
      });
    } catch (_) {
      setState(() => _loadingRequests = false);
    }
  }

  void _selectItem(InventoryItem item) {
    HapticFeedback.selectionClick();
    setState(() {
      _picked = item;
      _qty = 1.0;
      _submitError = null;
    });
  }

  void _adjustQty(double delta) {
    HapticFeedback.lightImpact();
    setState(() {
      _qty = (_qty + delta).clamp(0.5, 9999);
    });
  }

  Future<void> _logWaste() async {
    if (_picked == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Select an item first, then tap Log Waste.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    final qtyCtrl   = TextEditingController(text: _qty.toStringAsFixed(1));
    final notesCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A2634),
        title: Row(children: const [
          Icon(Icons.delete_rounded, color: Color(0xFFEF5350), size: 22),
          SizedBox(width: 8),
          Text('Log Wastage / Spoilage',
              style: TextStyle(color: Colors.white, fontSize: 16)),
        ]),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Item: ${_picked!.name}',
                  style: const TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 12),
              TextField(
                controller: qtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Wasted Quantity (${_picked!.unitOfMeasure})',
                  labelStyle: const TextStyle(color: Colors.white54),
                  enabledBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFEF5350))),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                  labelStyle: TextStyle(color: Colors.white54),
                  enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFEF5350))),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '⚠️  Waste is logged immediately. No approval needed. Stock will be deducted.',
                style: TextStyle(color: Colors.orange, fontSize: 11),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF5350)),
            child: const Text('Log Waste'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final qty = double.tryParse(qtyCtrl.text.trim());
    if (qty == null || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter a valid positive quantity'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    try {
      await ApiService.instance.logWaste(
        inventoryItemId:   _picked!.id,
        quantity:          qty,
        loggedBy:          widget.staff.name,
        notes:             notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
        requesterLocation: widget.staff.locationName,
      );
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      setState(() { _picked = null; _qty = 1.0; });
      _loadData();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('🗑️  Waste logged: $qty ${_picked?.unitOfMeasure ?? ''}'),
        backgroundColor: Colors.red.shade700,
      ));
    } on ApiException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> _submit() async {
    if (_picked == null) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await ApiService.instance.submitRequisition(
        inventoryItemId: _picked!.id,
        quantity:        _qty,
        unitOfMeasure:   _picked!.unitOfMeasure,
        requestedBy:     widget.staff.name,
        purpose:         _purpose,
        notes:           _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _picked = null;
        _qty = 1.0;
        _purpose = 'Sales';
        _notesCtrl.clear();
      });
      _loadMyRequests();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✅  Request submitted! Waiting for storekeeper.'),
        backgroundColor: AppTheme.paidGreen,
        duration: Duration(seconds: 3),
      ));
    } on ApiException catch (e) {
      setState(() {
        _submitting = false;
        _submitError = e.message;
      });
    } catch (e) {
      setState(() {
        _submitting = false;
        _submitError = 'Connection error. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1923),
      body: SafeArea(
        child: Column(
          children: [
            _Header(staff: widget.staff, onLogWaste: _logWaste),
            Expanded(
              child: _loadingItems
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.pinTeal))
                  : _items.isEmpty
                      ? const _EmptyInventory()
                      : _Body(
                          items:       _items,
                          picked:      _picked,
                          qty:         _qty,
                          purpose:     _purpose,
                          notesCtrl:   _notesCtrl,
                          submitting:  _submitting,
                          submitError: _submitError,
                          myRequests:  _myRequests,
                          loadingReqs: _loadingRequests,
                          search:      _search,
                          onSelect:    _selectItem,
                          onAdjustQty: _adjustQty,
                          onPurpose:   (p) => setState(() => _purpose = p),
                          onSubmit:    _submit,
                          onRefreshReqs: _loadMyRequests,
                          onSearch:    (v) => setState(() => _search = v),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final Staff staff;
  final VoidCallback onLogWaste;
  const _Header({required this.staff, required this.onLogWaste});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D1B26),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        children: [
          const Icon(Icons.restaurant_menu_rounded,
              color: AppTheme.pinTeal, size: 28),
          const SizedBox(width: 12),
          const Text('KITCHEN REQUESTS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              )),
          const Spacer(),
          // Log Waste button
          OutlinedButton.icon(
            onPressed: onLogWaste,
            icon: const Icon(Icons.delete_rounded, size: 16,
                color: Color(0xFFEF9A9A)),
            label: const Text('Log Waste',
                style: TextStyle(color: Color(0xFFEF9A9A), fontSize: 13)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFEF5350)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
          ),
          const SizedBox(width: 12),
          // Staff badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(Icons.person_rounded,
                    color: AppTheme.pinMuted, size: 16),
                const SizedBox(width: 6),
                Text(staff.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const PinLoginScreen()),
            ),
            icon: const Icon(Icons.lock_outline_rounded,
                color: AppTheme.pinMuted, size: 18),
            label: const Text('Lock',
                style: TextStyle(color: AppTheme.pinMuted, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main body – split into left form + right request history
// ─────────────────────────────────────────────────────────────────────────────

class _Body extends StatelessWidget {
  final List<InventoryItem> items;
  final InventoryItem? picked;
  final double qty;
  final String purpose;
  final TextEditingController notesCtrl;
  final bool submitting;
  final String? submitError;
  final List<Requisition> myRequests;
  final bool loadingReqs;
  final String search;
  final void Function(InventoryItem) onSelect;
  final void Function(double) onAdjustQty;
  final void Function(String) onPurpose;
  final VoidCallback onSubmit;
  final VoidCallback onRefreshReqs;
  final void Function(String) onSearch;

  const _Body({
    required this.items,
    required this.picked,
    required this.qty,
    required this.purpose,
    required this.notesCtrl,
    required this.submitting,
    required this.submitError,
    required this.myRequests,
    required this.loadingReqs,
    required this.search,
    required this.onSelect,
    required this.onAdjustQty,
    required this.onPurpose,
    required this.onSubmit,
    required this.onRefreshReqs,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 800;

        if (isMobile) {
          return Column(
            children: [
              Expanded(
                child: _RequestForm(
                  items:       items,
                  picked:      picked,
                  qty:         qty,
                  purpose:     purpose,
                  notesCtrl:   notesCtrl,
                  submitting:  submitting,
                  submitError: submitError,
                  search:      search,
                  onSelect:    onSelect,
                  onAdjustQty: onAdjustQty,
                  onPurpose:   onPurpose,
                  onSubmit:    onSubmit,
                  onSearch:    onSearch,
                ),
              ),
              const Divider(color: Color(0xFF263238), height: 1),
              SizedBox(
                height: 250,
                child: _MyRequestsPanel(
                  requests:   myRequests,
                  loading:    loadingReqs,
                  onRefresh:  onRefreshReqs,
                ),
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── LEFT: Request Form ───────────────────────────────
            Expanded(
              flex: 3,
              child: _RequestForm(
                items:       items,
                picked:      picked,
                qty:         qty,
                purpose:     purpose,
                notesCtrl:   notesCtrl,
                submitting:  submitting,
                submitError: submitError,
                search:      search,
                onSelect:    onSelect,
                onAdjustQty: onAdjustQty,
                onPurpose:   onPurpose,
                onSubmit:    onSubmit,
                onSearch:    onSearch,
              ),
            ),
            // ── RIGHT: My Requests Today ─────────────────────────
            SizedBox(
              width: 320,
              child: _MyRequestsPanel(
                requests:   myRequests,
                loading:    loadingReqs,
                onRefresh:  onRefreshReqs,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Request Form
// ─────────────────────────────────────────────────────────────────────────────

class _RequestForm extends StatelessWidget {
  final List<InventoryItem> items;
  final InventoryItem? picked;
  final double qty;
  final String purpose;
  final TextEditingController notesCtrl;
  final bool submitting;
  final String? submitError;
  final String search;
  final void Function(InventoryItem) onSelect;
  final void Function(double) onAdjustQty;
  final void Function(String) onPurpose;
  final void Function(String) onSearch;
  final VoidCallback onSubmit;

  const _RequestForm({
    required this.items,
    required this.picked,
    required this.qty,
    required this.purpose,
    required this.notesCtrl,
    required this.submitting,
    required this.submitError,
    required this.search,
    required this.onSelect,
    required this.onAdjustQty,
    required this.onPurpose,
    required this.onSearch,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final filteredItems = search.isEmpty
        ? items
        : items
            .where((i) => i.name.toLowerCase().contains(search.toLowerCase()))
            .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section 1: Item Picker ─────────────────────────
          const _SectionLabel(label: '1  WHAT DO YOU NEED?'),
          const SizedBox(height: 10),
          TextField(
            onChanged: onSearch,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search items…',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
              filled: true,
              fillColor: const Color(0xFF1E2D3D),
              prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.pinMuted, size: 20),
              suffixIcon: search.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, color: AppTheme.pinMuted, size: 18),
                      onPressed: () => onSearch(''),
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _ItemGrid(items: filteredItems, picked: picked, onSelect: onSelect),
          const SizedBox(height: 24),

          if (picked != null) ...[
            // ── Section 2: Quantity ────────────────────────────
            const _SectionLabel(label: '2  HOW MUCH?'),
            const SizedBox(height: 12),
            _QuantityStepper(
              qty:     qty,
              uom:     picked!.unitOfMeasure,
              onMinus: () => onAdjustQty(-0.5),
              onPlus:  () => onAdjustQty(0.5),
            ),
            const SizedBox(height: 24),

            // ── Section 3: Purpose ─────────────────────────────
            const _SectionLabel(label: '3  WHAT IS IT FOR?'),
            const SizedBox(height: 12),
            _PurposePicker(
              current:  purpose,
              onChange: onPurpose,
            ),
            const SizedBox(height: 20),

            // ── Notes (optional) ───────────────────────────────
            TextField(
              controller: notesCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Add a note (optional)…',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                filled: true,
                fillColor: const Color(0xFF1E2D3D),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(Icons.notes_rounded,
                    color: AppTheme.pinMuted),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 20),

            // ── Error ──────────────────────────────────────────
            if (submitError != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.debtRed.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.debtRed.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: AppTheme.debtRed, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(submitError!,
                          style: const TextStyle(
                              color: AppTheme.debtRed, fontSize: 14)),
                    ),
                  ],
                ),
              ),
            if (submitError != null) const SizedBox(height: 14),

            // ── Submit Button ──────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 72,
              child: ElevatedButton.icon(
                onPressed: submitting ? null : onSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.pinTeal,
                  disabledBackgroundColor: AppTheme.pinTeal.withOpacity(0.4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                icon: submitting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 3, color: Colors.white))
                    : const Icon(Icons.send_rounded,
                        color: Colors.white, size: 28),
                label: Text(
                  submitting ? 'SUBMITTING…' : 'SUBMIT REQUEST',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Item Grid
// ─────────────────────────────────────────────────────────────────────────────

class _ItemGrid extends StatelessWidget {
  final List<InventoryItem> items;
  final InventoryItem? picked;
  final void Function(InventoryItem) onSelect;

  const _ItemGrid(
      {required this.items, required this.picked, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: items.map((item) {
        final isSelected = picked?.id == item.id;
        final isLow = item.needsReorder;
        return GestureDetector(
          onTap: () => onSelect(item),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 150,
            height: 100,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.pinTeal.withOpacity(0.25)
                  : const Color(0xFF1A2A38),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? AppTheme.pinTeal
                    : isLow
                        ? AppTheme.debtRed.withOpacity(0.6)
                        : const Color(0xFF263238),
                width: isSelected ? 2.5 : 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    item.name,
                    style: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFFCFD8DC),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      isLow
                          ? Icons.warning_amber_rounded
                          : Icons.inventory_2_rounded,
                      size: 13,
                      color: isLow ? AppTheme.debtRed : AppTheme.pinMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      item.stockLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: isLow ? AppTheme.debtRed : AppTheme.pinMuted,
                        fontWeight: isLow ? FontWeight.w700 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quantity Stepper
// ─────────────────────────────────────────────────────────────────────────────

class _QuantityStepper extends StatelessWidget {
  final double qty;
  final String uom;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  const _QuantityStepper({
    required this.qty,
    required this.uom,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A38),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // Minus
          _StepBtn(icon: Icons.remove_rounded, onTap: onMinus),
          const SizedBox(width: 20),
          // Display
          Expanded(
            child: Column(
              children: [
                Text(
                  qty % 1 == 0
                      ? qty.toStringAsFixed(0)
                      : qty.toStringAsFixed(1),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                ),
                Text(
                  uom.toUpperCase(),
                  style: const TextStyle(
                    color: AppTheme.pinTeal,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          // Plus
          _StepBtn(icon: Icons.add_rounded, onTap: onPlus),
        ],
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _StepBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.pinSlate,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 72,
          height: 72,
          child: Center(
            child: Icon(icon, color: Colors.white, size: 32),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Purpose Picker
// ─────────────────────────────────────────────────────────────────────────────

class _PurposePicker extends StatelessWidget {
  final String current;
  final void Function(String) onChange;

  const _PurposePicker({required this.current, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _PurposeBtn(
            label: 'FOR SALES',
            icon: '📦',
            selected: current == 'Sales',
            color: AppTheme.pinTeal,
            onTap: () => onChange('Sales'),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _PurposeBtn(
            label: 'STAFF MEAL',
            icon: '🍽️',
            selected: current == 'Staff Meal',
            color: AppTheme.secondary,
            onTap: () => onChange('Staff Meal'),
          ),
        ),
      ],
    );
  }
}

class _PurposeBtn extends StatelessWidget {
  final String label;
  final String icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _PurposeBtn({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 80,
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.2) : const Color(0xFF1A2A38),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? color : const Color(0xFF263238),
            width: selected ? 2.5 : 1.5,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(icon, style: const TextStyle(fontSize: 24)),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected ? color : AppTheme.pinMuted,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// My Requests Panel (right side)
// ─────────────────────────────────────────────────────────────────────────────

class _MyRequestsPanel extends StatelessWidget {
  final List<Requisition> requests;
  final bool loading;
  final VoidCallback onRefresh;

  const _MyRequestsPanel(
      {required this.requests, required this.loading, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D1B26),
        border: Border(left: BorderSide(color: Color(0xFF1E2D3D), width: 1)),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
            child: Row(
              children: [
                const Text(
                  "TODAY'S REQUESTS",
                  style: TextStyle(
                    color: AppTheme.pinMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded,
                      color: AppTheme.pinMuted, size: 18),
                  onPressed: onRefresh,
                  tooltip: 'Refresh',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF1E2D3D), height: 1),

          // List
          Expanded(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.pinTeal))
                : requests.isEmpty
                    ? const Center(
                        child: Text('No requests yet',
                            style: TextStyle(
                                color: AppTheme.pinMuted, fontSize: 13)))
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: requests.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final r = requests[i];
                          return _RequestCard(req: r);
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final Requisition req;
  const _RequestCard({required this.req});

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    IconData statusIcon;
    switch (req.status) {
      case 'Issued':
        statusColor = AppTheme.paidGreen;
        statusIcon = Icons.check_circle_rounded;
        break;
      case 'Rejected':
        statusColor = AppTheme.debtRed;
        statusIcon = Icons.cancel_rounded;
        break;
      default:
        statusColor = AppTheme.secondary;
        statusIcon = Icons.access_time_rounded;
    }

    final timeFmt = DateFormat('HH:mm');
    final time = req.requestedAt.isNotEmpty
        ? timeFmt.format(DateTime.tryParse(req.requestedAt) ?? DateTime.now())
        : '–';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A38),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withOpacity(0.3), width: 1),
      ),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(req.itemName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  '${req.quantity.toStringAsFixed(req.quantity % 1 == 0 ? 0 : 1)} '
                  '${req.unitOfMeasure ?? req.itemUom ?? ''} · ${req.purpose}',
                  style: const TextStyle(
                      color: AppTheme.pinMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(time,
              style:
                  const TextStyle(color: AppTheme.pinMuted, fontSize: 11)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppTheme.pinMuted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
      ),
    );
  }
}

class _EmptyInventory extends StatelessWidget {
  const _EmptyInventory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.inventory_2_rounded,
              size: 64, color: AppTheme.pinMuted),
          const SizedBox(height: 16),
          const Text(
            'No inventory items yet.',
            style: TextStyle(color: AppTheme.pinMuted, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            'Ask the storekeeper to add items first.',
            style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 14),
          ),
        ],
      ),
    );
  }
}
