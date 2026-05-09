import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import '../../models/staff.dart';
import '../../models/station.dart';
import '../../services/api.dart';

/// Kitchen Closing Count Screen — mobile-first, blind count.
/// Staff see only item names and units. No system quantities shown.
/// One confirmed count per station per business day.
class KitchenClosingCountScreen extends StatefulWidget {
  final Staff staff;
  const KitchenClosingCountScreen({super.key, required this.staff});

  @override
  State<KitchenClosingCountScreen> createState() => _KitchenClosingCountState();
}

class _KitchenClosingCountState extends State<KitchenClosingCountScreen> {
  // ── Station selection ───────────────────────────────────────
  List<StationSummary> _stations = [];
  StationSummary? _selectedStation;
  bool _loadingStations = true;

  // ── Count items ─────────────────────────────────────────────
  List<CountItem> _items = [];
  final Map<String, TextEditingController> _qtyControllers = {};
  bool _loadingItems = false;
  bool _submitting = false;
  String? _error;

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
      var stations = data.map((j) => StationSummary.fromJson(j)).toList();

      // Kitchen staff only see their own station.
      // Managers, owners and storekeepers see all stations.
      final loc = widget.staff.locationName;
      if (widget.staff.isKitchen && loc != null && loc.isNotEmpty) {
        stations = stations.where((s) => s.name == loc).toList();
      }

