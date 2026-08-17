import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/app_config.dart';
import 'core/database/hive_adapters.dart';
import 'core/database/chat_message_adapter.dart';
import 'core/database/group_adapter.dart';
import 'core/network/call_service.dart';
import 'core/providers/call_provider.dart';
import 'core/providers/database_provider.dart';
import 'core/providers/chat_provider.dart';
import 'core/providers/signaling_provider.dart';
import 'ui/screens/call_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/signup_screen.dart';
import 'ui/screens/forgot_password_screen.dart';
import 'package:media_kit/media_kit.dart';

final navigatorKey = GlobalKey<NavigatorState>();
bool firebaseAvailable = false;

File get _crashLog => File('${Directory.systemTemp.path}/grychat_crash_${Platform.environment['APP_PROFILE'] ?? 'main'}.log');

void _logCrash(Object error, StackTrace stack) {
  // Suppress known transient errors during multi-instance failover
  if (error.toString().contains('PathAccessException') ||
      error.toString().contains('errno = 33') ||
      error.toString().contains('errno = 32')) {
    return;
  }
  final msg = '[${DateTime.now()}] CRASH: $error\n$stack\n---\n';
  try { _crashLog.writeAsStringSync(msg, mode: FileMode.append); } catch (_) {}
  print('CRASH LOGGED: $error');
}

void main() async {
  runZonedGuarded(_mainInner, _logCrash);
}

void _mainInner() async {
  print('[Init] step: binding');
  WidgetsFlutterBinding.ensureInitialized();
  print('[Init] step: media_kit');
  MediaKit.ensureInitialized();
  print('[Init] step: media_kit done');

  final skipFirebase = const String.fromEnvironment('SKIP_FIREBASE', defaultValue: '') == 'true';
  final firebaseAppId = const String.fromEnvironment('FIREBASE_APP_ID');
  if (skipFirebase) {
    print('[Init] SKIP_FIREBASE=true — skipping Firebase init');
  } else if (firebaseAppId.contains(':web:')) {
    print('[Init] Firebase app ID is web-only — skipping Firebase init');
  } else {
    try {
      print('[Init] step: firebase');
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: const String.fromEnvironment('FIREBASE_API_KEY'),
          authDomain: const String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
          projectId: const String.fromEnvironment('FIREBASE_PROJECT_ID'),
          storageBucket: const String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
          messagingSenderId: const String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
          appId: firebaseAppId,
        ),
      );
      print('[Init] step: firebase done');
      firebaseAvailable = true;
    } catch (e) {
      print('[Init] Firebase init failed (continue as guest): $e');
    }
  }

  try {
    print('[Init] step: supabase');
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
    print('[Init] step: supabase done');
  } catch (e) {
    print('[Init] Supabase init failed (continue as guest): $e');
  }
  
  final envProfile = Platform.environment['APP_PROFILE'];
  const dartDefineProfile = String.fromEnvironment('APP_PROFILE', defaultValue: '');
  
  final rawProfile = (envProfile != null && envProfile.trim().isNotEmpty) 
      ? envProfile.trim() 
      : (dartDefineProfile.trim().isNotEmpty ? dartDefineProfile.trim() : 'main_peer');

  Hive.registerAdapter(PeerModelAdapter());
  Hive.registerAdapter(MessageModelAdapter());
  Hive.registerAdapter(UserProfileAdapter());
  Hive.registerAdapter(ChatMessageAdapter());
  Hive.registerAdapter(GroupAdapter());
  
  FlutterError.onError = (details) {
    _logCrash(details.exception, details.stack ?? StackTrace.empty);
    FlutterError.presentError(details);
  };

  ErrorWidget.builder = (details) {
    _logCrash(details.exception, details.stack ?? StackTrace.empty);
    return Material(
      color: const Color(0xFF0F172A),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              Text(
                '${details.exception.runtimeType}',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '${details.exception}',
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Restart the app and try again.\nClose any other GryChat instances.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  };
  runApp(ProviderScope(
    overrides: [
      storageProfileProvider.overrideWithValue(rawProfile),
    ],
    child: const MyApp(),
  ));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  bool _incomingCallShowing = false;

  @override
  Widget build(BuildContext context) {
    final dbInitState = ref.watch(databaseInitProvider);

    ref.listen<AsyncValue<CallInfo?>>(callInfoProvider, (prev, next) {
      final info = next.valueOrNull;
      final wasRinging = prev?.valueOrNull?.state == CallState.incomingRinging;
      final isRinging = info?.state == CallState.incomingRinging;

      if (isRinging && !_incomingCallShowing) {
        _incomingCallShowing = true;
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => IncomingCallPage(
              callInfo: info!,
              onDismissed: () {
                _incomingCallShowing = false;
              },
            ),
          ),
        );
      } else if (!isRinging && wasRinging && _incomingCallShowing) {
        _incomingCallShowing = false;
        if (navigatorKey.currentState?.canPop() == true) {
          navigatorKey.currentState?.pop();
        }
      } else if (info == null && _incomingCallShowing) {
        _incomingCallShowing = false;
        if (navigatorKey.currentState?.canPop() == true) {
          navigatorKey.currentState?.pop();
        }
      }
    });

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Grychat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B4EBA),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B4EBA),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF171B24),
      ),
      themeMode: ref.watch(darkModeProvider) ? ThemeMode.dark : ThemeMode.light,
      routes: {
        '/login': (_) => const LoginScreen(),
        '/signup': (_) => const SignupScreen(),
        '/forgot-password': (_) => const ForgotPasswordScreen(),
      },
      home: dbInitState.when(
        data: (_) {
          if (!firebaseAvailable) {
            print('[Auth] Firebase not available — bypassing login');
            ref.read(signalingServiceProvider);
            return const HomeScreen();
          }
          return Consumer(builder: (context, ref, _) {
            final authState = ref.watch(currentUserProvider);
            return authState.when(
              data: (user) {
                if (user == null) return const LoginScreen();
                ref.read(signalingServiceProvider);
                return const HomeScreen();
              },
              loading: () => const SplashScreen(message: 'Checking login...'),
              error: (err, _) {
                print('[Auth] Error: $err');
                return const LoginScreen();
              },
            );
          });
        },
        loading: () => const SplashScreen(message: 'Initializing...'),
        error: (err, stack) => InitErrorScreen(error: err.toString()),
      ),
    );
  }
}

