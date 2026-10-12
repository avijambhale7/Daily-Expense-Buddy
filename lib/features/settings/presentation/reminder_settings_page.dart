import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_dependencies.dart';
import '../../../app/session/session_cubits.dart';
import '../../../core/formatting/app_format.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/common.dart';
import '../../../domain/models/user_preferences.dart';
import '../../../services/notifications/notification_service.dart';
import '../../reminders/reminder_coordinator.dart';

class ReminderSettingsPage extends StatefulWidget {
  const ReminderSettingsPage({super.key});

  @override
  State<ReminderSettingsPage> createState() => _ReminderSettingsPageState();
}

class _ReminderSettingsPageState extends State<ReminderSettingsPage>
    with WidgetsBindingObserver {
  bool? _permission;
  bool _requesting = false;

  NotificationService get _notifications =>
      context.read<AppDependencies>().notifications;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkPermission();
  }

  Future<void> _checkPermission() async {
    final granted = await _notifications.hasPermission();
    if (mounted) setState(() => _permission = granted);
  }

  void _update(ReminderSettings r) {
    final cubit = context.read<PreferencesCubit>();
    cubit.update(cubit.preferences.copyWith(reminders: r));
  }

  Future<void> _enable(ReminderSettings r) async {
    if (_permission != true) {
      final proceed = await showConfirmDialog(
        context,
        title: 'Allow reminder notifications?',
        message:
            "Daily Expense Buddy will send one reminder each evening (and optional "
            "follow-ups) only if you haven't completed the day. You can turn this "
            'off at any time. Your device will ask for permission next.',
        confirmLabel: 'Continue',
      );
      if (!proceed || !mounted) return;
      setState(() => _requesting = true);
      final granted = await _notifications.requestPermission();
      if (!mounted) return;
      setState(() {
        _requesting = false;
        _permission = granted;
      });
      if (!granted) {
        showMessage(
          context,
          'Notifications are blocked. You can allow them in your device or browser settings.',
        );
        return;
      }
    }
    _update(r.copyWith(enabled: true));
    await context.read<ReminderCoordinator>().refresh();
  }

  Future<int?> _pickTime(int minutes) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    return t == null ? null : t.hour * 60 + t.minute;
  }

  @override
  Widget build(BuildContext context) {
    final r = context.watch<PreferencesCubit>().state.preferences.reminders;
    final fmt = AppFormat.of(context);
    final capability = _notifications.capability;
    final unsupported = capability == ReminderCapability.unsupported;

    final platformNote = switch (capability) {
      ReminderCapability.scheduled =>
        'Reminders are scheduled on this device. The system may deliver them a '
            'few minutes late to save battery.',
      ReminderCapability.whileOpen =>
        'In the browser, reminders can only appear while Daily Expense Buddy is '
            'open in a tab. Install the mobile app for reminders when the app is closed.',
      ReminderCapability.unsupported =>
        'Notifications are not supported on this device or browser.',
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Daily reminders')),
      body: ListView(
        padding: pagePadding(context),
        children: [
          PageBody(
            maxWidth: 640,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InfoBanner(message: platformNote),
                if (r.enabled && _permission == false) ...[
                  const SizedBox(height: Space.md),
                  InfoBanner(
                    tone: BannerTone.warning,
                    icon: Icons.notifications_off_outlined,
                    message: 'Notifications are turned off for this app, so reminders cannot be shown.',
                    action: capability == ReminderCapability.scheduled
                        ? TextButton(
                            onPressed: _notifications.openSystemSettings,
                            child: const Text('Settings'),
                          )
                        : null,
                  ),
                ],
                const SizedBox(height: Space.lg),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(
                          Icons.notifications_active_outlined,
                        ),
                        title: const Text('Remind me every day'),
                        subtitle: const Text(
                          'Only if the day is not complete yet',
                        ),
                        value: r.enabled,
                        onChanged: unsupported || _requesting
                            ? null
                            : (v) => v
                                  ? _enable(r)
                                  : _update(r.copyWith(enabled: false)),
                      ),
                      ListTile(
                        enabled: r.enabled,
                        leading: const Icon(Icons.schedule_rounded),
                        title: const Text('Reminder time'),
                        trailing: Text(
                          fmt.timeOfDay(r.timeMinutes),
                          style: context.text.titleSmall,
                        ),
                        onTap: () async {
                          final m = await _pickTime(r.timeMinutes);
                          if (m != null) _update(r.copyWith(timeMinutes: m));
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.lg),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.repeat_rounded),
                        title: const Text('Follow-up reminders'),
                        subtitle: const Text(
                          'Stop automatically once the day is complete',
                        ),
                        value: r.followUpsEnabled,
                        onChanged: r.enabled
                            ? (v) => _update(r.copyWith(followUpsEnabled: v))
                            : null,
                      ),
                      for (var i = 0; i < r.followUpMinutes.length; i++)
                        ListTile(
                          enabled: r.enabled && r.followUpsEnabled,
                          leading: const SizedBox(width: 24),
                          title: Text('Follow-up ${i + 1}'),
                          subtitle: r.followUpMinutes[i] <= r.timeMinutes
                              ? Text(
                                  'Must be later than the main reminder – skipped',
                                  style: TextStyle(
                                    color: context.appColors.warning,
                                  ),
                                )
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                fmt.timeOfDay(r.followUpMinutes[i]),
                                style: context.text.titleSmall,
                              ),
                              IconButton(
                                tooltip: 'Remove follow-up',
                                onPressed: r.enabled && r.followUpsEnabled
                                    ? () => _update(
                                        r.copyWith(
                                          followUpMinutes: [
                                            ...r.followUpMinutes,
                                          ]..removeAt(i),
                                        ),
                                      )
                                    : null,
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                          onTap: () async {
                            final m = await _pickTime(r.followUpMinutes[i]);
                            if (m != null) {
                              final list = [...r.followUpMinutes]..[i] = m;
                              _update(
                                r.copyWith(followUpMinutes: list..sort()),
                              );
                            }
                          },
                        ),
                      if (r.followUpMinutes.length <
                          ReminderSettings.maxFollowUps)
                        ListTile(
                          enabled: r.enabled && r.followUpsEnabled,
                          leading: const Icon(Icons.add_rounded),
                          title: const Text('Add follow-up'),
                          onTap: () async {
                            final m = await _pickTime(
                              (r.timeMinutes + 45) % (24 * 60),
                            );
                            if (m != null) {
                              _update(
                                r.copyWith(
                                  followUpMinutes: [...r.followUpMinutes, m]
                                    ..sort(),
                                ),
                              );
                            }
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.lg),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.bedtime_outlined),
                        title: const Text('Quiet hours'),
                        subtitle: const Text('No reminders during this time'),
                        value: r.quietHoursEnabled,
                        onChanged: r.enabled
                            ? (v) => _update(r.copyWith(quietHoursEnabled: v))
                            : null,
                      ),
                      ListTile(
                        enabled: r.enabled && r.quietHoursEnabled,
                        leading: const SizedBox(width: 24),
                        title: const Text('From'),
                        trailing: Text(
                          fmt.timeOfDay(r.quietStartMinutes),
                          style: context.text.titleSmall,
                        ),
                        onTap: () async {
                          final m = await _pickTime(r.quietStartMinutes);
                          if (m != null) {
                            _update(r.copyWith(quietStartMinutes: m));
                          }
                        },
                      ),
                      ListTile(
                        enabled: r.enabled && r.quietHoursEnabled,
                        leading: const SizedBox(width: 24),
                        title: const Text('Until'),
                        trailing: Text(
                          fmt.timeOfDay(r.quietEndMinutes),
                          style: context.text.titleSmall,
                        ),
                        onTap: () async {
                          final m = await _pickTime(r.quietEndMinutes);
                          if (m != null) {
                            _update(r.copyWith(quietEndMinutes: m));
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.lg),
                Text(
                  'Reminder settings sync to your account. Notification permission is '
                  'granted separately on each device.',
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
