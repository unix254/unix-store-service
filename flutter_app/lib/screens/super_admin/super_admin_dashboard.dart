import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/feature_flag.dart';
import '../../services/api.dart';
import '../pin_login.dart';

/// Full-screen dashboard shown after Super Admin logs in via the backdoor.
/// Three tabs: Feature Flags toggle + Business Details config + Go-Live database wipe.
class SuperAdminDashboard extends StatefulWidget {
  /// Credentials carried from the login sheet — re-sent on the wipe call
  /// so the server re-validates before any destructive action.
  final String username;
  final String password;

  const SuperAdminDashboard({
    super.key,
    required this.username,
    required this.password,
  });

  @override
  State<SuperAdminDashboard> createState() => _SuperAdminDashboardState();
}

class _SuperAdminDashboardState extends State<SuperAdminDashboard> {
  List<FeatureFlag> _flags = [];
  bool _loadingFlags = true;
  String? _flagsError;

  @override
  void initState() {
    super.initState();
    _loadFlags();
  }

  Future<void> _loadFlags() async {
    setState(() { _loadingFlags = true; _flagsError = null; });
    try {
      final flags = await ApiService.instance.getFeatureFlags();
      if (!mounted) return;
      setState(() { _flags = flags; _loadingFlags = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _flagsError = e.toString(); _loadingFlags = false; });
    }
  }

  Future<void> _toggleFlag(FeatureFlag flag, bool newValue) async {
    // Optimistic update
    setState(() => flag.enabled = newValue);
    try {
      await ApiService.instance.updateFeatureFlag(flag.featureKey, newValue);
    } catch (e) {
      if (!mounted) return;
      // Revert on failure
      setState(() => flag.enabled = !newValue);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update flag: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _confirmGoLiveWipe() async {
    // ── Step 1: Info dialog ───────────────────────────────────
    final step1 = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A2E40),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 22),
          SizedBox(width: 8),
          Text('Go-Live Wipe',
              style: TextStyle(color: Colors.white, fontSize: 17)),
        ]),
        content: const Text(
          'This will permanently DELETE all transactional store_ data:\n\n'
          '❌  Supplier Ledger entries\n'
          '❌  Pay Runs & details\n'
          '❌  Requisitions\n'
          '❌  Purchase Orders & details\n\n'
          '✅  Suppliers, Inventory, Staff, Yield Config,\n'
          '     Business Settings and Feature Flags are KEPT.\n\n'
          'This action cannot be undone.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue →',
                style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
    if (step1 != true || !mounted) return;

    // ── Step 2: Type "GO LIVE" to confirm ─────────────────────
    final confirmCtrl = TextEditingController();
    final step2 = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A2E40),
        title: const Text('Final Confirmation',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Type  GO LIVE  below to confirm the wipe:',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: confirmCtrl,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2),
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'GO LIVE',
                hintStyle:
                    const TextStyle(color: Colors.grey, letterSpacing: 2),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: Color(0xFF2A3F50)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: Colors.red),
                ),
                filled: true,
                fillColor: const Color(0xFF0D1B2A),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          StatefulBuilder(
            builder: (_, setSt) => TextButton(
              onPressed: () {
                if (confirmCtrl.text.trim() == 'GO LIVE') {
                  Navigator.pop(context, true);
                } else {
                  setSt(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Type exactly: GO LIVE'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: const Text('WIPE DATABASE',
                  style: TextStyle(
                      color: Colors.red, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
    if (step2 != true || !mounted) return;

    // ── Execute wipe ───────────────────────────────────────────
    try {
      // Show a loading overlay
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: Card(
            color: Color(0xFF1A2E40),
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFFFF6B35)),
                  SizedBox(height: 16),
                  Text('Wiping transactional data…',
                      style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
        ),
      );

      final result = await ApiService.instance
          .goLiveWipe(widget.username, widget.password);

      if (!mounted) return;
      Navigator.pop(context); // close loading overlay

      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1A2E40),
          title: const Row(children: [
            Icon(Icons.check_circle_rounded, color: Colors.green, size: 22),
            SizedBox(width: 8),
            Text('Go-Live Ready',
                style: TextStyle(color: Colors.white)),
          ]),
          content: Text(
            result['message'] as String? ??
                'Transactional data cleared successfully.',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK',
                  style: TextStyle(color: Color(0xFFFF6B35))),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).popUntil(
          (r) => r.isFirst || r.settings.name == 'super-admin');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Wipe failed: $e'),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D1B2A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A2E40),
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Exit to Login',
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const PinLoginScreen()),
            ),
          ),
          title: const Row(
            children: [
              Icon(Icons.admin_panel_settings_rounded,
                  color: Color(0xFFFF6B35), size: 20),
              SizedBox(width: 8),
              Text(
                'Super Admin Dashboard',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          bottom: const TabBar(
            indicatorColor: Color(0xFFFF6B35),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(icon: Icon(Icons.toggle_on_rounded),     text: 'Feature Flags'),
              Tab(icon: Icon(Icons.business_rounded),       text: 'Business Details'),
              Tab(icon: Icon(Icons.restore_page_rounded),   text: 'Go-Live Reset'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _FeatureFlagsTab(
              flags:    _flags,
              loading:  _loadingFlags,
              error:    _flagsError,
              onToggle: _toggleFlag,
              onRetry:  _loadFlags,
            ),
            const _BusinessDetailsTab(),
            _GoLiveTab(onWipe: _confirmGoLiveWipe),
          ],
        ),
      ),
    );
  }
}