class IncomingCallPage extends ConsumerWidget {
  final CallInfo callInfo;
  final VoidCallback onDismissed;

  const IncomingCallPage({
    super.key,
    required this.callInfo,
    required this.onDismissed,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<CallInfo?>>(callInfoProvider, (prev, next) {
      final info = next.valueOrNull;
      if (info == null || (info.state != CallState.incomingRinging && info.state != CallState.connecting)) {
        onDismissed();
        if (context.mounted) Navigator.of(context).pop();
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1B4EBA),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    callInfo.peerName.isNotEmpty
                        ? callInfo.peerName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  callInfo.peerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  callInfo.callType == CallType.video
                      ? 'Incoming Video Call'
                      : 'Incoming Voice Call',
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
                const SizedBox(height: 40),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildButton(
                      icon: Icons.call_end,
                      label: 'Decline',
                      color: const Color(0xFFEF4444),
                      onTap: () {
                        ref.read(callServiceProvider).rejectCall();
                        onDismissed();
                        Navigator.of(context).pop();
                      },
                    ),
                    _buildButton(
                      icon: Icons.call,
                      label: 'Accept',
                      color: const Color(0xFF10B981),
                      onTap: () async {
                        final callService = ref.read(callServiceProvider);
                        await callService.answerCall();
                        onDismissed();
                        if (context.mounted) {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => CallScreen(
                                peerId: callService.remotePeerId,
                                peerName: callInfo.peerName,
                                callType: callInfo.callType,
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class SplashScreen extends StatelessWidget {
  final String message;

  const SplashScreen({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                    blurRadius: 24,
                    spreadRadius: 8,
                  )
                ],
              ),
              child: const Icon(
                Icons.radar,
                color: Color(0xFF6366F1),
                size: 64,
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'GRYCHAT',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'P2P SECURE FILE SYNCHRONIZATION',
              style: TextStyle(
                color: Color(0xFF818CF8),
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 48),
            const SizedBox(
              width: 150,
              child: LinearProgressIndicator(
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class InitErrorScreen extends ConsumerWidget {
  final String error;

  const InitErrorScreen({super.key, required this.error});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.redAccent,
                size: 64,
              ),
              const SizedBox(height: 24),
              const Text(
                'Initialization Failed',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  error,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 13,
                    fontFamily: 'Courier',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                onPressed: () {
                  ref.invalidate(databaseInitProvider);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
