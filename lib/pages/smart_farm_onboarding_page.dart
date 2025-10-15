import 'package:flutter/material.dart';
import 'smart_farm_greeting_page.dart';

class SmartFarmOnboardingPage extends StatelessWidget {
  const SmartFarmOnboardingPage({super.key});

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
        title: const Text('사전 인터뷰 안내'),
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

            // ✅ [수정] 안내 문구를 새로운 내용으로 변경하고 가독성을 개선했습니다.
            Column(
              crossAxisAlignment: CrossAxisAlignment.start, // 왼쪽 정렬
              children: [
                const Text(
                  '• 반갑습니다. "재미나"는 청년 농업인 그리고 스마트팜 현장기술관련 종사자, 정부와 지자체 산하기관 전문가분들의 현장 경험과 의견 그리고 개선사항을 공유하는 플랫폼 서비스입니다.',
                  style: TextStyle(fontSize: 16, height: 1.6),
                ),
                const SizedBox(height: 24), // 문단 사이 간격
                Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.6,
                      color: Colors.black87,
                    ), // 기본 스타일
                    children: const <TextSpan>[
                      TextSpan(text: '• 진행순서는 '),
                      TextSpan(
                        text: '참여자 정보입력',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(text: ' ⇒ '),
                      TextSpan(
                        text: '인터뷰응답',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(text: ' ⇒ '),
                      TextSpan(
                        text: 'AI 출판물 생성',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(text: ' ⇒ '),
                      TextSpan(
                        text: '출력',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(text: ' ⇒ '),
                      TextSpan(
                        text: '마이데이터(저장)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(text: ' ⇒ '),
                      TextSpan(
                        text: '다시보기 및 다시 생성',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(text: '의 순으로 진행됩니다.'),
                    ],
                  ),
                ),
              ],
            ),

            const Spacer(),

            ElevatedButton(
              style: buttonStyle,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SmartFarmGreetingPage(),
                  ),
                );
              },
              child: const Text('다음으로'),
            ),
          ],
        ),
      ),
    );
  }
}
