import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';

import 'app/router.dart';
import 'core/localization/sushi_localizations.dart';
import 'core/state/providers.dart';
import 'core/config.dart';
import 'core/cache/session_cache.dart';
import 'core/cache/profile_cache.dart';
import 'core/cache/location_cache.dart';
import 'core/cache/user_registry_cache.dart';
import 'core/theme/app_theme.dart';

const bool _isFlutterTest = bool.fromEnvironment('FLUTTER_TEST');
const AndroidNotificationChannel _pushChannel = AndroidNotificationChannel(
  'sushixl_general',
  'Sushi XL Notifications',
  description: 'Promotions, status updates, and app notifications.',
  importance: Importance.high,
);
bool _isTestBinding() {
  final name = WidgetsBinding.instance.runtimeType.toString();
  return name.contains('TestWidgetsFlutterBinding') ||
      name.contains('AutomatedTestWidgetsFlutterBinding') ||
      name.contains('LiveTestWidgetsFlutterBinding');
}

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (e) {
    debugPrint('[fcm] background init failed: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kReleaseMode) {
    debugPrint = (String? _, {int? wrapWidth}) {};
  }
  final shouldDisableRuntime = _isFlutterTest || _isTestBinding();
  if (!shouldDisableRuntime) {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);
    } catch (e) {
      debugPrint('[firebase] init failed: $e');
    }
  }
  runApp(const ProviderScope(child: SushiXLApp()));
}

class SushiXLApp extends ConsumerStatefulWidget {
  const SushiXLApp({super.key});

  @override
  ConsumerState<SushiXLApp> createState() => _SushiXLAppState();
}

class _SushiXLAppState extends ConsumerState<SushiXLApp> {
  bool _bootstrapped = false;
  late final GoRouter _router;
  String? _currentLangPushTopic;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _router = buildRouter();
    debugPrint('[app] router initialized');
    if (!(_isFlutterTest || _isTestBinding())) {
      _bootstrap();
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    debugPrint('[app] build locale=${locale.languageCode}');
    if (!_isFlutterTest && !_isTestBinding()) {
      unawaited(_syncPushLanguageTopic(locale.languageCode));
    }
    return MaterialApp.router(
      title: 'Sushi-XL',
      routerConfig: _router,
      locale: locale,
      theme: AppTheme.light(),
      localizationsDelegates: const [
        SushiLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('uz'),
        Locale('ru'),
        Locale('en'),
      ],
    );
  }

  void _bootstrap() {
    if (_bootstrapped) return;
    _bootstrapped = true;
    _initLocalNotifications();
    _initPushMessaging();
    final cache = SessionCache();
    cache.load().then((json) {
      if (json != null) {
        final loadedSession = UserSession.fromJson(json);
        final session =
            loadedSession.userId > 0 && loadedSession.accessToken.trim().isEmpty
                ? UserSession(
                    userId: 0,
                    phone: loadedSession.phone,
                    fullName: loadedSession.fullName,
                    preferredLang: loadedSession.preferredLang,
                    gender: loadedSession.gender,
                    accessToken: '',
                  )
                : loadedSession;
        ref.read(userSessionProvider.notifier).state = session;
        if (session.userId <= 0 && loadedSession.userId > 0) {
          SessionCache().save(session.toJson());
        }
        ref.read(localeProvider.notifier).state = Locale(session.preferredLang);
        ref.read(cartProvider.notifier).loadFromCache();
        ref.read(favoritesProvider.notifier).loadFromCache();
        ref.read(localOrderHistoryProvider.notifier).loadFromCache();
        UserRegistryCache().upsert(
          phone: session.phone,
          name: session.fullName,
          gender: session.gender,
        );
        unawaited(_syncCachedUserWithBackend(session));
        final scope = _locationScope(session);
        if (scope == null) {
          ref.read(deliveryLocationProvider.notifier).state = null;
        } else {
          LocationCache().load(scope: scope).then((data) {
            if (data == null) {
              ref.read(deliveryLocationProvider.notifier).state = null;
              return;
            }
            final address = data['address'] as String? ?? '';
            final lat = (data['lat'] as num?)?.toDouble();
            final lng = (data['lng'] as num?)?.toDouble();
            if (address.isNotEmpty && lat != null && lng != null) {
              ref.read(deliveryLocationProvider.notifier).state =
                  DeliveryLocation(address: address, lat: lat, lng: lng);
            } else {
              ref.read(deliveryLocationProvider.notifier).state = null;
            }
          });
        }
      } else {
        final lang = ref.read(localeProvider).languageCode;
        final guest = UserSession.guest(preferredLang: lang);
        ref.read(userSessionProvider.notifier).state = guest;
        SessionCache().save(guest.toJson());
        ref.read(cartProvider.notifier).loadFromCache();
        ref.read(favoritesProvider.notifier).loadFromCache();
        ref.read(localOrderHistoryProvider.notifier).loadFromCache();
        ref.read(deliveryLocationProvider.notifier).state = null;
      }
      // Warm cache from backend; if backend is temporarily unavailable the
      // repository falls back to the last cached backend menu.
      final locale = ref.read(localeProvider).languageCode;
      ref
          .read(menuRepositoryProvider)
          .fetchMenu(locale)
          .then((_) {}, onError: (_, __) {});
    });
    ref.read(mailingProvider.notifier).loadFromCache();
    ref.read(supportCenterProvider.notifier).loadFromCache();
    ref.read(supportInboxProvider.notifier).loadFromCache();
    ProfileCache().loadPhotoPath().then((path) {
      ref.read(profilePhotoProvider.notifier).state = path;
    });
  }

