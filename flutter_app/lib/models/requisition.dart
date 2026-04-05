class Requisition {
  final String id;
  final String inventoryItemId;
  final String itemName;
  final String? itemUom;
  final double quantity;
  final String? unitOfMeasure;
  final String requestedBy;
  final String purpose;   // 'Sales' | 'Staff Meal' | 'Wastage' | 'Other'
  final String status;    // 'Pending' | 'Approved' | 'Issued' | 'Rejected'
  final String? notes;
  final String requestedAt;
  final String? issuedAt;
  final String? issuedBy;

  const Requisition({
    required this.id,
    required this.inventoryItemId,
    required this.itemName,
    this.itemUom,
    required this.quantity,
    this.unitOfMeasure,
    required this.requestedBy,
    required this.purpose,
    required this.status,
    this.notes,
    required this.requestedAt,
    this.issuedAt,
    this.issuedBy,
  });

  factory Requisition.fromJson(Map<String, dynamic> j) => Requisition(
        id:               j['id'] as String,
        inventoryItemId:  j['inventory_item_id'] as String,
        itemName:         j['item_name'] as String? ?? 'Unknown',
        itemUom:          j['item_uom'] as String?,
        quantity:         double.tryParse(j['quantity']?.toString() ?? '0') ?? 0,
        unitOfMeasure:    j['unit_of_measure'] as String?,
        requestedBy:      j['requested_by'] as String? ?? '—',
        purpose:          j['purpose'] as String? ?? 'Sales',
        status:           j['status'] as String? ?? 'Pending',
        notes:            j['notes'] as String?,
        requestedAt:      j['requested_at'] as String? ?? '',
        issuedAt:         j['issued_at'] as String?,
        issuedBy:         j['issued_by'] as String?,
      );

  bool get isPending  => status == 'Pending';
  bool get isIssued   => status == 'Issued';
  bool get isRejected => status == 'Rejected';
  bool get isSales    => purpose == 'Sales';
  bool get isStaffMeal => purpose == 'Staff Meal';
}
