import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/staff_member.dart';
import '../../services/api.dart';

const _kLocations = ['Kitchen', 'Rooftop', 'Barista', 'Main Hall', 'Prep Room', 'Office'];

/// Manager-only screen for adding, editing, and deactivating staff PINs.
class StaffManagementScreen extends StatefulWidget {
  const StaffManagementScreen({super.key});

  @override
  State<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends State<StaffManagementScreen> {
  List<StaffMember> _staff = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await ApiService.instance.getAllStaff();
      setState(() { _staff = data; _loading = false; });
    } on ApiException catch (e) {
      setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _addStaff() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _StaffFormDialog(),
    );
    if (result == null) return;
    try {
      await ApiService.instance.createStaff(result);
      _load();
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _editStaff(StaffMember s) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _StaffFormDialog(existing: s),
    );
    if (result == null) return;
    try {
      await ApiService.instance.updateStaff(s.id, result);
      _load();
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _toggleActive(StaffMember s) async {
    final action = s.active ? 'deactivate' : 'reactivate';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${s.active ? 'Deactivate' : 'Reactivate'} ${s.name}?'),
        content: Text(s.active
            ? '${s.name} will no longer be able to log in.'
            : '${s.name} will be able to log in again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: s.active ? AppTheme.debtRed : AppTheme.paidGreen),
            child: Text(action[0].toUpperCase() + action.substring(1)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService.instance.toggleStaffActive(s.id);
      _load();
    } on ApiException catch (e) {
      _showError(e.message);
    }
  }

  Future<void> _deleteStaff(StaffMember s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete ${s.name}?'),
        content: const Text(
            'This permanently removes the staff record. '
            'Deactivating is safer and preserves audit history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.debtRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService.instance.deleteStaff(s.id);
      _load();
    } on ApiException catch (e) {
      _showError(e.message);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppTheme.debtRed));
  }

  @override
  Widget build(BuildContext context) {
    // Group by role order: owner → manager → store → kitchen
    final sorted = [..._staff]..sort((a, b) {
      const order = {'owner': 0, 'manager': 1, 'store': 2, 'kitchen': 3};
      final cmp = (order[a.role] ?? 9).compareTo(order[b.role] ?? 9);
      return cmp != 0 ? cmp : a.name.compareTo(b.name);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ───────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(28, 24, 24, 16),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
          ),
          child: Row(
            children: [
              const Icon(Icons.badge_rounded, color: AppTheme.pinTeal, size: 26),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Staff Management',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    Text('Add, edit, or deactivate staff PIN access',
                        style: TextStyle(fontSize: 12, color: AppTheme.pinMuted)),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _addStaff,
                icon: const Icon(Icons.person_add_rounded, size: 18),
                label: const Text('Add Staff'),
                style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.pinTeal),
              ),
            ],
          ),
        ),

        // ── Content ───────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              size: 48, color: AppTheme.debtRed),
                          const SizedBox(height: 12),
                          Text(_error!,
                              style: const TextStyle(color: AppTheme.debtRed)),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : sorted.isEmpty
                      ? const Center(
                          child: Text('No staff found.',
                              style: TextStyle(color: AppTheme.pinMuted)))
                      : ListView.separated(
                          padding: const EdgeInsets.all(24),
                          itemCount: sorted.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _StaffCard(
                            member: sorted[i],
                            onEdit: () => _editStaff(sorted[i]),
                            onToggle: () => _toggleActive(sorted[i]),
                            onDelete: () => _deleteStaff(sorted[i]),
                          ),
                        ),
        ),
      ],
    );
  }
}

// ── Staff Card ──────────────────────────────────────────────────────────────

class _StaffCard extends StatelessWidget {
  final StaffMember member;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _StaffCard({
    required this.member,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  static const _roleColors = {
    'owner':   Color(0xFF1565C0),
    'manager': Color(0xFF7B1FA2),
    'store':   AppTheme.pinTeal,
    'kitchen': Color(0xFFF57C00),
  };

  @override
  Widget build(BuildContext context) {
    final roleColor = _roleColors[member.role] ?? Colors.grey;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: member.active
                ? const Color(0xFFE0E0E0)
                : Colors.grey.shade300),
      ),
      color: member.active ? Colors.white : Colors.grey.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 22,
              backgroundColor: roleColor.withOpacity(member.active ? 0.15 : 0.07),
              child: Text(
                member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                style: TextStyle(
                    color: member.active ? roleColor : Colors.grey,
                    fontWeight: FontWeight.w800,
                    fontSize: 16),
              ),
            ),
            const SizedBox(width: 16),

            // Name + role badge
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(member.name,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: member.active
                                  ? const Color(0xFF263238)
                                  : Colors.grey)),
                      const SizedBox(width: 8),
                      if (!member.active)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('INACTIVE',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      // Role badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: roleColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(member.roleLabel,
                            style: TextStyle(
                                fontSize: 11,
                                color: roleColor,
                                fontWeight: FontWeight.w600)),
                      ),
                      // Location badge
                      if (member.locationName != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blueGrey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.location_on_rounded,
                                  size: 10, color: Colors.blueGrey),
                              const SizedBox(width: 3),
                              Text(member.locationName!,
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.blueGrey)),
                            ],
                          ),
                        ),
                      // Capability count badge
                      if (member.capabilities.isNotEmpty)
                        Tooltip(
                          message: member.capabilities
                              .map((c) => kAllCapabilities
                                  .firstWhere((k) => k.$1 == c,
                                      orElse: () => (c, c))
                                  .$2)
                              .join('\n'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.pinTeal.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('${member.capabilities.length} capabilities',
                                style: const TextStyle(
                                    fontSize: 11, color: AppTheme.pinTeal)),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // PIN mask hint
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: const Color(0xFFE0E0E0)),
              ),
              child: const Text('PIN: ••••',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.pinMuted,
                      fontFamily: 'monospace')),
            ),
            const SizedBox(width: 12),

            // Actions
            IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_rounded, size: 18),
              color: Colors.blueGrey,
              tooltip: 'Edit',
            ),
            IconButton(
              onPressed: onToggle,
              icon: Icon(
                member.active
                    ? Icons.person_off_rounded
                    : Icons.person_rounded,
                size: 18,
              ),
              color: member.active ? Colors.orange : AppTheme.paidGreen,
              tooltip: member.active ? 'Deactivate' : 'Reactivate',
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              color: AppTheme.debtRed,
              tooltip: 'Delete permanently',
            ),
          ],
        ),
      ),
    );
  }
}

