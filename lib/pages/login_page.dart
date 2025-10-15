import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'interview_selection_dialog.dart';
import 'conflict_self_page.dart'; // ✅ [추가] 새로운 페이지 import
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart'
    as kakao; // ✅ [추가] 카카오 SDK import
import 'package:cloud_functions/cloud_functions.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  Future<void> signInWithGoogle(BuildContext context) async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로그인에 실패했습니다. 다시 시도해주세요. 오류: $e')),
        );
      }
    }
  }

  Future<void> signInWithKakao(BuildContext context) async {
    try {
      // 1단계: 카카오 토큰 받기
      kakao.OAuthToken token =
          await kakao.UserApi.instance.loginWithKakaoAccount();

      // ✅ [추가] 2단계: 받은 토큰으로 Firebase 로그인
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-northeast3',
      ).httpsCallable('createFirebaseTokenWithKakao');

      final result = await callable.call({'accessToken': token.accessToken});
      final firebaseToken = result.data['firebaseToken'];

      if (firebaseToken != null && context.mounted) {
        // 3단계: 최종적으로 Firebase에 로그인
        await FirebaseAuth.instance.signInWithCustomToken(firebaseToken);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('카카오 로그인에 실패했습니다. 오류: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF318FFF),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Image.asset('assets/illustration.png', height: 150),
                const SizedBox(height: 30),
                const Text(
                  'AI 회고록',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'AI와 추억을 그림책으로 만들어요',
                  style: TextStyle(fontSize: 16, color: Colors.white70),
                ),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: () => signInWithGoogle(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 24,
                    ),
                    minimumSize: const Size(double.infinity, 56),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset('assets/google_logo.png', height: 24),
                      const SizedBox(width: 12),
                      const Text(
                        'Google 계정으로 시작하기',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => signInWithKakao(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFEE500), // 카카오 노란색
                    foregroundColor: Colors.black87,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    minimumSize: const Size(double.infinity, 56),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/kakao_logo.png',
                        height: 24,
                      ), // TODO: assets 폴더에 카카오 로고 이미지 추가
                      const SizedBox(width: 12),
                      const Text(
                        '카카오로 시작하기',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 60),

                // ✅ [추가] '갈등관리 자가진단표' 버튼 위의 설명글
                const Text(
                  '현재 당신의 회사는 안녕하십니까?',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12), // 설명글과 버튼 사이 간격
                // ✅ [수정] '갈등관리 자가진단표' 버튼 스타일 변경
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ConflictSelfPage(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600], // 녹색 배경
                    foregroundColor: Colors.white, // 흰색 글자
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    minimumSize: const Size(double.infinity, 56),
                  ),
                  child: const Text(
                    '갈등관리 자가진단표',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '기관/기업 참여자를 위한 서비스',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 12), // 여백 추가
                // 기존 '인터뷰 참여하기' 버튼
                ElevatedButton(
                  onPressed: () {
                    showInterviewSelectionDialog(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    minimumSize: const Size(double.infinity, 56),
                  ),
                  child: const Text(
                    '인터뷰 참여하기',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
