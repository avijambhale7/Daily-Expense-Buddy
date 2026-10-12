import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/theme_cubit.dart';
import '../features/auth/cubit/auth_cubit.dart';
import 'app_dependencies.dart';
import 'router.dart';
import 'session/user_scope.dart';

class DailyExpenseBuddyApp extends StatefulWidget {
  const DailyExpenseBuddyApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<DailyExpenseBuddyApp> createState() => _DailyExpenseBuddyAppState();
}

class _DailyExpenseBuddyAppState extends State<DailyExpenseBuddyApp> {
  late final AuthCubit _auth;
  late final ThemeCubit _theme;
  late final StreamListenable _refresh;
  late final GoRouter _router;
  late final StreamSubscription<String> _tapSub;
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  AppDependencies get _deps => widget.dependencies;

  @override
  void initState() {
    super.initState();
    _auth = AuthCubit(_deps.authRepository);
    _theme = ThemeCubit(_deps.themeStorage);
    _refresh = StreamListenable(_auth.stream);
    _router = buildRouter(
      auth: _auth,
      firebaseReady: _deps.firebase.isReady,
      refresh: _refresh,
      initialLocation: _deps.notifications.takeLaunchRoute(),
    );
    // Notification taps navigate to the referenced screen; the router's
    // redirect still enforces authentication.
    _tapSub = _deps.notifications.taps.listen(_router.go);
  }

  @override
  void dispose() {
    unawaited(_tapSub.cancel());
    _router.dispose();
    _refresh.dispose();
    unawaited(_auth.close());
    unawaited(_theme.close());
    super.dispose();
  }

  void _showMessage(String message) {
    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider.value(
      value: _deps,
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: _auth),
          BlocProvider.value(value: _theme),
        ],
        child: BlocBuilder<ThemeCubit, ThemeSettings>(
          builder: (context, settings) {
            final palette = settings.effectivePalette;
            final forced = palette.forcedBrightness;
            return MaterialApp.router(
              title: 'Daily Expense Buddy',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.build(palette, Brightness.light),
              darkTheme: AppTheme.build(palette, Brightness.dark),
              themeMode: forced == null
                  ? settings.mode
                  : (forced == Brightness.dark
                        ? ThemeMode.dark
                        : ThemeMode.light),
              routerConfig: _router,
              scaffoldMessengerKey: _messengerKey,
              builder: (context, child) => UserScope(
                onMessage: _showMessage,
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
        ),
      ),
    );
  }
}
