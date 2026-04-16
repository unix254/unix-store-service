class Requisition {
  final String id;
  final String? inventoryItemId; // null for new-item requests
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
  /// Phase 8: actual quantity the storekeeper chose to issue (may differ from [quantity]).
  final double? issuedQuantity;
  /// Phase 8: storekeeper's note explaining an adjustment or rejection reason.
  final String? issueNotes;

  const Requisition({
    required this.id,
    this.inventoryItemId,
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
    this.issuedQuantity,
    this.issueNotes,
  });

  factory Requisition.fromJson(Map<String, dynamic> j) => Requisition(
        id:               j['id'] as String,
        inventoryItemId:  j['inventory_item_id'] as String?,
        itemName:         j['item_name'] as String? ?? '[New Item Request]',
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
        issuedQuantity:   double.tryParse(j['issued_quantity']?.toString() ?? ''),
        issueNotes:       j['issue_notes'] as String?,
      );

  bool get isPending   => status == 'Pending';
  bool get isIssued    => status == 'Issued';
  bool get isRejected  => status == 'Rejected';
  bool get isSales     => purpose == 'Sales';
  bool get isStaffMeal => purpose == 'Staff Meal';

  /// True when this requisition is a kitchen "new item" request (no inventory_item_id).
  bool get isNewItemRequest =>
      inventoryItemId == null &&
      notes != null &&
      notes!.startsWith('[NEW ITEM REQUEST]');

  /// Parses the item name from the structured notes prefix.
  /// e.g. "[NEW ITEM REQUEST] Name: Jasmine Rice | Qty: 5 kg | Notes: urgent"
  /// Returns null if not a new item request or notes are malformed.
  String? get newItemName {
    if (!isNewItemRequest) return null;
    final match = RegExp(r'Name:\s*([^|]+)').firstMatch(notes!);
    return match?.group(1)?.trim();
  }
}
