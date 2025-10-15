import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert'; // JSON 인코딩/디코딩을 위해 필요

// --- 데이터 모델 ---
class InterviewQuestion {
  final String id;
  final String text;
  final String? nextQuestionId;
  InterviewQuestion({
    required this.id,
    required this.text,
    this.nextQuestionId,
  });
}

enum InterviewMessageType { user, bot, announcement }

class InterviewMessage {
  final String text;
  final InterviewMessageType type;
  InterviewMessage({required this.text, required this.type});
}

// --- 위젯 ---
class InterviewPage extends StatefulWidget {
  final Map<String, dynamic> userInfo;
  const InterviewPage({super.key, required this.userInfo});

  @override
  State<InterviewPage> createState() => _InterviewPageState();
}

class _InterviewPageState extends State<InterviewPage> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final SpeechToText _speechToText = SpeechToText();
  bool _isBotThinking = false;
  bool _speechEnabled = false;
  bool _isListening = false;
  bool _isSubmitting = false;
  String _recognizedWords = '';
  Timer? _speechTimer;

  late final Map<String, InterviewQuestion> _questionnaire;
  late InterviewQuestion _currentQuestion;
  final List<InterviewMessage> _messages = [];

  final Map<String, String> _answers = {};

  @override
  void initState() {
    super.initState();
    _loadOrStartNewInterview();
    _initSpeech();
  }

  Future<void> _loadOrStartNewInterview() async {
    final prefs = await SharedPreferences.getInstance();
    final savedJsonString = prefs.getString('saved_interview');

    if (savedJsonString != null && savedJsonString.isNotEmpty) {
      final savedData = jsonDecode(savedJsonString);
      final String savedAffiliation = savedData['affiliation'];
      final Map<String, dynamic> savedAnswersRaw = savedData['answers'];
      final savedAnswers = savedAnswersRaw.cast<String, String>();

      // ✅ [수정] 현재 선택한 소속과 저장된 소속이 일치하는지 확인합니다.
      if (savedAffiliation == widget.userInfo['affiliation']) {
        // 소속이 일치하면 '이어 쓰기' 여부를 물어봅니다.
        final wantToResume = await _showResumeDialog();
        if (wantToResume) {
          _restoreInterviewState(savedAnswers);
        } else {
          await _clearSavedData();
          _initializeQuestions();
        }
      } else {
        // 소속이 다르면, 이전 데이터는 무시하고 새 인터뷰를 시작합니다.
        await _clearSavedData();
        _initializeQuestions();
      }
    } else {
      // 저장된 내용이 없으면 새로 시작합니다.
      _initializeQuestions();
    }
  }

  // ✅ [신규 추가] '이어쓰기/새로쓰기' 선택 다이얼로그
  Future<bool> _showResumeDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: const Text('이어서 진행하시겠습니까?'),
            content: const Text('이전에 작성하던 인터뷰 내용이 있습니다.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false), // 새로쓰기
                child: const Text('새로 쓰기'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true), // 이어쓰기
                child: const Text('이어 쓰기'),
              ),
            ],
          ),
    );
    return result ?? false;
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _speechToText.stop();
    _speechTimer?.cancel();
    super.dispose();
  }

  // lib/interview_page.dart 의 _InterviewPageState 내부

  // lib/interview_page.dart 의 _InterviewPageState 내부

  Map<String, InterviewQuestion> _getQuestionnaireForAffiliation(
    String affiliation,
  ) {
    switch (affiliation) {
      case '고객지원팀':
        return {
          'team1_q1': InterviewQuestion(
            id: 'team1_q1',
            text:
                '1. 고객 민원 접수와 응대, 그리고 현장 업무(검침, 병물 공급 등)에서 가장 어려운 점은 무엇인가요? 여러 측면에서 다양한 내용을 말씀해 주세요.',
            nextQuestionId: 'team1_q2',
          ),
          'team1_q2': InterviewQuestion(
            id: 'team1_q2',
            text:
                '2. 민원인이 응대 절차를 무시하거나 현장에서 막무가내 요구를 하는 경우가 많을 텐데요. 그 원인이 어디에 있다고 보시나요? 기억나는 사례와 함께 작성해 주세요.',
            nextQuestionId: 'team1_q3',
          ),
          'team1_q3': InterviewQuestion(
            id: 'team1_q3',
            text:
                '3. 민원 응대나 현장 방문에 앞서 갈등이 고조되지 않도록 사전에 어떤 준비를 하고 계시나요? 자유롭게 작성해 주세요.',
            nextQuestionId: 'team1_q4',
          ),
          // ✅ 4번 질문 수정
          'team1_q4': InterviewQuestion(
            id: 'team1_q4',
            text:
                '4. 전화, 방문, 현장업무 등 다양한 매체를 통한 민원응대만으로는 해결할 수 없었던 케이스가 있었나요? 기억나는 대로 상세하게 말씀해 주세요.',
            nextQuestionId: 'team1_q5',
          ),
          // ✅ 5번 공통 질문 수정
          'team1_q5': InterviewQuestion(
            id: 'team1_q5',
            text:
                '5. 민원이나 갈등 상황에서 동료, 상급자, 또는 타 부서의 도움이 필요했던 적이 있으셨나요? 그때 어떤 절차와 과정을 통해 문제를 해결하셨는지, 구체적으로 설명해 주세요. 만약 아쉬웠던 점이 있었다면 그 이유도 함께 말씀해 주세요.',
            nextQuestionId: 'team1_q6',
          ),
          'team1_q6': InterviewQuestion(
            id: 'team1_q6',
            text:
                '6. 고객 민원 접수부터 요금 고지, 검침, 병물 공급 등 현장 업무 진행 과정에서 개선이 필요하다고 여겨지는 절차나 시스템상의 애로사항이 있다면 무엇이 떠오르시나요? 자유롭게 말씀해 주세요.',
            nextQuestionId: 'team1_q7',
          ),
          'team1_q7': InterviewQuestion(
            id: 'team1_q7',
            text:
                '7. 고객 응대 또는 현장 업무 중 갈등 상황에서 자신의 감정을 관리하는 노하우나 팁이 있나요? 괜찮으시다면, 나눠주시면 좋겠습니다.',
            nextQuestionId: 'team1_q8',
          ),
          'team1_q8': InterviewQuestion(
            id: 'team1_q8',
            text:
                '8. 고객 응대 및 현장 업무에 도움이 되는 교육 또는 자원은 어떤 것들이 있을까요? 자유롭게 작성해 주세요.',
            nextQuestionId: 'team1_q9',
          ),
          'team1_q9': InterviewQuestion(
            id: 'team1_q9',
            text: '9. 가장 기억에 남는 고객 응대 사례와 그 해결 과정을 소개해 주세요. 자유롭게 작성하시면 됩니다.',
            nextQuestionId: 'team1_q10',
          ),
          // ✅ 10번 공통 질문 수정
          'team1_q10': InterviewQuestion(
            id: 'team1_q10',
            text:
                '10. 고객의 문제 상황(요구)과 심리적 상태(욕구)를 정확히 파악하여, 사안은 신속하게 조치하고 관계 갈등은 원만히 조율했던 경험이 있으신가요? 그 과정에서 느낀 보람이나 성취감이 있었다면 자유롭게 들려주세요.',
            nextQuestionId: 'team1_q11',
          ),
          'team1_q11': InterviewQuestion(
            id: 'team1_q11',
            text:
                '11. 지금까지 10개의 인터뷰 문항에 응답하시면서 어떤 마음이 드셨는지요? 알게 된 사실과 기분, 감정 등 떠오르는 대로 자유롭게 말씀해 주세요.',
            nextQuestionId: 'end',
          ),
        };
      case '관망관리팀':
        return {
          'team2_q1': InterviewQuestion(
            id: 'team2_q1',
            text:
                '1. 수도관로 관리 및 누수 복구 현장에서 겪는 가장 큰 어려움은 무엇인가요? 기술적인 측면, 민원 응대 측면, 그리고 작업 환경적인 측면 등 다양한 내용을 말씀해 주세요.',
            nextQuestionId: 'team2_q2',
          ),
          'team2_q2': InterviewQuestion(
            id: 'team2_q2',
            text:
                '2. 누수 복구 현장 등에서 민원인이 응대 절차를 무시하고 막무가내 요구를 하는 경우가 많을 텐데요. 그 원인이 어디에 있다고 보시나요? 기억나는 사례와 함께 작성해 주세요.',
            nextQuestionId: 'team2_q3',
          ),
          'team2_q3': InterviewQuestion(
            id: 'team2_q3',
            text:
                '3. 현장 출동 및 작업에 앞서 민원인과의 갈등이 고조되지 않도록 사전에 어떤 준비를 하고 계시나요? 자유롭게 작성해 주세요.',
            nextQuestionId: 'team2_q4',
          ),
          'team2_q4': InterviewQuestion(
            id: 'team2_q4',
            text:
                '4. 현장 업무 중 기술적으로나 민원 응대 측면에서 귀하가 해결할 수 없었던 케이스가 있었나요? 기억나는 대로 상세하게 말씀해 주세요.',
            nextQuestionId: 'team2_q5',
          ),
          // ✅ 5번 공통 질문 수정
          'team2_q5': InterviewQuestion(
            id: 'team2_q5',
            text:
                '5. 민원이나 갈등 상황에서 동료, 상급자, 또는 타 부서의 도움이 필요했던 적이 있으셨나요? 그때 어떤 절차와 과정을 통해 문제를 해결하셨는지, 구체적으로 설명해 주세요. 만약 아쉬웠던 점이 있었다면 그 이유도 함께 말씀해 주세요.',
            nextQuestionId: 'team2_q6',
          ),
          'team2_q6': InterviewQuestion(
            id: 'team2_q6',
            text:
                '6. 수도관로 관리 및 누수 복구 작업 과정에서 개선이 필요하다고 여겨지는 절차나 시스템상의 애로사항이 있다면 무엇이 떠오르시나요? 자유롭게 말씀해 주세요.',
            nextQuestionId: 'team2_q7',
          ),
          'team2_q7': InterviewQuestion(
            id: 'team2_q7',
            text:
                '7. 현장 작업 중 민원인 응대 또는 갈등 상황에서 자신의 감정을 관리하는 노하우나 팁이 있나요? 괜찮으시다면, 나눠주시면 좋겠습니다.',
            nextQuestionId: 'team2_q8',
          ),
          'team2_q8': InterviewQuestion(
            id: 'team2_q8',
            text:
                '8. 관망 관리 및 누수 복구 업무에 도움이 되는 교육 또는 자원은 어떤 것들이 있을까요? 자유롭게 작성해 주세요.',
            nextQuestionId: 'team2_q9',
          ),
          'team2_q9': InterviewQuestion(
            id: 'team2_q9',
            text:
                '9. 가장 기억에 남는 누수 복구 또는 관로 관리 현장 사례와 그 해결 과정을 소개해 주세요. 자유롭게 작성하시면 됩니다.',
            nextQuestionId: 'team2_q10',
          ),
          // ✅ 10번 공통 질문 수정
          'team2_q10': InterviewQuestion(
            id: 'team2_q10',
            text:
                '10. 고객의 문제 상황(요구)과 심리적 상태(욕구)를 정확히 파악하여, 사안은 신속하게 조치하고 관계 갈등은 원만히 조율했던 경험이 있으신가요? 그 과정에서 느낀 보람이나 성취감이 있었다면 자유롭게 들려주세요.',
            nextQuestionId: 'team2_q11',
          ),
          'team2_q11': InterviewQuestion(
            id: 'team2_q11',
            text:
                '11. 지금까지 10개의 인터뷰 문항에 응답하시면서 어떤 마음이 드셨는지요? 알게 된 사실과 기분, 감정 등 떠오르는 대로 자유롭게 말씀해 주세요.',
            nextQuestionId: 'end',
          ),
        };
      case '시설운영팀':
        return {
          'team3_q1': InterviewQuestion(
            id: 'team3_q1',
            text:
                '1. 배수지, 가압장 등 수도 시설 관리 업무에서 가장 어려운 점은 무엇인가요? 시설 유지보수, 안전 관리, 그리고 예상치 못한 문제 발생 시 대응 등 다양한 내용을 말씀해 주세요.',
            nextQuestionId: 'team3_q2',
          ),
          'team3_q2': InterviewQuestion(
            id: 'team3_q2',
            text:
                '2. 시설 관련 민원인이 응대 절차를 무시하고 막무가내 요구를 하는 경우가 많을 텐데요. 그 원인이 어디에 있다고 보시나요? 기억나는 사례와 함께 작성해 주세요.',
            nextQuestionId: 'team3_q3',
          ),
          'team3_q3': InterviewQuestion(
            id: 'team3_q3',
            text:
                '3. 시설 관리 업무 중 주민과의 갈등이 발생하지 않도록 사전에 어떤 준비를 하고 계시나요? 자유롭게 작성해 주세요.',
            nextQuestionId: 'team3_q4',
          ),
          'team3_q4': InterviewQuestion(
            id: 'team3_q4',
            text:
                '4. 시설 관리 업무 중 귀하가 해결할 수 없었던 기술적인 문제나 민원 케이스가 있었나요? 기억나는 대로 상세하게 말씀해 주세요.',
            nextQuestionId: 'team3_q5',
          ),
          // ✅ 5번 공통 질문 수정
          'team3_q5': InterviewQuestion(
            id: 'team3_q5',
            text:
                '5. 민원이나 갈등 상황에서 동료, 상급자, 또는 타 부서의 도움이 필요했던 적이 있으셨나요? 그때 어떤 절차와 과정을 통해 문제를 해결하셨는지, 구체적으로 설명해 주세요. 만약 아쉬웠던 점이 있었다면 그 이유도 함께 말씀해 주세요.',
            nextQuestionId: 'team3_q6',
          ),
          'team3_q6': InterviewQuestion(
            id: 'team3_q6',
            text:
                '6. 수도 시설 관리 및 유지보수 과정에서 개선이 필요하다고 여겨지는 절차나 시스템상의 애로사항이 있다면 무엇이 떠오르시나요? 자유롭게 말씀해 주세요.',
            nextQuestionId: 'team3_q7',
          ),
          'team3_q7': InterviewQuestion(
            id: 'team3_q7',
            text:
                '7. 시설 관리 업무 중 민원인 응대 또는 갈등 상황에서 자신의 감정을 관리하는 노하우나 팁이 있나요? 괜찮으시다면, 나눠주시면 좋겠습니다.',
            nextQuestionId: 'team3_q8',
          ),
          'team3_q8': InterviewQuestion(
            id: 'team3_q8',
            text: '8. 수도 시설 관리 업무에 도움이 되는 교육 또는 자원은 어떤 것들이 있을까요? 자유롭게 작성해 주세요.',
            nextQuestionId: 'team3_q9',
          ),
          'team3_q9': InterviewQuestion(
            id: 'team3_q9',
            text:
                '9. 가장 기억에 남는 시설 관련 민원 응대 또는 기술적 문제 해결 사례와 그 해결 과정을 소개해 주세요. 자유롭게 작성하시면 됩니다.',
            nextQuestionId: 'team3_q10',
          ),
          // ✅ 10번 공통 질문 수정
          'team3_q10': InterviewQuestion(
            id: 'team3_q10',
            text:
                '10. 고객의 문제 상황(요구)과 심리적 상태(욕구)를 정확히 파악하여, 사안은 신속하게 조치하고 관계 갈등은 원만히 조율했던 경험이 있으신가요? 그 과정에서 느낀 보람이나 성취감이 있었다면 자유롭게 들려주세요.',
            nextQuestionId: 'team3_q11',
          ),
          'team3_q11': InterviewQuestion(
            id: 'team3_q11',
            text:
                '11. 지금까지 10개의 인터뷰 문항에 응답하시면서 어떤 마음이 드셨는지요? 알게 된 사실과 기분, 감정 등 떠오르는 대로 자유롭게 말씀해 주세요.',
            nextQuestionId: 'end',
          ),
        };
      case '시스템운영팀':
        return {
          'team4_q1': InterviewQuestion(
            id: 'team4_q1',
            text:
                '1. 통신 설비 및 서버 관리 업무에서 가장 어려운 점은 무엇인가요? 기술적인 문제 해결, 시스템 장애 대응, 그리고 타 부서와의 협업 등 다양한 내용을 말씀해 주세요.',
            nextQuestionId: 'team4_q2',
          ),
          'team4_q2': InterviewQuestion(
            id: 'team4_q2',
            text:
                '2. 시스템 관련 민원인이 응대 절차를 무시하고 막무가내 요구를 하는 경우가 많을 텐데요. 그 원인이 어디에 있다고 보시나요? 기억나는 사례와 함께 작성해 주세요.',
            nextQuestionId: 'team4_q3',
          ),
          'team4_q3': InterviewQuestion(
            id: 'team4_q3',
            text:
                '3. 시스템 관련 문제 발생 시 민원인과의 갈등이 고조되지 않도록 사전에 어떤 준비를 하고 계시나요? 자유롭게 작성해 주세요.',
            nextQuestionId: 'team4_q4',
          ),
          'team4_q4': InterviewQuestion(
            id: 'team4_q4',
            text:
                '4. 통신 설비 및 서버 관리 업무 중 귀하가 해결할 수 없었던 기술적인 문제나 민원 케이스가 있었나요? 기억나는 대로 상세하게 말씀해 주세요.',
            nextQuestionId: 'team4_q5',
          ),
          // ✅ 5번 공통 질문 수정
          'team4_q5': InterviewQuestion(
            id: 'team4_q5',
            text:
                '5. 민원이나 갈등 상황에서 동료, 상급자, 또는 타 부서의 도움이 필요했던 적이 있으셨나요? 그때 어떤 절차와 과정을 통해 문제를 해결하셨는지, 구체적으로 설명해 주세요. 만약 아쉬웠던 점이 있었다면 그 이유도 함께 말씀해 주세요.',
            nextQuestionId: 'team4_q6',
          ),
          'team4_q6': InterviewQuestion(
            id: 'team4_q6',
            text:
                '6. 통신 설비 및 서버 관리 과정에서 개선이 필요하다고 여겨지는 절차나 시스템상의 애로사항이 있다면 무엇이 떠오르시나요? 자유롭게 말씀해 주세요.',
            nextQuestionId: 'team4_q7',
          ),
          'team4_q7': InterviewQuestion(
            id: 'team4_q7',
            text:
                '7. 시스템 관련 민원 응대 또는 갈등 상황에서 자신의 감정을 관리하는 노하우나 팁이 있나요? 괜찮으시다면, 나눠주시면 좋겠습니다.',
            nextQuestionId: 'team4_q8',
          ),
          'team4_q8': InterviewQuestion(
            id: 'team4_q8',
            text:
                '8. 통신 설비 및 서버 관리 업무에 도움이 되는 교육 또는 자원은 어떤 것들이 있을까요? 자유롭게 작성해 주세요.',
            nextQuestionId: 'team4_q9',
          ),
          'team4_q9': InterviewQuestion(
            id: 'team4_q9',
            text:
                '9. 가장 기억에 남는 시스템 관련 민원 응대 또는 기술적 문제 해결 사례와 그 해결 과정을 소개해 주세요. 자유롭게 작성하시면 됩니다.',
            nextQuestionId: 'team4_q10',
          ),
          // ✅ 10번 공통 질문 수정
          'team4_q10': InterviewQuestion(
            id: 'team4_q10',
            text:
                '10. 고객의 문제 상황(요구)과 심리적 상태(욕구)를 정확히 파악하여, 사안은 신속하게 조치하고 관계 갈등은 원만히 조율했던 경험이 있으신가요? 그 과정에서 느낀 보람이나 성취감이 있었다면 자유롭게 들려주세요.',
            nextQuestionId: 'team4_q11',
          ),
          'team4_q11': InterviewQuestion(
            id: 'team4_q11',
            text:
                '11. 지금까지 10개의 인터뷰 문항에 응답하시면서 어떤 마음이 드셨는지요? 알게 된 사실과 기분, 감정 등 떠오르는 대로 자유롭게 말씀해 주세요.',
            nextQuestionId: 'end',
          ),
        };
      case '현장출장엔지니어':
        return {
          'team5_q1': InterviewQuestion(
            id: 'team5_q1',
            text:
                '1. 민원 현장을 방문하면 해결해야 하는 문제 상황과 불편한 심정의 민원인을 동시에 맞닥뜨리는 어려운 상황이 많으셨을 텐데요. 문제와 사람 중 어느 쪽에 좀 더 비중을 두고 대응하시나요? 예를 들어 설명해 주세요.',
            nextQuestionId: 'team5_q2',
          ),
          'team5_q2': InterviewQuestion(
            id: 'team5_q2',
            text: '2. 민원인과의 대화에서 특히 신경 쓰이는 점은 무엇인가요? 여러 가지 측면에서 다양하게 말씀해 주세요.',
            nextQuestionId: 'team5_q3',
          ),
          'team5_q3': InterviewQuestion(
            id: 'team5_q3',
            text: '3. 현장 업무 중 갈등이 발생하지 않도록 사전에 어떤 준비를 하고 계시나요? 자유롭게 작성해 주세요.',
            nextQuestionId: 'team5_q4',
          ),
          'team5_q4': InterviewQuestion(
            id: 'team5_q4',
            text:
                '4. 민원 현장 출장에서 귀하가 해결할 수 없었던 민원 케이스가 있었나요? 기억나는 대로 상세하게 말씀해 주세요.',
            nextQuestionId: 'team5_q5',
          ),
          // ✅ 5번 공통 질문 수정
          'team5_q5': InterviewQuestion(
            id: 'team5_q5',
            text:
                '5. 민원이나 갈등 상황에서 동료, 상급자, 또는 타 부서의 도움이 필요했던 적이 있으셨나요? 그때 어떤 절차와 과정을 통해 문제를 해결하셨는지, 구체적으로 설명해 주세요. 만약 아쉬웠던 점이 있었다면 그 이유도 함께 말씀해 주세요.',
            nextQuestionId: 'team5_q6',
          ),
          'team5_q6': InterviewQuestion(
            id: 'team5_q6',
            text:
                '6. 초기 고객 민원 접수에서부터 현장 방문 해결까지 진행하는 과정에서 개선이 필요하다고 여겨지는 절차나 시스템상의 애로사항이 있다면 무엇이 떠오르시나요? 자유롭게 말씀해 주세요.',
            nextQuestionId: 'team5_q7',
          ),
          'team5_q7': InterviewQuestion(
            id: 'team5_q7',
            text:
                '7. 현장 민원인 응대 과정 또는 갈등 상황에서 자신의 감정을 관리하는 노하우나 팁이 있나요? 괜찮으시다면, 나눠주시면 좋겠습니다.',
            nextQuestionId: 'team5_q8',
          ),
          'team5_q8': InterviewQuestion(
            id: 'team5_q8',
            text: '8. 민원 현장 대응에 도움이 되는 교육 또는 자원은 어떤 것들이 있을까요? 자유롭게 작성해 주세요.',
            nextQuestionId: 'team5_q9',
          ),
          'team5_q9': InterviewQuestion(
            id: 'team5_q9',
            text: '9. 가장 기억에 남는 민원 현장 사례의 해결 과정을 소개해 주시겠습니까? 자유롭게 작성하시면 됩니다.',
            nextQuestionId: 'team5_q10',
          ),
          // ✅ 10번 공통 질문 수정
          'team5_q10': InterviewQuestion(
            id: 'team5_q10',
            text:
                '10. 고객의 문제 상황(요구)과 심리적 상태(욕구)를 정확히 파악하여, 사안은 신속하게 조치하고 관계 갈등은 원만히 조율했던 경험이 있으신가요? 그 과정에서 느낀 보람이나 성취감이 있었다면 자유롭게 들려주세요.',
            nextQuestionId: 'team5_q11',
          ),
          'team5_q11': InterviewQuestion(
            id: 'team5_q11',
            text:
                '11. 지금까지 10개의 인터뷰 문항에 응답하시면서 어떤 마음이 드셨는지요? 알게 된 사실과 기분, 감정 등 떠오르는 대로 자유롭게 말씀해 주세요.',
            nextQuestionId: 'end',
          ),
        };
      case '민원인/지역주민':
        return {
          'minwon_q1': InterviewQuestion(
            id: 'minwon_q1',
            text:
                '1. 한국수자원공사 논산지방수도센터에 수도 관련 민원(예: 누수, 요금, 검침 등)을 접수하거나 문의했을 때 가장 어려웠던 점은 무엇인가요? 여러 측면에서 다양한 내용을 말씀해 주세요.',
            nextQuestionId: 'minwon_q2',
          ),
          'minwon_q2': InterviewQuestion(
            id: 'minwon_q2',
            text:
                '2. 민원 응대 과정에서 응대 직원이 절차를 무시하거나 비합리적인 요구를 한다고 느낀 적이 있으신가요? 만약 있다면, 그 원인이 어디에 있다고 보시나요? 기억나는 사례와 함께 작성해 주세요.',
            nextQuestionId: 'minwon_q3',
          ),
          'minwon_q3': InterviewQuestion(
            id: 'minwon_q3',
            text: '3. 민원 접수나 문의 전에 갈등이 고조되지 않도록 사전에 어떤 준비를 하셨나요? 자유롭게 작성해 주세요.',
            nextQuestionId: 'minwon_q4',
          ),
          'minwon_q4': InterviewQuestion(
            id: 'minwon_q4',
            text:
                '4. 전화, 방문 등 다양한 매체를 통해 민원을 제기했으나 해결되지 않았던 케이스가 있었나요? 기억나는 대로 상세하게 말씀해 주세요.',
            nextQuestionId: 'minwon_q5',
          ),
          // ✅ 5번 공통 질문 수정
          'minwon_q5': InterviewQuestion(
            id: 'minwon_q5',
            text:
                '5. 민원이나 갈등 상황에서 동료, 상급자, 또는 타 부서의 도움이 필요했던 적이 있으셨나요? 그때 어떤 절차와 과정을 통해 문제를 해결하셨는지, 구체적으로 설명해 주세요. 만약 아쉬웠던 점이 있었다면 그 이유도 함께 말씀해 주세요.',
            nextQuestionId: 'minwon_q6',
          ),
          'minwon_q6': InterviewQuestion(
            id: 'minwon_q6',
            text:
                '6. 초기 민원 접수부터 문제 해결까지 진행되는 과정에서 개선이 필요하다고 여겨지는 절차나 시스템상의 애로사항이 있다면 무엇이 떠오르시나요? 자유롭게 말씀해 주세요.',
            nextQuestionId: 'minwon_q7',
          ),
          'minwon_q7': InterviewQuestion(
            id: 'minwon_q7',
            text:
                '7. 민원 접수 과정 또는 불편 상황에서 본인의 감정을 관리하는 노하우나 팁이 있으신가요? 괜찮으시다면, 나눠주시면 좋겠습니다.',
            nextQuestionId: 'minwon_q8',
          ),
          'minwon_q8': InterviewQuestion(
            id: 'minwon_q8',
            text: '8. 민원 해결에 도움이 되는 정보나 서비스는 어떤 것들이 있을까요? 자유롭게 작성해 주세요.',
            nextQuestionId: 'minwon_q9',
          ),
          'minwon_q9': InterviewQuestion(
            id: 'minwon_q9',
            text:
                '9. 가장 기억에 남는 민원 접수 해결 사례와 그 과정에서 느꼈던 점을 소개해 주세요. 자유롭게 작성하시면 됩니다.',
            nextQuestionId: 'minwon_q10',
          ),
          // ✅ 10번 공통 질문 수정
          'minwon_q10': InterviewQuestion(
            id: 'minwon_q10',
            text:
                '10. 고객의 문제 상황(요구)과 심리적 상태(욕구)를 정확히 파악하여, 사안은 신속하게 조치하고 관계 갈등은 원만히 조율했던 경험이 있으신가요? 그 과정에서 느낀 보람이나 성취감이 있었다면 자유롭게 들려주세요.',
            nextQuestionId: 'minwon_q11',
          ),
          'minwon_q11': InterviewQuestion(
            id: 'minwon_q11',
            text:
                '11. 지금까지 10개의 인터뷰 문항에 응답하시면서 어떤 마음이 드셨는지요? 알게 된 사실과 기분, 감정 등 떠오르는 대로 자유롭게 말씀해 주세요.',
            nextQuestionId: 'end',
          ),
        };
      default:
        return {
          'default_q1': InterviewQuestion(
            id: 'default_q1',
            text: '인터뷰를 시작합니다. 자유롭게 이야기해주세요.',
            nextQuestionId: 'end',
          ),
        };
    }
  }

  void _initializeQuestions() {
    final String affiliation = widget.userInfo['affiliation'] ?? '';
    _questionnaire = _getQuestionnaireForAffiliation(affiliation);

    // 시작 질문 ID를 동적으로 찾습니다.
    final startQuestionId = _questionnaire.keys.first;
    _currentQuestion = _questionnaire[startQuestionId]!;

    // ✅ [복원] 인삿말과 딜레이 후 첫 질문을 보여주는 로직
    const String introMessage = """안녕하세요. ㈜한국갈등관리디지털진흥원입니다.

본 인터뷰는 논산수도센터의 민원 데이터를 바탕으로, 보다 효과적인 민원 응대 매뉴얼 시스템을 구축하기 위해 기획되었습니다. 
인터뷰는 완전한 익명으로 진행되며, 모든 내용은 철저히 보호되오니 솔직하고 자세한 답변을 부탁드립니다.

여러분의 생생한 경험이 더 나은 소통과 문제 해결의 밑거름이 됩니다. 소중한 의견에 귀 기울여 현장에서 바로 활용 가능한 결과물로 보답하겠습니다.

참여해주셔서 진심으로 감사합니다.""";

    _addMessage(introMessage, InterviewMessageType.bot);

    Future.delayed(const Duration(seconds: 1)).then((_) {
      if (mounted) {
        _addMessage(_currentQuestion.text, InterviewMessageType.bot);
      }
    });
  }

  void _addMessage(String text, InterviewMessageType type) {
    setState(() {
      _messages.insert(0, InterviewMessage(text: text, type: type));
    });
    _scrollToBottom();
  }

  void _handleAnswer(String answer) async {
    if (answer.trim().isEmpty) return;

    _addMessage(answer, InterviewMessageType.user);
    _answers[_currentQuestion.text] = answer;
    _textController.clear();

    await _saveProgress();

    final nextQuestionId = _currentQuestion.nextQuestionId;

    // ❗️ [수정] 인터뷰가 끝났는지 먼저 확인하도록 순서 변경
    if (nextQuestionId != null && nextQuestionId != 'end') {
      // 인터뷰가 아직 끝나지 않았을 때의 로직

      // ✅ 다음 질문이 있다는 것이 확인된 후에 nextQuestion을 찾으므로 안전합니다.
      final nextQuestion = _questionnaire[nextQuestionId]!;

      setState(() => _isBotThinking = true);
      final empathyResponse = await _getEmpathyResponse(
        _currentQuestion.text,
        answer,
        nextQuestion.text,
      );
      setState(() => _isBotThinking = false);

      // 공감 응답이 비어있지 않은 경우에만 메시지 추가
      if (empathyResponse.isNotEmpty) {
        _addMessage(empathyResponse, InterviewMessageType.bot);
        await Future.delayed(const Duration(milliseconds: 1500));
      }

      _currentQuestion = nextQuestion;
      _addMessage(_currentQuestion.text, InterviewMessageType.bot);
    } else {
      // 인터뷰가 끝났을 때의 로직
      await _submitInterview();
    }
  }

  Future<void> _saveProgress() async {
    final prefs = await SharedPreferences.getInstance();
    // ✅ [수정] 답변 내용과 현재 소속을 함께 저장합니다.
    final progressData = {
      'affiliation': widget.userInfo['affiliation'],
      'answers': _answers,
    };
    await prefs.setString('saved_interview', jsonEncode(progressData));
  }

  Future<void> _submitInterview() async {
    setState(() => _isSubmitting = true);

    final conversationList =
        _answers.entries.map((entry) {
          return {'question': entry.key, 'answer': entry.value};
        }).toList();

    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-northeast3',
      ).httpsCallable('submitInterview');

      await callable.call({
        'conversation': conversationList,
        'userInfo': widget.userInfo,
      });

      // ✅ [추가] 제출 성공 시, 저장된 임시 데이터를 삭제합니다.
      await _clearSavedData();

      if (mounted) {
        setState(() => _isSubmitting = false);
        _addMessage('참여해주셔서 감사합니다.', InterviewMessageType.bot);
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          _showCompletionDialog();
        }
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('제출에 실패했습니다. 다시 시도해주세요.')));
      }
    }
  }

  // ✅ [신규 추가] 저장된 데이터를 삭제하는 함수
  Future<void> _clearSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_interview');
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // 바깥 영역을 눌러도 닫히지 않음
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('제출 완료'),
          content: const Text(
            '수고 많으셨습니다. 당신의 노고에 늘 감사드립니다.',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            ElevatedButton(
              onPressed: () {
                // 확인 버튼을 누르면 홈 화면으로 복귀
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: const Text('확인'),
            ),
          ],
        );
      },
    );
  }

  Future<String> _getEmpathyResponse(
    String previousQuestion,
    String userAnswer,
    String nextQuestion,
  ) async {
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-northeast3',
      ).httpsCallable('generateInterviewResponse');

      // ✅ [수정] 백엔드로 3가지 정보를 모두 전송합니다.
      final result = await callable.call({
        'previousQuestion': previousQuestion,
        'userAnswer': userAnswer,
        'nextQuestion': nextQuestion,
      });

      // ✅ 백엔드에서 오는 키 이름은 'empathyText' 입니다.
      return result.data['empathyText'] ?? '그렇군요.';
    } catch (e) {
      // 에러 발생 시, 대화가 끊기지 않도록 빈 문자열을 반환합니다.
      return '';
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _initSpeech() async {
    _speechEnabled = await _speechToText.initialize();
    if (mounted) setState(() {});
  }

  void _startListening(StateSetter setState) {
    _recognizedWords = '';
    _speechToText.listen(
      onResult: (result) {
        setState(() {
          _recognizedWords = result.recognizedWords;
        });
        _resetSpeechTimer(setState);
      },
      localeId: 'ko_KR',
    );
    setState(() => _isListening = true);
    _resetSpeechTimer(setState);
  }

  void _stopListening(StateSetter setState) {
    _speechToText.stop();
    _speechTimer?.cancel();
    setState(() => _isListening = false);
  }

  void _resetSpeechTimer(StateSetter setState) {
    _speechTimer?.cancel();
    _speechTimer = Timer(const Duration(seconds: 5), () {
      if (_isListening) {
        _stopListening(setState);
        if (mounted) {
          Navigator.pop(context, _recognizedWords);
        }
      }
    });
  }

  // ❗️ [수정] _restoreInterviewState 함수
  void _restoreInterviewState(Map<String, String> savedAnswers) {
    final String affiliation = widget.userInfo['affiliation'] ?? '';
    // ✅ 헬퍼 함수를 통해 현재 소속에 맞는 질문지를 먼저 불러옵니다.
    _questionnaire = _getQuestionnaireForAffiliation(affiliation);

    setState(() {
      _answers.addAll(savedAnswers);
      _messages.clear();

      InterviewQuestion? lastAnsweredQuestion;
      List<InterviewMessage> restoredMessages = [];

      // ✅ 소속에 맞는 시작 질문 ID를 동적으로 결정합니다.
      final String startQuestionId = _questionnaire.keys.first;
      var tempQuestion = _questionnaire[startQuestionId];

      while (tempQuestion != null) {
        final questionText = tempQuestion.text;
        if (savedAnswers.containsKey(questionText)) {
          final answerText = savedAnswers[questionText]!;

          restoredMessages.insert(
            0,
            InterviewMessage(text: answerText, type: InterviewMessageType.user),
          );
          restoredMessages.insert(
            0,
            InterviewMessage(
              text: questionText,
              type: InterviewMessageType.bot,
            ),
          );

          lastAnsweredQuestion = tempQuestion;

          final nextId = tempQuestion.nextQuestionId;
          if (nextId == null ||
              nextId == 'end' ||
              !_questionnaire.containsKey(nextId)) {
            tempQuestion = null;
          } else {
            tempQuestion = _questionnaire[nextId]!;
          }
        } else {
          tempQuestion = null;
        }
      }

      _messages.addAll(restoredMessages);

      if (lastAnsweredQuestion != null) {
        final nextId = lastAnsweredQuestion.nextQuestionId;
        if (nextId != null && nextId != 'end') {
          _currentQuestion = _questionnaire[nextId]!;
          _addEmpathyAndNextQuestionAfterRestore(lastAnsweredQuestion);
        } else {
          _submitInterview();
        }
      }
    });
  }

  // ❗️ [수정] _addEmpathyAndNextQuestionAfterRestore 함수
  // ✅ lastAnsweredQuestion을 파라미터로 받도록 수정
  void _addEmpathyAndNextQuestionAfterRestore(
    InterviewQuestion lastAnsweredQuestion,
  ) async {
    // ✅ 이제 파라미터로 받은 값을 사용하므로 에러가 발생하지 않습니다.
    final lastQuestionText = lastAnsweredQuestion.text;
    final lastAnswerText = _answers[lastQuestionText]!;

    setState(() => _isBotThinking = true);
    final empathyResponse = await _getEmpathyResponse(
      lastQuestionText,
      lastAnswerText,
      _currentQuestion.text,
    );
    setState(() => _isBotThinking = false);

    if (empathyResponse.isNotEmpty) {
      _addMessage(empathyResponse, InterviewMessageType.bot);
      await Future.delayed(const Duration(milliseconds: 700));
    }
    _addMessage(_currentQuestion.text, InterviewMessageType.bot);
  }

  void _showVoiceInputDialog() {
    _recognizedWords = '';
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              height: MediaQuery.of(context).size.height * 0.35,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isListening ? "듣고 있어요..." : "음성으로 답변해주세요",
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        _recognizedWords.isEmpty && !_isListening
                            ? '아래 마이크를 누르면 녹음이 시작됩니다.'
                            : _recognizedWords,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // 취소 버튼
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.grey.shade200,
                        child: IconButton(
                          icon: Icon(Icons.close, color: Colors.grey.shade800),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      // 녹음 시작/중지 버튼
                      GestureDetector(
                        onTap: () {
                          if (!_speechEnabled) return;
                          _isListening
                              ? _stopListening(setState)
                              : _startListening(setState);
                        },
                        child: CircleAvatar(
                          radius: 40,
                          backgroundColor:
                              _isListening
                                  ? Colors.red.shade100
                                  : Colors.blue.shade100,
                          child: Icon(
                            _isListening ? Icons.stop_rounded : Icons.mic,
                            size: 40,
                            color:
                                _isListening
                                    ? Colors.red
                                    : Theme.of(context).primaryColor,
                          ),
                        ),
                      ),
                      // 수동 완료 버튼
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.green.shade100,
                        child: IconButton(
                          icon: Icon(
                            Icons.check_circle,
                            color: Colors.green.shade600,
                          ),
                          onPressed: () {
                            if (_isListening) _stopListening(setState);
                            Navigator.pop(context, _recognizedWords);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    ).then((value) {
      if (value != null && value.isNotEmpty) {
        _textController.text = value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          '인터뷰',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        centerTitle: true,
        elevation: 0.5,
      ),
      // ✅ Stack을 사용해 로딩 화면을 대화 화면 위에 겹쳐서 띄웁니다.
      body: Stack(
        children: [
          Center(
            child: Opacity(
              // ✅ 투명도 조절 (0.05 = 5%)
              opacity: 0.05,
              child: Image.asset(
                'assets/kwater_logo.png',
                width: MediaQuery.of(context).size.width * 0.7,
              ),
            ),
          ),
          // 1. 기존의 대화 화면 UI
          Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  reverse: true,
                  itemCount: _messages.length + (_isBotThinking ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_isBotThinking && index == 0) {
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            "AI가 답변을 읽고 있어요...",
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      );
                    }
                    final message = _messages[index - (_isBotThinking ? 1 : 0)];
                    return _buildMessageBubble(message);
                  },
                ),
              ),
              _buildMessageInput(),
            ],
          ),

          // 2. _isSubmitting이 true일 때만 로딩 오버레이를 표시
          if (_isSubmitting)
            Container(
              // 화면 전체를 반투명한 검은색으로 덮습니다.
              color: Colors.black.withOpacity(0.5),
              // 중앙에 로딩 인디케이터와 텍스트를 표시합니다.
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 20),
                    Text(
                      '제출 중입니다...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            offset: const Offset(0, -1),
            blurRadius: 4,
            color: Colors.black.withOpacity(0.05),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end, // 아이콘과 텍스트 필드 세로 정렬
          children: [
            IconButton(
              icon: Icon(Icons.mic, color: Colors.grey.shade600),
              onPressed: _showVoiceInputDialog,
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _textController,
                  keyboardType: TextInputType.multiline,
                  maxLines: null,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: "답변을 입력하세요...",
                    border: InputBorder.none,
                  ),
                  // onSubmitted 속성을 제거하여 Enter 키로 제출되는 것을 방지
                  // onSubmitted: _handleAnswer,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _handleAnswer(_textController.text),
              child: const CircleAvatar(
                radius: 20,
                backgroundColor: Color(0xff007AFF),
                child: Icon(Icons.arrow_upward, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(InterviewMessage message) {
    if (message.type == InterviewMessageType.announcement) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Text(
          message.text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.blue.shade800,
            fontWeight: FontWeight.bold,
            height: 1.5,
          ),
        ),
      );
    }
    // ✅ [수정] 메시지 종류에 따라 색상을 다르게 설정
    Color bubbleColor;
    Color textColor;
    final bool isUser = message.type == InterviewMessageType.user;

    if (isUser) {
      // 사용자 메시지: 초록색 배경, 흰색 글자
      bubbleColor = const Color(0xFF318FFF);
      textColor = Colors.white;
    } else {
      // 봇 메시지
      textColor = Colors.black87;
      // 봇 메시지 텍스트가 숫자로 시작하는지 확인 (예: "1.", "2.")
      if (RegExp(r'^\d+\.').hasMatch(message.text)) {
        // 질문 메시지: 연한 노란색 배경
        bubbleColor = Colors.yellow.shade100;
      } else {
        // 공감 메시지: 회색 배경
        bubbleColor = Colors.yellow.shade100;
      }
    }
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: bubbleColor, // ✅ 위에서 결정된 색상 적용
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            fontSize: 16,
            height: 1.4,
            color: isUser ? Colors.white : Colors.black87, // ✅ 위에서 결정된 색상 적용
          ),
        ),
      ),
    );
  }
}
