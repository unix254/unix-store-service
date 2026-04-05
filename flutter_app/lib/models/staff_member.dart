/// Full staff record used in the Staff Management screen.
/// (Different from [Staff] which is the minimal logged-in user session object.)
class StaffMember {
  final String id;
  final String name;
  final String role; // 'kitchen' | 'store' | 'manager'
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
        'owner'   => 'Owner',
        'manager' => 'Manager',
        'store'   => 'Store Keeper',
        'kitchen' => 'Kitchen Staff',
        _         => role,
      };

  bool get isManager => role == 'manager';
  bool hasCapability(String cap) => capabilities.contains(cap);
}

/// All available capabilities with their display labels
const kAllCapabilities = <(String, String)>[
  ('can_approve_requisitions', 'Approve Requisitions'),
  ('can_manage_inventory',     'Manage Inventory'),
  ('can_draft_po',             'Draft Purchase Orders'),
  ('can_approve_payrun',       'Approve Pay Runs'),
  ('can_log_waste',            'Log Waste/Spoilage'),
  ('can_manage_staff',         'Manage Staff'),
  ('can_view_variance',        'View Variance Dashboard'),
];

/// Default capabilities seeded per role
List<String> defaultCapabilities(String role) => switch (role) {
      'kitchen' => ['can_log_waste'],
      'store'   => ['can_approve_requisitions', 'can_manage_inventory', 'can_draft_po', 'can_view_variance'],
      'manager' => ['can_approve_requisitions', 'can_manage_inventory', 'can_draft_po',
                    'can_approve_payrun', 'can_log_waste', 'can_manage_staff', 'can_view_variance'],
      'owner'   => kAllCapabilities.map((e) => e.$1).toList(),
      _         => [],
    };
