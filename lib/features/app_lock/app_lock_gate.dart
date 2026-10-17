import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/widgets/app_logo.dart';
import '../../services/app_lock/app_lock.dart';
import '../auth/cubit/auth_cubit.dart';

/// PINs are exactly this many digits.
const pinLength = 4;

/// Covers the app with the lock screen while [controller] is locked. The
/// app underneath keeps its state but is hidden and unreachable.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.controller, required this.child});

  final AppLockController controller;
  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> {
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onHide: widget.controller.paused,
    onShow: widget.controller.resumed,
  );

  @override
  void initState() {
    super.initState();
    _lifecycle; // Start listening.
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, child) {
        final locked = widget.controller.locked;
        return Stack(
          children: [
            Offstage(offstage: locked, child: child),
            if (locked)
              Positioned.fill(
                child: Navigator(
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) => LockScreen(controller: widget.controller),
                  ),
                ),
              ),
          ],
        );
      },
      child: widget.child,
    );
  }
}

class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.controller});

  final AppLockController controller;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _pin = '';
  String? _error;
  int _failures = 0;

  @override
  void initState() {
    super.initState();
    if (widget.controller.store.biometric) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _biometric());
    }
  }

  Future<void> _biometric() async {
    await widget.controller.unlockWithBiometrics();
  }

  void _digit(String d) {
    if (_pin.length >= pinLength) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length == pinLength) {
      if (!widget.controller.unlockWithPin(_pin)) {
        HapticFeedback.heavyImpact();
        setState(() {
          _failures++;
          _pin = '';
          _error = 'Wrong PIN. Try again.';
        });
      }
    }
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _forgot() async {
    final auth = context.read<AuthCubit>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Forgot your PIN?'),
        content: const Text(
          'Log out and sign in again with your password. The PIN lock is '
          'removed from this device when you log out.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (ok == true) await auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLogo(size: 64),
                  const SizedBox(height: Space.lg),
                  Text('Enter your PIN', style: context.text.titleLarge),
                  const SizedBox(height: Space.lg),
                  Semantics(
                    label: '${_pin.length} of $pinLength digits entered',
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < pinLength; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i < _pin.length
                                  ? c.primary
                                  : Colors.transparent,
                              border: Border.all(color: c.primary, width: 2),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 32,
                    child: Center(
                      child: _error == null
                          ? null
                          : Text(
                              _error!,
                              style: context.text.bodySmall?.copyWith(
                                color: c.error,
                              ),
                            ),
                    ),
                  ),
                  _Keypad(
                    onDigit: _digit,
                    onBackspace: _backspace,
                    biometric: widget.controller.store.biometric
                        ? _biometric
                        : null,
                  ),
                  const SizedBox(height: Space.lg),
                  TextButton(
                    onPressed: _forgot,
                    child: Text(
                      _failures >= 3 ? 'Forgot PIN? Log out' : 'Forgot PIN?',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.onDigit,
    required this.onBackspace,
    this.biometric,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? biometric;

  @override
  Widget build(BuildContext context) {
    Widget key(Widget child, VoidCallback? onTap, {String? label}) => Padding(
      padding: const EdgeInsets.all(6),
      child: SizedBox.square(
        dimension: 72,
        child: Semantics(
          button: true,
          label: label,
          child: Material(
            color: onTap == null
                ? Colors.transparent
                : context.colors.surfaceContainerHighest,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
    Widget digit(String d) => key(
      Text(d, style: context.text.headlineSmall),
      () => onDigit(d),
      label: d,
    );
    return Column(
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (final d in row) digit(d)],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            biometric == null
                ? key(const SizedBox.shrink(), null)
                : key(
                    const Icon(Icons.fingerprint_rounded, size: 32),
                    biometric,
                    label: 'Unlock with fingerprint',
                  ),
            digit('0'),
            key(
              const Icon(Icons.backspace_outlined),
              onBackspace,
              label: 'Delete',
            ),
          ],
        ),
      ],
    );
  }
}

/// Asks for a new PIN twice. Returns it, or null if cancelled.
Future<String?> askNewPin(BuildContext context) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const _NewPinPage(),
    ),
  );
}

class _NewPinPage extends StatefulWidget {
  const _NewPinPage();

  @override
  State<_NewPinPage> createState() => _NewPinPageState();
}

class _NewPinPageState extends State<_NewPinPage> {
  String _first = '';
  String _pin = '';
  String? _error;

  void _digit(String d) {
    if (_pin.length >= pinLength) return;
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length < pinLength) return;
    if (_first.isEmpty) {
      setState(() {
        _first = _pin;
        _pin = '';
      });
    } else if (_pin == _first) {
      Navigator.pop(context, _pin);
    } else {
      setState(() {
        _first = '';
        _pin = '';
        _error = "The PINs didn't match. Start again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Set app PIN')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _first.isEmpty
                    ? 'Choose a $pinLength-digit PIN'
                    : 'Enter the same PIN again',
                style: context.text.titleMedium,
              ),
              const SizedBox(height: Space.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < pinLength; i++)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _pin.length ? c.primary : Colors.transparent,
                        border: Border.all(color: c.primary, width: 2),
                      ),
                    ),
                ],
              ),
              SizedBox(
                height: 32,
                child: Center(
                  child: _error == null
                      ? null
                      : Text(
                          _error!,
                          style: context.text.bodySmall?.copyWith(
                            color: c.error,
                          ),
                        ),
                ),
              ),
              _Keypad(
                onDigit: _digit,
                onBackspace: () {
                  if (_pin.isNotEmpty) {
                    setState(() => _pin = _pin.substring(0, _pin.length - 1));
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