// ── Feature Flags Tab ──────────────────────────────────────────────────────

class _FeatureFlagsTab extends StatelessWidget {
  final List<FeatureFlag> flags;
  final bool loading;
  final String? error;
  final void Function(FeatureFlag, bool) onToggle;
  final VoidCallback onRetry;

  const _FeatureFlagsTab({
    required this.flags,
    required this.loading,
    required this.error,
    required this.onToggle,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFFFF6B35)));
    }
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error!,
                style: const TextStyle(color: Colors.red, fontSize: 13)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onRetry,
              child: const Text('Retry',
                  style: TextStyle(color: Color(0xFFFF6B35))),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text(
            'Toggle modules on or off for this client. Changes take effect immediately — '
            'staff will see the updated navigation on their next login.',
            style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.5),
          ),
        ),
        ...flags.map(
          (flag) => Card(
            color: const Color(0xFF1A2E40),
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            child: SwitchListTile(
              value: flag.enabled,
              onChanged: (v) => onToggle(flag, v),
              activeColor: const Color(0xFFFF6B35),
              title: Text(
                flag.label,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                flag.description,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Business Details Tab ───────────────────────────────────────────────────

/// Moved from settings_screen.dart — only the Super Admin can configure
/// core business branding (business name, slogan, owner contact).
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
  bool _saving  = false;
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
      if (!mounted) return;
      setState(() {
        _nameCtrl.text       = settings['business_name'] ?? '';
        _sloganCtrl.text     = settings['slogan']        ?? '';
        _ownerNameCtrl.text  = settings['owner_name']    ?? '';
        _ownerPhoneCtrl.text = settings['owner_phone']   ?? '';
        _loading             = false;
      });
    } catch (e) {
      if (!mounted) return;
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
      if (!mounted) return;
      setState(() { _saving = false; _successMsg = 'Business details saved.'; });
    } on ApiException catch (e) {
      setState(() { _saving = false; _error = e.message; });
    } catch (e) {
      setState(() { _saving = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFFFF6B35)));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Branding section
                const Text('Branding',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                const SizedBox(height: 4),
                const Text(
                  'These details appear on the login screen and reports.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 20),

                TextFormField(
                  controller: _nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: _fieldDeco('Business Name *', Icons.storefront_rounded),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Business name is required'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _sloganCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: _fieldDeco('Slogan / Tagline', Icons.format_quote_rounded),
                ),
                const SizedBox(height: 28),

                // Owner Contact section
                const Text('Owner Contact',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                const SizedBox(height: 4),
                const Text(
                  'Used to pre-fill the pay run WhatsApp approval message.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 20),

                TextFormField(
                  controller: _ownerNameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: _fieldDeco('Owner Name', Icons.person_rounded),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _ownerPhoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white),
                  decoration: _fieldDeco(
                      'Owner Phone (WhatsApp) — e.g. 0712345678',
                      Icons.phone_android_rounded),
                ),
                const SizedBox(height: 28),

                // Live preview
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1923),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF1A2E40)),
                  ),
                  child: Column(children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: AppTheme.pinTeal.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.storefront_rounded,
                          color: AppTheme.pinTeal, size: 26),
                    ),
                    const SizedBox(height: 10),
                    const Text('YUNIX STORE',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 4)),
                    AnimatedBuilder(
                      animation: Listenable.merge([_nameCtrl, _sloganCtrl]),
                      builder: (_, __) => Column(children: [
                        if (_nameCtrl.text.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(_nameCtrl.text,
                              style: const TextStyle(
                                  color: AppTheme.pinTeal,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700),
                              textAlign: TextAlign.center),
                        ],
                        if (_sloganCtrl.text.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(_sloganCtrl.text,
                              style: const TextStyle(
                                  color: AppTheme.pinMuted, fontSize: 11),
                              textAlign: TextAlign.center),
                        ],
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 24),

                // Feedback
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Text(_error!,
                        style: const TextStyle(
                            color: Color(0xFFEF5350), fontSize: 13)),
                  ),
                if (_successMsg != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(children: [
                      const Icon(Icons.check_circle_outline_rounded,
                          color: Colors.green, size: 16),
                      const SizedBox(width: 6),
                      Text(_successMsg!,
                          style: const TextStyle(
                              color: Colors.green, fontSize: 13)),
                    ]),
                  ),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B35),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_rounded, size: 18),
                    label: Text(_saving ? 'Saving…' : 'Save Business Details'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDeco(String label, IconData icon) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        prefixIcon: Icon(icon, color: Colors.grey),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF2A3F50)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFFF6B35)),
        ),
        filled: true,
        fillColor: const Color(0xFF1A2E40),
      );
}

