/// Full staff record used in the Staff Management screen.
/// (Different from [Staff] which is the minimal logged-in user session object.)
class StaffMember {
  final String id;
  final String name;
  final String role; // 'kitchen' | 'store' | 'manager'
  final bool active;
  final String? createdAt;

  const StaffMember({
    required this.id,
    required this.name,
    required this.role,
    required this.active,
    this.createdAt,
  });

  factory StaffMember.fromJson(Map<String, dynamic> j) => StaffMember(
        id: j['id'] as String,
        name: j['name'] as String,
        role: j['role'] as String,
        active: j['active'] == 1 || j['active'] == true,
        createdAt: j['created_at'] as String?,
      );

  String get roleLabel => switch (role) {
        'manager' => 'Manager',
        'store' => 'Store Keeper',
        'kitchen' => 'Kitchen Staff',
        _ => role,
      };

  bool get isManager => role == 'manager';
}
