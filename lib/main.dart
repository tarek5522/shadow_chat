import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:audioplayers/audioplayers.dart';
import 'package:cryptography/cryptography.dart';
import 'package:record/record.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

// متغير عام يتحكم في حالة حركة الحوت في كل التطبيق
final ValueNotifier<bool> whaleMotionNotifier = ValueNotifier<bool>(true);

// متغير عام يتحكم في تفعيل أو إيقاف صوت الحوت من الإعدادات
final ValueNotifier<bool> whaleSoundNotifier = ValueNotifier<bool>(true);
final ValueNotifier<bool> messageSoundNotifier = ValueNotifier<bool>(true);

// متغير عام يتحكم في التشفير التلقائي للرسائل
final ValueNotifier<bool> autoEncryptNotifier = ValueNotifier<bool>(false);

// كود ثابت خاص بالغرفة السرية ولا يوجد خيار لتغييره من داخل التطبيق.
const String secretRoomCode = '174285396';
final ValueNotifier<String?> secretRoomCodeHashNotifier =
    ValueNotifier<String?>(null);

// مفتاح إدارة الأعضاء للمالك فقط، ولا يظهر في أي واجهة للمستخدم.
const String initialRoomOwnerKey = 'DARK132465798';
final ValueNotifier<String?> roomOwnerKeyHashNotifier = ValueNotifier<String?>(
  null,
);

const String defaultAppLockPassword = '174285396';
const String initialSecretGroupPassword = '132465798';
const String legacySecretGroupPassword = 'SHADOW-GROUP-2026';
const bool secureLocalDemoMode = false;
final ValueNotifier<Map<String, String>> chatPasswordsNotifier =
    ValueNotifier<Map<String, String>>({});
const int maxSecretRoomMembers = 100;
final ValueNotifier<List<String>> secretRoomMembersNotifier =
    ValueNotifier<List<String>>(['أنت', 'System']);

final ValueNotifier<bool> englishLanguageNotifier = ValueNotifier<bool>(false);
final ValueNotifier<bool> appLockEnabledNotifier = ValueNotifier<bool>(false);
final ValueNotifier<String?> appLockPasswordNotifier = ValueNotifier<String?>(
  null,
);
final ValueNotifier<bool> ghostModeNotifier = ValueNotifier<bool>(true);
final ValueNotifier<bool> autoDeleteMessagesNotifier = ValueNotifier<bool>(
  false,
);
final ValueNotifier<int> clearHistoryNotifier = ValueNotifier<int>(0);
final ValueNotifier<bool> globalDarkModeNotifier = ValueNotifier<bool>(true);
final ValueNotifier<Uint8List?> userProfileImageBytesNotifier =
    ValueNotifier<Uint8List?>(null);
const String appLockEnabledKey = 'app_lock_enabled';
const String appLockPasswordHashKey = 'app_lock_password_hash';
const String darkModeKey = 'dark_mode_enabled';
bool firebaseReady = false;
String firebaseFailureMessage = '';
String? currentPublicUserId;

Future<void> setupPushNotifications() async {
  if (!firebaseReady) return;
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  try {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    final token = await messaging.getToken();
    if (token != null && token.isNotEmpty) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fcmToken': token,
        'fcmUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    messaging.onTokenRefresh.listen((newToken) async {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fcmToken': newToken,
        'fcmUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  } catch (error) {
    debugPrint('Push notification setup failed: $error');
  }
}

String appText(String arabic, String english) {
  return englishLanguageNotifier.value ? english : arabic;
}

Future<String> hashPassword(String password) async {
  final bytes = await Sha256().hash(utf8.encode(password));
  return base64Encode(bytes.bytes);
}

Future<void> loadRoomOwnerKey() async {
  final fallbackHash = await hashPassword(initialRoomOwnerKey);
  roomOwnerKeyHashNotifier.value = fallbackHash;
  if (!firebaseReady) return;
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('config')
        .doc('app')
        .get();
    final storedHash = snapshot.data()?['ownerKeyHash'];
    if (storedHash is String && storedHash.isNotEmpty) {
      roomOwnerKeyHashNotifier.value = storedHash;
    }
  } catch (error) {
    debugPrint('Room owner key load error: $error');
  }
}

Future<void> loadSecretRoomCode() async {
  final fallbackHash = await hashPassword(secretRoomCode);
  secretRoomCodeHashNotifier.value = fallbackHash;
  if (!firebaseReady) return;
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('config')
        .doc('secretRoom')
        .get();
    final storedHash = snapshot.data()?['codeHash'];
    if (storedHash is String && storedHash.isNotEmpty) {
      secretRoomCodeHashNotifier.value = storedHash;
    }
  } catch (error) {
    debugPrint('Secret room code load error: $error');
  }
}

Future<void> savePrivacySetting(String key, bool value) async {
  if (!firebaseReady) return;
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  try {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('settings')
        .doc('privacy')
        .set({
          key: value,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  } catch (error) {
    debugPrint('Privacy setting save error: $error');
  }
}

Future<Map<String, dynamic>> loadPrivacySettings() async {
  if (!firebaseReady) return {};
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return {};
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('settings')
        .doc('privacy')
        .get();
    return snapshot.data() ?? {};
  } catch (error) {
    debugPrint('Privacy settings load error: $error');
    return {};
  }
}

Future<void> deleteOwnChatMessages(String chatId) async {
  if (!firebaseReady) return;
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('uid', isEqualTo: user.uid)
        .get();
    final batch = FirebaseFirestore.instance.batch();
    for (final message in snapshot.docs) {
      batch.delete(message.reference);
    }
    await batch.commit();
  } catch (error) {
    debugPrint('Chat history delete error: $error');
  }
}

Future<void> deleteExpiredOwnChatMessages(String chatId) async {
  if (!firebaseReady) return;
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('uid', isEqualTo: user.uid)
        .where('expiresAt', isLessThanOrEqualTo: Timestamp.now())
        .get();
    final batch = FirebaseFirestore.instance.batch();
    for (final message in snapshot.docs) {
      batch.delete(message.reference);
    }
    await batch.commit();
  } catch (error) {
    debugPrint('Expired chat message delete error: $error');
  }
}

String chatDocumentId(String chatName) =>
    chatName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

Future<void> saveChatPassword(String chatName, String password) async {
  final passwordHash = await hashPassword(password);
  chatPasswordsNotifier.value = {
    ...chatPasswordsNotifier.value,
    chatName: passwordHash,
  };
  if (!firebaseReady) return;
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  try {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('chatSecurity')
        .doc(chatDocumentId(chatName))
        .set({
          'chatName': chatName,
          'passwordHash': passwordHash,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  } catch (error) {
    debugPrint('Chat password Firebase sync failed: $error');
  }
}

Future<void> disableChatPassword(String chatName) async {
  chatPasswordsNotifier.value = {...chatPasswordsNotifier.value}
    ..remove(chatName);
  if (!firebaseReady) return;
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  try {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('chatSecurity')
        .doc(chatDocumentId(chatName))
        .delete();
  } catch (error) {
    debugPrint('Chat password Firebase delete failed: $error');
  }
}

Future<bool> matchesGroupPassword(String password, String? storedHash) async {
  if (password == initialSecretGroupPassword ||
      password == legacySecretGroupPassword) {
    return true;
  }
  return storedHash != null && await hashPassword(password) == storedHash;
}

Future<void> loadAppLockSettings() async {
  final preferences = await SharedPreferences.getInstance();
  var passwordHash = await hashPassword(defaultAppLockPassword);
  var enabled = preferences.getBool(appLockEnabledKey) ?? false;

  if (firebaseReady) {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final lockRef = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('security')
            .doc('appLock');
        final lockSnapshot = await lockRef.get();
        final data = lockSnapshot.data();
        if (data?['passwordHash'] is String) {
          passwordHash = data!['passwordHash'] as String;
          enabled = data['enabled'] == true;
        } else {
          await lockRef.set({
            'passwordHash': passwordHash,
            'enabled': enabled,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      } catch (error) {
        debugPrint('App lock Firebase load failed: $error');
      }
    }
  }

  await preferences.setBool(appLockEnabledKey, enabled);
  await preferences.setString(appLockPasswordHashKey, passwordHash);
  appLockEnabledNotifier.value = enabled;
  appLockPasswordNotifier.value = passwordHash;
  globalDarkModeNotifier.value = preferences.getBool(darkModeKey) ?? true;
}

Future<void> saveDarkModeSetting(bool enabled) async {
  globalDarkModeNotifier.value = enabled;
  final preferences = await SharedPreferences.getInstance();
  await preferences.setBool(darkModeKey, enabled);
}

Future<void> saveAppLockSettings({
  required bool enabled,
  required String passwordHash,
}) async {
  if (!firebaseReady) await initializeFirebase();
  final user = FirebaseAuth.instance.currentUser;
  final preferences = await SharedPreferences.getInstance();
  await preferences.setBool(appLockEnabledKey, enabled);
  await preferences.setString(appLockPasswordHashKey, passwordHash);
  appLockEnabledNotifier.value = enabled;
  appLockPasswordNotifier.value = passwordHash;

  if (!firebaseReady || user == null) return;
  try {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('security')
        .doc('appLock')
        .set({
          'passwordHash': passwordHash,
          'enabled': enabled,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  } catch (error) {
    debugPrint('App lock Firebase sync failed: $error');
  }
}

Future<void> showChangeAppLockPasswordDialog(BuildContext context) async {
  final oldController = TextEditingController();
  final newController = TextEditingController();
  final confirmController = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('تغيير كلمة سر قفل التطبيق'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: oldController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'كلمة السر القديمة'),
          ),
          TextField(
            controller: newController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'كلمة السر الجديدة'),
          ),
          TextField(
            controller: confirmController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'تأكيد كلمة السر الجديدة',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: () async {
            final newPassword = newController.text.trim();
            if (await hashPassword(oldController.text.trim()) !=
                    appLockPasswordNotifier.value ||
                newPassword.length < 4 ||
                newPassword != confirmController.text.trim()) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('تحقق من كلمة السر القديمة والجديدة'),
                ),
              );
              return;
            }
            try {
              await saveAppLockSettings(
                enabled: true,
                passwordHash: await hashPassword(newPassword),
              );
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم حفظ كلمة السر في Firebase')),
                );
              }
            } catch (error) {
              debugPrint('App lock password save error: $error');
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      firebaseFailureMessage.contains('operation-not-allowed')
                          ? 'فعّل Anonymous Authentication في Firebase Console'
                          : 'تم حفظ كلمة السر على الجهاز، وستتم مزامنتها عند اتصال Firebase',
                    ),
                  ),
                );
              }
            }
          },
          child: const Text('حفظ'),
        ),
      ],
    ),
  );
  oldController.dispose();
  newController.dispose();
  confirmController.dispose();
}

Future<void> showChangeGroupPasswordDialog(BuildContext context) async {
  final oldController = TextEditingController();
  final newController = TextEditingController();
  String? storedHash;

  try {
    if (firebaseReady) {
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('secretGroup')
          .get();
      final value = doc.data()?['passwordHash'];
      storedHash = value is String
          ? value
          : await hashPassword(initialSecretGroupPassword);
    }
  } catch (_) {
    storedHash = null;
  }

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('تغيير كلمة سر المجموعة'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: oldController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'كلمة السر القديمة'),
          ),
          TextField(
            controller: newController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'كلمة السر الجديدة'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: () async {
            if (storedHash == null ||
                newController.text.trim().isEmpty ||
                await hashPassword(oldController.text) != storedHash) {
              if (context.mounted)
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'كلمة السر القديمة غير صحيحة أو Firebase غير متصل',
                    ),
                  ),
                );
              return;
            }
            try {
              await FirebaseFirestore.instance
                  .collection('config')
                  .doc('secretGroup')
                  .set({
                    'passwordHash': await hashPassword(
                      newController.text.trim(),
                    ),
                    'updatedAt': FieldValue.serverTimestamp(),
                  }, SetOptions(merge: true));
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (context.mounted)
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم تغيير كلمة السر بنجاح')),
                );
            } catch (error) {
              debugPrint('Group password update error: $error');
              if (context.mounted)
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('لا يمكن تغيير كلمة السر من هذا الحساب'),
                  ),
                );
            }
          },
          child: const Text('حفظ'),
        ),
      ],
    ),
  );
  oldController.dispose();
  newController.dispose();
}

Future<void> initializeFirebase() async {
  if (secureLocalDemoMode) {
    firebaseReady = false;
    firebaseFailureMessage = 'Local demo mode enabled';
    return;
  }

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'AIzaSyC8Ft8gdu-41A5bgQItt0J8zsTTqMSYaR0',
          appId: '1:663578459909:web:66e60586316af862b8c16c',
          messagingSenderId: '663578459909',
          projectId: 'shadow-chat-318a0',
          authDomain: 'shadow-chat-318a0.firebaseapp.com',
          storageBucket: 'shadow-chat-318a0.firebasestorage.app',
        ),
      );
    }

    firebaseReady = true;
    if (FirebaseAuth.instance.currentUser != null) {
      try {
        await ensureUserProfile();
        await setupPushNotifications();
        final privacySettings = await loadPrivacySettings();
        if (privacySettings['messageSound'] is bool) {
          messageSoundNotifier.value = privacySettings['messageSound'] as bool;
        }
      } catch (error) {
        debugPrint('User profile setup failed: $error');
      }
      await loadAppLockSettings();
      await loadRoomOwnerKey();
      await loadSecretRoomCode();
    }
  } catch (error) {
    firebaseFailureMessage = error.toString();
    debugPrint('Firebase initialization failed: $error');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (secureLocalDemoMode) {
    firebaseReady = false;
    await loadAppLockSettings();
  } else {
    await initializeFirebase();
  }
  runApp(const ShadowChatApp());
}

