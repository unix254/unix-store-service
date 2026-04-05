class PosProduct {
  final String id;
  final String name;
  final String? categoryName;
  final double pricesell;

  const PosProduct({
    required this.id,
    required this.name,
    this.categoryName,
    required this.pricesell,
  });

  factory PosProduct.fromJson(Map<String, dynamic> j) => PosProduct(
        id:           j['id'] as String,
        name:         j['name'] as String,
        categoryName: j['category_name'] as String?,
        pricesell:    double.tryParse(j['pricesell']?.toString() ?? '0') ?? 0,
      );

  /// For dropdowns: "Chicken Portion (Poultry)"
  String get displayLabel =>
      categoryName != null ? '$name  ·  $categoryName' : name;
}
