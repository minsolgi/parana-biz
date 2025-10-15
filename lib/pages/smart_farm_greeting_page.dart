import 'package:flutter/material.dart';
import 'smart_farm_profile_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_page.dart';

class SmartFarmGreetingPage extends StatelessWidget {
  const SmartFarmGreetingPage({super.key});

  void _showLoginIncentiveDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false, // 사용자가 명확히 선택하도록 강제
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('🚀 로그인하고 특별 기능 사용하기'),
          content: const Text(
            '로그인하시면 인터뷰 종료 후, 대화 내용을 바탕으로 AI가 멋진 이미지를 생성해 드립니다!',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('그냥 시작할래요'),
              onPressed: () {
                // 1. 다이얼로그를 닫고,
                Navigator.of(dialogContext).pop();
                // 2. 기존 흐름대로 프로필 페이지로 이동
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SmartFarmProfilePage(),
                  ),
                );
              },
            ),
            ElevatedButton(
              child: const Text('로그인하기'),
              onPressed: () {
                // 1. 다이얼로그를 닫고,
                Navigator.of(dialogContext).pop();
                // 2. 로그인 페이지로 이동
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LoginPage(), // 실제 로그인 페이지로 연결
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final buttonStyle = ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF318FFF),
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 16),
      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('인사말'),
        // ✅ [추가] AppBar 스타일 통일
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            // ✅ [추가] 요청하신 인사말 텍스트
            Column(
              children: [
                Text(
                  '논산시 스마트팜 발전 포럼 회원 여러분\n안녕하세요?',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                const Text(
                  '디지털 인터뷰는 청년 농업인, 스마트팜 종사자분들의 목소리를 익명으로 직접 듣고 모아진 결과를 반영해 드리는 서비스입니다.',
                  style: TextStyle(fontSize: 16, height: 1.6),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  '솔직하게 응답 제출해주신 내용이 논산시 청년 스마트팜 정책과 지원방향에 반영될 수 있도록 최선을 다하겠습니다. 감사합니다.',
                  style: TextStyle(fontSize: 16, height: 1.6),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            const Spacer(),
            ElevatedButton(
              style: buttonStyle,
              onPressed: () {
                final user = FirebaseAuth.instance.currentUser;

                if (user != null) {
                  // 👈 1. 로그인 상태일 경우: 팝업 없이 바로 프로필 페이지로 이동
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      // ❗️ 중요: 프로필 페이지에 로그인 상태임을 알려주어야 합니다.
                      builder:
                          (context) =>
                              const SmartFarmProfilePage(isLoggedIn: true),
                    ),
                  );
                } else {
                  // 👈 2. 비로그인 상태일 경우: 기존처럼 로그인 안내 팝업 표시
                  _showLoginIncentiveDialog(context);
                }
              },
              child: const Text('다음으로'),
            ),
          ],
        ),
      ),
    );
  }
}
