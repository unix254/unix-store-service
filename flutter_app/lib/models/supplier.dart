class Supplier {
  final String id;
  final String name;
  final String? phone;
  final String? location;
  final String? paymentDay;
  final int leadTimeDays;
  final String? notes;
  final double balanceDue;

  const Supplier({
    required this.id,
    required this.name,
    this.phone,
    this.location,
    this.paymentDay,
    this.leadTimeDays = 1,
    this.notes,
    this.balanceDue = 0,
  });

  factory Supplier.fromJson(Map<String, dynamic> j) => Supplier(
        id:           j['id'] as String,
        name:         j['name'] as String,
        phone:        j['phone'] as String?,
        location:     j['location'] as String?,
        paymentDay:   j['payment_day'] as String?,
        leadTimeDays: (j['lead_time_days'] as num?)?.toInt() ?? 1,
        notes:        j['notes'] as String?,
        balanceDue:   double.tryParse(j['balance_due']?.toString() ?? '0') ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'name':           name,
        'phone':          phone,
        'location':       location,
        'payment_day':    paymentDay,
        'lead_time_days': leadTimeDays,
        'notes':          notes,
      };
}
