import 'package:flutter/material.dart';
import 'smart_farm_onboarding_page.dart';

Future<void> showInterviewSelectionDialog(BuildContext context) async {
  await showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('인터뷰 참여'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: const Text('진행할 인터뷰를 선택해주세요.'),
        actionsAlignment: MainAxisAlignment.center,
        // ✅ [수정] 버튼 목록을 Column으로 변경
        contentPadding: const EdgeInsets.only(top: 20, left: 24, right: 24),
        actionsPadding: const EdgeInsets.only(bottom: 24, top: 16),
        actions: <Widget>[
          Column(
            children: [
              // 1. K-Water 버튼 (비활성화)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(220, 50),
                  // ✅ 불투명하고 클릭 안 되도록 스타일 수정
                  backgroundColor: Colors.grey.shade300,
                  foregroundColor: Colors.grey.shade600,
                ),
                onPressed: null, // onPressed를 null로 설정하여 비활성화
                child: const Text('K-Water 논산수도센터'),
              ),
              const SizedBox(height: 12),
              // 2. 스마트팜 인터뷰 버튼 (신규)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(220, 50),
                  backgroundColor: Colors.green, // 새로운 테마 색상
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      // ✅ 새로운 온보딩 페이지로 이동
                      builder: (context) => const SmartFarmOnboardingPage(),
                    ),
                  );
                },
                child: const Text('논산시 청년 스마트팜 발전 포럼'),
              ),
            ],
          ),
        ],
      );
    },
  );
}