// ── Go-Live Reset Tab ──────────────────────────────────────────────────────

class _GoLiveTab extends StatelessWidget {
  final VoidCallback onWipe;
  const _GoLiveTab({required this.onWipe});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Warning card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.red.shade800),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.orange, size: 20),
                  SizedBox(width: 8),
                  Text('Danger Zone',
                      style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                ]),
                const SizedBox(height: 12),
                const Text(
                  'The Go-Live Wipe clears all training / onboarding transaction data '
                  'so the client starts with a clean slate on opening day.',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 14),
                _dataRow('✅  KEPT',
                    'Suppliers · Inventory · Staff · Yield Config · Business Settings · Feature Flags'),
                const SizedBox(height: 6),
                _dataRow('❌  WIPED',
                    'Supplier Ledger · Pay Runs · Requisitions · Purchase Orders'),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Core uniCenta tables notice
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.07),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: Colors.blue.shade900),
            ),
            child: const Row(
              children: [
                Icon(Icons.shield_rounded,
                    color: Colors.blueAccent, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Core uniCenta tables (receipts, tickets, stockdiary, products, etc.) '
                    'are NEVER touched by this operation.',
                    style: TextStyle(
                        color: Colors.blueAccent,
                        fontSize: 12,
                        height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 36),

          Center(
            child: SizedBox(
              width: 290,
              height: 54,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 4,
                ),
                icon: const Icon(Icons.restore_page_rounded, size: 20),
                label: const Text(
                  'Clear Transactions & Go Live',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                ),
                onPressed: onWipe,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dataRow(String badge, String text) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(badge,
                style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style:
                      const TextStyle(color: Colors.grey, fontSize: 12)),
            ),
          ],
        ),
      );
}
