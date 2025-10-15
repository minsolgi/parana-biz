import 'dart:async'; // StreamSubscription을 위해 import
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'pages/profile_setup_page.dart';
import 'firebase_options.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'config/kakao_config.dart';

// ✅ 1. 앱의 현재 화면에 접근하기 위한 GlobalKey 생성
final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  kakao.KakaoSdk.init(javaScriptAppKey: kakaoJavaScriptAppKey);
  runApp(const MyApp());
}

// ✅ 2. 앱을 StatefulWidget으로 변경하여 리스너를 관리
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // ✅ 3. Firestore 리스너와 이전 개수를 저장할 변수
  StreamSubscription? _bookSubscription;
  int? _previousBookCount;

  @override
  void initState() {
    super.initState();
    // 로그인 상태가 변경될 때마다 리스너를 설정하거나 해제
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _startListeningForNewBooks(user.uid);
      } else {
        _stopListeningForNewBooks();
      }
    });
  }

  @override
  void dispose() {
    _stopListeningForNewBooks();
    super.dispose();
  }

  // ✅ 4. 새 회고록을 감지하는 리스너 시작 함수
  void _startListeningForNewBooks(String uid) {
    // 혹시 모를 이전 리스너를 중지
    _stopListeningForNewBooks();

    final stream =
        FirebaseFirestore.instance
            .collection('books')
            .where('ownerUid', isEqualTo: uid)
            .snapshots();

    _bookSubscription = stream.listen((snapshot) {
      final currentBookCount = snapshot.docs.length;
      if (_previousBookCount != null &&
          currentBookCount > _previousBookCount!) {
        _showCreationCompleteDialog();
      }
      _previousBookCount = currentBookCount;
    });
  }

  // ✅ 5. 리스너 중지 함수
  void _stopListeningForNewBooks() {
    _bookSubscription?.cancel();
    _bookSubscription = null;
    _previousBookCount = null;
  }

  // ✅ 6. 화면 중앙에 Dialog를 띄우는 함수
  void _showCreationCompleteDialog() {
    final context = navigatorKey.currentContext;
    if (context != null && mounted) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.celebration_rounded, color: Colors.amber),
                SizedBox(width: 8),
                Text('🎉 회고록 도착!'),
              ],
            ),
            content: const Text(
              '새로운 회고록 생성이 완료되었습니다.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('확인'),
              ),
            ],
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Parana',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
        primarySwatch: Colors.blue,
        textTheme: GoogleFonts.notoSansKrTextTheme(Theme.of(context).textTheme),
      ),
      // 기존의 웹 화면 크기 조절 로직은 그대로 유지
      builder: (context, child) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 450.0),
            child: child!,
          ),
        );
      },
      // 기존의 로그인 및 프로필 확인 로직은 그대로 유지
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasData) {
            return _ProfileCheck(user: snapshot.data!);
          } else {
            return const LoginPage();
          }
        },
      ),
    );
  }
}

// _ProfileCheck 위젯은 기존 코드와 동일하게 유지
class _ProfileCheck extends StatelessWidget {
  final User user;
  const _ProfileCheck({required this.user});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future:
          FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return const Scaffold(body: Center(child: Text('오류가 발생했습니다.')));
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const ProfileSetupPage();
        } else {
          return const HomePage();
        }
      },
    );
  }
}
