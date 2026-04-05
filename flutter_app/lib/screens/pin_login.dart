import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';
import '../services/api.dart';
import '../models/staff.dart';
import 'store/store_shell.dart';
import 'kitchen/kitchen_home.dart';

class PinLoginScreen extends StatefulWidget {
  const PinLoginScreen({super.key});

  @override
  State<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends State<PinLoginScreen>
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
      TweenSequenceItem(tween: Tween(begin: 0, end: -12), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -12, end: 12), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 12, end: -8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8, end: 0), weight: 1),
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
      _pin += digit;
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
      final Widget dest = staff.isStore
          ? StoreShell(staff: staff)
          : KitchenHome(staff: staff);
      Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, a, __) => dest,
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 400),
          ));
    } on ApiException catch (e) {
      HapticFeedback.vibrate();
      _shakeCtrl.forward(from: 0);
      setState(() {
        _pin = '';
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _pin = '';
        _error = 'Connection error. Is the server running?';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.pinBg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Logo ───────────────────────────────────────
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    color: AppTheme.pinTeal.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.storefront_rounded,
                      color: AppTheme.pinTeal, size: 40),
                ),
                const SizedBox(height: 16),
                const Text(
                  'YUNIX STORE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 5,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Enter your PIN to continue',
                  style: TextStyle(color: AppTheme.pinMuted, fontSize: 13),
                ),
                const SizedBox(height: 48),

                // ── PIN Dots ────────────────────────────────────
                AnimatedBuilder(
                  animation: _shakeAnim,
                  builder: (ctx, child) => Transform.translate(
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
                        width: 18,
                        height: 18,
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

                // ── Error ───────────────────────────────────────
                AnimatedOpacity(
                  opacity: _error != null ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(
                      _error ?? '',
                      style: const TextStyle(
                          color: Color(0xFFEF5350), fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                const SizedBox(height: 40),

                // ── Numpad / Spinner ────────────────────────────
                if (_loading)
                  const SizedBox(
                    height: 240,
                    child: Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.pinTeal),
                    ),
                  )
                else
                  _Numpad(onTap: _tap, onDelete: _delete),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Numpad Widget ─────────────────────────────────────────────────────────────

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
                  child: _NumKey(label: e.value, onTap: () => onTap(e.value)),
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
