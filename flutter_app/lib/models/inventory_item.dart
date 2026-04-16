class InventoryItem {
  final String id;
  final String name;
  final String? category;
  final String unitOfMeasure;
  final double quantityInStock;
  final double? reorderLevel;
  final double? costPerUnit;
  final String? supplierId;
  final String? supplierName;
  final String? defaultPurchaserId;
  final String? defaultPurchaserName;
  final String? notes;
  final bool needsReorder;

  const InventoryItem({
    required this.id,
    required this.name,
    this.category,
    required this.unitOfMeasure,
    required this.quantityInStock,
    this.reorderLevel,
    this.costPerUnit,
    this.supplierId,
    this.supplierName,
    this.defaultPurchaserId,
    this.defaultPurchaserName,
    this.notes,
    this.needsReorder = false,
  });

  factory InventoryItem.fromJson(Map<String, dynamic> j) => InventoryItem(
        id:                   j['id'] as String,
        name:                 j['name'] as String,
        category:             j['category'] as String?,
        unitOfMeasure:        j['unit_of_measure'] as String? ?? 'pcs',
        quantityInStock:      double.tryParse(j['quantity_in_stock']?.toString() ?? '0') ?? 0,
        reorderLevel:         double.tryParse(j['reorder_level']?.toString() ?? ''),
        costPerUnit:          double.tryParse(j['cost_per_unit']?.toString() ?? ''),
        supplierId:           j['supplier_id'] as String?,
        supplierName:         j['supplier_name'] as String?,
        defaultPurchaserId:   j['default_purchaser_id'] as String?,
        defaultPurchaserName: j['default_purchaser_name'] as String?,
        notes:                j['notes'] as String?,
        needsReorder:         (j['needs_reorder'] as num?)?.toInt() == 1,
      );

  /// Display label: "42.0 kg"
  String get stockLabel => '${quantityInStock.toStringAsFixed(1)} $unitOfMeasure';

  Map<String, dynamic> toFormJson() => {
        'name':                 name,
        'category':             category,
        'unit_of_measure':      unitOfMeasure,
        'quantity_in_stock':    quantityInStock,
        'reorder_level':        reorderLevel,
        'cost_per_unit':        costPerUnit,
        'supplier_id':          supplierId,
        'default_purchaser_id': defaultPurchaserId,
        'notes':                notes,
      };
}
