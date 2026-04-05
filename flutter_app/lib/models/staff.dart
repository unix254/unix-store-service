class Staff {
  final String id;
  final String name;
  final String role; // 'kitchen' | 'store' | 'manager'

  const Staff({required this.id, required this.name, required this.role});

  factory Staff.fromJson(Map<String, dynamic> j) => Staff(
        id:   j['id']   as String,
        name: j['name'] as String,
        role: j['role'] as String,
      );

  bool get isStore   => role == 'store' || role == 'manager';
  bool get isKitchen => role == 'kitchen';
  bool get isManager => role == 'manager';
}
