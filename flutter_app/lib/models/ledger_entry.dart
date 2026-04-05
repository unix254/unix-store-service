class LedgerEntry {
  final String id;
  final String supplierId;
  final String transactionType; // 'PURCHASE' | 'PAYMENT'
  final double amount;
  final String? description;
  final String? referenceDoc;
  final String transactionDate;
  final String createdAt;
  final double? runningBalance;

  const LedgerEntry({
    required this.id,
    required this.supplierId,
    required this.transactionType,
    required this.amount,
    this.description,
    this.referenceDoc,
    required this.transactionDate,
    required this.createdAt,
    this.runningBalance,
  });

  factory LedgerEntry.fromJson(Map<String, dynamic> j) => LedgerEntry(
        id:               j['id'] as String,
        supplierId:       j['supplier_id'] as String,
        transactionType:  j['transaction_type'] as String,
        amount:           double.tryParse(j['amount']?.toString() ?? '0') ?? 0.0,
        description:      j['description'] as String?,
        referenceDoc:     j['reference_doc'] as String?,
        transactionDate:  j['transaction_date'] as String,
        createdAt:        j['created_at'] as String,
        runningBalance:   double.tryParse(j['running_balance']?.toString() ?? ''),
      );

  bool get isPurchase => transactionType == 'PURCHASE';
}
