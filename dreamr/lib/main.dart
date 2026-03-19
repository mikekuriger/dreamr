// main.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:dreamr/screens/splash_screen.dart';
import 'package:dreamr/screens/login_screen.dart';
import 'package:dreamr/screens/register_screen.dart';
import 'package:dreamr/screens/dashboard_screen.dart';
import 'package:dreamr/screens/dream_journal_screen.dart';
import 'package:dreamr/screens/dream_journal_editor_screen.dart';
import 'package:dreamr/screens/dream_gallery_screen.dart';
import 'package:dreamr/screens/forgot_password_screen.dart';
import 'package:dreamr/screens/profile_screen.dart';
import 'package:dreamr/screens/subscription_screen.dart';
import 'package:dreamr/screens/interpreters_screen.dart';

import 'package:dreamr/services/dio_client.dart';
import 'package:dreamr/theme/colors.dart';
import 'package:dreamr/constants.dart';

import 'package:dreamr/repository/dream_repository.dart';
import 'package:dreamr/state/dream_list_model.dart';
import 'package:dreamr/state/subscription_model.dart';
import 'package:dreamr/state/selected_interpreter_model.dart';
import 'package:dreamr/state/display_scale_model.dart';
import 'package:dreamr/services/notification_service.dart';
import 'package:dreamr/services/route_observer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().init();
  await DioClient.init();

  runApp(
    MultiProvider(
      providers: [
        Provider<DreamRepository>(create: (_) => DreamRepository()),
        ChangeNotifierProvider<DreamListModel>(
          // includeHidden: true if you want hidden entries in the list model
          lazy: false,
          create: (ctx) => DreamListModel(repo: ctx.read<DreamRepository>())..init(),
        ),
        ChangeNotifierProvider<SubscriptionModel>(
          create: (_) => SubscriptionModel()..init(),
        ),
        ChangeNotifierProvider<SelectedInterpreterModel>(
          create: (_) => SelectedInterpreterModel(),
        ),
        ChangeNotifierProvider<DisplayScaleModel>(
          create: (_) => DisplayScaleModel()..init(),
        ),
      ],
      child: const DreamrApp(),
    ),
  );
}

class DreamrApp extends StatelessWidget {
  const DreamrApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      scaffoldBackgroundColor: AppColors.background,
    );

    return MaterialApp(
      title: 'Dreamr',
      debugShowCheckedModeBanner: false,
      theme: baseTheme,
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();

        final mq = MediaQuery.of(context);
        final userScale = context.watch<DisplayScaleModel>().scale;
        final isIpadLike =
            !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS &&
            mq.size.shortestSide >= 600;

        // iPad gets an extra 1.25× on top of the user's chosen scale.
        final totalScale = userScale * (isIpadLike ? 1.25 : 1.0);

        if (totalScale == 1.0) return child;

        final iconBase = (baseTheme.iconTheme.size ?? 24.0) * totalScale;

        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(mq.textScaler.scale(1.0) * totalScale),
          ),
          child: Theme(
            data: baseTheme.copyWith(
              iconTheme: baseTheme.iconTheme.copyWith(size: iconBase),
              primaryIconTheme:
                  baseTheme.primaryIconTheme.copyWith(size: iconBase),
            ),
            child: child,
          ),
        );
      },
      navigatorObservers: [dreamrRouteObserver],
      home: const SplashScreen(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/dashboard': (context) => DashboardScreen(refreshTrigger: dreamEntryRefreshTrigger),
        '/journal': (context) => DreamJournalScreen(refreshTrigger: journalRefreshTrigger),
        '/editor': (context) => DreamJournalEditorScreen(refreshTrigger: journalRefreshTrigger),
        '/gallery': (context) => DreamGalleryScreen(refreshTrigger: galleryRefreshTrigger),
        '/image': (context) => const Placeholder(),
        '/profile': (context) => ProfileScreen(refreshTrigger: profileRefreshTrigger),
        '/forgot-password': (_) => const ForgotPasswordScreen(),
        '/subscription': (context) => const SubscriptionScreen(),
        '/interpreters': (context) => const InterpretersScreen(),
      },
    );
  }
}
