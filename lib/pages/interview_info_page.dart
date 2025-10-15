import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'interview_page.dart';

class InterviewInfoPage extends StatefulWidget {
  const InterviewInfoPage({super.key});

  @override
  State<InterviewInfoPage> createState() => _InterviewInfoPageState();
}

class _InterviewInfoPageState extends State<InterviewInfoPage> {
  final Map<String, String> affiliations = {
    '고객지원팀': '(콜센터 종사자 포함)',
    '관망관리팀': '', // 부제가 없는 경우 빈 문자열
    '시설운영팀': '',
    '시스템운영팀': '(전문위원실, 자회사 포함)',
    '현장출장엔지니어': '개인사업자',
    '민원인/지역주민': '',
  };

  void _handleAffiliationSelection(String selectedAffiliation) async {
    final prefs = await SharedPreferences.getInstance();
    final savedJsonString = prefs.getString('saved_interview');

    // 1. 저장된 데이터가 있을 경우
    if (savedJsonString != null && savedJsonString.isNotEmpty) {
      final savedData = jsonDecode(savedJsonString);
      final String savedAffiliation = savedData['affiliation'];

      // 1-1. 다른 소속을 선택한 경우 -> 경고창 표시
      if (savedAffiliation != selectedAffiliation) {
        final bool? wantsToProceed = await _showChangeInterviewWarningDialog(
          savedAffiliation,
        );
        if (wantsToProceed == true) {
          await prefs.remove('saved_interview'); // 기존 데이터 삭제
          _navigateToInterviewPage(selectedAffiliation);
        }
      }
      // 1-2. 같은 소속을 선택한 경우 -> 바로 인터뷰 페이지로 이동 (거기서 '이어쓰기' 질문)
      else {
        _navigateToInterviewPage(selectedAffiliation);
      }
    }
    // 2. 저장된 데이터가 없을 경우 -> 바로 인터뷰 페이지로 이동
    else {
      _navigateToInterviewPage(selectedAffiliation);
    }
  }

  // [신규 추가] 다른 인터뷰 시작 시 경고를 표시하는 다이얼로그
  Future<bool?> _showChangeInterviewWarningDialog(String savedAffiliation) {
    return showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('다른 인터뷰 시작'),
            content: Text(
              "현재 '$savedAffiliation' 인터뷰를 작성하고 계십니다.\n\n새로운 인터뷰를 시작하면 작성 중인 내용은 사라집니다. 계속하시겠습니까?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false), // 취소
                child: const Text('취소'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true), // 계속 진행
                child: const Text('계속 진행', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
    );
  }

  // [신규 추가] 인터뷰 페이지로 이동하는 함수
  void _navigateToInterviewPage(String affiliation) {
    final userInfo = {'affiliation': affiliation};
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => InterviewPage(userInfo: userInfo),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('소속 선택'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(24.0),
        itemCount: affiliations.length,
        itemBuilder: (context, index) {
          final title = affiliations.keys.elementAt(index);
          final subtitle = affiliations.values.elementAt(index);
          return _buildAffiliationButton(title, subtitle);
        },
        separatorBuilder: (context, index) => const SizedBox(height: 16),
      ),
    );
  }

  // 버튼 UI를 생성하는 헬퍼 위젯
  Widget _buildAffiliationButton(String title, String subtitle) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        foregroundColor: Colors.black87,
        backgroundColor: Colors.white,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade300),
        ),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      ),
      onPressed: () => _handleAffiliationSelection(title),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    );
  }
}
