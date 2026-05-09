class Station {
  final String id;
  final String name;
  final String? description;
  final bool isActive;

  const Station({
    required this.id,
    required this.name,
    this.description,
    this.isActive = true,
  });

  factory Station.fromJson(Map<String, dynamic> j) => Station(
    id:          j['id'] as String,
    name:        j['name'] as String,
    description: j['description'] as String?,
    isActive:    (j['is_active'] == 1 || j['is_active'] == true),
  );
}

class KitchenLedgerRow {
  final String inventoryItemId;
  final String itemName;
  final String unitOfMeasure;
  final String stationId;
  final String stationName;
  final String? closingStatus;
  final String? openingStatus;
  final bool isPeakHours;

  // Chronological audit columns
  final double opening;
  final double? morningCount;
  final double? handoverVariance;
  final double transfers;
  final double waste;
  final double? closing;
  final double expectedClosing;

  const KitchenLedgerRow({
    required this.inventoryItemId,
    required this.itemName,
    required this.unitOfMeasure,
    required this.stationId,
    required this.stationName,
    this.closingStatus,
    this.openingStatus,
    this.isPeakHours = false,
    required this.opening,
    this.morningCount,
    this.handoverVariance,
    required this.transfers,
    required this.waste,
    this.closing,
    required this.expectedClosing,
  });

  factory KitchenLedgerRow.fromJson(Map<String, dynamic> j) {
    double? _d(String key) {
      final v = j[key];
      if (v == null) return null;
      return double.tryParse(v.toString()) ?? 0.0;
    }
    double _dd(String key) => _d(key) ?? 0.0;
    return KitchenLedgerRow(
      inventoryItemId:  j['inventory_item_id'] as String,
      itemName:         j['item_name'] as String,
      unitOfMeasure:    j['unit_of_measure'] as String? ?? '—',
      stationId:        j['station_id'] as String,
      stationName:      j['station_name'] as String,
      closingStatus:    j['closing_status'] as String?,
      openingStatus:    j['opening_status'] as String?,
      isPeakHours:      j['is_peak_hours'] == true || j['is_peak_hours'] == 1,
      opening:          _dd('opening'),
      morningCount:     _d('morning_count'),
      handoverVariance: _d('handover_variance'),
      transfers:        _dd('transfers'),
      waste:            _dd('waste'),
      closing:          _d('closing'),
      expectedClosing:  _dd('expected_closing'),
    );
  }
}

class StationSummary {
  final String id;
  final String name;
  final String? description;
  final String? closingStatus;
  final String? openingStatus;
  final String? closingSnapshotId;
  final String? openingSnapshotId;

  const StationSummary({
    required this.id,
    required this.name,
    this.description,
    this.closingStatus,
    this.openingStatus,
    this.closingSnapshotId,
    this.openingSnapshotId,
  });

  factory StationSummary.fromJson(Map<String, dynamic> j) => StationSummary(
    id:                j['id'] as String,
    name:              j['name'] as String,
    description:       j['description'] as String?,
    closingStatus:     j['closing_status'] as String?,
    openingStatus:     j['opening_status'] as String?,
    closingSnapshotId: j['closing_snapshot_id'] as String?,
    openingSnapshotId: j['opening_snapshot_id'] as String?,
  );

  bool get closingDone => closingStatus != null;
  bool get closingConfirmed => closingStatus == 'CONFIRMED';
  bool get openingDone => openingStatus != null;
  bool get openingConfirmed => openingStatus == 'CONFIRMED';
  bool get closingPendingConfirm => closingStatus == 'SUBMITTED';
  bool get openingPendingConfirm => openingStatus == 'SUBMITTED';
}

class CountItem {
  final String inventoryItemId;
  final String name;
  final String unitOfMeasure;
  final double? costPerUnit;
  final String effectiveRiskTier; // 'High' | 'Standard' | 'Low'
  // Only populated for opening confirmation (previous closing qty for low-risk confirm UX)
  final double? previousClosingQty;

  const CountItem({
    required this.inventoryItemId,
    required this.name,
    required this.unitOfMeasure,
    this.costPerUnit,
    required this.effectiveRiskTier,
    this.previousClosingQty,
  });

  factory CountItem.fromJson(Map<String, dynamic> j) => CountItem(
    inventoryItemId:    j['inventory_item_id'] as String,
    name:               j['name'] as String,
    unitOfMeasure:      j['unit_of_measure'] as String? ?? 'pcs',
    costPerUnit:        j['cost_per_unit'] != null
                          ? double.tryParse(j['cost_per_unit'].toString())
                          : null,
    effectiveRiskTier:  j['effective_risk_tier'] as String? ?? 'Standard',
    previousClosingQty: j['counted_quantity'] != null
                          ? double.tryParse(j['counted_quantity'].toString())
                          : null,
  );

  bool get requiresBlindCount => effectiveRiskTier == 'High' || effectiveRiskTier == 'Standard';
}
