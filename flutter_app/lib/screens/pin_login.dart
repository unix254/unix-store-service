import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';
import '../models/staff.dart';
import '../models/staff_member.dart';
import '../services/api.dart';
import 'store/store_shell.dart';
import 'kitchen/kitchen_home.dart';
import 'super_admin/super_admin_dashboard.dart';

class PinLoginScreen extends StatefulWidget {
  const PinLoginScreen({super.key});

  @override
  State<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends State<PinLoginScreen> {
  // Staff grid
  List<StaffMember> _staff = [];
  bool _loadingStaff = true;
  String? _staffError;
  String _selectedRole = 'all';

  List<String> get _availableRoles {
    final rolesInDb = _staff.map((s) => s.role).toSet();
    final desiredOrder = const ['all', 'kitchen', 'store', 'manager', 'owner'];
    return desiredOrder.where((r) => r == 'all' || rolesInDb.contains(r)).toList();
  }

  Color _getRoleColor(String role) {
    if (role == 'all') return AppTheme.pinTeal;
    return _StaffGrid._roleColor(role);
  }

  List<StaffMember> get _filteredStaff {
    if (_selectedRole == 'all') return _staff;
    return _staff.where((s) => s.role == _selectedRole).toList();
  }


  // Branding
  String? _businessName;
  String? _slogan;

  // Super-admin backdoor: tap the logo 5 times within 2 seconds
  int _tapCount = 0;
  Timer? _tapTimer;

  @override
  void initState() {
    super.initState();
    _loadBranding();
    _loadStaff();
  }

  @override
  void dispose() {
    _tapTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadBranding() async {
    try {
      final settings = await ApiService.instance.getSettings();
      if (!mounted) return;
      setState(() {
        _businessName = settings['business_name'];
        _slogan       = settings['slogan'];
      });
    } catch (_) {
      // Branding is cosmetic — silently ignore failures
    }
  }

  Future<void> _loadStaff() async {
    setState(() { _loadingStaff = true; _staffError = null; });
    try {
      final all = await ApiService.instance.getAllStaff();
      if (!mounted) return;
      setState(() {
        _staff        = all.where((s) => s.active).toList();
        _loadingStaff = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _staffError   = 'Could not load staff list.\nIs the server running?';
        _loadingStaff = false;
      });
    }
  }

  // ── Super-admin backdoor ───────────────────────────────────────
  void _onLogoTap() {
    _tapCount++;
    _tapTimer?.cancel();
    if (_tapCount >= 5) {
      _tapCount = 0;
      _showSuperAdminModal();
      return;
    }
    _tapTimer = Timer(const Duration(seconds: 2), () => _tapCount = 0);
  }

  void _showSuperAdminModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SuperAdminLoginSheet(
        onSuccess: (username, password) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) =>
                  SuperAdminDashboard(username: username, password: password),
            ),
          );
        },
      ),
    );
  }

  // ── Staff tap → PIN sheet ──────────────────────────────────────
  void _onSelectStaff(StaffMember member) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: false,
      builder: (_) => _PinEntrySheet(
        staffName: member.name,
        onAuthenticated: _navigate,
      ),
    );
  }

  void _navigate(Staff staff) {
    final dest = staff.isStore
        ? StoreShell(staff: staff)
        : KitchenHome(staff: staff);
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, a, __) => dest,
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.pinBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 700;
            if (isWide) {
              return Row(
                children: [
                  // Splitted Sidebar
                  Container(
                    width: 280,
                    decoration: const BoxDecoration(
                      color: Color(0xFF152028),
                      border: Border(right: BorderSide(color: Color(0xFF202F3A), width: 1)),
                    ),
                    child: Column(
                      children: [
                        _buildBrandingHeader(isWide: true),
                        const SizedBox(height: 12),
                        Expanded(child: _buildRoleSidebar()),
                      ],
                    ),
                  ),
                  // Grid Area
                  Expanded(
                    child: Column(
                      children: [
                        _buildGreetingBar(),
                        Expanded(child: _buildGrid()),
                      ],
                    ),
                  ),
                ],
              );
            }
            
            // Narrow Layout
            return Column(
              children: [
                _buildBrandingHeader(isWide: false),
                _buildRoleTabs(),
                const SizedBox(height: 4),
                Expanded(child: _buildGrid()),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBrandingHeader({required bool isWide}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, isWide ? 40 : 32, 24, isWide ? 10 : 20),
      child: Column(
        children: [
          GestureDetector(
            onTap: _onLogoTap,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.pinTeal.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.storefront_rounded,
                  color: AppTheme.pinTeal, size: 36),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'YUNIX STORE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: 5,
            ),
          ),
          if (_businessName != null && _businessName!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              _businessName!,
              style: const TextStyle(
                color: AppTheme.pinTeal,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (_slogan != null && _slogan!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              _slogan!,
              style: const TextStyle(
                  color: AppTheme.pinMuted, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
          if (!isWide) ...[
            const SizedBox(height: 10),
            const Text(
              'Select your name to sign in',
              style: TextStyle(color: AppTheme.pinMuted, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGreetingBar() {
    return Padding(
      padding: const EdgeInsets.only(left: 32, top: 40, bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Welcome Back 👋',
              style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 4),
            Text(
              'Select your name from the grid to sign in',
              style: TextStyle(color: AppTheme.pinMuted, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleSidebar() {
    if (_loadingStaff) return const SizedBox.shrink();
    return ListView.builder(
      itemCount: _availableRoles.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (context, index) {
        final role = _availableRoles[index];
        final isSelected = _selectedRole == role;
        final color = _getRoleColor(role);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Material(
            color: isSelected ? color.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _selectedRole = role),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(
                      _roleIcon(role),
                      color: isSelected ? color : AppTheme.pinMuted,
                      size: 22,
                    ),
                    const SizedBox(width: 14),
                    Text(
                      _roleLabelUI(role),
                      style: TextStyle(
                        color: isSelected ? color : AppTheme.pinMuted,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRoleTabs() {
    if (_loadingStaff) return const SizedBox.shrink();
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _availableRoles.length,
        itemBuilder: (context, index) {
          final role = _availableRoles[index];
          final isSelected = _selectedRole == role;
          final color = _getRoleColor(role);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: isSelected ? color : const Color(0xFF1E2A35),
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => setState(() => _selectedRole = role),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: Text(
                      _roleLabelUI(role),
                      style: TextStyle(
                        color: isSelected ? Colors.white : color.withOpacity(0.8),
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _roleLabelUI(String role) {
    if (role == 'all') return 'All Staff';
    return _StaffGrid._roleLabel(role);
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'all': return Icons.group_outlined;
      case 'owner': return Icons.verified_user_outlined;
      case 'manager': return Icons.person_pin_outlined;
      case 'store': return Icons.inventory_2_outlined;
      default: return Icons.restaurant_menu_outlined;
    }
  }

  Widget _buildGrid() {
    if (_loadingStaff) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.pinTeal));
    }
    if (_staffError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  color: AppTheme.pinMuted, size: 48),
              const SizedBox(height: 12),
              Text(
                _staffError!,
                style:
                    const TextStyle(color: AppTheme.pinMuted, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _loadStaff,
                child: const Text('Retry',
                    style: TextStyle(color: AppTheme.pinTeal)),
              ),
            ],
          ),
        ),
      );
    }
    if (_staff.isEmpty) {
      return const Center(
        child: Text(
          'No active staff found.\nAdd staff in Settings.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.pinMuted, fontSize: 13),
        ),
      );
    }
    if (_filteredStaff.isEmpty) {
      return Center(
        child: Text(
          'No $_selectedRole staff found.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.pinMuted, fontSize: 13),
        ),
      );
    }
    return _StaffGrid(staff: _filteredStaff, onSelect: _onSelectStaff);
  }
}

// ── Staff Grid ─────────────────────────────────────────────────────────────

class _StaffGrid extends StatelessWidget {
  final List<StaffMember> staff;
  final void Function(StaffMember) onSelect;

  const _StaffGrid({required this.staff, required this.onSelect});

  static Color _roleColor(String role) {
    switch (role) {
      case 'owner':     return const Color(0xFFFFB300);
      case 'manager':   return const Color(0xFF26C6DA);
      case 'store':     return const Color(0xFF66BB6A);
      case 'ict_admin': return const Color(0xFF0097A7);
      default:          return const Color(0xFF78909C); // kitchen
    }
  }

  static String _roleLabel(String role) {
    switch (role) {
      case 'owner':     return 'Owner';
      case 'manager':   return 'Manager';
      case 'store':     return 'Storekeeper';
      case 'ict_admin': return 'ICT Admin';
      default:          return 'Kitchen';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: staff.length,
      itemBuilder: (_, i) {
        final s = staff[i];
        final color = _roleColor(s.role);
        return Material(
          color: const Color(0xFF1E2A35),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            splashColor: color.withOpacity(0.2),
            onTap: () => onSelect(s),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: color.withOpacity(0.18),
                    child: Text(
                      s.name.isNotEmpty ? s.name[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: color,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    s.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _roleLabel(s.role),
                      style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── PIN Entry Bottom Sheet ─────────────────────────────────────────────────

class _PinEntrySheet extends StatefulWidget {
  final String staffName;
  final void Function(Staff) onAuthenticated;

  const _PinEntrySheet({
    required this.staffName,
    required this.onAuthenticated,
  });

  @override
  State<_PinEntrySheet> createState() => _PinEntrySheetState();
}

class _PinEntrySheetState extends State<_PinEntrySheet>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  bool _loading = false;
  String? _error;

  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450));
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -12.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -12.0, end: 12.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 12.0, end: -8.0),  weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0),   weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: 0.0),    weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _tap(String digit) {
    if (_loading || _pin.length >= 4) return;
    HapticFeedback.lightImpact();
    setState(() {
      _pin  += digit;
      _error = null;
    });
    if (_pin.length == 4) _submit();
  }

  void _delete() {
    if (_loading || _pin.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      final Staff staff = await ApiService.instance.verifyPin(_pin);
      if (!mounted) return;
      Navigator.pop(context); // close sheet
      widget.onAuthenticated(staff);
    } on ApiException catch (e) {
      HapticFeedback.vibrate();
      _shakeCtrl.forward(from: 0);
      setState(() {
        _pin    = '';
        _error  = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pin    = '';
        _error  = 'Connection error. Try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF152028),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Staff name
          Text(
            widget.staffName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Enter your 4-digit PIN',
            style: TextStyle(color: AppTheme.pinMuted, fontSize: 13),
          ),
          const SizedBox(height: 24),

          // PIN dots with shake
          AnimatedBuilder(
            animation: _shakeAnim,
            builder: (_, child) => Transform.translate(
              offset: Offset(_shakeAnim.value, 0),
              child: child,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                4,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _pin.length
                        ? AppTheme.pinTeal
                        : Colors.transparent,
                    border: Border.all(
                      color: i < _pin.length
                          ? AppTheme.pinTeal
                          : const Color(0xFF546E7A),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Error message
          AnimatedOpacity(
            opacity: _error != null ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error ?? '',
                style:
                    const TextStyle(color: Color(0xFFEF5350), fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Numpad or spinner
          if (_loading)
            const SizedBox(
              height: 240,
              child: Center(
                  child:
                      CircularProgressIndicator(color: AppTheme.pinTeal)),
            )
          else
            _Numpad(onTap: _tap, onDelete: _delete),
        ],
      ),
    );
  }
}

// ── Super Admin Login Sheet ────────────────────────────────────────────────

class _SuperAdminLoginSheet extends StatefulWidget {
  final void Function(String username, String password) onSuccess;
  const _SuperAdminLoginSheet({required this.onSuccess});

  @override
  State<_SuperAdminLoginSheet> createState() => _SuperAdminLoginSheetState();
}

class _SuperAdminLoginSheetState extends State<_SuperAdminLoginSheet> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure  = true;
  bool _loading  = false;
  String? _error;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_usernameCtrl.text.isEmpty || _passwordCtrl.text.isEmpty) {
      setState(() => _error = 'Username and password are required');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ApiService.instance.superAdminLogin(
        _usernameCtrl.text.trim(),
        _passwordCtrl.text,
      );
      if (!mounted) return;
      widget.onSuccess(_usernameCtrl.text.trim(), _passwordCtrl.text);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _error = e.message; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = 'Connection error. Try again.'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D1B2A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 28,
        right: 28,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          const Icon(Icons.admin_panel_settings_rounded,
              color: Color(0xFFFF6B35), size: 36),
          const SizedBox(height: 10),
          const Text(
            'Super Admin Access',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'System administrator credentials required',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 24),

          // Username
          TextField(
            controller: _usernameCtrl,
            style: const TextStyle(color: Colors.white),
            textInputAction: TextInputAction.next,
            decoration: _inputDeco('Username', Icons.person_outline),
          ),
          const SizedBox(height: 12),

          // Password
          TextField(
            controller: _passwordCtrl,
            obscureText: _obscure,
            style: const TextStyle(color: Colors.white),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _login(),
            decoration: _inputDeco('Password', Icons.lock_outline).copyWith(
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(
                    color: Color(0xFFEF5350), fontSize: 13)),
          ],
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                disabledBackgroundColor:
                    const Color(0xFFFF6B35).withOpacity(0.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _loading ? null : _login,
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Text(
                      'Login as Super Admin',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDeco(String label, IconData icon) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        prefixIcon: Icon(icon, color: Colors.grey),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2A3F50)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFF6B35)),
        ),
        filled: true,
        fillColor: const Color(0xFF1A2E40),
      );
}

// ── Numpad ─────────────────────────────────────────────────────────────────

class _Numpad extends StatelessWidget {
  final void Function(String) onTap;
  final VoidCallback onDelete;

  const _Numpad({required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _row(['1', '2', '3']),
        const SizedBox(height: 14),
        _row(['4', '5', '6']),
        const SizedBox(height: 14),
        _row(['7', '8', '9']),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 88),
            const SizedBox(width: 14),
            _NumKey(label: '0', onTap: () => onTap('0')),
            const SizedBox(width: 14),
            _DeleteKey(onDelete: onDelete),
          ],
        ),
      ],
    );
  }

  Widget _row(List<String> digits) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: digits
            .asMap()
            .entries
            .map((e) => Padding(
                  padding: EdgeInsets.only(left: e.key > 0 ? 14 : 0),
                  child:
                      _NumKey(label: e.value, onTap: () => onTap(e.value)),
                ))
            .toList(),
      );
}

class _NumKey extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _NumKey({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.pinSlate,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        splashColor: AppTheme.pinTeal.withOpacity(0.3),
        child: SizedBox(
          width: 88,
          height: 68,
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeleteKey extends StatelessWidget {
  final VoidCallback onDelete;
  const _DeleteKey({required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.pinSlate,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onDelete,
        child: const SizedBox(
          width: 88,
          height: 68,
          child: Center(
            child: Icon(Icons.backspace_outlined,
                color: AppTheme.pinMuted, size: 24),
          ),
        ),
      ),
    );
  }
}
