import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/api.dart';

/// Stations Management — add, edit, toggle, delete kitchen stations.
/// Accessible from Settings tab to anyone with canManageSettings or canApproveRequisitions.
class StationsScreen extends StatefulWidget {
  const StationsScreen({super.key});

  @override
  State<StationsScreen> createState() => _StationsScreenState();
}

class _StationsScreenState extends State<StationsScreen> {
  List<Map<String, dynamic>> _stations = [];
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
      final data = await ApiService.instance.getStations();
      if (!mounted) return;
      setState(() { _stations = data; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _add() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _StationFormDialog(),
    );
    if (result == null) return;
    try {
      await ApiService.instance.createStation(
        result['name']!,
        description: result['description']?.isEmpty == true ? null : result['description'],
      );
      _load();
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _edit(Map<String, dynamic> station) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _StationFormDialog(existing: station),
    );
    if (result == null) return;
    try {
      await ApiService.instance.updateStation(
        station['id'] as String,
        result['name']!,
        description: result['description']?.isEmpty == true ? null : result['description'],
      );
      _load();
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _toggle(Map<String, dynamic> station) async {
    final isActive = station['is_active'] == 1 || station['is_active'] == true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${isActive ? 'Deactivate' : 'Reactivate'} Station?'),
        content: Text(
          isActive
              ? '${station['name']} will no longer appear in the count picker.'
              : '${station['name']} will reappear in the count picker.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: isActive ? Colors.orange : AppTheme.paidGreen,
            ),
            child: Text(isActive ? 'Deactivate' : 'Reactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService.instance.toggleStation(station['id'] as String);
      _load();
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _delete(Map<String, dynamic> station) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete ${station['name']}?'),
        content: const Text(
          'This permanently removes the station and all its count history. '
          'Deactivating is safer and preserves audit history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
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
      await ApiService.instance.deleteStation(station['id'] as String);
      _load();
    } catch (e) {
      _showError(e.toString());
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.debtRed),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Sub-header ─────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(28, 20, 24, 16),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
          ),
          child: Row(
            children: [
              const Icon(Icons.kitchen_rounded, color: AppTheme.pinTeal, size: 22),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Kitchen Stations',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    Text(
                      'Stations appear in the closing/opening count picker for kitchen staff.',
                      style: TextStyle(fontSize: 12, color: AppTheme.pinMuted),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _loading ? null : _add,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Station'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.pinTeal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ],
          ),
        ),

        // ── Content ────────────────────────────────────────────
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
                  : _stations.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.kitchen_rounded,
                                  size: 72, color: Colors.grey.shade300),
                              const SizedBox(height: 16),
                              const Text('No stations yet',
                                  style: TextStyle(
                                      fontSize: 16, color: AppTheme.pinMuted)),
                              const SizedBox(height: 8),
                              const Text(
                                'Add your kitchen stations (e.g. Main Kitchen, Juice Station).\n'
                                'Staff select a station when submitting a count.',
                                style: TextStyle(
                                    fontSize: 13, color: AppTheme.pinMuted),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              FilledButton.icon(
                                onPressed: _add,
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Add First Station'),
                                style: FilledButton.styleFrom(
                                    backgroundColor: AppTheme.pinTeal),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(24),
                          itemCount: _stations.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final s = _stations[i];
                            final isActive =
                                s['is_active'] == 1 || s['is_active'] == true;
                            return Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: isActive
                                      ? const Color(0xFFE0E0E0)
                                      : Colors.grey.shade300,
                                ),
                              ),
                              color: isActive ? Colors.white : Colors.grey.shade50,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 14),
                                child: Row(
                                  children: [
                                    // Icon
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: isActive
                                            ? AppTheme.pinTeal.withValues(alpha: 0.1)
                                            : Colors.grey.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        Icons.kitchen_rounded,
                                        color: isActive
                                            ? AppTheme.pinTeal
                                            : Colors.grey,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 16),

                                    // Name + description
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                s['name'] as String,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                  color: isActive
                                                      ? const Color(0xFF263238)
                                                      : Colors.grey,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              if (!isActive)
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
                                          if ((s['description'] as String?)?.isNotEmpty == true)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 2),
                                              child: Text(
                                                s['description'] as String,
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    color: AppTheme.pinMuted),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),

                                    // Actions
                                    IconButton(
                                      icon: const Icon(Icons.edit_rounded, size: 18),
                                      color: Colors.blueGrey,
                                      tooltip: 'Edit',
                                      onPressed: () => _edit(s),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        isActive
                                            ? Icons.visibility_off_rounded
                                            : Icons.visibility_rounded,
                                        size: 18,
                                      ),
                                      color: isActive ? Colors.orange : AppTheme.paidGreen,
                                      tooltip: isActive ? 'Deactivate' : 'Reactivate',
                                      onPressed: () => _toggle(s),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded,
                                          size: 18),
                                      color: AppTheme.debtRed,
                                      tooltip: 'Delete permanently',
                                      onPressed: () => _delete(s),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}

// ── Station Form Dialog ────────────────────────────────────────────────────────

class _StationFormDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _StationFormDialog({this.existing});

  @override
  State<_StationFormDialog> createState() => _StationFormDialogState();
}

class _StationFormDialogState extends State<_StationFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
        text: widget.existing?['name'] as String? ?? '');
    _descCtrl = TextEditingController(
        text: widget.existing?['description'] as String? ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, {
      'name': _nameCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit Station' : 'Add Station'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Station Name *',
                  hintText: 'e.g. Main Kitchen, Juice Station, Prep Room',
                  prefixIcon: Icon(Icons.kitchen_rounded),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  hintText: 'e.g. Hot food prep area',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.pinTeal),
          child: Text(_isEdit ? 'Save Changes' : 'Add Station'),
        ),
      ],
    );
  }
}
