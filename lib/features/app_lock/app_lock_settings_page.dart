import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/widgets/common.dart';
import '../../services/app_lock/app_lock.dart';
import '../premium/premium_gate.dart';
import 'app_lock_gate.dart';

/// Premium: protect the app with a PIN (and fingerprint) on this device.
class AppLockSettingsPage extends StatefulWidget {
  const AppLockSettingsPage({super.key});

  @override
  State<AppLockSettingsPage> createState() => _AppLockSettingsPageState();
}

class _AppLockSettingsPageState extends State<AppLockSettingsPage> {
  bool? _bioAvailable;

  AppLockController? get _lock => context.read<AppLockHandle>().controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final b = _lock?.biometrics;
      final ok = b == null ? false : await b.available();
      if (mounted) setState(() => _bioAvailable = ok);
    });
  }

  Future<void> _enable() async {
    final pin = await askNewPin(context);
    final lock = _lock;
    if (pin == null || lock == null || !mounted) return;
    await lock.store.setPin(pin);
    lock.settingsChanged();
    setState(() {});
    if (mounted) showMessage(context, 'App lock is on');
  }

  Future<void> _disable() async {
    final lock = _lock;
    if (lock == null) return;
    final ok = await showConfirmDialog(
      context,
      title: 'Turn off app lock?',
      message: 'Anyone with this phone will be able to open the app.',
      confirmLabel: 'Turn off',
      destructive: true,
    );
    if (!ok) return;
    await lock.store.clear();
    lock.settingsChanged();
    if (mounted) {
      setState(() {});
      showMessage(context, 'App lock is off');
    }
  }

  Future<void> _setBiometric(bool on) async {
    final lock = _lock;
    if (lock == null) return;
    if (on &&
        !await lock.biometrics!.authenticate('Confirm your fingerprint')) {
      return;
    }
    await lock.store.setBiometric(on);
    lock.settingsChanged();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final lock = context.read<AppLockHandle>().controller;
    final enabled = lock?.store.enabled ?? false;
    final premium = hasPremium(context);
    final Widget body;
    if (lock == null) {
      body = const EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Not available here',
        message: 'App lock is available in the Android app.',
      );
    } else if (!premium && !enabled) {
      body = const PremiumGate(
        feature: 'App lock',
        description:
            'Protect your expenses with a PIN or your fingerprint whenever '
            'the app is opened.',
        icon: Icons.lock_rounded,
        child: SizedBox.shrink(),
      );
    } else {
      body = ListView(
        padding: pagePadding(context),
        children: [
          PageBody(
            maxWidth: 640,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.lock_rounded),
                        title: const Text('Lock with PIN'),
                        subtitle: Text(
                          enabled
                              ? 'Asked when the app opens, and after 1 minute '
                                    'in the background'
                              : 'Off',
                        ),
                        value: enabled,
                        onChanged: (on) => on ? _enable() : _disable(),
                      ),
                      if (enabled) ...[
                        ListTile(
                          leading: const Icon(Icons.pin_rounded),
                          title: const Text('Change PIN'),
                          onTap: _enable,
                        ),
                        if (_bioAvailable == true)
                          SwitchListTile(
                            secondary: const Icon(Icons.fingerprint_rounded),
                            title: const Text('Unlock with fingerprint'),
                            value: lock.store.biometric,
                            onChanged: _setBiometric,
                          ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: Space.md),
                Text(
                  'The PIN is stored only on this phone, as a secure hash. If '
                  'you forget it, log out and sign in again with your '
                  'password – logging out removes the lock.',
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('App lock')),
      body: body,
    );
  }
}