// ── Staff Form Dialog ───────────────────────────────────────────────────────

class _StaffFormDialog extends StatefulWidget {
  final StaffMember? existing;
  const _StaffFormDialog({this.existing});

  @override
  State<_StaffFormDialog> createState() => _StaffFormDialogState();
}

class _StaffFormDialogState extends State<_StaffFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _pin;
  late final TextEditingController _pinConfirm;
  String _role = 'kitchen';
  String? _locationName;
  late List<String> _capabilities;
  bool _showPin = false;
  bool _showCapabilities = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _name         = TextEditingController(text: widget.existing?.name ?? '');
    _pin          = TextEditingController();
    _pinConfirm   = TextEditingController();
    _role         = widget.existing?.role ?? 'kitchen';
    _locationName = widget.existing?.locationName;
    _capabilities = widget.existing?.capabilities.toList()
        ?? defaultCapabilities('kitchen');
  }

  void _onRoleChanged(String role) {
    setState(() {
      _role = role;
      // Seed default capabilities when role changes (only if not editing)
      if (!_isEdit) _capabilities = defaultCapabilities(role);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    _pinConfirm.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final body = <String, dynamic>{
      'name':          _name.text.trim(),
      'role':          _role,
      'capabilities':  _capabilities,
      'location_name': _locationName,
    };
    if (_pin.text.isNotEmpty) body['pin'] = _pin.text;
    if (!_isEdit) body['pin'] = _pin.text; // required for create
    Navigator.pop(context, body);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit Staff Member' : 'Add Staff Member'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
        child: SingleChildScrollView(
          child: SizedBox(
            width: 420,
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              // Name
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                    labelText: 'Full Name *',
                    prefixIcon: Icon(Icons.person_outline_rounded)),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 16),

              // Role
              const Text('Role *',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.pinMuted,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (final (r, label) in [
                    ('kitchen', '🍳 Kitchen'),
                    ('store',   '📦 Store'),
                    ('manager','👔 Manager'),
                    ('owner',  '👑 Owner'),
                  ])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(label,
                              style: const TextStyle(fontSize: 12)),
                          selected: _role == r,
                          onSelected: (_) => _onRoleChanged(r),
                          selectedColor: AppTheme.pinTeal.withOpacity(0.2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // PIN
              TextFormField(
                controller: _pin,
                obscureText: !_showPin,
                maxLength: 4,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _isEdit ? 'New PIN (leave blank to keep)' : 'PIN *',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(_showPin
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded),
                    onPressed: () => setState(() => _showPin = !_showPin),
                  ),
                  counterText: '',
                ),
                validator: (v) {
                  if (!_isEdit && (v == null || v.isEmpty)) return 'PIN is required';
                  if (v != null && v.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(v)) {
                    return 'PIN must be exactly 4 digits';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // PIN confirm
              TextFormField(
                controller: _pinConfirm,
                obscureText: !_showPin,
                maxLength: 4,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Confirm PIN',
                  prefixIcon: Icon(Icons.lock_outline_rounded),
                  counterText: '',
                ),
                validator: (v) {
                  if (_pin.text.isNotEmpty && v != _pin.text) {
                    return 'PINs do not match';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Location
              DropdownButtonFormField<String?>(
                value: _locationName,
                decoration: const InputDecoration(
                  labelText: 'Location (optional)',
                  prefixIcon: Icon(Icons.location_on_rounded),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Not assigned')),
                  ..._kLocations.map((l) =>
                      DropdownMenuItem<String?>(value: l, child: Text(l))),
                ],
                onChanged: (v) => setState(() => _locationName = v),
              ),
              const SizedBox(height: 16),

              // Capabilities
              GestureDetector(
                onTap: () => setState(() => _showCapabilities = !_showCapabilities),
                child: Row(
                  children: [
                    const Text('Capabilities',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.pinMuted,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    Text('(${_capabilities.length} selected)',
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.pinTeal)),
                    const Spacer(),
                    Icon(
                      _showCapabilities
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: AppTheme.pinMuted,
                    ),
                  ],
                ),
              ),
              if (_showCapabilities) ...[
                const SizedBox(height: 8),
                ...kAllCapabilities.map((cap) {
                  final (key, label) = cap;
                  return CheckboxListTile(
                    dense: true,
                    value: _capabilities.contains(key),
                    title: Text(label, style: const TextStyle(fontSize: 13)),
                    activeColor: AppTheme.pinTeal,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _capabilities = [..._capabilities, key];
                      } else {
                        _capabilities = _capabilities.where((c) => c != key).toList();
                      }
                    }),
                  );
                }),
              ],
            ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.pinTeal),
          child: Text(_isEdit ? 'Save Changes' : 'Add Staff'),
        ),
      ],
    );
  }
}
