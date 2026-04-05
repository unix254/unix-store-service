class Staff {
  final String id;
  final String name;
  final String role; // 'kitchen' | 'store' | 'manager'
  final List<String> capabilities;
  final String? locationName;

  const Staff({
    required this.id,
    required this.name,
    required this.role,
    this.capabilities = const [],
    this.locationName,
  });

  factory Staff.fromJson(Map<String, dynamic> j) {
    List<String> caps = [];
    final rawCaps = j['capabilities'];
    if (rawCaps is List) {
      caps = rawCaps.map((e) => e.toString()).toList();
    }
    return Staff(
      id:           j['id']   as String,
      name:         j['name'] as String,
      role:         j['role'] as String,
      capabilities: caps,
      locationName: j['location_name'] as String?,
    );
  }

  /// Role shortcuts (keep for backward compat)
  bool get isStore   => role == 'store' || role == 'manager' || role == 'owner';
  bool get isKitchen => role == 'kitchen';
  bool get isManager => role == 'manager';
  bool get isOwner   => role == 'owner';

  /// Capability-based gating (use for new M6+ features)
  bool hasCapability(String cap) => capabilities.contains(cap);

  bool get canApproveRequisitions => hasCapability('can_approve_requisitions') || isManager || isOwner;
  bool get canManageInventory     => hasCapability('can_manage_inventory')     || isManager || isOwner;
  bool get canDraftPO             => hasCapability('can_draft_po')             || isManager || isOwner;
  bool get canApprovePayRun       => hasCapability('can_approve_payrun')       || isManager || isOwner;
  bool get canLogWaste            => hasCapability('can_log_waste')            || true; // all can log waste
  bool get canManageStaff         => hasCapability('can_manage_staff')         || isManager || isOwner;
  bool get canViewVariance        => hasCapability('can_view_variance')        || isManager || isOwner;
}
