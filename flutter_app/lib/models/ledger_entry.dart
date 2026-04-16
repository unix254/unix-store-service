class LedgerEntry {
  final String id;
  final String supplierId;
  final String transactionType; // 'PURCHASE' | 'PAYMENT' | 'SUPPLIER_PAYMENT' | 'CASH_IN'
  final double amount;
  final String? description;
  final String? referenceDoc;
  final String transactionDate;
  final String createdAt;
  final double? runningBalance;
  final String? relatedSupplierId;
  final String? relatedSupplierName;

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
    this.relatedSupplierId,
    this.relatedSupplierName,
  });

  factory LedgerEntry.fromJson(Map<String, dynamic> j) => LedgerEntry(
        id:                   j['id'] as String,
        supplierId:           j['supplier_id'] as String,
        transactionType:      j['transaction_type'] as String,
        amount:               double.tryParse(j['amount']?.toString() ?? '0') ?? 0.0,
        description:          j['description'] as String?,
        referenceDoc:         j['reference_doc'] as String?,
        transactionDate:      j['transaction_date'] as String,
        createdAt:            j['created_at'] as String,
        runningBalance:       double.tryParse(j['running_balance']?.toString() ?? ''),
        relatedSupplierId:    j['related_supplier_id'] as String?,
        relatedSupplierName:  j['related_supplier_name'] as String?,
      );

  /// True for transactions that increase a debit (spend) on the account.
  bool get isPurchase        => transactionType == 'PURCHASE';
  bool get isSupplierPayment => transactionType == 'SUPPLIER_PAYMENT';
  bool get isCashIn          => transactionType == 'CASH_IN';
  bool get isPayment         => transactionType == 'PAYMENT';
  bool get isOtherExpense    => transactionType == 'OTHER_EXPENSE';
  // CASH_IN is a credit (reduces outstanding balance), same as PAYMENT.
  // OTHER_EXPENSE is a debit (cash spent from float, no linked supplier record).
  bool get isDebit => isPurchase || isSupplierPayment || isOtherExpense;
}
