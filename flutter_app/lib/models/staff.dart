class Staff {
  final String id;
  final String name;
  final String role; // 'kitchen' | 'store' | 'manager' | 'owner' | 'ict_admin'
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

  /// Role shortcuts
  bool get isStore    => role == 'store' || role == 'manager' || role == 'owner' || role == 'ict_admin';
  bool get isKitchen  => role == 'kitchen';
  bool get isManager  => role == 'manager';
  bool get isOwner    => role == 'owner';
  bool get isIctAdmin => role == 'ict_admin';

  /// Capability-based gating — DB capabilities are the sole source of truth.
  bool hasCapability(String cap) => capabilities.contains(cap);

  // ── Existing capabilities ─────────────────────────────────────
  // Pattern A: capability only (no manager/owner fallback)
  bool get canManageInventory       => hasCapability('can_manage_inventory');
  bool get canDraftPO               => hasCapability('can_draft_po');
  bool get canLogWaste              => true; // every staff member may log waste
  bool get canManageStaff           => hasCapability('can_manage_staff');
  bool get canManageSettings        => hasCapability('can_manage_settings');

  // Pattern B: capability OR manager/owner fallback
  bool get canApproveRequisitions   => hasCapability('can_approve_requisitions') || isManager || isOwner;
  bool get canApprovePayRun         => hasCapability('can_approve_payrun')       || isManager || isOwner;
  bool get canViewVariance          => hasCapability('can_view_variance')        || isManager || isOwner;

  // ── New capabilities (Phase 10/11) ───────────────────────────
  bool get canDeleteInventory       => hasCapability('can_delete_inventory')       || isManager || isOwner;
  bool get canManageYieldConfig     => hasCapability('can_manage_yield_config')    || isManager || isOwner;
  bool get canManageProcurement     => hasCapability('can_manage_procurement')     || isManager || isOwner;
  bool get canManageCycleCount      => hasCapability('can_manage_cycle_count')     || isManager || isOwner;
  /// Access to Expense Accounts (manager float / Cash-In workflows).
  bool get canManageExpenseAccounts => hasCapability('can_manage_expense_accounts') || isManager || isOwner;

  // ── Milestone 16: Business Intelligence Hub ──────────────────
  /// Gates the entire BI Hub (Variance, Yield Config, Price Impact Advisory).
  /// Consolidates canViewVariance + canManageYieldConfig into a single flag.
  bool get canAccessBI => hasCapability('can_access_bi') || isManager || isOwner;
}
