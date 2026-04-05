class YieldConfig {
  final String id;
  final String inventoryItemId;
  final String inventoryItemName;
  final String unitOfMeasure;
  final String unicentaProductId;
  final String? posProductName;
  final double portionsPerUnit;
  final String? notes;

  const YieldConfig({
    required this.id,
    required this.inventoryItemId,
    required this.inventoryItemName,
    required this.unitOfMeasure,
    required this.unicentaProductId,
    this.posProductName,
    required this.portionsPerUnit,
    this.notes,
  });

  factory YieldConfig.fromJson(Map<String, dynamic> j) => YieldConfig(
        id:                  j['id'] as String,
        inventoryItemId:     j['inventory_item_id'] as String,
        inventoryItemName:   j['inventory_item_name'] as String? ?? '–',
        unitOfMeasure:       j['unit_of_measure'] as String? ?? '',
        unicentaProductId:   j['unicenta_product_id'] as String,
        posProductName:      j['pos_product_name'] as String?,
        portionsPerUnit:     double.tryParse(j['portions_per_unit']?.toString() ?? '1') ?? 1,
        notes:               j['notes'] as String?,
      );

  /// Human-readable summary: "1 kg Whole Chicken → 8 × Chicken Portion"
  String get summary =>
      '1 $unitOfMeasure $inventoryItemName → '
      '${portionsPerUnit % 1 == 0 ? portionsPerUnit.toInt() : portionsPerUnit} × '
      '${posProductName ?? unicentaProductId}';
}
