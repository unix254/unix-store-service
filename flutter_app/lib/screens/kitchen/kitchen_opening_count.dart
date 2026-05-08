import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import '../../models/staff.dart';
import '../../models/station.dart';
import '../../services/api.dart';

/// Kitchen Opening Confirmation Screen.
/// High/Standard-risk items → blind recount (qty field empty, no hint shown).
/// Low-risk items → show a "Confirm ✓" chip; staff can override by typing.
class KitchenOpeningCountScreen extends StatefulWidget {
  final Staff staff;
  const KitchenOpeningCountScreen({super.key, required this.staff});

  @override
  State<KitchenOpeningCountScreen> createState() => _KitchenOpeningCountState();
}

class _KitchenOpeningCountState extends State<KitchenOpeningCountScreen> {
  List<StationSummary> _stations = [];
  StationSummary? _selectedStation;
  bool _loadingStations = true;

  List<CountItem> _items = [];
  final Map<String, TextEditingController> _qtyControllers = {};
  // For low-risk items: true = confirmed (no manual entry), false = custom entry
  final Map<String, bool> _confirmed = {};
  bool _loadingData = false;
  bool _submitting = false;
  String? _error;
  bool _hasPreviousClosing = false;

  @override
  void initState() {
    super.initState();
    _loadStations();
  }

  @override
  void dispose() {
    for (final c in _qtyControllers.values) c.dispose();
    super.dispose();
  }

  Future<void> _loadStations() async {
    setState(() { _loadingStations = true; _error = null; });
    try {
      final data = await ApiService.instance.getStationsSummary();
      final stations = data.map((j) => StationSummary.fromJson(j)).toList();
      if (!mounted) return;
      setState(() {
        _stations = stations;
        _loadingStations = false;
        if (stations.length == 1) _selectStation(stations.first);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loadingStations = false; });
    }
  }

  Future<void> _selectStation(StationSummary station) async {
    setState(() { _selectedStation = station; _loadingData = true; _error = null; });
    try {
      final data = await ApiService.instance.getOpeningData(station.id);
      _hasPreviousClosing = data['has_previous_closing'] == true;

      final List<CountItem> items;
      if (_hasPreviousClosing && data['previous_closing'] != null) {
        final rawItems = data['previous_closing']['items'] as List;
        items = rawItems.map((j) => CountItem.fromJson(j as Map<String, dynamic>)).toList();
      } else {
        items = [];
      }

      for (final c in _qtyControllers.values) c.dispose();
      _qtyControllers.clear();
      _confirmed.clear();

      for (final item in items) {
        _qtyControllers[item.inventoryItemId] = TextEditingController();
        // Low-risk items start pre-confirmed (auto-agree with previous closing)
        _confirmed[item.inventoryItemId] = !item.requiresBlindCount;
      }

      if (!mounted) return;
      setState(() { _items = items; _loadingData = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loadingData = false; });
    }
  }

