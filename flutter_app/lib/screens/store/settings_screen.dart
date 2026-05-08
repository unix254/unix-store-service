import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/staff.dart';
import '../../services/api.dart';
import 'staff_management_screen.dart';
import 'stations_screen.dart';

/// Settings screen — Staff Management only.
/// Business Details have been moved to the Super Admin Dashboard.
class SettingsScreen extends StatefulWidget {
  final Staff staff;
  const SettingsScreen({super.key, required this.staff});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  late List<({String label, IconData icon, Widget body})> _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = [
      if (widget.staff.canManageStaff)
        (
          label: 'Staff Management',
          icon: Icons.badge_rounded,
          body: const StaffManagementScreen(),
        ),
      if (widget.staff.canManageStaff || widget.staff.canApproveRequisitions)
        (
          label: 'Kitchen Stations',
          icon: Icons.kitchen_rounded,
          body: const StationsScreen(),
        ),
    ];
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Header + Tabs ──────────────────────────────────────
        Container(
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 24, 24, 12),
                child: Row(
                  children: [
                    const Icon(Icons.settings_rounded,
                        color: AppTheme.pinTeal, size: 26),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Settings',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w700)),
                          Text('Business configuration & staff access',
                              style: TextStyle(
                                  fontSize: 12, color: AppTheme.pinMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_tabs.length > 1)
                TabBar(
                  controller: _tabCtrl,
                  labelColor: AppTheme.pinTeal,
                  unselectedLabelColor: AppTheme.pinMuted,
                  indicatorColor: AppTheme.pinTeal,
                  indicatorWeight: 3,
                  labelStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                  tabs: _tabs
                      .map((t) => Tab(
                            icon: Icon(t.icon, size: 18),
                            text: t.label,
                          ))
                      .toList(),
                ),
              const Divider(height: 1, color: Color(0xFFE0E0E0)),
            ],
          ),
        ),

        // ── Tab content ─────────────────────────────────────────
        Expanded(
          child: _tabs.length > 1
              ? TabBarView(
                  controller: _tabCtrl,
                  children: _tabs.map((t) => t.body).toList(),
                )
              : _tabs.isNotEmpty
                  ? _tabs.first.body
                  : const Center(
                      child: Text('No settings available',
                          style: TextStyle(color: AppTheme.pinMuted))),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Business Details Tab
// ─────────────────────────────────────────────────────────────────────────────

class _BusinessDetailsTab extends StatefulWidget {
  const _BusinessDetailsTab();

  @override
  State<_BusinessDetailsTab> createState() => _BusinessDetailsTabState();
}

class _BusinessDetailsTabState extends State<_BusinessDetailsTab> {
  final _formKey        = GlobalKey<FormState>();
  final _nameCtrl       = TextEditingController();
  final _sloganCtrl     = TextEditingController();
  final _ownerNameCtrl  = TextEditingController();
  final _ownerPhoneCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _successMsg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _sloganCtrl.dispose();
    _ownerNameCtrl.dispose();
    _ownerPhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final settings = await ApiService.instance.getSettings();
      setState(() {
        _nameCtrl.text       = settings['business_name'] ?? '';
        _sloganCtrl.text     = settings['slogan']        ?? '';
        _ownerNameCtrl.text  = settings['owner_name']    ?? '';
        _ownerPhoneCtrl.text = settings['owner_phone']   ?? '';
        _loading             = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; _successMsg = null; });
    try {
      await ApiService.instance.updateSettings({
        'business_name': _nameCtrl.text.trim(),
        'slogan':        _sloganCtrl.text.trim(),
        'owner_name':    _ownerNameCtrl.text.trim(),
        'owner_phone':   _ownerPhoneCtrl.text.trim(),
      });
      setState(() { _saving = false; _successMsg = 'Settings saved successfully.'; });
    } on ApiException catch (e) {
      setState(() { _saving = false; _error = e.message; });
    } catch (e) {
      setState(() { _saving = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Section title ──────────────────────────────
                const Text('Branding',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF263238))),
                const SizedBox(height: 4),
                Text(
                  'These details appear on the login screen and reports.',
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 28),

                // ── Business Name ──────────────────────────────
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Business Name *',
                    hintText: 'e.g. Aspire Hotel and Restaurant',
                    prefixIcon: Icon(Icons.storefront_rounded),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty)
                          ? 'Business name is required'
                          : null,
                ),
                const SizedBox(height: 20),

                // ── Slogan ─────────────────────────────────────
                TextFormField(
                  controller: _sloganCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Slogan / Tagline',
                    hintText: 'e.g. Premium Restaurant Management',
                    prefixIcon: Icon(Icons.format_quote_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 36),

                // ── Owner Contact section ──────────────────────
                const Text('Owner Contact',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF263238))),
                const SizedBox(height: 4),
                Text(
                  'Used to personalise and pre-fill the pay run WhatsApp approval message.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 20),

                // ── Owner Name ─────────────────────────────────
                TextFormField(
                  controller: _ownerNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Owner Name',
                    hintText: 'e.g. James Mwangi',
                    prefixIcon: Icon(Icons.person_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Owner Phone ────────────────────────────────
                TextFormField(
                  controller: _ownerPhoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Owner Phone (WhatsApp)',
                    hintText: 'e.g. 0712345678 or 254712345678',
                    prefixIcon: Icon(Icons.phone_android_rounded),
                    border: OutlineInputBorder(),
                    helperText:
                        'Kenyan numbers: enter as 07xx or 254xx — both work.',
                  ),
                ),
                const SizedBox(height: 32),

                // ── Preview card ───────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      vertical: 28, horizontal: 24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1923),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppTheme.pinTeal.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.storefront_rounded,
                            color: AppTheme.pinTeal, size: 30),
                      ),
                      const SizedBox(height: 12),
                      const Text('YUNIX STORE',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 4)),
                      const SizedBox(height: 6),
                      AnimatedBuilder(
                        animation: Listenable.merge(
                            [_nameCtrl, _sloganCtrl]),
                        builder: (_, __) => Column(children: [
                          if (_nameCtrl.text.isNotEmpty)
                            Text(
                              _nameCtrl.text,
                              style: const TextStyle(
                                  color: AppTheme.pinTeal,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700),
                              textAlign: TextAlign.center,
                            ),
                          if (_sloganCtrl.text.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                _sloganCtrl.text,
                                style: const TextStyle(
                                    color: AppTheme.pinMuted,
                                    fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                            ),
                        ]),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // ── Feedback ───────────────────────────────────
                if (_error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.debtRed.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppTheme.debtRed.withOpacity(0.4)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline_rounded,
                          color: AppTheme.debtRed, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: AppTheme.debtRed, fontSize: 13))),
                    ]),
                  ),
                if (_successMsg != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.paidGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppTheme.paidGreen.withOpacity(0.4)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.check_circle_outline_rounded,
                          color: AppTheme.paidGreen, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(_successMsg!,
                              style: const TextStyle(
                                  color: AppTheme.paidGreen, fontSize: 13))),
                    ]),
                  ),

                // ── Save button ────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_rounded, size: 18),
                    label: Text(_saving ? 'Saving…' : 'Save Settings'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.pinTeal,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