Future<void> ensureUserProfile() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  final profileRef = FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid);
  final profile = await profileRef.get();
  final publicId =
      profile.data()?['publicId'] as String? ??
      'SC-${user.uid.substring(0, 6).toUpperCase()}';
  currentPublicUserId = publicId;
  await profileRef.set({
    'publicId': publicId,
    'displayName': profile.data()?['displayName'] ?? 'Shadow User',
    if (user.phoneNumber != null)
      'phoneNumber': _normalizePhoneNumber(user.phoneNumber!),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

String _normalizePhoneNumber(String phone) =>
    phone.replaceAll(RegExp(r'[^0-9+]'), '');

Future<void> updatePresence(bool isOnline) async {
  if (!firebaseReady) return;
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  try {
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'isOnline': isOnline,
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  } catch (error) {
    debugPrint('Presence update error: $error');
  }
}

class ShadowChatApp extends StatelessWidget {
  const ShadowChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: englishLanguageNotifier,
      builder: (context, isEnglish, child) {
        return ValueListenableBuilder<bool>(
          valueListenable: globalDarkModeNotifier,
          builder: (context, isDark, child) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData.light(useMaterial3: true).copyWith(
                scaffoldBackgroundColor: const Color(0xFFF4F7F6),
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF167A5A),
                ),
                appBarTheme: const AppBarTheme(
                  backgroundColor: Color(0xFFEAF1EF),
                  foregroundColor: Color(0xFF14211D),
                ),
                cardTheme: const CardThemeData(
                  color: Colors.white,
                  surfaceTintColor: Colors.transparent,
                ),
                inputDecorationTheme: const InputDecorationTheme(
                  filled: true,
                  fillColor: Color(0xFFF1F5F3),
                ),
              ),
              darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
                scaffoldBackgroundColor: const Color(0xFF101716),
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF38E8A5),
                  brightness: Brightness.dark,
                ),
                appBarTheme: const AppBarTheme(
                  backgroundColor: Color(0xFF15211F),
                  foregroundColor: Color(0xFFE8F3EF),
                ),
                cardTheme: const CardThemeData(
                  color: Color(0xFF192522),
                  surfaceTintColor: Colors.transparent,
                ),
                dividerTheme: const DividerThemeData(color: Color(0x334DD6A2)),
                inputDecorationTheme: const InputDecorationTheme(
                  filled: true,
                  fillColor: Color(0xFF1C2B27),
                ),
              ),
              themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
              home: Directionality(
                textDirection: isEnglish
                    ? TextDirection.ltr
                    : TextDirection.rtl,
                child: const StartupGate(),
              ),
            );
          },
        );
      },
    );
  }
}

class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  static const String _introSeenKey = 'startup_intro_seen';

  @override
  void initState() {
    super.initState();
    _showStartupInfoIfNeeded();
  }

  Future<void> _showStartupInfoIfNeeded() async {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(_introSeenKey) == true || !mounted) return;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.shield_rounded, color: Color(0xFF38E8A5)),
            SizedBox(width: 10),
            Text('Shadow Chat BETA'),
          ],
        ),
        content: const Text(
          'مساحتك الخاصة للمحادثات. يستخدم التطبيق Firebase لحفظ الرسائل، ويطلب الإشعارات لإبلاغك بالرسائل الجديدة، والكاميرا والميكروفون عند استخدام الوسائط أو الرسائل الصوتية.',
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('فهمت'),
          ),
        ],
      ),
    );
    await preferences.setBool(_introSeenKey, true);
  }

  @override
  Widget build(BuildContext context) => const AuthGate();
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isTryingAnonymousLogin = false;
  String? _authError;

  Future<void> _ensureAnonymousLogin() async {
    if (!firebaseReady || FirebaseAuth.instance.currentUser != null) return;

    try {
      await FirebaseAuth.instance.signInAnonymously();
      await setupPushNotifications();
      if (mounted) setState(() => _authError = null);
    } catch (error) {
      debugPrint('Anonymous login failed: $error');
      if (mounted) {
        setState(() {
          _isTryingAnonymousLogin = false;
          _authError = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (secureLocalDemoMode) {
      return const AppLockGate();
    }

    if (!firebaseReady) {
      return Scaffold(
        body: Center(
          child: Text(
            firebaseFailureMessage.isEmpty
                ? 'تعذر الاتصال بـ Firebase'
                : 'تعذر الاتصال بـ Firebase\n$firebaseFailureMessage',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.data == null) {
          if (!_isTryingAnonymousLogin) {
            _isTryingAnonymousLogin = true;
            unawaited(_ensureAnonymousLogin());
          }
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    _authError == null
                        ? 'جاري تجهيز التطبيق...'
                        : 'تعذر الدخول، اضغط لإعادة المحاولة',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  if (_authError != null)
                    TextButton.icon(
                      onPressed: _ensureAnonymousLogin,
                      icon: const Icon(Icons.refresh),
                      label: const Text('إعادة المحاولة'),
                    ),
                ],
              ),
            ),
          );
        }

        return const AppLockGate();
      },
    );
  }
}

class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final TextEditingController _passwordController = TextEditingController();
  late AnimationController _lockAnimationController;
  late Animation<double> _lockAnimation;
  bool _unlocked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(updatePresence(true));
    appLockEnabledNotifier.addListener(_onLockChanged);
    _unlocked = !appLockEnabledNotifier.value;
    _lockAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _lockAnimation = Tween<double>(begin: 0.94, end: 1.06).animate(
      CurvedAnimation(
        parent: _lockAnimationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(updatePresence(true));
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(updatePresence(false));
    }
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.inactive) &&
        appLockEnabledNotifier.value &&
        mounted) {
      setState(() => _unlocked = false);
    }
  }

  void _onLockChanged() {
    if (!appLockEnabledNotifier.value) {
      setState(() => _unlocked = true);
    } else if (appLockPasswordNotifier.value != null) {
      setState(() => _unlocked = false);
    }
  }

  Future<void> _unlock() async {
    if (await hashPassword(_passwordController.text.trim()) ==
        appLockPasswordNotifier.value) {
      setState(() {
        _unlocked = true;
        _passwordController.clear();
      });
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('كلمة المرور غير صحيحة')));
    }
  }

  @override
  void dispose() {
    unawaited(updatePresence(false));
    WidgetsBinding.instance.removeObserver(this);
    appLockEnabledNotifier.removeListener(_onLockChanged);
    _lockAnimationController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked || !appLockEnabledNotifier.value)
      return const ChatListScreen();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: const Color(0xFF06110D),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF071A13), Color(0xFF020504)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Text(
                  '✦  SHADOW SHAT  ✦',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.5,
                  ),
                ),
              ),
              const Text(
                'Private space',
                style: TextStyle(
                  color: Color(0xFF8BA99A),
                  fontSize: 11,
                  letterSpacing: 1.4,
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 410),
                      padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0C1B15).withOpacity(0.96),
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(
                          color: const Color(0xFF3D8062).withOpacity(0.45),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x3300FF66),
                            blurRadius: 30,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ScaleTransition(
                            scale: _lockAnimation,
                            child: Container(
                              padding: const EdgeInsets.all(19),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF00FF66).withOpacity(0.1),
                                border: Border.all(
                                  color: const Color(0xFF00FF66),
                                  width: 1.5,
                                ),
                              ),
                              child: const Icon(
                                Icons.phonelink_lock_rounded,
                                color: Color(0xFF00FF66),
                                size: 48,
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          const Text(
                            'APP SECURED',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 23,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'مساحتك الخاصة محمية بالكامل',
                            style: TextStyle(
                              color: Color(0xFF9BB5A7),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 25),
                          TextField(
                            controller: _passwordController,
                            obscureText: true,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              letterSpacing: 3,
                            ),
                            decoration: InputDecoration(
                              hintText: 'اكتب كلمة مرورك هنا',
                              hintStyle: TextStyle(
                                color: isDark ? Colors.white : Colors.black,
                                letterSpacing: 0,
                              ),
                              filled: true,
                              fillColor: Colors.black.withOpacity(0.28),
                              prefixIcon: const Icon(
                                Icons.key_rounded,
                                color: Colors.amberAccent,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15),
                                borderSide: const BorderSide(
                                  color: Color(0xFF00FF66),
                                  width: 1.5,
                                ),
                              ),
                            ),
                            onSubmitted: (_) => _unlock(),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton.icon(
                              onPressed: _unlock,
                              icon: const Icon(Icons.lock_open_rounded),
                              label: const Text(
                                'دخول آمن',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00FF66),
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                            ),
                          ),
                          if (appLockEnabledNotifier.value)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: TextButton.icon(
                                onPressed: () =>
                                    showChangeAppLockPasswordDialog(context),
                                icon: const Icon(
                                  Icons.password_rounded,
                                  size: 18,
                                ),
                                label: const Text('تغيير كلمة سر قفل التطبيق'),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.amberAccent,
                                ),
                              ),
                            ),
                          const SizedBox(height: 15),
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.verified_user_outlined,
                                color: Colors.amberAccent,
                                size: 15,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Shadow Chat Security',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 1. القائمة الرئيسية