  Future<void> _syncCachedUserWithBackend(UserSession session) async {
    if (!useBackend) return;
    final phone = session.phone.trim();
    final fullName = session.fullName.trim();
    if (phone.isEmpty || fullName.isEmpty) return;
    if (session.userId > 0 && session.accessToken.trim().isNotEmpty) {
      try {
        await ref.read(orderHistoryRepositoryProvider).list(session.userId);
        return;
      } on DioException catch (error) {
        if (error.response?.statusCode != 401) {
          debugPrint('[auth] cached session validation skipped: $error');
          return;
        }
      } catch (error) {
        debugPrint('[auth] cached session validation skipped: $error');
        return;
      }
    }
    try {
      final auth = ref.read(authRepositoryProvider);
      final challenge = await auth.requestLoginCode(
        phone: phone,
        fullName: fullName,
        preferredLang: session.preferredLang,
      );
      final code = challenge.debugCode.trim();
      if (code.isEmpty) {
        return;
      }
      final login = await auth.verifyLoginCode(
        phone: phone,
        code: code,
        fullName: fullName,
        preferredLang: session.preferredLang,
      );
      final upgraded = UserSession(
        userId: login.userId,
        phone: login.phone,
        fullName: login.fullName,
        preferredLang: login.preferredLang,
        gender: session.gender,
        accessToken: login.accessToken,
      );
      ref.read(userSessionProvider.notifier).state = upgraded;
      await SessionCache().save(upgraded.toJson());
      await UserRegistryCache().upsert(
        phone: upgraded.phone,
        name: upgraded.fullName,
        gender: upgraded.gender,
      );
    } catch (e) {
      debugPrint('[auth] bootstrap session sync skipped: $e');
    }
  }

  String? _locationScope(UserSession session) {
    if (session.userId > 0) return 'uid_${session.userId}';
    final phone = session.phone.trim();
    if (phone.isNotEmpty) return 'phone_$phone';
    return null;
  }

  Future<void> _initLocalNotifications() async {
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings();
      const settings = InitializationSettings(android: android, iOS: ios);
      await _localNotifications.initialize(settings);
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_pushChannel);
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('[fcm] local notifications init failed: $e');
    }
  }

  String _remoteText(RemoteMessage message, String langCode, String field) {
    final normalized = langCode.trim().toLowerCase();
    final suffix = normalized == 'uz'
        ? 'Uz'
        : normalized == 'en'
            ? 'En'
            : 'Ru';
    final data = message.data;
    final localized = '${data['$field$suffix'] ?? ''}'.trim();
    if (localized.isNotEmpty) return localized;
    final shared = '${data[field] ?? ''}'.trim();
    if (shared.isNotEmpty) return shared;
    if (field == 'title') {
      return (message.notification?.title ?? '').trim();
    }
    if (field == 'message') {
      final fromBody = (message.notification?.body ?? '').trim();
      if (fromBody.isNotEmpty) return fromBody;
      return '${data['body'] ?? ''}'.trim();
    }
    return '';
  }

  Future<void> _handleForegroundPush(RemoteMessage message) async {
    final langCode = ref.read(localeProvider).languageCode;
    final title = _remoteText(message, langCode, 'title');
    final body = _remoteText(message, langCode, 'message');
    final imageUrl = '${message.data['imageUrl'] ?? ''}'.trim();
    if (title.isNotEmpty || body.isNotEmpty || imageUrl.isNotEmpty) {
      await ref.read(mailingProvider.notifier).send(
            title: title.isEmpty ? 'Sushi XL' : title,
            image: imageUrl,
            message: body,
            publishRemote: false,
          );
    }

    try {
      final androidDetails = AndroidNotificationDetails(
        _pushChannel.id,
        _pushChannel.name,
        channelDescription: _pushChannel.description,
        importance: Importance.high,
        priority: Priority.high,
      );
      const iosDetails = DarwinNotificationDetails();
      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      final rawId = int.tryParse('${message.data['notificationId'] ?? ''}');
      final notificationId =
          rawId ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await _localNotifications.show(
        notificationId,
        title.isEmpty ? 'Sushi XL' : title,
        body,
        details,
      );
    } catch (e) {
      debugPrint('[fcm] foreground display failed: $e');
    }
  }

  Future<void> _initPushMessaging() async {
    if (Firebase.apps.isEmpty) {
      debugPrint('[fcm] Firebase not initialized, skipping push setup');
      return;
    }
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final token = await messaging.getToken();
      debugPrint(
          token == null ? '[fcm] token unavailable' : '[fcm] token received');
      await messaging.subscribeToTopic('clients_all');
      await _syncPushLanguageTopic(ref.read(localeProvider).languageCode);
      FirebaseMessaging.onMessage.listen((message) async {
        debugPrint('[fcm] foreground message id=${message.messageId}');
        await _handleForegroundPush(message);
      });
    } catch (e) {
      debugPrint('[fcm] init failed: $e');
    }
  }

  Future<void> _syncPushLanguageTopic(String langCode) async {
    if (Firebase.apps.isEmpty) return;
    final normalized = (langCode.trim().toLowerCase() == 'uz')
        ? 'uz'
        : (langCode.trim().toLowerCase() == 'en')
            ? 'en'
            : 'ru';
    final nextTopic = 'lang_$normalized';
    if (_currentLangPushTopic == nextTopic) return;
    try {
      final messaging = FirebaseMessaging.instance;
      final previous = _currentLangPushTopic;
      if (previous != null && previous.isNotEmpty) {
        await messaging.unsubscribeFromTopic(previous);
      }
      await messaging.subscribeToTopic(nextTopic);
      _currentLangPushTopic = nextTopic;
    } catch (e) {
      debugPrint('[fcm] language topic sync failed: $e');
    }
  }
}