      if (!mounted) return;
      setState(() {
        _stations = stations;
        _loadingStations = false;
        // Auto-select if only one station
        if (stations.length == 1) _selectStation(stations.first);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loadingStations = false; });
    }
  }

  Future<void> _selectStation(StationSummary station) async {
    setState(() { _selectedStation = station; _loadingItems = true; _error = null; });
    try {
      final data = await ApiService.instance.getActiveCountList(station.id);
      final items = (data['items'] as List)
          .map((j) => CountItem.fromJson(j as Map<String, dynamic>))
          .toList();

      // Build controllers
      for (final c in _qtyControllers.values) c.dispose();
      _qtyControllers.clear();
      for (final item in items) {
        _qtyControllers[item.inventoryItemId] = TextEditingController();
      }

      if (!mounted) return;
      setState(() { _items = items; _loadingItems = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loadingItems = false; });
    }
  }

  Future<void> _submit() async {
    if (_selectedStation == null) return;

    // Validate: all items need a value
    final missing = _items.where((item) {
      final text = _qtyControllers[item.inventoryItemId]?.text.trim() ?? '';
      return text.isEmpty;
    }).toList();

    if (missing.isNotEmpty) {
      setState(() => _error = 'Please enter a quantity for all items (enter 0 if none left).');
      return;
    }

    setState(() { _submitting = true; _error = null; });
    try {
      final items = _items.map((item) => {
        'inventory_item_id': item.inventoryItemId,
        'counted_quantity': double.tryParse(
            _qtyControllers[item.inventoryItemId]!.text.trim()) ?? 0.0,
      }).toList();

      final result = await ApiService.instance.submitClosingCount(
        stationId:  _selectedStation!.id,
        countedBy:  widget.staff.name,
        items:      items,
      );

      if (!mounted) return;
      final isPeak = result['peak_hours'] == true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: Row(children: [
            Icon(Icons.check_circle_rounded,
                color: AppTheme.paidGreen, size: 28),
            const SizedBox(width: 10),
            const Text('Count Submitted'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Closing count for ${_selectedStation!.name} has been submitted.',
                  style: const TextStyle(fontSize: 15)),
              const SizedBox(height: 8),
              if (isPeak)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.amber.shade700, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Flagged as High-Risk — counted during peak hours. Storekeeper will review.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              const Text('The storekeeper will review and confirm the count.',
                  style: TextStyle(fontSize: 13, color: AppTheme.pinMuted)),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(context); // close dialog
                Navigator.pop(context); // back to kitchen home
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
            const Text('Closing Stock Count',
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.store_mall_directory_rounded,
                size: 72, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('No stations set up yet.',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
            const SizedBox(height: 8),
            const Text('Ask the storekeeper to add kitchen stations in Settings.',
                style: TextStyle(fontSize: 13, color: AppTheme.pinMuted),
                textAlign: TextAlign.center),
          ],
        ),
      );
    }

    if (_selectedStation == null) {
      return _StationPicker(
        stations: _stations,
        onSelect: _selectStation,
        countType: 'Closing',
      );
    }

    return Column(
      children: [
        // Station chip + change button
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.white,
          child: Row(
            children: [
              const Icon(Icons.store_mall_directory_rounded,
                  color: AppTheme.pinTeal, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_selectedStation!.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              if (_stations.length > 1)
                TextButton(
                  onPressed: () => setState(() {
                    _selectedStation = null;
                    _items = [];
                  }),
                  child: const Text('Change'),
                ),
            ],
          ),
        ),

        // Blind-count instruction banner
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.shade300),
          ),
          child: const Row(
            children: [
              Icon(Icons.visibility_off_rounded, color: Colors.amber, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Count what you see — do not enter what you think the system expects. Enter 0 if nothing is left.',
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
            child: Text(_error!,
                style: const TextStyle(color: AppTheme.debtRed, fontSize: 13)),
          ),

        if (_loadingItems)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_items.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inventory_2_rounded,
                      size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text('No items to count for this station.',
                      style: TextStyle(color: Colors.grey.shade500)),
                  const SizedBox(height: 6),
                  const Text('Items appear here once stock is transferred to this station.',
                      style: TextStyle(fontSize: 12, color: AppTheme.pinMuted),
                      textAlign: TextAlign.center),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _CountItemTile(
                item: _items[i],
                controller: _qtyControllers[_items[i].inventoryItemId]!,
              ),
            ),
          ),

        // Submit footer
        if (!_loadingItems && _items.isNotEmpty)
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
                      : const Icon(Icons.check_circle_outline_rounded),
                  label: Text(_submitting ? 'Submitting…' : 'Submit Closing Count'),
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

// ── Station Picker ─────────────────────────────────────────────────────────────

class _StationPicker extends StatelessWidget {
  final List<StationSummary> stations;
  final void Function(StationSummary) onSelect;
  final String countType;

  const _StationPicker({
    required this.stations,
    required this.onSelect,
    required this.countType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Text('Select your station',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700)),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: stations.map((s) {
              final done = countType == 'Closing' ? s.closingDone : s.openingDone;
              final confirmed = countType == 'Closing' ? s.closingConfirmed : false;
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: confirmed
                        ? AppTheme.paidGreen
                        : done
                            ? Colors.amber.shade300
                            : const Color(0xFFE0E0E0),
                    width: confirmed ? 2 : 1,
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: confirmed
                        ? AppTheme.paidGreen.withValues(alpha: 0.15)
                        : done
                            ? Colors.amber.withValues(alpha: 0.15)
                            : AppTheme.pinTeal.withValues(alpha: 0.12),
                    child: Icon(
                      confirmed
                          ? Icons.check_circle_rounded
                          : done
                              ? Icons.pending_rounded
                              : Icons.store_mall_directory_rounded,
                      color: confirmed
                          ? AppTheme.paidGreen
                          : done
                              ? Colors.amber.shade700
                              : AppTheme.pinTeal,
                    ),
                  ),
                  title: Text(s.name,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  subtitle: Text(
                    confirmed
                        ? 'Count confirmed'
                        : done
                            ? 'Submitted — awaiting confirmation'
                            : '$countType count not yet done',
                    style: TextStyle(
                      fontSize: 12,
                      color: confirmed
                          ? AppTheme.paidGreen
                          : done
                              ? Colors.amber.shade700
                              : Colors.grey.shade500,
                    ),
                  ),
                  trailing: confirmed
                      ? null
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: confirmed ? null : () => onSelect(s),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ── Count Item Tile ─────────────────────────────────────────────────────────────

class _CountItemTile extends StatelessWidget {
  final CountItem item;
  final TextEditingController controller;

  const _CountItemTile({required this.item, required this.controller});

  Color get _tierColor {
    switch (item.effectiveRiskTier) {
      case 'High': return AppTheme.debtRed;
      case 'Standard': return Colors.orange.shade700;
      default: return Colors.grey.shade500;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE0E0E0)),
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
            SizedBox(
              width: 100,
              child: TextField(
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
