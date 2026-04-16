import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../config/theme.dart';
import '../../models/staff.dart';
import '../../models/inventory_item.dart';
import '../../models/requisition.dart';
import '../../services/api.dart';
import '../pin_login.dart';

/// A single entry in the request basket.
class _BasketItem {
  final InventoryItem item;
  final double qty;
  final String purpose;
  const _BasketItem({required this.item, required this.qty, required this.purpose});
}

/// Kitchen Tablet UI – designed for 11-inch Android tablet, large touch targets.
/// Workflow: Pick item → Set quantity → Choose purpose → Add to list → Submit all
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
  String _purpose = 'Sales';
  final _notesCtrl = TextEditingController();
  String _search = '';

  List<_BasketItem> _basket = [];
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
      setState(() { _items = items; _loadingItems = false; });
    } catch (e) {
      setState(() => _loadingItems = false);
    }
    _loadMyRequests();
  }

  Future<void> _showNewItemRequestDialog() async {
    final nameCtrl    = TextEditingController();
    final qtyCtrl     = TextEditingController(text: '1');
    final purposeCtrl = TextEditingController();
    String unit = 'pcs';
    const units = ['kg', 'g', 'L', 'ml', 'pcs', 'dozen', 'bag', 'box', 'bunch'];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: const Color(0xFF1A2634),
          title: const Row(children: [
            Icon(Icons.add_box_rounded, color: AppTheme.pinTeal, size: 22),
            SizedBox(width: 8),
            Text('Request New Item',
                style: TextStyle(color: Colors.white, fontSize: 17)),
          ]),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Request an item that is not yet in the inventory.',
                    style: TextStyle(color: AppTheme.pinMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  // Item name
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      filled: true,
                      fillColor: Color(0xFF0F1923),
                      labelText: 'Item Name *',
                      labelStyle: TextStyle(color: Colors.white54),
                      prefixIcon: Icon(Icons.inventory_2_rounded, color: AppTheme.pinMuted),
                      enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppTheme.pinTeal, width: 2)),
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 12),
                  // Quantity + Unit row
                  Row(children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: qtyCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          filled: true,
                          fillColor: Color(0xFF0F1923),
                          labelText: 'Quantity *',
                          labelStyle: TextStyle(color: Colors.white54),
                          prefixIcon: Icon(Icons.numbers_rounded, color: AppTheme.pinMuted),
                          enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.white24)),
                          focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: AppTheme.pinTeal, width: 2)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: unit,
                        dropdownColor: const Color(0xFF1A2634),
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          filled: true,
                          fillColor: Color(0xFF0F1923),
                          labelText: 'Unit',
                          labelStyle: TextStyle(color: Colors.white54),
                          enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.white24)),
                          focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: AppTheme.pinTeal, width: 2)),
                        ),
                        items: units
                            .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                            .toList(),
                        onChanged: (v) => setDlg(() => unit = v!),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  // Purpose / Notes
                  TextField(
                    controller: purposeCtrl,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 2,
                    decoration: const InputDecoration(
                      filled: true,
                      fillColor: Color(0xFF0F1923),
                      labelText: 'Purpose / Notes (optional)',
                      labelStyle: TextStyle(color: Colors.white54),
                      hintText: 'e.g. urgent, for weekend event',
                      hintStyle: TextStyle(color: Colors.white24),
                      prefixIcon: Icon(Icons.notes_rounded, color: AppTheme.pinMuted),
                      enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24)),
                      focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppTheme.pinTeal, width: 2)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.pinTeal),
              icon: const Icon(Icons.send_rounded, size: 16, color: Colors.white),
              label: const Text('Send Request',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    final name = nameCtrl.text.trim();
    final qty  = double.tryParse(qtyCtrl.text.trim());
    if (name.isEmpty || qty == null || qty <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please enter a valid item name and quantity.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    try {
      await ApiService.instance.submitNewItemRequest(
        requestedBy: widget.staff.name,
        itemName:    name,
        unit:        unit,
        qty:         qty,
        purpose:     'Sales',
        notes:       purposeCtrl.text.trim().isEmpty ? null : purposeCtrl.text.trim(),
      );
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      _loadMyRequests();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('📋  New item request sent for "$name"!'),
        backgroundColor: AppTheme.paidGreen,
        duration: const Duration(seconds: 3),
      ));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> _loadMyRequests() async {
    setState(() => _loadingRequests = true);
    try {
      final all = await ApiService.instance.getRequisitions();
      final mine = all.where((r) => r.requestedBy == widget.staff.name).toList();
      setState(() { _myRequests = mine; _loadingRequests = false; });
    } catch (_) {
      setState(() => _loadingRequests = false);
    }
  }

  void _selectItem(InventoryItem item) {
    HapticFeedback.selectionClick();
    setState(() { _picked = item; _qty = 1.0; _submitError = null; });
  }

  void _adjustQty(double delta) {
    HapticFeedback.lightImpact();
    setState(() => _qty = (_qty + delta).clamp(0.5, 9999));
  }

  void _setQty(double qty) => setState(() => _qty = qty.clamp(0.5, 9999));

  // Opens a dialog to type a quantity directly
  Future<void> _editQtyDirect() async {
    if (_picked == null) return;
    final result = await showDialog<double>(
      context: context,
      builder: (_) => _QtyInputDialog(initial: _qty, uom: _picked!.unitOfMeasure),
    );
    if (result != null) _setQty(result);
  }

  // Adds the currently picked item to the basket, then resets the picker
  void _addToBasket() {
    if (_picked == null) return;
    HapticFeedback.mediumImpact();
    final item = _picked!;
    final qty = _qty;
    final purpose = _purpose;
    // Merge if same item + purpose already in list
    final idx = _basket.indexWhere((b) => b.item.id == item.id && b.purpose == purpose);
    setState(() {
      if (idx >= 0) {
        final existing = _basket[idx];
        _basket = List.from(_basket)
          ..[idx] = _BasketItem(item: existing.item, qty: existing.qty + qty, purpose: existing.purpose);
      } else {
        _basket = [..._basket, _BasketItem(item: item, qty: qty, purpose: purpose)];
      }
      _picked = null;
      _qty = 1.0;
    });
  }

  void _removeFromBasket(int index) {
    HapticFeedback.lightImpact();
    setState(() => _basket = List.from(_basket)..removeAt(index));
  }

  Future<void> _submit() async {
    if (_basket.isEmpty) return;
    setState(() { _submitting = true; _submitError = null; });
    final n = _basket.length;
    final notes = _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();
    try {
      for (final b in _basket) {
        await ApiService.instance.submitRequisition(
          inventoryItemId: b.item.id,
          quantity:        b.qty,
          unitOfMeasure:   b.item.unitOfMeasure,
          requestedBy:     widget.staff.name,
          purpose:         b.purpose,
          notes:           notes,
        );
      }
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _basket = [];
        _picked = null;
        _qty = 1.0;
        _purpose = 'Sales';
        _notesCtrl.clear();
      });
      _loadMyRequests();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✅  $n item${n == 1 ? '' : 's'} requested! Waiting for storekeeper.'),
        backgroundColor: AppTheme.paidGreen,
        duration: const Duration(seconds: 3),
      ));
    } on ApiException catch (e) {
      setState(() { _submitting = false; _submitError = e.message; });
    } catch (e) {
      setState(() { _submitting = false; _submitError = 'Connection error. Try again.'; });
    }
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
        title: const Row(children: [
          Icon(Icons.delete_rounded, color: Color(0xFFEF5350), size: 22),
          SizedBox(width: 8),
          Text('Log Wastage / Spoilage',
              style: TextStyle(color: Colors.white, fontSize: 16)),
        ]),
        content: SingleChildScrollView(
          child: SizedBox(
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
                    filled: true,
                    fillColor: const Color(0xFF0F1923),
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
                    filled: true,
                    fillColor: Color(0xFF0F1923),
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

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  void _logOut() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const PinLoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 800;
        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: const Color(0xFF0F1923),
          drawer: isMobile
              ? _MenuDrawer(
                  staff: widget.staff,
                  onLogWaste: _logWaste,
                  onLogOut: _logOut,
                  requests: _myRequests,
                  loading: _loadingRequests,
                  onRefresh: _loadMyRequests,
                )
              : null,
          body: SafeArea(
            child: Column(
              children: [
                _Header(
                  staff: widget.staff,
                  onLogWaste: _logWaste,
                  onLogOut: _logOut,
                  isMobile: isMobile,
                  onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
                ),
                Expanded(
                  child: _loadingItems
                      ? const Center(
                          child: CircularProgressIndicator(color: AppTheme.pinTeal))
                      : _items.isEmpty
                          ? const _EmptyInventory()
                          : _Body(
                              items:              _items,
                              picked:             _picked,
                              qty:                _qty,
                              purpose:            _purpose,
                              notesCtrl:          _notesCtrl,
                              submitting:         _submitting,
                              submitError:        _submitError,
                              myRequests:         _myRequests,
                              loadingReqs:        _loadingRequests,
                              search:             _search,
                              basket:             _basket,
                              isMobile:           isMobile,
                              onSelect:           _selectItem,
                              onAdjustQty:        _adjustQty,
                              onEditQty:          _editQtyDirect,
                              onPurpose:          (p) => setState(() => _purpose = p),
                              onAddToBasket:      _addToBasket,
                              onRemoveFromBasket: _removeFromBasket,
                              onSubmit:           _submit,
                              onRefreshReqs:      _loadMyRequests,
                              onSearch:           (v) => setState(() => _search = v),
                              onNewItemRequest:   _showNewItemRequestDialog,
                            ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final Staff staff;
  final VoidCallback onLogWaste;
  final VoidCallback onLogOut;
  final bool isMobile;
  final VoidCallback onMenuTap;

  const _Header({
    required this.staff,
    required this.onLogWaste,
    required this.onLogOut,
    required this.isMobile,
    required this.onMenuTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D1B26),
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24, vertical: 14),
      child: Row(
        children: [
          if (isMobile) ...[
            IconButton(
              icon: const Icon(Icons.menu_rounded, color: Colors.white),
              onPressed: onMenuTap,
            ),
            const SizedBox(width: 4),
          ] else ...[
            const Icon(Icons.restaurant_menu_rounded, color: AppTheme.pinTeal, size: 28),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Text(
                    '${(staff.locationName?.isNotEmpty == true ? staff.locationName! : 'STOCK').toUpperCase()} REQUESTS',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(width: 16),
                  OutlinedButton.icon(
                    onPressed: onLogWaste,
                    icon: const Icon(Icons.delete_rounded, size: 16, color: Color(0xFFEF9A9A)),
                    label: const Text('Log Waste', style: TextStyle(color: Color(0xFFEF9A9A), fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFEF5350)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!isMobile) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_rounded, color: AppTheme.pinMuted, size: 16),
                  const SizedBox(width: 6),
                  Text(staff.name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: onLogOut,
              icon: const Icon(Icons.logout_rounded, color: AppTheme.pinMuted, size: 18),
              label: const Text('Log Out', style: TextStyle(color: AppTheme.pinMuted, fontSize: 13)),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main body
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
  final List<_BasketItem> basket;
  final bool isMobile;
  final void Function(InventoryItem) onSelect;
  final void Function(double) onAdjustQty;
  final VoidCallback onEditQty;
  final void Function(String) onPurpose;
  final VoidCallback onAddToBasket;
  final void Function(int) onRemoveFromBasket;
  final VoidCallback onSubmit;
  final VoidCallback onRefreshReqs;
  final void Function(String) onSearch;
  final VoidCallback onNewItemRequest;

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
    required this.basket,
    required this.isMobile,
    required this.onSelect,
    required this.onAdjustQty,
    required this.onEditQty,
    required this.onPurpose,
    required this.onAddToBasket,
    required this.onRemoveFromBasket,
    required this.onSubmit,
    required this.onRefreshReqs,
    required this.onSearch,
    required this.onNewItemRequest,
  });

  @override
  Widget build(BuildContext context) {
    final form = _RequestForm(
      items:              items,
      picked:             picked,
      qty:                qty,
      purpose:            purpose,
      notesCtrl:          notesCtrl,
      submitting:         submitting,
      submitError:        submitError,
      search:             search,
      basket:             basket,
      onSelect:           onSelect,
      onAdjustQty:        onAdjustQty,
      onEditQty:          onEditQty,
      onPurpose:          onPurpose,
      onAddToBasket:      onAddToBasket,
      onRemoveFromBasket: onRemoveFromBasket,
      onSubmit:           onSubmit,
      onSearch:           onSearch,
      onNewItemRequest:   onNewItemRequest,
    );

    if (isMobile) {
      return form;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: form),
        SizedBox(
          width: 320,
          child: _MyRequestsPanel(
            requests:  myRequests,
            loading:   loadingReqs,
            onRefresh: onRefreshReqs,
          ),
        ),
      ],
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
  final List<_BasketItem> basket;
  final void Function(InventoryItem) onSelect;
  final void Function(double) onAdjustQty;
  final VoidCallback onEditQty;
  final void Function(String) onPurpose;
  final VoidCallback onAddToBasket;
  final void Function(int) onRemoveFromBasket;
  final VoidCallback onSubmit;
  final void Function(String) onSearch;
  final VoidCallback onNewItemRequest;

  const _RequestForm({
    required this.items,
    required this.picked,
    required this.qty,
    required this.purpose,
    required this.notesCtrl,
    required this.submitting,
    required this.submitError,
    required this.search,
    required this.basket,
    required this.onSelect,
    required this.onAdjustQty,
    required this.onEditQty,
    required this.onPurpose,
    required this.onAddToBasket,
    required this.onRemoveFromBasket,
    required this.onSubmit,
    required this.onSearch,
    required this.onNewItemRequest,
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
              prefixIcon: const Icon(Icons.search_rounded,
                  color: AppTheme.pinMuted, size: 20),
              suffixIcon: search.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded,
                          color: AppTheme.pinMuted, size: 18),
                      onPressed: () => onSearch(''),
                    )
                  : null,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // ── Request New Item (not in stock) ───────────────────
          OutlinedButton.icon(
            onPressed: onNewItemRequest,
            icon: const Icon(Icons.add_box_rounded,
                size: 16, color: AppTheme.pinMuted),
            label: const Text(
              'Request New Item (Not in Stock)',
              style: TextStyle(color: AppTheme.pinMuted, fontSize: 13),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppTheme.pinMuted, width: 1),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 12),
          _ItemGrid(items: filteredItems, picked: picked, onSelect: onSelect),
          const SizedBox(height: 24),

          // ── Sections 2 & 3 only when item is picked ────────
          if (picked != null) ...[
            const _SectionLabel(label: '2  HOW MUCH?'),
            const SizedBox(height: 12),
            _QuantityStepper(
              qty:          qty,
              uom:          picked!.unitOfMeasure,
              onMinus:      () => onAdjustQty(-0.5),
              onPlus:       () => onAdjustQty(0.5),
              onTapDisplay: onEditQty,
            ),
            const SizedBox(height: 24),

            const _SectionLabel(label: '3  WHAT IS IT FOR?'),
            const SizedBox(height: 12),
            _PurposePicker(current: purpose, onChange: onPurpose),
            const SizedBox(height: 20),

            // ── Add to List button ─────────────────────────
            SizedBox(
              width: double.infinity,
              height: 64,
              child: OutlinedButton.icon(
                onPressed: onAddToBasket,
                icon: const Icon(Icons.add_shopping_cart_rounded,
                    color: AppTheme.pinTeal, size: 22),
                label: Text(
                  basket.isEmpty
                      ? 'ADD TO LIST'
                      : 'ADD TO LIST  (${basket.length} already)',
                  style: const TextStyle(
                    color: AppTheme.pinTeal,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.pinTeal, width: 2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(height: 28),
          ],

          // ── Basket ─────────────────────────────────────────
          if (basket.isNotEmpty) ...[
            Row(children: [
              const Icon(Icons.shopping_cart_rounded,
                  color: AppTheme.pinTeal, size: 18),
              const SizedBox(width: 8),
              _SectionLabel(
                  label: 'YOUR LIST  (${basket.length} item${basket.length == 1 ? '' : 's'})'),
              const Spacer(),
              TextButton(
                onPressed: () {
                  // Remove all — trigger each removal from last to first
                  for (int i = basket.length - 1; i >= 0; i--) {
                    onRemoveFromBasket(i);
                  }
                },
                child: const Text('Clear all',
                    style: TextStyle(color: AppTheme.debtRed, fontSize: 12)),
              ),
            ]),
            const SizedBox(height: 8),
            ...basket.asMap().entries.map((e) => _BasketRow(
                  entry: e.value,
                  onRemove: () => onRemoveFromBasket(e.key),
                )),
            const SizedBox(height: 16),

            // Notes field (shared across all items)
            TextField(
              controller: notesCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Add a note for the whole request (optional)…',
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
            const SizedBox(height: 16),

            // Error
            if (submitError != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.debtRed.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppTheme.debtRed.withOpacity(0.5)),
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
              const SizedBox(height: 14),
            ],

            // Submit button
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
                  submitting
                      ? 'SUBMITTING…'
                      : 'SUBMIT ${basket.length} ITEM${basket.length == 1 ? '' : 'S'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Hint when nothing selected and basket empty
          if (picked == null && basket.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: Text(
                  'Tap an item above to start your request',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.25), fontSize: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Basket Row
// ─────────────────────────────────────────────────────────────────────────────

class _BasketRow extends StatelessWidget {
  final _BasketItem entry;
  final VoidCallback onRemove;
  const _BasketRow({required this.entry, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final qtyStr = entry.qty % 1 == 0
        ? entry.qty.toStringAsFixed(0)
        : entry.qty.toStringAsFixed(1);
    final isMeal = entry.purpose == 'Staff Meal';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A38),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF263238)),
      ),
      child: Row(
        children: [
          Icon(
            isMeal ? Icons.restaurant_rounded : Icons.storefront_rounded,
            size: 18,
            color: isMeal ? const Color(0xFFFFB74D) : AppTheme.pinTeal,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.item.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                Text(
                  '$qtyStr ${entry.item.unitOfMeasure}  ·  ${entry.purpose}',
                  style: const TextStyle(
                      color: AppTheme.pinMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            color: const Color(0xFF607080),
            onPressed: onRemove,
            tooltip: 'Remove',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quantity direct-input dialog
// ─────────────────────────────────────────────────────────────────────────────

class _QtyInputDialog extends StatefulWidget {
  final double initial;
  final String uom;
  const _QtyInputDialog({required this.initial, required this.uom});

  @override
  State<_QtyInputDialog> createState() => _QtyInputDialogState();
}

class _QtyInputDialogState extends State<_QtyInputDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.initial % 1 == 0
          ? widget.initial.toStringAsFixed(0)
          : widget.initial.toStringAsFixed(1),
    );
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _pick(double v) => setState(() {
    _ctrl.text = v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  });

  void _confirm() {
    final v = double.tryParse(_ctrl.text.trim());
    if (v != null && v > 0) Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A2634),
      title: Text(
        'Enter Quantity (${widget.uom.toUpperCase()})',
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Large text input
              TextField(
                controller: _ctrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 44,
                    fontWeight: FontWeight.w800),
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: Color(0xFF0F1923),
                  enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: OutlineInputBorder(
                      borderSide:
                          BorderSide(color: AppTheme.pinTeal, width: 2)),
                ),
                onSubmitted: (_) => _confirm(),
              ),
              const SizedBox(height: 16),
              // Quick-pick
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [5, 10, 25, 50, 100].map((v) {
                  return OutlinedButton(
                    onPressed: () => _pick(v.toDouble()),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.pinTeal,
                      side: const BorderSide(color: AppTheme.pinTeal),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text('$v',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54))),
        ElevatedButton(
          onPressed: _confirm,
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.pinTeal),
          child: const Text('Set Quantity',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ),
      ],
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
    final query = MediaQuery.of(context);
    final isMobile = query.size.width < 800;

    final grid = GridView.builder(
      shrinkWrap: true,
      physics: isMobile ? const BouncingScrollPhysics() : const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: isMobile ? (query.size.width / 2) : 150,
        mainAxisExtent: isMobile ? 70 : 80, // reduced to fit more items
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final isSelected = picked?.id == item.id;
        final isLow = item.needsReorder;
        return GestureDetector(
          onTap: () => onSelect(item),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.all(isMobile ? 10 : 12),
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
                      fontSize: isMobile ? 12 : 14,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      isLow ? Icons.warning_amber_rounded : Icons.inventory_2_rounded,
                      size: 13,
                      color: isLow ? AppTheme.debtRed : AppTheme.pinMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      item.stockLabel,
                      style: TextStyle(
                        color: isLow ? AppTheme.debtRed : AppTheme.pinMuted,
                        fontSize: isMobile ? 11 : 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (isMobile) {
      // Limit to approx 4 rows for scrolling on tiny screens 
      return Container(
        constraints: const BoxConstraints(maxHeight: 310),
        child: grid,
      );
    }
    return grid;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quantity Stepper  (tap the number to type it directly)
// ─────────────────────────────────────────────────────────────────────────────

class _QuantityStepper extends StatelessWidget {
  final double qty;
  final String uom;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onTapDisplay;

  const _QuantityStepper({
    required this.qty,
    required this.uom,
    required this.onMinus,
    required this.onPlus,
    required this.onTapDisplay,
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
          _StepBtn(icon: Icons.remove_rounded, onTap: onMinus),
          const SizedBox(width: 16),
          // Tappable quantity display
          Expanded(
            child: GestureDetector(
              onTap: onTapDisplay,
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
                  const SizedBox(height: 2),
                  const Text(
                    'tap to type',
                    style: TextStyle(
                        color: AppTheme.pinMuted,
                        fontSize: 10,
                        letterSpacing: 0.5),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
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
          child: Center(child: Icon(icon, color: Colors.white, size: 32)),
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
            label:     'FOR SALES',
            icon:      Icons.storefront_rounded,
            iconColor: AppTheme.pinTeal,
            selected:  current == 'Sales',
            color:     AppTheme.pinTeal,
            onTap:     () => onChange('Sales'),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _PurposeBtn(
            label:     'STAFF MEAL',
            icon:      Icons.restaurant_rounded,
            iconColor: const Color(0xFFFFB74D),
            selected:  current == 'Staff Meal',
            color:     const Color(0xFFFFB74D),
            onTap:     () => onChange('Staff Meal'),
          ),
        ),
      ],
    );
  }
}

class _PurposeBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color iconColor;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _PurposeBtn({
    required this.label,
    required this.icon,
    required this.iconColor,
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
              Icon(
                icon,
                size: 28,
                color: selected ? iconColor : const Color(0xFF607080),
              ),
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
                        itemBuilder: (_, i) => _RequestCard(req: requests[i]),
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
        statusIcon  = Icons.check_circle_rounded;
        break;
      case 'Rejected':
        statusColor = AppTheme.debtRed;
        statusIcon  = Icons.cancel_rounded;
        break;
      default:
        statusColor = AppTheme.secondary;
        statusIcon  = Icons.access_time_rounded;
    }

    final timeFmt = DateFormat('HH:mm');
    final time = req.requestedAt.isNotEmpty
        ? timeFmt.format(
            DateTime.tryParse(req.requestedAt) ?? DateTime.now())
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
                  style:
                      const TextStyle(color: AppTheme.pinMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(time,
              style: const TextStyle(color: AppTheme.pinMuted, fontSize: 11)),
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
            style: TextStyle(
                color: AppTheme.pinMuted.withOpacity(0.6), fontSize: 14),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Menu Drawer (Mobile)
// ─────────────────────────────────────────────────────────────────────────────

class _MenuDrawer extends StatelessWidget {
  final Staff staff;
  final VoidCallback onLogWaste;
  final VoidCallback onLogOut;
  final List<Requisition> requests;
  final bool loading;
  final VoidCallback onRefresh;

  const _MenuDrawer({
    required this.staff,
    required this.onLogWaste,
    required this.onLogOut,
    required this.requests,
    required this.loading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF0D1B26),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.person_rounded, color: AppTheme.pinMuted, size: 20),
                  const SizedBox(width: 10),
                  Text(staff.name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const Divider(color: Color(0xFF1E2D3D), height: 1),
            Expanded(
              child: _MyRequestsPanel(
                requests: requests,
                loading: loading,
                onRefresh: onRefresh,
              ),
            ),
            const Divider(color: Color(0xFF1E2D3D), height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextButton.icon(
                onPressed: onLogOut,
                icon: const Icon(Icons.logout_rounded, color: AppTheme.pinMuted, size: 20),
                label: const Text('Log Out', style: TextStyle(color: AppTheme.pinMuted, fontSize: 14)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  alignment: Alignment.centerLeft,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