  Future<void> _submit() async {
    if (_selectedStation == null) return;

    // Validate: non-confirmed items need a quantity
    final missing = _items.where((item) {
      if (_confirmed[item.inventoryItemId] == true) return false;
      final text = _qtyControllers[item.inventoryItemId]?.text.trim() ?? '';
      return text.isEmpty;
    }).toList();

    if (missing.isNotEmpty) {
      setState(() => _error = 'Please enter quantities or confirm all items.');
      return;
    }

    setState(() { _submitting = true; _error = null; });
    try {
      final items = _items.map((item) {
        final isConfirmed = _confirmed[item.inventoryItemId] == true;
        final qty = isConfirmed
            ? (item.previousClosingQty ?? 0.0)
            : (double.tryParse(_qtyControllers[item.inventoryItemId]!.text.trim()) ?? 0.0);
        return {
          'inventory_item_id': item.inventoryItemId,
          'counted_quantity':  qty,
        };
      }).toList();

      await ApiService.instance.submitOpeningCount(
        stationId: _selectedStation!.id,
        countedBy: widget.staff.name,
        items:     items,
      );

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: Row(children: [
            const Icon(Icons.check_circle_rounded, color: AppTheme.paidGreen, size: 28),
            const SizedBox(width: 10),
            const Text('Opening Confirmed'),
          ]),
          content: Text(
            'Opening stock for ${_selectedStation!.name} has been confirmed. '
            'The storekeeper will verify any discrepancies.',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              style: FilledButton.styleFrom(backgroundColor: AppTheme.paidGreen),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _submitting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(
        backgroundColor: AppTheme.sidebar,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Opening Stock Confirmation',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            Text(widget.staff.name,
                style: const TextStyle(color: AppTheme.pinMuted, fontSize: 11)),
          ],
        ),
      ),
      body: _loadingStations
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_stations.isEmpty) {
      return const Center(child: Text('No stations set up yet.'));
    }
    if (_selectedStation == null) {
      return _StationPickerOpening(stations: _stations, onSelect: _selectStation);
    }

    if (_loadingData) return const Center(child: CircularProgressIndicator());

    if (!_hasPreviousClosing || _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.nightlight_round, size: 72, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('No previous closing count for ${_selectedStation!.name}.',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text(
              'A closing count must be submitted by the night shift before the opening confirmation can be done.',
              style: TextStyle(fontSize: 13, color: AppTheme.pinMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Station + header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.white,
          child: Row(
            children: [
              const Icon(Icons.wb_sunny_rounded, color: AppTheme.pinTeal, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_selectedStation!.name,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              if (_stations.length > 1)
                TextButton(
                  onPressed: () => setState(() { _selectedStation = null; _items = []; }),
                  child: const Text('Change'),
                ),
            ],
          ),
        ),

        // Instruction banner
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFA5D6A7)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: Color(0xFF388E3C), size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'High & Standard risk items: count blind and enter. '
                  'Low risk items: tap Confirm if you agree with yesterday\'s closing, or enter a new count.',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),

        if (_error != null)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.debtRed.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.debtRed.withValues(alpha: 0.4)),
            ),
            child: Text(_error!, style: const TextStyle(color: AppTheme.debtRed, fontSize: 13)),
          ),

        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            itemCount: _items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final item = _items[i];
              final isConfirmed = _confirmed[item.inventoryItemId] ?? false;
              return _OpeningItemTile(
                item:       item,
                controller: _qtyControllers[item.inventoryItemId]!,
                isConfirmed: isConfirmed,
                onToggleConfirm: item.requiresBlindCount ? null : (val) {
                  setState(() {
                    _confirmed[item.inventoryItemId] = val;
                    if (val) _qtyControllers[item.inventoryItemId]!.clear();
                  });
                },
              );
            },
          ),
        ),

        SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Color(0x1A000000), blurRadius: 8, offset: Offset(0, -2))],
            ),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.wb_sunny_rounded),
                label: Text(_submitting ? 'Submitting…' : 'Confirm Opening Stock'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.pinTeal,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StationPickerOpening extends StatelessWidget {
  final List<StationSummary> stations;
  final void Function(StationSummary) onSelect;
  const _StationPickerOpening({required this.stations, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Text('Select your station for opening confirmation',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700)),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: stations.map((s) => Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFE0E0E0)),
              ),
              child: ListTile(
                leading: const Icon(Icons.store_mall_directory_rounded, color: AppTheme.pinTeal),
                title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => onSelect(s),
              ),
            )).toList(),
          ),
        ),
      ],
    );
  }
}

class _OpeningItemTile extends StatelessWidget {
  final CountItem item;
  final TextEditingController controller;
  final bool isConfirmed;
  final void Function(bool)? onToggleConfirm;

  const _OpeningItemTile({
    required this.item,
    required this.controller,
    required this.isConfirmed,
    this.onToggleConfirm,
  });

  Color get _tierColor {
    switch (item.effectiveRiskTier) {
      case 'High': return AppTheme.debtRed;
      case 'Standard': return Colors.orange.shade700;
      default: return Colors.grey.shade500;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLowRisk = !item.requiresBlindCount;

    return Card(
      elevation: 0,
      color: isConfirmed ? const Color(0xFFF1F8F2) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isConfirmed ? AppTheme.paidGreen.withValues(alpha: 0.5) : const Color(0xFFE0E0E0),
          width: isConfirmed ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _tierColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(item.effectiveRiskTier,
                            style: TextStyle(fontSize: 10, color: _tierColor,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 6),
                      Text(item.unitOfMeasure,
                          style: const TextStyle(fontSize: 12, color: AppTheme.pinMuted)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (isLowRisk && !isConfirmed)
              // Show both confirm chip and input option
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: () => onToggleConfirm?.call(true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.paidGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.paidGreen.withValues(alpha: 0.5)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_rounded, color: AppTheme.paidGreen, size: 16),
                          SizedBox(width: 4),
                          Text('Confirm', style: TextStyle(
                              color: AppTheme.paidGreen, fontWeight: FontWeight.w700, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 90,
                    child: _QtyField(controller: controller),
                  ),
                ],
              )
            else if (isLowRisk && isConfirmed)
              GestureDetector(
                onTap: () => onToggleConfirm?.call(false),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.paidGreen,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
                      SizedBox(width: 4),
                      Text('Confirmed', style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                    ],
                  ),
                ),
              )
            else
              SizedBox(
                width: 100,
                child: _QtyField(controller: controller),
              ),
          ],
        ),
      ),
    );
  }
}

class _QtyField extends StatelessWidget {
  final TextEditingController controller;
  const _QtyField({required this.controller});

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
    textAlign: TextAlign.center,
    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
    decoration: InputDecoration(
      hintText: '0',
      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 18),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppTheme.pinTeal, width: 2),
      ),
    ),
  );
}
