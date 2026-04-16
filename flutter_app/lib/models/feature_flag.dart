class FeatureFlag {
  final String featureKey;
  bool enabled; // mutable for optimistic toggle in UI
  final String label;
  final String description;

  FeatureFlag({
    required this.featureKey,
    required this.enabled,
    required this.label,
    required this.description,
  });

  factory FeatureFlag.fromJson(Map<String, dynamic> json) => FeatureFlag(
        featureKey:  json['feature_key']  as String,
        enabled:     (json['enabled'] as int) == 1,
        label:       json['label']        as String? ?? '',
        description: json['description']  as String? ?? '',
      );
}
