import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/staff.dart';
import '../pin_login.dart';
import 'supplier_ledger.dart';
import 'requisition_approval.dart';
import 'inventory_screen.dart';
import 'yield_config_screen.dart';
import 'variance_screen.dart';
import 'staff_management_screen.dart';

enum _NavItem { suppliers, inventory, requisitions, yield_, variance, staff }

class StoreShell extends StatefulWidget {
  final Staff staff;
  const StoreShell({super.key, required this.staff});

  @override
  State<StoreShell> createState() => _StoreShellState();
}

class _StoreShellState extends State<StoreShell> {
  _NavItem _selected = _NavItem.suppliers;

  // Core nav items available to all store/manager roles
  static const _coreNavItems = [
    (icon: Icons.people_alt_rounded,  label: 'Suppliers',     item: _NavItem.suppliers),
    (icon: Icons.inventory_2_rounded, label: 'Inventory',     item: _NavItem.inventory),
    (icon: Icons.assignment_rounded,  label: 'Requisitions',  item: _NavItem.requisitions),
    (icon: Icons.tune_rounded,        label: 'Yield Config',  item: _NavItem.yield_),
    (icon: Icons.analytics_rounded,   label: 'Variance',      item: _NavItem.variance),
  ];

  // Manager-only nav items
  static const _managerNavItems = [
    (icon: Icons.badge_rounded, label: 'Staff', item: _NavItem.staff),
  ];

  List<({IconData icon, String label, _NavItem item})> get _navItems => [
        ..._coreNavItems,
        if (widget.staff.isManager) ..._managerNavItems,
      ];

  Widget _body() {
    switch (_selected) {
      case _NavItem.suppliers:
        return SupplierLedgerScreen(staff: widget.staff);
      case _NavItem.inventory:
        return InventoryScreen(staff: widget.staff);
      case _NavItem.requisitions:
        return RequisitionApprovalScreen(staff: widget.staff);
      case _NavItem.yield_:
        return const YieldConfigScreen();
      case _NavItem.variance:
        return const VarianceScreen();
      case _NavItem.staff:
        return const StaffManagementScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      body: Row(
        children: [
          // ── Sidebar ─────────────────────────────────────────
          _Sidebar(
            staff: widget.staff,
            selected: _selected,
            navItems: _navItems,
            onSelect: (item) => setState(() => _selected = item),
            onLogout: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const PinLoginScreen()),
            ),
          ),
          // ── Content ─────────────────────────────────────────
          Expanded(child: _body()),
        ],
      ),
    );
  }
}

// ── Sidebar ────────────────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final Staff staff;
  final _NavItem selected;
  final List<({IconData icon, String label, _NavItem item})> navItems;
  final void Function(_NavItem) onSelect;
  final VoidCallback onLogout;

  const _Sidebar({
    required this.staff,
    required this.selected,
    required this.navItems,
    required this.onSelect,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      color: AppTheme.sidebar,
      child: Column(
        children: [
          // ── Header ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
            child: Row(
              children: [
                const Icon(Icons.storefront_rounded,
                    color: AppTheme.pinTeal, size: 28),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('YUNIX STORE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                      )),
                ),
              ],
            ),
          ),

          // ── Staff chip ──────────────────────────────────────
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 20),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.07),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_circle_rounded,
                    color: AppTheme.pinMuted, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(staff.name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      Text(staff.role.toUpperCase(),
                          style: const TextStyle(
                              color: AppTheme.pinMuted, fontSize: 10)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Divider(color: Color(0xFF263238), thickness: 1),
          ),
          const SizedBox(height: 8),

          // ── Nav Items ────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: navItems
                  .map((n) => _NavTile(
                        icon: n.icon,
                        label: n.label,
                        selected: selected == n.item,
                        onTap: () => onSelect(n.item),
                      ))
                  .toList(),
            ),
          ),

          // ── Logout ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(12),
            child: _NavTile(
              icon: Icons.lock_outline_rounded,
              label: 'Lock / Change PIN',
              selected: false,
              onTap: onLogout,
              danger: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool danger;

  const _NavTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? const Color(0xFFEF5350)
        : selected
            ? AppTheme.pinTeal
            : AppTheme.pinMuted;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: selected ? AppTheme.pinTeal.withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: color, size: 20),
        title: Text(label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            )),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

// ── Coming Soon placeholder ───────────────────────────────────────────────

class _ComingSoon extends StatelessWidget {
  final String label;
  const _ComingSoon({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.construction_rounded,
              size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('$label – Coming in next milestone',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