// ==========================================
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndShowIntroduction();
    });
  }

  Future<void> _checkAndShowIntroduction() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasSeenIntro = prefs.getBool('has_seen_onboarding') ?? false;
      
      if (!hasSeenIntro && mounted) {
        _showIntroductionDialog();
      } else if (firebaseReady && hasSeenIntro) {
        // مزامنة حالة الترحيب مع Firebase في الخلفية
        _syncOnboardingStatusWithFirebase(true);
      }
    } catch (error) {
      debugPrint('Error checking introduction: $error');
    }
  }

  Future<void> _syncOnboardingStatusWithFirebase(bool completed) async {
    if (!firebaseReady) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('onboarding')
          .set({
            'onboardingCompleted': completed,
            'completedAt': FieldValue.serverTimestamp(),
            'appVersion': '1.0.0-beta.1',
          }, SetOptions(merge: true));
      debugPrint('Onboarding status synced to Firebase');
    } catch (error) {
      debugPrint('Error syncing onboarding status: $error');
    }
  }

  Future<void> _showIntroductionDialog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'أهلاً بك في Shadow Chat 👋',
          style: TextStyle(
            color: Color(0xFF00FF66),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'تطبيق المراسلة الآمن والمشفر',
                style: TextStyle(color: Colors.white70, fontSize: 16),
                textAlign: TextAlign.right,
              ),
              const SizedBox(height: 16),
              Text(
                'الإصدار التجريبي: BETA 1.0.0-beta.1',
                style: TextStyle(color: Colors.white54, fontSize: 14),
                textAlign: TextAlign.right,
              ),
              const SizedBox(height: 12),
              const Divider(color: Color(0xFF00FF66)),
              const SizedBox(height: 12),
              const Text(
                'المميزات:',
                style: TextStyle(
                  color: Color(0xFF00FF66),
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.right,
              ),
              const SizedBox(height: 8),
              const Text(
                '🔐 تشفير AES-256 للرسائل\n'
                '🎙️ رسائل صوتية مشفرة\n'
                '📸 مشاركة الصور والفيديوهات\n'
                '🌙 وضع مظلم حصري\n'
                '👻 وضع الشبح المتقدم\n'
                '🔒 غرفة سرية بكلمة مرور\n'
                '⏰ حذف تلقائي للرسائل',
                style: TextStyle(color: Colors.white70, height: 1.6),
                textAlign: TextAlign.right,
              ),
              const SizedBox(height: 16),
              const Divider(color: Color(0xFF00FF66)),
              const SizedBox(height: 12),
              const Text(
                'الأذونات المطلوبة:',
                style: TextStyle(
                  color: Color(0xFF00FF66),
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.right,
              ),
              const SizedBox(height: 8),
              const Text(
                '📷 الكاميرا: لمشاركة الصور والفيديوهات\n'
                '🎙️ الميكروفون: للرسائل الصوتية\n'
                '🔔 الإشعارات: للتنبيهات الفورية',
                style: TextStyle(color: Colors.white70, height: 1.6),
                textAlign: TextAlign.right,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF00FF66).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF00FF66), width: 1),
                ),
                child: const Text(
                  '💾 سيتم حفظ بياناتك بأمان في Firebase\nجميع البيانات مشفرة وآمنة 🔐',
                  style: TextStyle(
                    color: Color(0xFF00FF66),
                    fontSize: 12,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('has_seen_onboarding', true);
                
                // مزامنة الحالة مع Firebase
                await _syncOnboardingStatusWithFirebase(true);
                
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (error) {
                debugPrint('Error saving onboarding flag: $error');
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              }
            },
            child: const Text(
              'الدخول',
              style: TextStyle(
                color: Color(0xFF00FF66),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _chooseChatToSecure(BuildContext context) {
    const List<String> chats = [];
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'اختر دردشة لتأمينها',
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: chats.length,
            itemBuilder: (context, index) => ListTile(
              leading: const Icon(
                Icons.chat_bubble_outline,
                color: Color(0xFF00FF66),
              ),
              title: Text(
                chats[index],
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(dialogContext);
                _setChatPassword(context, chats[index]);
              },
            ),
          ),
        ),
      ),
    );
  }

  void _setChatPassword(BuildContext context, String chatName) {
    final TextEditingController passwordController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(
          'تأمين $chatName',
          style: const TextStyle(color: Color(0xFF00FF66)),
        ),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'اكتب كلمة المرور',
            hintStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () async {
              final String password = passwordController.text.trim();
              if (password.length < 4) return;
              try {
                await saveChatPassword(chatName, password);
              } catch (error) {
                debugPrint('Chat password save error: $error');
                return;
              }
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('تم تأمين $chatName')));
            },
            child: const Text(
              'تأمين',
              style: TextStyle(color: Color(0xFF00FF66)),
            ),
          ),
        ],
      ),
    ).then((_) => passwordController.dispose());
  }

  @override
  Widget build(BuildContext context) {
    const List<String> names = [];
    const List<String> lastMessages = [];

    return Directionality(
      textDirection: englishLanguageNotifier.value
          ? TextDirection.ltr
          : TextDirection.rtl,
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: ClipRect(
                child: Transform.scale(
                  scale: MediaQuery.sizeOf(context).width < 600 ? 1.9 : 1.0,
                  child: Image.asset(
                    'assets/images/magic_bg.jpg',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Container(color: Colors.black.withOpacity(0.5)),
            ),
            Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                backgroundColor: Colors.black.withOpacity(0.6),
                centerTitle: true,
                title: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    "✨ 🌑 SHADOW CHAT BETA 🌑 ✨",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.search, color: Color(0xFF00FF66)),
                    tooltip: appText('بحث', 'Search'),
                    onPressed: () {},
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings, color: Colors.white70),
                    tooltip: 'الإعدادات',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SettingsScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
              body: ListView.builder(
                itemCount: names.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    leading: CircleAvatar(
                      radius: 28,
                      backgroundColor: const Color(0xFF00FF66).withOpacity(0.2),
                      child: Text(
                        names[index][0],
                        style: const TextStyle(
                          color: Color(0xFF00FF66),
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(
                      names[index],
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      lastMessages[index],
                      style: const TextStyle(color: Colors.white70),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Text(
                      "أمس",
                      style: TextStyle(color: Color(0xFF00FF66), fontSize: 12),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              ChatScreen(chatName: names[index]),
                        ),
                      );
                    },
                  );
                },
              ),
              floatingActionButton: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00FF66).withOpacity(0.6),
                      blurRadius: 18,
                      spreadRadius: 3,
                    ),
                  ],
                ),
                child: PopupMenuButton<String>(
                  color: Colors.grey[900],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Color(0xFF00FF66), width: 1),
                  ),
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<String>>[
                        const PopupMenuItem<String>(
                          value: 'status',
                          child: Row(
                            children: [
                              Icon(Icons.amp_stories, color: Color(0xFF00FF66)),
                              SizedBox(width: 10),
                              Text(
                                'خيارات الحالة',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem<String>(
                          value: 'security',
                          child: Row(
                            children: [
                              Icon(Icons.security, color: Colors.cyanAccent),
                              SizedBox(width: 10),
                              Text(
                                'تأمين الدردشة',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem<String>(
                          value: 'contacts',
                          child: Row(
                            children: [
                              Icon(
                                Icons.person_add_alt_1,
                                color: Colors.amberAccent,
                              ),
                              SizedBox(width: 10),
                              Text(
                                'إضافة جهات اتصال',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem<String>(
                          value: 'secret_room',
                          child: Row(
                            children: [
                              Icon(Icons.vpn_key, color: Colors.amberAccent),
                              SizedBox(width: 10),
                              Text(
                                'الغرفة السرية (Password)',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem<String>(
                          value: 'ghost',
                          child: Row(
                            children: [
                              Icon(
                                Icons.visibility_off,
                                color: Colors.purpleAccent,
                              ),
                              SizedBox(width: 10),
                              Text(
                                ' المجموعة السرية (Password)',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ],
                  onSelected: (String result) {
                    if (result == 'status') {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم فتح خيارات الحالة ✨')),
                      );
                    } else if (result == 'security') {
                      _chooseChatToSecure(context);
                    } else if (result == 'contacts') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ContactsScreen(),
                        ),
                      );
                    } else if (result == 'secret_room') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SecretRoomScreen(),
                        ),
                      );
                    } else if (result == 'ghost') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SecretChatScreen(),
                        ),
                      );
                    }
                  },
                  child: FloatingActionButton(
                    onPressed: null,
                    backgroundColor: Colors.black,
                    elevation: 0,
                    highlightElevation: 0,
                    shape: const CircleBorder(
                      side: BorderSide(color: Color(0xFF00FF66), width: 2),
                    ),
                    child: const Icon(
                      Icons.fingerprint,
                      color: Color(0xFF00FF66),
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 2. شاشة الغرفة السرية
// ==========================================
class SecretRoomScreen extends StatefulWidget {
  const SecretRoomScreen({super.key});

  @override
  State<SecretRoomScreen> createState() => _SecretRoomScreenState();
}

enum ContactScope { regular, group, room }

String contactsCollectionName(ContactScope scope) {
  switch (scope) {
    case ContactScope.regular:
      return 'regularContacts';
    case ContactScope.group:
      return 'groupContacts';
    case ContactScope.room:
      return 'roomContacts';
  }
}

class ContactsScreen extends StatefulWidget {
  final ContactScope scope;
  final bool ownerVerified;

  const ContactsScreen({
    super.key,
    this.scope = ContactScope.regular,
    this.ownerVerified = false,
  });

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final TextEditingController _contactIdController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  List<Contact> _phoneContacts = [];
  bool _loadingPhoneContacts = false;

  @override
  void dispose() {
    _contactIdController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _addContact() async {
    final String publicId = _contactIdController.text.trim().toUpperCase();
    final String name = _nameController.text.trim();
    final User? user = FirebaseAuth.instance.currentUser;
    if (!firebaseReady ||
        user == null ||
        publicId.isEmpty ||
        publicId == currentPublicUserId)
      return;
    try {
      final matchingUsers = await FirebaseFirestore.instance
          .collection('users')
          .where('publicId', isEqualTo: publicId)
          .limit(1)
          .get();
      if (matchingUsers.docs.isEmpty) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('المعرّف غير موجود في Firebase')),
          );
        return;
      }
      final contactId = matchingUsers.docs.first.id;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection(contactsCollectionName(widget.scope))
          .doc(contactId)
          .set({
            'contactId': publicId,
            'uid': contactId,
            'displayName': name.isEmpty ? 'جهة اتصال' : name,
            'createdAt': FieldValue.serverTimestamp(),
          });
      if (widget.scope != ContactScope.regular) {
        final roomId = widget.scope == ContactScope.group
            ? 'secret_group'
            : 'secret_room';
        await FirebaseFirestore.instance
            .collection('rooms')
            .doc(roomId)
            .collection('members')
            .doc(contactId)
            .set({
              'displayName': name.isEmpty ? 'جهة اتصال' : name,
              'addedBy': user.uid,
              'addedAt': FieldValue.serverTimestamp(),
            });
      }
      _contactIdController.clear();
      _nameController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تمت إضافة جهة الاتصال وحفظها')),
        );
      }
    } catch (error) {
      debugPrint('Contact save error: $error');
    }
  }

  Future<void> _loadPhoneContacts() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('جهات اتصال الهاتف متاحة على Android فقط')),
      );
      return;
    }
    setState(() => _loadingPhoneContacts = true);
    try {
      final permissionGranted = await FlutterContacts.permissions.has(
        PermissionType.read,
      );
      if (!permissionGranted &&
          await FlutterContacts.permissions.request(PermissionType.read) !=
              PermissionStatus.granted) {
        return;
      }
      final contacts = await FlutterContacts.getAll(
        properties: {ContactProperty.phone},
      );
      if (mounted) setState(() => _phoneContacts = contacts);
    } catch (error) {
      debugPrint('Phone contacts load error: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر قراءة جهات اتصال الهاتف')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingPhoneContacts = false);
    }
  }

  String _normalizePhone(String phone) {
    final arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    var normalized = phone;
    for (var index = 0; index < arabicDigits.length; index++) {
      normalized = normalized.replaceAll(
        arabicDigits[index],
        index.toString(),
      );
    }
    return normalized.replaceAll(RegExp(r'[^0-9+]'), '');
  }

  Future<void> _addPhoneContact(Contact contact) async {
    final phone = contact.phones.isEmpty
        ? ''
        : _normalizePhone(contact.phones.first.number);
    final user = FirebaseAuth.instance.currentUser;
    if (!firebaseReady || user == null || phone.isEmpty) return;
    try {
      final matchingUsers = await FirebaseFirestore.instance
          .collection('users')
          .where('phoneNumber', isEqualTo: phone)
          .limit(1)
          .get();
      if (matchingUsers.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('هذا الرقم غير مسجل في التطبيق')),
          );
        }
        return;
      }
      final contactId = matchingUsers.docs.first.id;
      if (contactId == user.uid) return;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection(contactsCollectionName(widget.scope))
          .doc(contactId)
          .set({
            'contactId': matchingUsers.docs.first.data()['publicId'] ?? contactId,
            'uid': contactId,
            'displayName': (contact.displayName ?? '').isEmpty
                ? 'جهة اتصال'
                : contact.displayName,
            'createdAt': FieldValue.serverTimestamp(),
          });
      if (widget.scope != ContactScope.regular) {
        final roomId = widget.scope == ContactScope.group
            ? 'secret_group'
            : 'secret_room';
        await FirebaseFirestore.instance
            .collection('rooms')
            .doc(roomId)
            .collection('members')
            .doc(contactId)
            .set({
              'displayName': (contact.displayName ?? '').isEmpty
                  ? 'جهة اتصال'
                  : contact.displayName,
              'addedBy': user.uid,
              'addedAt': FieldValue.serverTimestamp(),
            });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تمت إضافة جهة الاتصال')),
        );
      }
    } catch (error) {
      debugPrint('Phone contact save error: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.scope == ContactScope.room && !widget.ownerVerified) {
      return const Scaffold(
        body: Center(child: Text('يجب التحقق من مفتاح المالك أولًا')),
      );
    }
    final User? user = FirebaseAuth.instance.currentUser;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF07110F),
        appBar: AppBar(
          title: Text(
            widget.scope == ContactScope.regular
                ? 'جهات اتصال الشات'
                : widget.scope == ContactScope.group
                ? 'جهات اتصال المجموعة'
                : 'جهات اتصال الغرفة',
          ),
          backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
          iconTheme: const IconThemeData(color: Color(0xFF38E8A5)),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (user != null)
                    SelectableText(
                      'معرّفك السهل: ${currentPublicUserId ?? 'جارٍ التحميل...'}',
                      style: const TextStyle(
                        color: Color(0xFF38E8A5),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _loadingPhoneContacts ? null : _loadPhoneContacts,
                      icon: _loadingPhoneContacts
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.contacts_outlined),
                      label: const Text('اختيار من جهات اتصال الهاتف'),
                    ),
                  ),
                  if (_phoneContacts.isNotEmpty)
                    SizedBox(
                      height: 180,
                      child: ListView.builder(
                        itemCount: _phoneContacts.length,
                        itemBuilder: (context, index) {
                          final contact = _phoneContacts[index];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.person_outline),
                            title: Text(contact.displayName ?? 'جهة اتصال'),
                            subtitle: Text(
                              contact.phones.isEmpty
                                  ? 'لا يوجد رقم'
                                  : contact.phones.first.number,
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.person_add_alt_1),
                              onPressed: contact.phones.isEmpty
                                  ? null
                                  : () => _addPhoneContact(contact),
                            ),
                          );
                        },
                      ),
                    ),
                  TextField(
                    controller: _contactIdController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'المعرّف السهل مثل SC-A1B2C3',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  TextField(
                    controller: _nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'اسم جهة الاتصال',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _addContact,
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('حفظ جهة الاتصال'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF38E8A5),
                        foregroundColor: Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: user == null
                  ? const Center(
                      child: Text(
                        'Firebase غير متصل',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .collection(contactsCollectionName(widget.scope))
                          .orderBy('createdAt')
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError)
                          return const Center(
                            child: Text(
                              'تعذر تحميل جهات الاتصال',
                              style: TextStyle(color: Colors.white70),
                            ),
                          );
                        final docs = snapshot.data?.docs ?? [];
                        if (docs.isEmpty)
                          return const Center(
                            child: Text(
                              'لا توجد جهات اتصال بعد',
                              style: TextStyle(color: Colors.white54),
                            ),
                          );
                        return ListView.builder(
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final data = docs[index].data();
                            return ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.person),
                              ),
                              title: Text(
                                data['displayName'] ?? 'جهة اتصال',
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                data['contactId'] ?? docs[index].id,
                                style: const TextStyle(color: Colors.white54),
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(
                                      chatName:
                                          data['displayName'] ?? 'جهة اتصال',
                                      contactUid: data['uid'] ?? docs[index].id,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecretRoomScreenState extends State<SecretRoomScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _codeController = TextEditingController();
  bool _isUnlocked = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    _pulseController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF07110F),
        appBar: AppBar(
          title: const Text(
            '🔐 الغرفة السرية المحصنة',
            style: TextStyle(
              color: Colors.amberAccent,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          backgroundColor: Colors.black87,
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.amberAccent),
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black, Colors.grey[900]!, Colors.black],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: _isUnlocked
                ? _buildSecretWorkspace()
                : _buildCodeEntryView(),
          ),
        ),
      ),
    );
  }

  Widget _buildCodeEntryView() {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.amberAccent.withOpacity(0.5),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.amberAccent.withOpacity(0.2),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.fingerprint,
                  size: 70,
                  color: Colors.amberAccent,
                ),
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              'منطقة مقيدة أمنياً',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'أدخل كود الغرفة الثابت للوصول إلى محتواها',
              style: TextStyle(color: Colors.white54, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            const SizedBox(height: 30),
            TextField(
              controller: _codeController,
              style: const TextStyle(color: Colors.white, letterSpacing: 2),
              obscureText: true,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: '••••••••',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: Colors.grey[900],
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: Colors.amberAccent,
                    width: 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: Color(0xFF00FF66),
                    width: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amberAccent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 5,
                ),
                icon: const Icon(Icons.lock_open, color: Colors.black),
                label: const Text(
                  'فك التشفير والدخول',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                onPressed: () async {
                  if (await hashPassword(_codeController.text.trim()) ==
                      secretRoomCodeHashNotifier.value) {
                    setState(() {
                      _isUnlocked = true;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تم فتح الغرفة السرية بنجاح 🚀'),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('الكود خطأ! ❌ برجاء مراجعة كود الغرفة'),
                      ),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecretWorkspace() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.amberAccent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.amberAccent, width: 1),
          ),
          child: Row(
            children: [
              const Icon(Icons.security, color: Colors.amberAccent, size: 36),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'أنت الآن في النطاق الآمن',
                      style: TextStyle(
                        color: Colors.amberAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'البيانات هنا مشفرة كلياً ولا تظهر في السجل الرئيسي للتطبيق.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'إدارة إعدادات الغرفة:',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 10),
        ValueListenableBuilder<List<String>>(
          valueListenable: secretRoomMembersNotifier,
          builder: (context, members, child) {
            return ListTile(
              tileColor: Colors.grey[900],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              leading: const Icon(Icons.group_add, color: Color(0xFF00FF66)),
              title: Text(
                'إدارة أعضاء الغرفة (للمالك فقط)',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              subtitle: Text(
                'الأعضاء: ${members.length} / $maxSecretRoomMembers',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              trailing: const Icon(
                Icons.arrow_forward_ios,
                color: Colors.white54,
                size: 16,
              ),
              onTap: () => _verifyRoomOwner(context),
            );
          },
        ),
        const SizedBox(height: 15),
        const Text(
          'المحادثات المخفية داخل الغرفة:',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView(
            children: [
              ListTile(
                tileColor: Colors.grey[900]?.withOpacity(0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: const CircleAvatar(
                  backgroundColor: Colors.amberAccent,
                  child: Icon(Icons.vpn_key, color: Colors.black),
                ),
                title: const Text(
                  'الغرفة السوداء (Shadow Ops)',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'آخر رسالة: تم تأمين التردد بنجاح...',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                trailing: const Icon(
                  Icons.lock,
                  color: Color(0xFF00FF66),
                  size: 18,
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const BlackRoomScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showRoomMembersDialog(BuildContext context) {
    final User? owner = FirebaseAuth.instance.currentUser;
    showDialog(
      context: context,
      builder: (dialogContext) =>
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: owner == null
                ? null
                : FirebaseFirestore.instance
                      .collection('users')
                      .doc(owner.uid)
                      .collection(contactsCollectionName(ContactScope.room))
                      .orderBy('createdAt')
                      .snapshots(),
            builder: (context, contactsSnapshot) =>
                ValueListenableBuilder<List<String>>(
                  valueListenable: secretRoomMembersNotifier,
                  builder: (context, members, child) {
                    final contacts = contactsSnapshot.data?.docs ?? [];
                    final availableContacts = contacts
                        .where((contact) => !members.contains(contact.id))
                        .toList();
                    return AlertDialog(
                      backgroundColor: Colors.grey[900],
                      title: Text(
                        'أعضاء الغرفة (${members.length}/$maxSecretRoomMembers)',
                        style: const TextStyle(color: Colors.white),
                      ),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: members.length >= maxSecretRoomMembers
                            ? const Text(
                                'تم الوصول إلى الحد الأقصى للأعضاء.',
                                style: TextStyle(color: Colors.white70),
                              )
                            : availableContacts.isEmpty
                            ? const Text(
                                'أضف جهات اتصال أولًا من زر البصمة.',
                                style: TextStyle(color: Colors.white70),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                itemCount: availableContacts.length,
                                itemBuilder: (context, index) {
                                  final contact = availableContacts[index];
                                  final data = contact.data();
                                  return ListTile(
                                    leading: const Icon(
                                      Icons.person_add,
                                      color: Color(0xFF00FF66),
                                    ),
                                    title: Text(
                                      data['displayName'] ?? 'جهة اتصال',
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                    subtitle: Text(
                                      contact.id,
                                      style: const TextStyle(
                                        color: Colors.white54,
                                      ),
                                    ),
                                    onTap: () async {
                                      await FirebaseFirestore.instance
                                          .collection('rooms')
                                          .doc('secret_room')
                                          .collection('members')
                                          .doc(contact.id)
                                          .set({
                                            'displayName':
                                                data['displayName'] ??
                                                'جهة اتصال',
                                            'addedBy': owner?.uid,
                                            'addedAt':
                                                FieldValue.serverTimestamp(),
                                          });
                                      secretRoomMembersNotifier.value = [
                                        ...members,
                                        contact.id,
                                      ];
                                      if (dialogContext.mounted)
                                        Navigator.pop(dialogContext);
                                    },
                                  );
                                },
                              ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text(
                            'إغلاق',
                            style: TextStyle(color: Colors.amberAccent),
                          ),
                        ),
                      ],
                    );
                  },
                ),
          ),
    );
  }

  void _verifyRoomOwner(BuildContext context) {
    final TextEditingController ownerKeyController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'تحقق من المالك',
          style: TextStyle(color: Colors.amberAccent),
        ),
        content: TextField(
          controller: ownerKeyController,
          obscureText: true,
          autofocus: true,
          style: const TextStyle(color: Colors.white, letterSpacing: 2),
          decoration: const InputDecoration(
            hintText: 'مفتاح المالك',
            hintStyle: TextStyle(color: Colors.white54),
            prefixIcon: Icon(
              Icons.admin_panel_settings,
              color: Colors.amberAccent,
            ),
          ),
          onSubmitted: (_) =>
              _submitOwnerKey(dialogContext, ownerKeyController),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => _submitOwnerKey(dialogContext, ownerKeyController),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amberAccent,
              foregroundColor: Colors.black,
            ),
            child: const Text('تحقق'),
          ),
        ],
      ),
    ).then((_) => ownerKeyController.dispose());
  }

  Future<void> _submitOwnerKey(
    BuildContext dialogContext,
    TextEditingController controller,
  ) async {
    if (await hashPassword(controller.text.trim()) ==
        roomOwnerKeyHashNotifier.value) {
      Navigator.pop(dialogContext);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const ContactsScreen(
            scope: ContactScope.room,
            ownerVerified: true,
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('مفتاح المالك غير صحيح'),
        backgroundColor: Colors.redAccent,
      ),
    );
  }
}

// ==========================================
// 3. شاشة الشات الجماعي السري (المجموعة السرية الآمنة 🛡️)
// ==========================================
class SecretChatScreen extends StatefulWidget {
  final bool requirePassword;
  final String chatTitle;

  const SecretChatScreen({
    super.key,
    this.requirePassword = true,
    this.chatTitle = 'المجموعة السرية الآمنة',
  });

  @override
  State<SecretChatScreen> createState() => _SecretChatScreenState();
}

class BlackRoomScreen extends StatelessWidget {
  const BlackRoomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SecretChatScreen(
      chatTitle: 'الغرفة السوداء (Shadow Ops)',
      requirePassword: false,
    );
  }
}

class _SecretChatScreenState extends State<SecretChatScreen>
    with SingleTickerProviderStateMixin {
  bool _isUnlocked = false;
  bool _isSecretMember = false;
  String? _groupPasswordHash;
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _secretMessagesSubscription;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final List<Map<String, dynamic>> _secretMessages = [
    {
      "sender": "System",
      "text": "أهلاً بك في المجموعة السرية الآمنة",
      "isMe": false,
    },
  ];

  @override
  void initState() {
    super.initState();
    _isUnlocked = !widget.requirePassword;
    if (widget.chatTitle.contains('الغرفة السوداء')) {
      _secretMessages[0]['text'] = 'أهلاً بك في غرفة Shadow Ops';
      _secretMessages[0]['roomNote'] = 'قناة خاصة وآمنة داخل الغرفة السرية';
    }
    _listenToSecretMessages();
    _loadSecretMembership();
    _loadGroupPassword();
    clearHistoryNotifier.addListener(_clearSecretMessages);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  Future<void> _sendSecretMessage() async {
    final String text = _messageController.text.trim();
    if (text.isNotEmpty) {
      if (!_isSecretMember) {
        await _loadSecretMembership();
      }
      if (!_isSecretMember) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('أنت لست عضوًا في هذه المجموعة ولا يمكنك الإرسال'),
            ),
          );
        }
        return;
      }
      setState(() {
        _secretMessages.add({
          "sender": "أنت",
          "text": text,
          "isMe": true,
          "time": _formatMessageTime(),
        });
        _messageController.clear();
      });

      _saveSecretMessage(text);
      if (autoDeleteMessagesNotifier.value) {
        Future.delayed(const Duration(seconds: 8), () {
          if (mounted && autoDeleteMessagesNotifier.value) {
            setState(() {
              _secretMessages.removeWhere(
                (message) => message['text'] == text && message['isMe'] == true,
              );
            });
          }
          unawaited(deleteExpiredOwnChatMessages(_secretChatId));
        });
      }
    }
  }

  Future<void> _loadGroupPassword() async {
    if (!widget.requirePassword) return;
    final fallbackHash = await hashPassword(initialSecretGroupPassword);
    if (!firebaseReady) {
      if (mounted) setState(() => _groupPasswordHash = fallbackHash);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('secretGroup')
          .get();
      final storedHash = doc.data()?['passwordHash'];
      final hash = storedHash is String
          ? storedHash
          : await hashPassword(initialSecretGroupPassword);
      if (mounted) setState(() => _groupPasswordHash = hash);
    } catch (error) {
      debugPrint('Group password load error: $error');
      if (mounted) setState(() => _groupPasswordHash = fallbackHash);
    }
  }

  Future<void> _changeGroupPassword() async {
    final oldController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    if (!firebaseReady) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذر الاتصال بـ Firebase')));
      oldController.dispose();
      newController.dispose();
      confirmController.dispose();
      return;
    }
    _groupPasswordHash ??= await hashPassword(initialSecretGroupPassword);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF101B18),
        title: const Text(
          'تغيير كلمة السر',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: oldController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'كلمة السر القديمة'),
            ),
            TextField(
              controller: newController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'كلمة السر الجديدة'),
            ),
            TextField(
              controller: confirmController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'تأكيد كلمة السر الجديدة',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newPassword = newController.text.trim();
              final oldPasswordVerified = await matchesGroupPassword(
                oldController.text.trim(),
                _groupPasswordHash,
              );
              if (!oldPasswordVerified ||
                  newPassword.length < 4 ||
                  newPassword != confirmController.text.trim()) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تحقق من القديمة والجديدة وتأكيدها'),
                    ),
                  );
                }
                return;
              }
              try {
                await FirebaseFirestore.instance
                    .collection('config')
                    .doc('secretGroup')
                    .set({
                      'passwordHash': await hashPassword(newPassword),
                      'updatedAt': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true));
                final newHash = await hashPassword(newPassword);
                if (mounted) setState(() => _groupPasswordHash = newHash);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم تغيير كلمة السر بنجاح')),
                  );
              } catch (error) {
                debugPrint('Group password update error: $error');
                if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تعذر حفظ كلمة سر المجموعة في Firebase'),
                    ),
                  );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD76A),
              foregroundColor: Colors.black,
            ),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    oldController.dispose();
    newController.dispose();
    confirmController.dispose();
  }

  String get _secretChatId => widget.chatTitle.contains('الغرفة السوداء')
      ? 'shadow_ops'
      : 'secret_group';

  Future<void> _loadSecretMembership() async {
    if (!firebaseReady) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final ownerDoc = await FirebaseFirestore.instance
          .collection('config')
          .doc('app')
          .get();
      final memberDoc = await FirebaseFirestore.instance
          .collection('rooms')
          .doc(_secretChatId)
          .collection('members')
          .doc(user.uid)
          .get();
      if (mounted) {
        setState(
          () => _isSecretMember =
              ownerDoc.data()?['ownerUid'] == user.uid || memberDoc.exists,
        );
      }
    } catch (error) {
      debugPrint('Membership check error: $error');
    }
  }

  void _listenToSecretMessages() {
    if (!firebaseReady) return;
    _secretMessagesSubscription = FirebaseFirestore.instance
        .collection('chats')
        .doc(_secretChatId)
        .collection('messages')
        .orderBy('createdAt')
        .limit(100)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;
            final messages = snapshot.docs.map((doc) {
              final data = doc.data();
              final timestamp = data['createdAt'];
              return {
                'sender': data['sender'] ?? 'مستخدم',
                'text': data['text'] ?? '',
                'isMe': data['uid'] == FirebaseAuth.instance.currentUser?.uid,
                'time': timestamp is Timestamp
                    ? _formatTimestamp(timestamp)
                    : _formatMessageTime(),
              };
            }).toList();
            setState(() {
              _secretMessages
                ..clear()
                ..addAll(messages);
            });
          },
          onError: (error) {
            debugPrint('Secret messages listener error: $error');
          },
        );
  }

  Future<void> _saveSecretMessage(String text) async {
    if (!firebaseReady) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_firebaseUnavailableMessage())));
      }
      return;
    }
    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(_secretChatId)
          .collection('messages')
          .add({
            'sender': 'أنت',
            'text': text,
            'uid': user?.uid,
            'createdAt': FieldValue.serverTimestamp(),
            if (autoDeleteMessagesNotifier.value)
              'expiresAt': Timestamp.fromDate(
                DateTime.now().add(const Duration(seconds: 8)),
              ),
          });
    } catch (error) {
      debugPrint('Secret message save error: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر حفظ الرسالة في Firebase')),
        );
      }
    }
  }

  String _formatTimestamp(Timestamp timestamp) {
    final date = timestamp.toDate();
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _showGroupContactDialog() {
    final User? owner = FirebaseAuth.instance.currentUser;
    if (!firebaseReady || owner == null) return;
    showDialog(
      context: context,
      builder: (dialogContext) =>
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: owner == null
                ? null
                : FirebaseFirestore.instance
                      .collection('users')
                      .doc(owner.uid)
                      .collection(contactsCollectionName(ContactScope.group))
                      .orderBy('createdAt')
                      .snapshots(),
            builder: (context, snapshot) {
              final contacts = snapshot.data?.docs ?? [];
              return AlertDialog(
                backgroundColor: const Color(0xFF101B18),
                title: const Text(
                  'إضافة جهة اتصال للمجموعة',
                  style: TextStyle(color: Colors.white),
                ),
                content: SizedBox(
                  width: double.maxFinite,
                  child: contacts.isEmpty
                      ? const Text(
                          'أضف جهات اتصال أولًا من زر البصمة.',
                          style: TextStyle(color: Colors.white70),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: contacts.length,
                          itemBuilder: (context, index) {
                            final data = contacts[index].data();
                            return ListTile(
                              leading: const Icon(
                                Icons.person_add,
                                color: Color(0xFFFFD76A),
                              ),
                              title: Text(
                                data['displayName'] ?? 'جهة اتصال',
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                contacts[index].id,
                                style: const TextStyle(color: Colors.white54),
                              ),
                              onTap: () async {
                                await FirebaseFirestore.instance
                                    .collection('rooms')
                                    .doc('secret_group')
                                    .collection('members')
                                    .doc(contacts[index].id)
                                    .set({
                                      'displayName':
                                          data['displayName'] ?? 'جهة اتصال',
                                      'addedBy': owner?.uid,
                                      'addedAt': FieldValue.serverTimestamp(),
                                    });
                                if (dialogContext.mounted)
                                  Navigator.pop(dialogContext);
                              },
                            );
                          },
                        ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text(
                      'إغلاق',
                      style: TextStyle(color: Colors.amberAccent),
                    ),
                  ),
                ],
              );
            },
          ),
    );
  }

  String _firebaseUnavailableMessage() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      return 'Firebase Firestore غير مدعوم على Linux desktop. شغّل التطبيق على Android أو Chrome.';
    }
    if (firebaseFailureMessage.contains('operation-not-allowed')) {
      return 'فعّل Anonymous Authentication من Firebase Console ثم أعد تشغيل التطبيق.';
    }
    return 'Firebase غير متصل: لم يتم حفظ الرسالة. فعّل Anonymous Authentication وتأكد من إعداد Firebase Web.';
  }

  String _formatMessageTime() {
    final DateTime now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _secretMessagesSubscription?.cancel();
    clearHistoryNotifier.removeListener(_clearSecretMessages);
    _pulseController.dispose();
    _passController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _clearSecretMessages() {
    if (mounted) setState(_secretMessages.clear);
    unawaited(deleteOwnChatMessages(_secretChatId));
  }

  @override
  Widget build(BuildContext context) {
    return _isUnlocked ? _buildChatInterface() : _buildPasswordInterface();
  }

  // 1. واجهة الباسورد (العنوان في المنتصف والقفل على الشمال)
  Widget _buildPasswordInterface() {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        appBar: AppBar(
          centerTitle: true, // جعل العنوان في المنتصف
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.chatTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(width: 8),
              Icon(
                Icons.lock_rounded,
                color: Colors.amberAccent,
                size: 18,
              ), // القفل على الشمال من النص
            ],
          ),
          backgroundColor: const Color(0xFF121212),
          elevation: 2,
          iconTheme: const IconThemeData(color: Colors.amberAccent),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.amberAccent.withOpacity(0.08),
                      border: Border.all(color: Colors.amberAccent, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amberAccent.withOpacity(0.3),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      color: Colors.amberAccent,
                      size: 55,
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                const Text(
                  'المجموعة السرية الآمنة 🛡️',
                  style: TextStyle(
                    color: Colors.amberAccent,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'منطقة مقيدة أمنياً - أدخل مفتاح التشفير',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 40),
                Container(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: TextField(
                    controller: _passController,
                    obscureText: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 18,
                      letterSpacing: 2,
                    ),
                    decoration: InputDecoration(
                      hintText: '••••••••••••',
                      hintStyle: TextStyle(color: Colors.grey[700]),
                      filled: true,
                      fillColor: const Color(0xFF141414),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(
                          color: Colors.amberAccent,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 25),
                Container(
                  constraints: const BoxConstraints(maxWidth: 380),
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amberAccent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      elevation: 8,
                      shadowColor: Colors.amberAccent.withOpacity(0.5),
                    ),
                    onPressed: () async {
                      if (await matchesGroupPassword(
                        _passController.text.trim(),
                        _groupPasswordHash,
                      )) {
                        setState(() => _isUnlocked = true);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'الكود غير صحيح! حاول مجدداً',
                              style: TextStyle(color: Colors.white),
                            ),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    },
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_open_rounded, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'فك التشفير والدخول',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (widget.requirePassword)
                  TextButton(
                    onPressed: _changeGroupPassword,
                    child: const Text(
                      'تغيير كلمة السر',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 2. واجهة الشات الجماعي السري
  Widget _buildChatInterface() {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D1117),
        appBar: AppBar(
          centerTitle: true,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.chatTitle,
                style: TextStyle(
                  color: Colors.amberAccent,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.verified_user_rounded,
                color: Color(0xFF38E8A5),
                size: 20,
              ),
            ],
          ),
          backgroundColor: const Color(0xFF171D26),
          elevation: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: const Color(0xFF3A4655)),
          ),
          iconTheme: const IconThemeData(color: Color(0xFF38E8A5)),
          actions: [
            if (!widget.chatTitle.contains('الغرفة السوداء'))
              IconButton(
                icon: const Icon(
                  Icons.person_add_alt_1,
                  color: Color(0xFFFFD76A),
                ),
                tooltip: 'إضافة جهة اتصال للمجموعة',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          const ContactsScreen(scope: ContactScope.group),
                    ),
                  );
                },
              ),
          ],
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0D1117), Color(0xFF111A1D)],
            ),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2930),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF61E7C0).withOpacity(0.45),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lock_outline_rounded,
                      color: Color(0xFF38E8A5),
                      size: 18,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        widget.chatTitle.contains('الغرفة السوداء')
                            ? 'قناة Shadow Ops الخاصة'
                            : 'اتصال مشفّر داخل المجموعة',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const Text(
                      'متصل الآن',
                      style: TextStyle(color: Color(0xFF38E8A5), fontSize: 11),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                  itemCount: _secretMessages.length,
                  itemBuilder: (context, index) {
                    final msg = _secretMessages[index];
                    final bool isMe = msg["isMe"]!;

                    bool isWelcomeMsg = msg["text"].toString().contains(
                      "أهلاً بك في المجموعة السرية الآمنة",
                    );

                    if (isWelcomeMsg && !isMe) {
                      return Container(
                        margin: const EdgeInsets.only(top: 10, bottom: 20),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.amberAccent.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.amberAccent.withOpacity(0.25),
                          ),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.verified_user_rounded,
                              color: Colors.amberAccent,
                              size: 38,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              msg["text"]!,
                              style: const TextStyle(
                                color: Colors.amberAccent,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              "جميع الرسائل داخل هذه الغرفة مشفرة ومؤمنة بالكامل.",
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    }

                    return Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 330),
                        margin: const EdgeInsets.symmetric(vertical: 5),
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                        decoration: BoxDecoration(
                          color: isMe
                              ? const Color(0xFF176B59)
                              : const Color(0xFF202733),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(18),
                            topRight: const Radius.circular(18),
                            bottomLeft: Radius.circular(isMe ? 18 : 4),
                            bottomRight: Radius.circular(isMe ? 4 : 18),
                          ),
                          border: Border.all(
                            color: isMe
                                ? const Color(0xFF38E8A5)
                                : const Color(0xFF3B4A5C),
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x22000000),
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isMe
                                      ? Icons.account_circle
                                      : Icons.shield_rounded,
                                  color: isMe
                                      ? const Color(0xFF8FFFD0)
                                      : const Color(0xFFFFD76A),
                                  size: 15,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  msg["sender"]!,
                                  style: TextStyle(
                                    color: isMe
                                        ? const Color(0xFF8FFFD0)
                                        : const Color(0xFFFFD76A),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              msg["text"]!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Align(
                              alignment: AlignmentDirectional.bottomEnd,
                              child: Text(
                                msg["time"] ?? _formatMessageTime(),
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              Container(
                margin: const EdgeInsets.fromLTRB(10, 4, 10, 12),
                padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF18231F),
                  borderRadius: const BorderRadius.all(Radius.circular(18)),
                  border: Border.all(color: const Color(0xFF3A665A)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'اكتب رسالتك السرية...',
                          hintStyle: const TextStyle(color: Colors.white38),
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _sendSecretMessage(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.send_rounded,
                        color: Color(0xFF38E8A5),
                      ),
                      onPressed: _sendSecretMessage,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 4. إعدادات النظام وشاشات التطبيق
// ==========================================
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Directionality(
      textDirection: englishLanguageNotifier.value
          ? TextDirection.ltr
          : TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(
            'إعدادات النظام',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: isDark ? const Color(0xFF0B1D19) : Colors.white,
          foregroundColor: isDark ? Colors.white : Colors.black,
          iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
          centerTitle: true,
        ),
        body: ListView(
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: englishLanguageNotifier,
              builder: (context, isEnglish, child) {
                return ListTile(
                  leading: Icon(
                    Icons.language,
                    color: isDark ? Colors.cyanAccent : Colors.black,
                  ),
                  title: Text(
                    isEnglish ? 'Language' : 'اللغة',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    isEnglish ? 'Choose the app language' : 'اختار لغة التطبيق',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: DropdownButton<bool>(
                    value: isEnglish,
                    dropdownColor: isDark ? Colors.grey[900] : Colors.white,
                    underline: const SizedBox.shrink(),
                    items: [
                      DropdownMenuItem(
                        value: false,
                        child: Text(
                          'العربية',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      DropdownMenuItem(
                        value: true,
                        child: Text(
                          'English',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) englishLanguageNotifier.value = value;
                    },
                  ),
                );
              },
            ),
            Divider(color: Theme.of(context).dividerColor),
            ListTile(
              leading: Icon(
                Icons.folder_special,
                color: isDark ? const Color(0xFF00FF66) : Colors.black,
              ),
              title: Text(
                'الإعدادات المتغيرة',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                'تحكم في الحركة، الصوت، والتشفير التلقائي',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: Icon(
                Icons.arrow_forward_ios,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 16,
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DynamicSettingsScreen(),
                  ),
                );
              },
            ),
            Divider(color: Theme.of(context).dividerColor),
            ListTile(
              leading: Icon(
                Icons.security,
                color: isDark ? Colors.cyanAccent : Colors.black,
              ),
              title: Text(
                'الخصوصية والأمان',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                'الوضع الخفي، قفل التطبيق، وحذف السجل',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: Icon(
                Icons.arrow_forward_ios,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 16,
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PrivacySettingsScreen(),
                  ),
                );
              },
            ),
            Divider(color: Theme.of(context).dividerColor),
            ListTile(
              leading: Icon(
                Icons.account_circle,
                color: isDark ? const Color(0xFF38E8A5) : Colors.black,
              ),
              title: Text(
                'الحساب والمظهر',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                'الملف الشخصي وتخصيص المظهر والألوان',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: Icon(
                Icons.arrow_forward_ios,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 16,
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AccountAndThemeScreen(),
                  ),
                );
              },
            ),
            Divider(color: Theme.of(context).dividerColor),
            ListTile(
              leading: Icon(
                Icons.notifications_active,
                color: isDark ? Colors.pinkAccent : Colors.black,
              ),
              title: Text(
                'الإشعارات والأصوات',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                'تخصيص نغمات التنبيه والاهتزاز',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: Icon(
                Icons.arrow_forward_ios,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 16,
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const NotificationsScreen(),
                  ),
                );
              },
            ),
            Divider(color: Theme.of(context).dividerColor),
            ListTile(
              leading: Icon(
                Icons.info_outline,
                color: isDark ? Colors.blueAccent : Colors.black,
              ),
              title: Text(
                'حول التطبيق',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                'Shadow Chat BETA v1.0.0-beta.1 ومعلومات المبرمج',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: Icon(
                Icons.arrow_forward_ios,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 16,
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AboutAppScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class DynamicSettingsScreen extends StatelessWidget {
  const DynamicSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(
            'الإعدادات المتغيرة',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
          foregroundColor: isDark ? Colors.white : Colors.black,
          iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
          centerTitle: true,
        ),
        body: ListView(
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: whaleMotionNotifier,
              builder: (context, isMoving, child) {
                return SwitchListTile(
                  secondary: Icon(
                    Icons.waves,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.cyanAccent
                        : Colors.black,
                  ),
                  title: Text(
                    'تحريك خلفية الحوت',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    'تفعيل أو إيقاف حركة طفو الحوت في الخلفية',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  value: isMoving,
                  activeColor: isDark ? const Color(0xFF00FF66) : Colors.black,
                  onChanged: (bool value) {
                    whaleMotionNotifier.value = value;
                  },
                );
              },
            ),
            Divider(color: Theme.of(context).dividerColor),
            ValueListenableBuilder<bool>(
              valueListenable: whaleSoundNotifier,
              builder: (context, isSoundEnabled, child) {
                return SwitchListTile(
                  secondary: Icon(
                    Icons.volume_up,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.pinkAccent
                        : Colors.black,
                  ),
                  title: Text(
                    'صوت ترحيب الحوت',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    'تشغيل أو إيقاف المؤثر الصوتي عند فتح الشات',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  value: isSoundEnabled,
                  activeColor: isDark ? const Color(0xFF00FF66) : Colors.black,
                  onChanged: (bool value) {
                    whaleSoundNotifier.value = value;
                  },
                );
              },
            ),
            Divider(color: Theme.of(context).dividerColor),
            ValueListenableBuilder<bool>(
              valueListenable: autoEncryptNotifier,
              builder: (context, isAutoEncryptEnabled, child) {
                return SwitchListTile(
                  secondary: Icon(
                    Icons.security,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF00FF66)
                        : Colors.black,
                  ),
                  title: Text(
                    'تشفير الرسائل التلقائي',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    'تشفير كل رسالة جديدة فور إرسالها تلقائياً',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  value: isAutoEncryptEnabled,
                  activeColor: isDark ? const Color(0xFF00FF66) : Colors.black,
                  onChanged: (bool value) {
                    autoEncryptNotifier.value = value;
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  bool _appLockEnabled = false;
  bool _ghostModeEnabled = true;
  bool _autoDeleteMessages = false;

  @override
  void initState() {
    super.initState();
    _appLockEnabled = appLockEnabledNotifier.value;
    _ghostModeEnabled = ghostModeNotifier.value;
    _autoDeleteMessages = autoDeleteMessagesNotifier.value;
    _loadPrivacySettings();
  }

  Future<void> _loadPrivacySettings() async {
    final settings = await loadPrivacySettings();
    if (!mounted) return;
    setState(() {
      if (settings['ghostMode'] is bool) {
        _ghostModeEnabled = settings['ghostMode'] as bool;
        ghostModeNotifier.value = _ghostModeEnabled;
      }
      if (settings['autoDeleteMessages'] is bool) {
        _autoDeleteMessages = settings['autoDeleteMessages'] as bool;
        autoDeleteMessagesNotifier.value = _autoDeleteMessages;
      }
      if (settings['messageSound'] is bool) {
        messageSoundNotifier.value = settings['messageSound'] as bool;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'الخصوصية والأمان',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(width: 8),
              Icon(
                Icons.lock,
                color: isDark ? const Color(0xFF00FF66) : Colors.black,
                size: 20,
              ),
            ],
          ),
          backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
          centerTitle: true,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            Text(
              'حماية التطبيق',
              style: TextStyle(
                color: isDark ? const Color(0xFF00FF66) : Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              secondary: Icon(
                Icons.fingerprint,
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF63F5C2)
                    : Colors.black,
              ),
              title: Text(
                'قفل التطبيق بالبصمة / كلمة السر',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              subtitle: Text(
                'طلب التحقق عند فتح Shadow Chat',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              value: _appLockEnabled,
              activeColor: isDark ? const Color(0xFF00FF66) : Colors.black,
              onChanged: (bool value) async {
                if (value) {
                  _setAppLockPassword();
                  return;
                }
                final currentHash = appLockPasswordNotifier.value;
                if (currentHash == null) return;
                await saveAppLockSettings(
                  enabled: false,
                  passwordHash: currentHash,
                );
                if (mounted) setState(() => _appLockEnabled = false);
              },
            ),
            ValueListenableBuilder<String?>(
              valueListenable: appLockPasswordNotifier,
              builder: (context, passwordHash, child) {
                if (passwordHash == null || !appLockEnabledNotifier.value)
                  return const SizedBox.shrink();
                return ListTile(
                  leading: Icon(
                    Icons.password_rounded,
                    color: isDark ? Colors.amberAccent : Colors.black,
                  ),
                  title: Text(
                    'كلمة سر قفل التطبيق',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    'كلمة السر ثابتة ومربوطة بإعدادات Firebase',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: Icon(
                    Icons.arrow_forward_ios,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 16,
                  ),
                  onTap: () => showChangeAppLockPasswordDialog(context),
                );
              },
            ),
            Divider(color: Theme.of(context).dividerColor, height: 30),
            Text(
              'خصوصية المحادثات',
              style: TextStyle(
                color: isDark ? const Color(0xFF00FF66) : Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 10),
            ValueListenableBuilder<bool>(
              valueListenable: ghostModeNotifier,
              builder: (context, isGhostModeEnabled, child) {
                return SwitchListTile(
                  secondary: Icon(
                    Icons.visibility_off,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.purpleAccent
                        : Colors.black,
                  ),
                  title: Text(
                    'الوضع الخفي (Ghost Mode)',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    'إخفاء مؤشر "جاري الكتابة" وحالة الاتصال',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  value: isGhostModeEnabled,
                  activeColor: isDark ? const Color(0xFF00FF66) : Colors.black,
                  onChanged: (bool value) {
                    ghostModeNotifier.value = value;
                    savePrivacySetting('ghostMode', value);
                    setState(() => _ghostModeEnabled = value);
                  },
                );
              },
            ),
            SwitchListTile(
              secondary: Icon(
                Icons.timer_off,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.orangeAccent
                    : Colors.black,
              ),
              title: Text(
                'الرسائل ذاتية التدمير',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              subtitle: Text(
                'حذف الرسائل تلقائياً بعد قراءتها',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              value: autoDeleteMessagesNotifier.value,
              activeColor: isDark ? const Color(0xFF00FF66) : Colors.black,
              onChanged: (bool value) {
                autoDeleteMessagesNotifier.value = value;
                savePrivacySetting('autoDeleteMessages', value);
                setState(() {
                  _autoDeleteMessages = value;
                });
              },
            ),
            Divider(color: Theme.of(context).dividerColor, height: 30),
            const Text(
              'إدارة البيانات',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(
                Icons.delete_forever,
                color: Colors.redAccent,
              ),
              title: Text(
                'حذف سجل المحادثات بالكامل',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              subtitle: Text(
                'مسح كافة الرسائل المخزنة نهائياً',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              onTap: () {
                _showDeleteConfirmationDialog(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _setAppLockPassword() {
    final TextEditingController passwordController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'تفعيل قفل التطبيق',
          style: TextStyle(color: Color(0xFF00FF66)),
        ),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'اكتب كلمة مرورك هنا',
            hintStyle: TextStyle(color: Colors.black),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () async {
              final String password = passwordController.text.trim();
              if (password.isEmpty) return;
              if (password.length < 4) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('كلمة السر يجب أن تكون 4 أحرف على الأقل'),
                  ),
                );
                return;
              }
              await saveAppLockSettings(
                enabled: true,
                passwordHash: await hashPassword(password),
              );
              if (!mounted) return;
              setState(() => _appLockEnabled = true);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text(
              'تفعيل',
              style: TextStyle(color: Color(0xFF00FF66)),
            ),
          ),
        ],
      ),
    ).then((_) => passwordController.dispose());
  }

  void _showDeleteConfirmationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Text(
              'تحذير أمني',
              style: TextStyle(color: Colors.redAccent),
            ),
            content: const Text(
              'هل أنت متأكد من حذف جميع سجلات الشات نهائياً؟ لا يمكن التراجع عن هذه الخطوة.',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                child: const Text(
                  'إلغاء',
                  style: TextStyle(color: Colors.cyanAccent),
                ),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
              TextButton(
                child: const Text(
                  'حذف الكل',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onPressed: () {
                  clearHistoryNotifier.value++;
                  Navigator.of(dialogContext).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم حذف سجل المحادثات من جهازك'),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(
            'الإشعارات والأصوات',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
          centerTitle: true,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: messageSoundNotifier,
              builder: (context, isSoundEnabled, child) => SwitchListTile(
                secondary: Icon(
                  Icons.music_note,
                  color: isDark ? Colors.pinkAccent : Colors.black,
                ),
                title: Text(
                  'صوت الرسائل الواردة',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                value: isSoundEnabled,
                activeColor: isDark ? const Color(0xFF38E8A5) : Colors.black,
                onChanged: (value) {
                  messageSoundNotifier.value = value;
                  unawaited(savePrivacySetting('messageSound', value));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = true;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text(
            'حول التطبيق',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.black87,
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? const Color(0xFF00FF66) : Colors.black,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00FF66).withOpacity(0.4),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.code,
                  size: 50,
                  color: const Color(0xFF00FF66),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.public, color: Colors.cyanAccent, size: 20),
                  SizedBox(width: 8),
                  Text(
                    '✨ 🌑 SHADOW CHAT BETA 🌑 ✨',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.public, color: Colors.cyanAccent, size: 20),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                    'BETA Version v1.0.0-beta.1',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Divider(color: Colors.white24, thickness: 1),
              ),
              const Text(
                'Lead Developer & Architect:',
                style: TextStyle(color: Color(0xFF00FF66), fontSize: 13),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Eng. Hatem',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.public, color: Colors.cyanAccent, size: 20),
                  SizedBox(width: 4),
                  Text('✨', style: TextStyle(fontSize: 18)),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF00FF66).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF00FF66).withOpacity(0.5),
                  ),
                ),
                child: const Text(
                  '« Secure Flutter Application »',
                  style: TextStyle(
                    color: Color(0xFF00FF66),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 25),
              const Text(
                'تطبيق محادثة مشفر وآمن، مصمم بأعلى معايير الأداء والخصوصية في عالم الظل.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 5. شاشة الشات العادية (بدون AppBar - عائمة في الماء)
// ==========================================
class Message {
  final String originalText;
  final String encryptedData; // هنحفظ هنا النص المتشفر بجد
  bool isEncrypted;
  final bool isMe;
  final String? mediaType;
  final XFile? mediaFile;
  final String? mediaUrl;

  Duration? voiceDuration;
  bool isPlayingVoice;
  Duration currentPlaybackPosition;

  Message({
    required this.originalText,
    required this.encryptedData,
    required this.isMe,
    this.isEncrypted = false,
    this.mediaType,
    this.mediaFile,
    this.mediaUrl,
    this.voiceDuration,
    this.isPlayingVoice = false,
    this.currentPlaybackPosition = Duration.zero,
  });

  String get displayText {
    if (!isEncrypted) return originalText;
    // الشكل السري الغامض (المربعات) مع الحفاظ على التشفير الحقيقي جواه
    return encryptedData.replaceAll(RegExp(r'[^\s]'), '█');
  }
}

class _MediaOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _MediaOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 34),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShellClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final Path path = Path()..moveTo(22, 0);
    path.quadraticBezierTo(size.width * 0.25, 8, size.width * 0.42, 0);
    path.quadraticBezierTo(size.width * 0.58, -8, size.width * 0.74, 0);
    path.quadraticBezierTo(size.width * 0.9, 8, size.width - 22, 0);
    path.quadraticBezierTo(size.width, 0, size.width, 22);
    path.lineTo(size.width, size.height - 22);
    path.quadraticBezierTo(
      size.width,
      size.height,
      size.width - 22,
      size.height,
    );
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height - 8,
      size.width * 0.58,
      size.height,
    );
    path.quadraticBezierTo(
      size.width * 0.42,
      size.height + 8,
      size.width * 0.26,
      size.height,
    );
    path.quadraticBezierTo(8, size.height - 8, 22, size.height);
    path.quadraticBezierTo(0, size.height, 0, size.height - 22);
    path.lineTo(0, 22);
    path.quadraticBezierTo(0, 0, 22, 0);
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _ShellBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = const Color(0xFF00FF66).withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    canvas.drawPath(_ShellClipper().getClip(size), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FloatingChatButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onPressed;

  const _FloatingChatButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        icon,
        color: color,
        shadows: [Shadow(color: color.withOpacity(0.8), blurRadius: 12)],
      ),
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }
}

class _SeaShellPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Path shell = Path()..moveTo(24, 6);
    shell.quadraticBezierTo(size.width * 0.18, 14, size.width * 0.3, 7);
    shell.quadraticBezierTo(size.width * 0.42, 0, size.width * 0.54, 7);
    shell.quadraticBezierTo(size.width * 0.66, 14, size.width * 0.78, 7);
    shell.quadraticBezierTo(size.width * 0.9, 0, size.width - 24, 6);
    shell.quadraticBezierTo(size.width, 8, size.width - 4, 22);
    shell.lineTo(size.width - 4, size.height - 20);
    shell.quadraticBezierTo(
      size.width - 8,
      size.height - 6,
      size.width - 24,
      size.height - 6,
    );
    shell.quadraticBezierTo(
      size.width * 0.78,
      size.height - 14,
      size.width * 0.66,
      size.height - 6,
    );
    shell.quadraticBezierTo(
      size.width * 0.54,
      size.height + 2,
      size.width * 0.42,
      size.height - 6,
    );
    shell.quadraticBezierTo(
      size.width * 0.3,
      size.height - 14,
      size.width * 0.18,
      size.height - 6,
    );
    shell.quadraticBezierTo(8, size.height - 6, 4, size.height - 20);
    shell.lineTo(4, 22);
    shell.quadraticBezierTo(0, 8, 24, 6);
    shell.close();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ShellMediaPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Rect bounds = Rect.fromLTWH(5, 4, size.width - 10, size.height - 8);
    final Paint fill = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF174B38), Color(0xFF0B2119)],
      ).createShader(bounds);
    final Paint outline = Paint()
      ..color = Colors.amberAccent.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final Path shell = Path()
      ..moveTo(7, size.height - 9)
      ..quadraticBezierTo(size.width * 0.16, 5, size.width * 0.5, 6)
      ..quadraticBezierTo(size.width * 0.84, 5, size.width - 7, size.height - 9)
      ..quadraticBezierTo(size.width * 0.5, size.height + 2, 7, size.height - 9)
      ..close();
    canvas.drawPath(shell, fill);
    canvas.drawPath(shell, outline);

    final Paint ridges = Paint()
      ..color = const Color(0x99FFDF75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (int index = 1; index < 5; index++) {
      final double x = size.width * index / 5;
      canvas.drawLine(Offset(7, size.height - 10), Offset(x, 8), ridges);
    }
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width * 0.58, size.height * 0.55),
        radius: 6,
      ),
      0.4,
      4.8,
      false,
      ridges,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ChatScreen extends StatefulWidget {
  final String chatName;
  final String? contactUid;

  const ChatScreen({
    super.key,
    this.chatName = '✨ 🌑 SHADOW CHAT 🌑 ✨',
    this.contactUid,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final List<Message> _messages = [
    Message(
      originalText: 'أهلاً بك في نظام shadow chat ✨ 🌑 ✨',
      encryptedData: 'أهلاً بك في نظام shadow chat ✨ 🌑 ✨',
      isMe: false,
    ),
  ];
  final TextEditingController _controller = TextEditingController();
  final AudioPlayer _chatAudioPlayer = AudioPlayer();
  final AudioPlayer _messageNotificationPlayer = AudioPlayer();
  final AudioRecorder _voiceRecorder = AudioRecorder();
  final ImagePicker _mediaPicker = ImagePicker();

  late AnimationController _whaleController;
  late Animation<double> _whaleAnimation;

  late AnimationController _launchController;
  late AnimationController _lockPulseController;
  late Animation<double> _lockPulseAnimation;
  bool _isLaunching = false;
  bool _isRecording = false;
  bool _isOtherTyping = false;
  bool _hasLoadedMessages = false;
  bool _chatLocked = false;
  String? _chatPassword;
  final TextEditingController _chatPasswordController = TextEditingController();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _messagesSubscription;

  Stream<DocumentSnapshot<Map<String, dynamic>>>? get _contactPresenceStream {
    if (!firebaseReady || widget.contactUid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(widget.contactUid)
        .snapshots();
  }

  String _presenceText(Map<String, dynamic>? data) {
    if (data?['isOnline'] == true) return 'متصل الآن';
    final value = data?['lastSeen'];
    if (value is! Timestamp) return 'آخر ظهور غير متاح';
    final date = value.toDate().toLocal();
    final localizations = MaterialLocalizations.of(context);
    final formattedDate = localizations.formatShortDate(date);
    final formattedTime = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(date),
    );
    return 'آخر ظهور $formattedDate - $formattedTime';
  }

  @override
  void initState() {
    super.initState();
    clearHistoryNotifier.addListener(_clearChatMessages);
    whaleMotionNotifier.addListener(_onWhaleMotionChanged);
    whaleSoundNotifier.addListener(_onWhaleSoundChanged);
    _chatPassword = chatPasswordsNotifier.value[widget.chatName];
    _chatLocked = _chatPassword != null;
    _loadChatPassword();
    _listenToChatMessages();
    if (!_chatLocked && whaleSoundNotifier.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_chatLocked) unawaited(_playWhaleSound());
      });
    }

    _whaleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
    if (whaleMotionNotifier.value) {
      _whaleController.repeat(reverse: true);
    }

    _whaleAnimation = Tween<double>(begin: -12.0, end: 12.0).animate(
      CurvedAnimation(parent: _whaleController, curve: Curves.easeInOut),
    );

    _launchController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    _lockPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _lockPulseAnimation = Tween<double>(begin: 0.94, end: 1.04).animate(
      CurvedAnimation(parent: _lockPulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _messagesSubscription?.cancel();
    clearHistoryNotifier.removeListener(_clearChatMessages);
    whaleMotionNotifier.removeListener(_onWhaleMotionChanged);
    whaleSoundNotifier.removeListener(_onWhaleSoundChanged);
    _chatAudioPlayer.dispose();
    _messageNotificationPlayer.dispose();
    _whaleController.dispose();
    _launchController.dispose();
    _lockPulseController.dispose();
    _voiceRecorder.dispose();
    _controller.dispose();
    _chatPasswordController.dispose();
    super.dispose();
  }

  void _clearChatMessages() {
    if (mounted) setState(_messages.clear);
    unawaited(deleteOwnChatMessages(_chatId));
  }

  void _onWhaleSoundChanged() {
    if (!whaleSoundNotifier.value) {
      unawaited(_stopWhaleSound());
    }
  }

  void _onWhaleMotionChanged() {
    if (whaleMotionNotifier.value) {
      _whaleController.repeat(reverse: true);
    } else {
      _whaleController.stop();
    }
  }

  Future<void> _stopWhaleSound() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) return;
    try {
      await _chatAudioPlayer.stop().timeout(const Duration(milliseconds: 300));
    } catch (_) {}
  }

  String get _chatId => chatDocumentId(widget.chatName);

  Future<void> _loadChatPassword() async {
    if (!firebaseReady) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('chatSecurity')
          .doc(_chatId)
          .get();
      final passwordHash = snapshot.data()?['passwordHash'];
      if (passwordHash is String && mounted) {
        setState(() {
          _chatPassword = passwordHash;
          _chatLocked = true;
        });
      }
    } catch (error) {
      debugPrint('Chat password load error: $error');
    }
  }

  void _listenToChatMessages() {
    if (!firebaseReady) return;
    _messagesSubscription = FirebaseFirestore.instance
        .collection('chats')
        .doc(_chatId)
        .collection('messages')
        .orderBy('createdAt')
        .limit(100)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;
            final currentUid = FirebaseAuth.instance.currentUser?.uid;
            final shouldNotify = _hasLoadedMessages && snapshot.docChanges.any(
              (change) =>
                  change.type == DocumentChangeType.added &&
              change.doc.data()?['uid'] != currentUid,
            );
            final messages = snapshot.docs.map((doc) {
              final data = doc.data();
              return Message(
                originalText: data['text'] ?? '',
                encryptedData: data['text'] ?? '',
                isMe: data['uid'] == currentUid,
                mediaType: data['mediaType'] as String?,
                mediaUrl: data['mediaUrl'] as String?,
              );
            }).toList();
            setState(() {
              _messages
                ..clear()
                ..addAll(messages);
            });
            _hasLoadedMessages = true;
            if (shouldNotify) unawaited(_playMessageNotification());
          },
          onError: (error) {
            debugPrint('Chat messages listener error: $error');
          },
        );
  }

  Future<void> _saveChatMessage(
    String text, {
    required bool isEncrypted,
  }) async {
    if (!firebaseReady) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_firebaseUnavailableMessage())));
      }
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(_chatId)
          .collection('messages')
          .add({
            'text': isEncrypted ? await _realEncrypt(text) : text,
            'sender': 'مستخدم',
            'uid': FirebaseAuth.instance.currentUser?.uid,
            if (widget.contactUid != null) 'recipientUid': widget.contactUid,
            'createdAt': FieldValue.serverTimestamp(),
            if (autoDeleteMessagesNotifier.value)
              'expiresAt': Timestamp.fromDate(
                DateTime.now().add(const Duration(seconds: 8)),
              ),
          });
    } catch (error) {
      debugPrint('Chat message save error: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر حفظ الرسالة في Firebase')),
        );
      }
    }
  }

  String _firebaseUnavailableMessage() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      return 'Firebase Firestore غير مدعوم على Linux desktop. شغّل التطبيق على Android أو Chrome.';
    }
    if (firebaseFailureMessage.contains('operation-not-allowed')) {
      return 'فعّل Anonymous Authentication من Firebase Console ثم أعد تشغيل التطبيق.';
    }
    return 'Firebase غير متصل: لم يتم حفظ الرسالة. فعّل Anonymous Authentication وتأكد من إعداد Firebase Web.';
  }

  Future<void> _unlockChat() async {
    if (await hashPassword(_chatPasswordController.text.trim()) ==
        _chatPassword) {
      setState(() {
        _chatLocked = false;
        _chatPasswordController.clear();
      });
      if (whaleSoundNotifier.value) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_chatLocked) unawaited(_playWhaleSound());
        });
      }
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('كلمة المرور غير صحيحة')));
    }
  }

  Future<void> _playWhaleSound() async {
    if (!whaleSoundNotifier.value ||
        (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux)) {
      return;
    }
    try {
      await _chatAudioPlayer.play(AssetSource('audio/whale_sound.mp3'));
    } catch (_) {
      // Audio is optional; a browser or device may deny playback.
    }
  }

  Future<void> _playMessageNotification() async {
    if (!messageSoundNotifier.value ||
        (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux)) {
      return;
    }
    try {
      await _messageNotificationPlayer.play(
        AssetSource('audio/whale_sound.mp3'),
        volume: 0.22,
      );
    } catch (_) {}
  }

  Future<void> _changeChatPassword() async {
    final oldController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تغيير كلمة سر الدردشة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: oldController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'كلمة السر القديمة'),
            ),
            TextField(
              controller: newController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'كلمة السر الجديدة'),
            ),
            TextField(
              controller: confirmController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'تأكيد كلمة السر الجديدة',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newPassword = newController.text.trim();
              final oldHash = await hashPassword(oldController.text.trim());
              if (oldHash != _chatPassword ||
                  newPassword.length < 4 ||
                  newPassword != confirmController.text.trim()) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تحقق من كلمة السر القديمة والجديدة'),
                  ),
                );
                return;
              }
              try {
                await saveChatPassword(widget.chatName, newPassword);
                final newHash = await hashPassword(newPassword);
                if (mounted) {
                  setState(() => _chatPassword = newHash);
                }
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (error) {
                debugPrint('Chat password update error: $error');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تعذر حفظ كلمة السر في Firebase'),
                    ),
                  );
                }
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    oldController.dispose();
    newController.dispose();
    confirmController.dispose();
  }

  Future<void> _disableChatPassword() async {
    final enteredHash = await hashPassword(_chatPasswordController.text.trim());
    if (enteredHash != _chatPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل كلمة السر الحالية أولًا')),
      );
      return;
    }
    if (mounted) {
      setState(() {
        _chatLocked = false;
        _chatPassword = null;
        _chatPasswordController.clear();
      });
    }
    unawaited(disableChatPassword(widget.chatName));
  }

  Future<void> _toggleVoiceRecording() async {
    if (_isRecording) {
      final String? path = await _voiceRecorder.stop();
      if (!mounted) return;
      setState(() => _isRecording = false);
      if (path != null) {
        final voiceFile = XFile(path);
        final mediaUrl = await _uploadMedia(voiceFile, 'audio');
        setState(() {
          final Message voiceMessage = Message(
            originalText: '🎙️ رسالة صوتية',
            encryptedData: path,
            isMe: true,
            mediaType: 'audio',
            mediaFile: voiceFile,
            mediaUrl: mediaUrl,
          );
          _messages.add(voiceMessage);
          _scheduleMessageDeletion(voiceMessage);
        });
        await _saveUploadedMediaMessage('🎙️ رسالة صوتية', 'audio', mediaUrl);
      }
      return;
    }

    if (!await _voiceRecorder.hasPermission()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اسمح للتطبيق باستخدام الميكروفون أولًا')),
      );
      return;
    }

    await _voiceRecorder.start(
      const RecordConfig(encoder: AudioEncoder.opus),
      path: 'shadow_voice_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    if (mounted) setState(() => _isRecording = true);
  }

  Future<void> _pickMedia({
    required bool video,
    ImageSource source = ImageSource.gallery,
  }) async {
    final XFile? file = video
        ? await _mediaPicker.pickVideo(source: source)
        : await _mediaPicker.pickImage(source: source);
    if (file == null || !mounted) return;
    final mediaType = video ? 'video' : 'image';
    final mediaUrl = await _uploadMedia(file, mediaType);

    setState(() {
      _messages.add(
        Message(
          originalText: video ? '🎬 فيديو' : '🖼️ صورة',
          encryptedData: file.name,
          isMe: true,
          mediaType: mediaType,
          mediaFile: file,
          mediaUrl: mediaUrl,
        ),
      );
      _scheduleMessageDeletion(_messages.last);
    });
    await _saveUploadedMediaMessage(
      video ? '🎬 فيديو' : '🖼️ صورة',
      mediaType,
      mediaUrl,
    );
  }

  Future<String?> _uploadMedia(XFile file, String mediaType) async {
    return null;
  }

  Future<void> _saveUploadedMediaMessage(
    String text,
    String mediaType,
    String? mediaUrl,
  ) async {
    if (!firebaseReady || mediaUrl == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(_chatId)
          .collection('messages')
          .add({
            'text': text,
            'uid': user.uid,
            'sender': 'مستخدم',
            'mediaType': mediaType,
            'mediaUrl': mediaUrl,
            'createdAt': FieldValue.serverTimestamp(),
          });
    } catch (error) {
      debugPrint('Media message save error: $error');
    }
  }

  void _showMediaPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF101714),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _MediaOption(
                  icon: Icons.photo_library_rounded,
                  label: 'صورة',
                  color: const Color(0xFF00FF66),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickMedia(video: false);
                  },
                ),
                _MediaOption(
                  icon: Icons.video_library_rounded,
                  label: 'فيديو',
                  color: Colors.amberAccent,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickMedia(video: true);
                  },
                ),
                _MediaOption(
                  icon: Icons.photo_camera_rounded,
                  label: 'كاميرا',
                  color: Colors.cyanAccent,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickMedia(video: false, source: ImageSource.camera);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<String> _realEncrypt(String text) async {
    if (text.isEmpty) return '';

    final AesGcm cipher = AesGcm.with256bits();
    final List<int> keySeed = utf8.encode('SHADOW_KEY_2026');
    final List<int> keyBytes = (await Sha256().hash(keySeed)).bytes;
    final SecretKey secretKey = SecretKey(keyBytes);
    final SecretBox encrypted = await cipher.encrypt(
      utf8.encode(text),
      secretKey: secretKey,
    );

    return base64Encode([
      ...encrypted.nonce,
      ...encrypted.cipherText,
      ...encrypted.mac.bytes,
    ]);
  }

  void _scheduleMessageDeletion(Message message) {
    if (!autoDeleteMessagesNotifier.value || !message.isMe) return;
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted && autoDeleteMessagesNotifier.value) {
        setState(() => _messages.remove(message));
      }
      unawaited(deleteExpiredOwnChatMessages(_chatId));
    });
  }

  void _showMessageActions(Message message) {
    if (!message.isMe) return;
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'إغلاق الخيارات',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 270,
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF101714),
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(20),
                ),
                border: Border.all(
                  color: const Color(0xFF00FF66).withOpacity(0.45),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x6600FF66),
                    blurRadius: 18,
                    offset: Offset(-4, 0),
                  ),
                ],
              ),
              child: ListTile(
                leading: const Icon(
                  Icons.delete_forever,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'حذف لدي فقط',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'إزالة الرسالة من جهازك',
                  style: TextStyle(color: Colors.white54),
                ),
                onTap: () {
                  setState(() => _messages.remove(message));
                  Navigator.pop(dialogContext);
                },
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final Animation<Offset> slideAnimation =
            Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );
        return SlideTransition(position: slideAnimation, child: child);
      },
    );
  }

  // دعم تحويل النصوص العربية والإنجليزية لنيون
  String _toNeonGreenText(String text) {
    const Map<String, String> normalToNeon = {
      // الحروف العربية
      'ا': '𝕒',
      'ب': '𝕓',
      'ت': '𝕥',
      'ث': '𝕥𝕙',
      'ج': '𝕛',
      'ح': '𝕙',
      'خ': '𝕩',
      'د': '𝕕',
      'ذ': 'ẕ',
      'ر': '𝕣',
      'ز': '𝕫',
      'س': '𝕤',
      'ش': '𝕤𝕙',
      'ص': '𝕤',
      'ض': 'ḏ', 'ط': '𝕥', 'ظ': 'ẓ', 'ع': '𝕔', 'غ': 'ǧ', 'ف': '𝕗', 'ق': 'զ',
      'ك': '𝕜',
      'ل': '𝕝',
      'م': '𝕞',
      'ن': '𝕟',
      'ه': '𝕙',
      'و': '𝕨',
      'ي': '𝟪',
      'أ': '𝕒',
      'إ': '𝕒',
      'آ': '𝕒',
      'ة': '𝕥',
      'ى': '𝟪',
      'ئ': '𝟪',
      'ؤ': '𝕨',
      'ء': '𝕩', 'لا': '𝕝𝕒',

      // الحروف الإنجليزية الصغيرة
      'a': '𝕒',
      'b': '𝕓',
      'c': '𝕔',
      'd': '𝕕',
      'e': '𝕖',
      'f': '𝕗',
      'g': '𝕘',
      'h': '𝕙',
      'i': '𝕚',
      'j': '𝕛',
      'k': '𝕜',
      'l': '𝕝',
      'm': '𝕞',
      'n': '𝕟',
      'o': '𝕠',
      'p': '𝕡',
      'q': 'զ',
      'r': '𝕣',
      's': '𝕤',
      't': '𝕥',
      'u': '𝕦',
      'v': '𝕧', 'w': '𝕨', 'x': '𝕩', 'y': '𝕪', 'z': '𝕫',

      // الحروف الإنجليزية الكبيرة
      'A': '𝔸',
      'B': '𝔹',
      'C': 'ℂ',
      'D': '𝔻',
      'E': '𝔼',
      'F': '𝔽',
      'G': '𝔾',
      'H': 'ℍ', 'I': '𝕀', 'J': '𝕁', 'K': '𝕂', 'L': '𝔏', 'M': '𝕄', 'N': 'ℕ',
      'O': '𝕆', 'P': 'ℙ', 'Q': 'ℚ', 'R': 'ℝ', 'S': '𝕊', 'T': '𝕋', 'U': '𝕌',
      'V': '𝕍', 'W': '𝕎', 'X': '𝕏', 'Y': '𝕐', 'Z': 'ℤ',

      // الأرقام
      '0': '𝟘',
      '1': '𝟙',
      '2': '𝟚',
      '3': '𝟛',
      '4': '𝟜',
      '5': '𝟝',
      '6': '𝟞',
      '7': '𝟟', '8': '𝟠', '9': '𝟡',
    };

    StringBuffer result = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      String char = text[i];
      final bool isArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(char);
      result.write(isArabic ? char : normalToNeon[char] ?? char);
    }
    return result.toString();
  }

  Future<void> _sendMessage() async {
    if (_controller.text.trim().isNotEmpty && !_isLaunching) {
      String userText = _controller.text.trim();
      _controller.clear();

      setState(() {
        _isLaunching = true;
      });

      // تشفير البيانات بجد في الخلفية لو الـ autoEncrypt مفعل
      bool isEncrypted = autoEncryptNotifier.value;
      final String processedText = isEncrypted
          ? await _realEncrypt(userText)
          : userText;

      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            final Message sentMessage = Message(
              originalText: userText,
              encryptedData: processedText,
              isMe: true,
              isEncrypted: isEncrypted,
            );
            _messages.add(sentMessage);
            _saveChatMessage(userText, isEncrypted: isEncrypted);
            _scheduleMessageDeletion(sentMessage);
            _isOtherTyping = true;
          });
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) setState(() => _isOtherTyping = false);
          });
        }
      });

      _launchController.forward(from: 0.0).then((_) {
        if (mounted) {
          setState(() {
            _isLaunching = false;
          });
        }
      });
    }
  }

  Widget _buildMessageContent(Message message) {
    if (message.mediaType == 'image' &&
        (message.mediaFile != null || message.mediaUrl != null)) {
      if (message.mediaUrl != null && message.mediaFile == null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            message.mediaUrl!,
            width: 220,
            height: 160,
            fit: BoxFit.cover,
          ),
        );
      }
      return FutureBuilder<Uint8List>(
        future: message.mediaFile!.readAsBytes(),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const SizedBox(
              width: 180,
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            );
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              snapshot.data!,
              width: 220,
              height: 160,
              fit: BoxFit.cover,
            ),
          );
        },
      );
    }
    if (message.mediaType == 'video') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.play_circle_fill_rounded,
            color: Colors.amberAccent,
            size: 34,
          ),
          const SizedBox(width: 8),
          Text(
            message.mediaFile?.name ?? 'فيديو',
            style: const TextStyle(color: Colors.white),
          ),
        ],
      );
    }
    if (message.mediaType == 'audio') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.graphic_eq_rounded,
            color: Color(0xFF00FF66),
            size: 28,
          ),
          const SizedBox(width: 8),
          const Text('رسالة صوتية', style: TextStyle(color: Colors.white)),
        ],
      );
    }
    return Text(
      _toNeonGreenText(message.displayText),
      style: TextStyle(
        color: const Color(0xFF00FF66),
        fontWeight: FontWeight.bold,
        shadows: [
          Shadow(
            color: const Color(0xFF00FF66).withOpacity(0.8),
            blurRadius: 6,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_chatLocked) return _buildLockedChat();
    const isDark = true;
    return Theme(
      data: ThemeData.dark(useMaterial3: true),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: isDark
              ? const Color(0xFF101716)
              : const Color(0xFFF4F7F6),
          body: Stack(
            children: [
              if (isDark)
                ValueListenableBuilder<bool>(
                  valueListenable: whaleMotionNotifier,
                  builder: (context, isMoving, child) {
                    return AnimatedBuilder(
                      animation: _whaleAnimation,
                      child: Image.asset(
                        'assets/images/whale.jpg',
                        fit: BoxFit.cover,
                        cacheWidth: 896,
                      ),
                      builder: (context, child) {
                        return Positioned.fill(
                          child: RepaintBoundary(
                            child: Transform.translate(
                              offset: isMoving
                                  ? Offset(0, _whaleAnimation.value)
                                  : Offset.zero,
                              child: Transform.scale(
                                scale: 1.08,
                                child: child,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              if (isDark)
                Positioned.fill(
                  child: Container(color: Colors.black.withOpacity(0.35)),
                ),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8.0,
                        horizontal: 12,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.arrow_back,
                              color: Color(0xFF00FF66),
                            ),
                            tooltip: 'رجوع',
                            onPressed: () => Navigator.pop(context),
                          ),
                          Expanded(
                            child:
                                StreamBuilder<
                                  DocumentSnapshot<Map<String, dynamic>>
                                >(
                                  stream: _contactPresenceStream,
                                  builder: (context, snapshot) {
                                    final data = snapshot.data?.data();
                                    return Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          widget.chatName,
                                          textAlign: TextAlign.center,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: isDark
                                                ? Colors.white
                                                : const Color(0xFF14211D),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            letterSpacing: 1.2,
                                          ),
                                        ),
                                        if (widget.contactUid != null)
                                          Text(
                                            _presenceText(data),
                                            style: TextStyle(
                                              color: data?['isOnline'] == true
                                                  ? const Color(0xFF00FF66)
                                                  : Colors.white60,
                                              fontSize: 11,
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                          ),
                          ValueListenableBuilder<bool>(
                            valueListenable: ghostModeNotifier,
                            builder: (context, isGhostModeEnabled, child) {
                              return Icon(
                                isGhostModeEnabled
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: isGhostModeEnabled
                                    ? Colors.purpleAccent
                                    : Colors.white30,
                                size: 18,
                              );
                            },
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          return GestureDetector(
                            onLongPress: () => _showMessageActions(msg),
                            child: Align(
                              alignment: msg.isMe
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.black.withOpacity(0.6)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: const Color(0xFF00FF66),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF00FF66,
                                      ).withOpacity(0.4),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: _buildMessageContent(msg),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Row(
                      children: [
                        _FloatingChatButton(
                          icon: Icons.send_rounded,
                          color: const Color(0xFF00FF66),
                          tooltip: 'إرسال',
                          onPressed: _sendMessage,
                        ),
                        _FloatingChatButton(
                          icon: _isRecording
                              ? Icons.stop_circle
                              : Icons.mic_none_rounded,
                          color: _isRecording
                              ? Colors.redAccent
                              : Colors.amberAccent,
                          tooltip: _isRecording
                              ? 'إيقاف التسجيل'
                              : 'تسجيل رسالة صوتية',
                          onPressed: _toggleVoiceRecording,
                        ),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              filled: false,
                              contentPadding: EdgeInsets.zero,
                              hintText:
                                  'اكتب رسالتك السرية... / Type a message...',
                              hintStyle: const TextStyle(color: Colors.white70),
                              border: InputBorder.none,
                            ),
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                        SizedBox(
                          width: 62,
                          height: 48,
                          child: IconButton(
                            icon: const Text(
                              '🌊',
                              style: TextStyle(fontSize: 25),
                            ),
                            tooltip: 'إرسال صورة أو فيديو',
                            onPressed: _showMediaPicker,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLockedChat() {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1220),
        appBar: AppBar(
          title: const Text(
            'دردشة محمية',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          backgroundColor: const Color(0xFF17243A),
          iconTheme: const IconThemeData(color: Color(0xFF7DE7FF)),
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF0B1220),
                      const Color(0xFF142B42),
                      const Color(0xFF081018),
                    ],
                  ),
                ),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 410),
                  padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF152235).withOpacity(0.98),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: const Color(0xFF7DE7FF).withOpacity(0.45),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4CC9F0).withOpacity(0.16),
                        blurRadius: 28,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ScaleTransition(
                        scale: _lockPulseAnimation,
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF00FF66).withOpacity(0.1),
                            border: Border.all(
                              color: const Color(0xFF00FF66),
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.lock_rounded,
                            color: Color(0xFF00FF66),
                            size: 48,
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'الدردشة مؤمنة',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 23,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'أدخل كلمة المرور للوصول إلى الرسائل',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white60, fontSize: 13),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _chatPasswordController,
                        obscureText: true,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          letterSpacing: 3,
                        ),
                        decoration: InputDecoration(
                          hintText: '••••••••',
                          hintStyle: const TextStyle(
                            color: Colors.white30,
                            letterSpacing: 3,
                          ),
                          filled: true,
                          fillColor: Colors.black.withOpacity(0.35),
                          prefixIcon: const Icon(
                            Icons.key_rounded,
                            color: Colors.amberAccent,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: Colors.white.withOpacity(0.12),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: Colors.white.withOpacity(0.12),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFF00FF66),
                              width: 1.5,
                            ),
                          ),
                        ),
                        onSubmitted: (_) => _unlockChat(),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _unlockChat,
                          icon: const Icon(Icons.lock_open_rounded),
                          label: const Text(
                            'فتح الدردشة',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00FF66),
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton.icon(
                            onPressed: _changeChatPassword,
                            icon: const Icon(Icons.password_rounded, size: 18),
                            label: const Text('تغيير كلمة السر'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.amberAccent,
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: _disableChatPassword,
                            icon: const Icon(Icons.lock_open_rounded, size: 18),
                            label: const Text('إيقاف كلمة السر'),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF61E7C0),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            color: Colors.amberAccent,
                            size: 15,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'حماية Shadow Chat',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------
// ضع هذا الجزء في نهاية ملف main.dart تماماً (بدون أي imports جديدة)
// ---------------------------------------------------------

ValueNotifier<XFile?> userProfileImageNotifier = ValueNotifier<XFile?>(null);

class AccountAndThemeScreen extends StatefulWidget {
  const AccountAndThemeScreen({super.key});

  @override
  State<AccountAndThemeScreen> createState() => _AccountAndThemeScreenState();
}

class _AccountAndThemeScreenState extends State<AccountAndThemeScreen> {
  String userName = "Shadow User";
  late TextEditingController nameController;
  final ImagePicker _picker = ImagePicker();
  String? _profileImageUrl;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: userName);
    _loadProfile();
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  Future<void> _pickProfileImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final bytes = await image.readAsBytes();
      userProfileImageBytesNotifier.value = bytes;
      if (mounted) setState(() => _profileImageUrl = null);
    }
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (!firebaseReady || user == null) return;
    try {
      final data =
          (await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .get())
              .data();
      if (mounted) {
        setState(() {
          userName = data?['displayName'] as String? ?? userName;
          _profileImageUrl = data?['photoUrl'] as String?;
          nameController.text = userName;
        });
      }
    } catch (error) {
      debugPrint('Profile load error: $error');
    }
  }

  void _showEditNameDialog() {
    nameController.text = userName;
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: ValueListenableBuilder<bool>(
          valueListenable: globalDarkModeNotifier,
          builder: (context, isDark, child) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: Color(0xFF00FF66), width: 1.5),
              ),
              title: Row(
                children: const [
                  Icon(Icons.edit_outlined, size: 20),
                  SizedBox(width: 8),
                  Text(
                    "تعديل اسم المستخدم",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              titleTextStyle: TextStyle(
                color: isDark ? const Color(0xFF00FF66) : Colors.black,
              ),
              content: TextField(
                controller: nameController,
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  hintText: "أدخل الاسم الجديد",
                  hintStyle: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF00FF66)),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF00FF66), width: 2),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "إلغاء",
                    style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00FF66),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    if (nameController.text.trim().isNotEmpty) {
                      setState(() {
                        userName = nameController.text.trim();
                      });
                      final user = FirebaseAuth.instance.currentUser;
                      if (firebaseReady && user != null) {
                        FirebaseFirestore.instance
                            .collection('users')
                            .doc(user.uid)
                            .set({
                              'displayName': userName,
                            }, SetOptions(merge: true));
                      }
                    }
                    Navigator.pop(context);
                  },
                  child: const Text(
                    "حفظ",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: globalDarkModeNotifier,
      builder: (context, isDark, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            appBar: AppBar(
              title: Row(
                children: [
                  Icon(
                    Icons.account_circle,
                    size: 20,
                    color: isDark ? const Color(0xFF38E8A5) : Colors.black,
                  ),
                  SizedBox(width: 10),
                  Text(
                    "الحساب والمظهر",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              backgroundColor: isDark
                  ? const Color(0xFF1A1A1A)
                  : const Color(0xFFE2E7EC),
              foregroundColor: isDark ? Colors.white : Colors.black,
              elevation: 0,
            ),
            body: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [const Color(0xFF1A1A1A), const Color(0xFF000000)]
                      : [const Color(0xFFF4F6F9), const Color(0xFFE4E8EE)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Center(
                    child: Stack(
                      children: [
                        Material(
                          color: Colors.transparent,
                          shape: const CircleBorder(),
                          clipBehavior: Clip.hardEdge,
                          child: InkWell(
                            onTap: _pickProfileImage,
                            child: ValueListenableBuilder<XFile?>(
                              valueListenable: userProfileImageNotifier,
                              builder: (context, profileImg, child) {
                                return ValueListenableBuilder<Uint8List?>(
                                  valueListenable:
                                      userProfileImageBytesNotifier,
                                  builder: (context, imageBytes, child) =>
                                      CircleAvatar(
                                        radius: 62,
                                        backgroundColor: isDark
                                            ? const Color(0xFF00FF66)
                                            : Colors.black,
                                        child: CircleAvatar(
                                          radius: 56,
                                          backgroundColor: isDark
                                              ? Colors.black
                                              : Colors.white,
                                          backgroundImage: imageBytes != null
                                              ? MemoryImage(imageBytes)
                                              : _profileImageUrl != null
                                              ? NetworkImage(_profileImageUrl!)
                                              : null,
                                          child:
                                              imageBytes == null &&
                                                  _profileImageUrl == null
                                              ? Icon(
                                                  Icons.person,
                                                  size: 65,
                                                  color: isDark
                                                      ? const Color(0xFF00FF66)
                                                      : Colors.black54,
                                                )
                                              : null,
                                        ),
                                      ),
                                );
                              },
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 2,
                          left: 2,
                          child: IgnorePointer(
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF00FF66)
                                    : Colors.black,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.camera_alt,
                                size: 16,
                                color: isDark ? Colors.black : Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),
                  Center(
                    child: Text(
                      userName,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Row(
                    children: [
                      Icon(
                        Icons.palette_outlined,
                        size: 18,
                        color: isDark ? const Color(0xFF38E8A5) : Colors.black,
                      ),
                      SizedBox(width: 8),
                      Text(
                        "إعدادات الحساب والمظهر",
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFF00FF66)
                              : Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Card(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                    child: Column(
                      children: [
                        ListTile(
                          leading: Icon(
                            Icons.edit_rounded,
                            color: isDark
                                ? const Color(0xFF00FF66)
                                : Colors.black,
                          ),
                          title: Text(
                            "تعديل اسم المستخدم",
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          trailing: const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 16,
                            color: Colors.grey,
                          ),
                          onTap: _showEditNameDialog,
                        ),
                        Divider(
                          color: isDark ? Colors.white24 : Colors.grey[300],
                          height: 1,
                          indent: 15,
                          endIndent: 15,
                        ),
                        SwitchListTile(
                          secondary: Icon(
                            isDark
                                ? Icons.dark_mode_rounded
                                : Icons.light_mode_rounded,
                            color: isDark
                                ? const Color(0xFF00FF66)
                                : Colors.black,
                          ),
                          title: Text(
                            "الوضع المظلم (Dark Mode)",
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            isDark
                                ? "التطبيق يعمل بالوضع المظلم حالياً"
                                : "التطبيق يعمل بالوضع الهادئ المريح",
                            style: TextStyle(
                              color: isDark ? Colors.white54 : Colors.black,
                              fontSize: 12,
                            ),
                          ),
                          value: isDark,
                          activeColor: isDark
                              ? const Color(0xFF00FF66)
                              : Colors.black,
                          onChanged: (bool value) {
                            saveDarkModeSetting(value);
                          },
                        ),
                      ],
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
