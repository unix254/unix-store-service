/// Full staff record used in the Staff Management screen.
/// (Different from [Staff] which is the minimal logged-in user session object.)
class StaffMember {
  final String id;
  final String name;
  final String role; // 'kitchen' | 'store' | 'manager' | 'owner' | 'ict_admin'
  final bool active;
  final List<String> capabilities;
  final String? locationName;
  final String? createdAt;

  const StaffMember({
    required this.id,
    required this.name,
    required this.role,
    required this.active,
    this.capabilities = const [],
    this.locationName,
    this.createdAt,
  });

  factory StaffMember.fromJson(Map<String, dynamic> j) {
    List<String> caps = [];
    final rawCaps = j['capabilities'];
    if (rawCaps is List) {
      caps = rawCaps.map((e) => e.toString()).toList();
    }
    return StaffMember(
      id:           j['id'] as String,
      name:         j['name'] as String,
      role:         j['role'] as String,
      active:       j['active'] == 1 || j['active'] == true,
      capabilities: caps,
      locationName: j['location_name'] as String?,
      createdAt:    j['created_at'] as String?,
    );
  }

  String get roleLabel => switch (role) {
        'owner'     => 'Owner',
        'manager'   => 'Manager',
        'store'     => 'Store Keeper',
        'kitchen'   => 'Kitchen Staff',
        'ict_admin' => 'ICT Admin',
        _           => role,
      };

  bool get isManager  => role == 'manager';
  bool get isIctAdmin => role == 'ict_admin';
  bool hasCapability(String cap) => capabilities.contains(cap);
}

/// All available capabilities with their display labels.
const kAllCapabilities = <(String, String)>[
  // ── Core operations ─────────────────────────────────────────
  ('can_approve_requisitions',    'Approve Requisitions'),
  ('can_manage_inventory',        'Manage Inventory'),
  ('can_delete_inventory',        'Delete Inventory Item'),
  ('can_draft_po',                'Manage Purchase Orders'),
  ('can_manage_cycle_count',      'Manage Cycle Counts'),
  ('can_approve_payrun',          'Approve Pay Runs'),
  ('can_manage_staff',            'Manage Staff'),
  ('can_view_variance',           'View Variance Dashboard'),
  ('can_manage_settings',         'Manage System Settings'),
  // ── New capabilities (Phase 10) ──────────────────────────────
  ('can_manage_yield_config',     'Manage Yield Config'),
  ('can_manage_procurement',      'Manage Procurement'),
  ('can_manage_expense_accounts', 'Manage Expense Accounts'),
  // Milestone 16: BI Hub access (consolidates can_view_variance + can_manage_yield_config)
  ('can_access_bi',               'Access Business Intelligence Hub'),
  // v1.2.0: Kitchen station counts
  ('can_do_stock_count',          'Submit Kitchen Stock Counts'),
];

/// Default capabilities seeded per role when a new staff member is created.
List<String> defaultCapabilities(String role) => switch (role) {
      'kitchen'   => [],
      'store'     => [
                       'can_approve_requisitions',
                       'can_manage_inventory',
                       'can_draft_po',
                     ],
      'manager'   => [
                       'can_approve_requisitions',
                       'can_manage_inventory',
                       'can_delete_inventory',
                       'can_draft_po',
                       'can_manage_cycle_count',
                       'can_approve_payrun',
                       'can_manage_staff',
                       'can_view_variance',
                       'can_manage_settings',
                       'can_manage_yield_config',
                       'can_manage_procurement',
                       'can_manage_expense_accounts',
                       'can_access_bi',
                     ],
      'owner'     => kAllCapabilities.map((e) => e.$1).toList(),
      'ict_admin' => ['can_manage_settings'],
      _           => [],
    };
