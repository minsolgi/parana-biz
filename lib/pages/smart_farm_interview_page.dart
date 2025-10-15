import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'dart:async';
import 'login_page.dart'; // ✅ [추가] 로그인 페이지 경로
import 'smart_farm_article_page.dart';

// ✅ [수정] 최종적으로 사용할 상태 Enum. 기존 것은 삭제합니다.
enum InterviewFlowState {
  chatting, // 1. 인터뷰 및 설문 대화 진행 중
  summaryLoading, // 2. 요약 생성 중
  imageGenerationProcessing, // 3. 최종 신문기사 생성 중
  finished, // 4. 모든 과정 종료
}

// ✅ [수정] 다양한 답변 형태를 정의하는 QuestionType Enum
enum QuestionType { buttonSelection, directInputButton, longText }

// ✅ [수정] 기존 InterviewQuestion을 대체하는 새로운 Question 모델
class Question {
  final String id;
  final String text;
  final QuestionType type;
  final List<String>? options;
  final String? nextQuestionId;
  final bool needsEmpathy;
  final String? exampleText;

  Question({
    required this.id,
    required this.text,
    required this.type,
    this.options,
    this.nextQuestionId,
    this.needsEmpathy = false,
    this.exampleText,
  });
}

// ✅ [수정] 메시지에 버튼 옵션을 포함할 수 있도록 ChatMessage 모델 확장
enum MessageType { user, bot, botExample }

class ChatMessage {
  final String text;
  final MessageType type;
  final String questionId;
  final List<String>? options; // 버튼 옵션
  final Function(String)? onOptionSelected; // 버튼 선택 시 콜백

  ChatMessage({
    required this.text,
    required this.type,
    required this.questionId,
    this.options,
    this.onOptionSelected,
  });
}

class SmartFarmInterviewPage extends StatefulWidget {
  final Map<String, dynamic> userInfo;
  const SmartFarmInterviewPage({super.key, required this.userInfo});

  @override
  State<SmartFarmInterviewPage> createState() => _SmartFarmInterviewPageState();
}

class _SmartFarmInterviewPageState extends State<SmartFarmInterviewPage> {
  // --- 컨트롤러 ---
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _directInputController = TextEditingController();

  // --- 상태 및 데이터 저장 변수 ---
  final List<ChatMessage> _messages = [];
  final Map<String, dynamic> _answers = {};
  final Map<String, dynamic> _imageGenConfig = {};

  bool _showDirectInputField = false;

  // --- 새로운 Question 모델 기반 변수 ---
  late final Map<String, Question> _questionnaire; // 👈 타입 수정
  late Question _currentQuestion; // 👈 타입 수정

  // --- 흐름 제어 변수 ---
  InterviewFlowState _flowState = InterviewFlowState.chatting;
  String _lastGeneratedSummary = '';

  // --- 로딩 상태 변수 ---
  bool _isBotThinking = false; // 공감표현 등 짧은 로딩
  bool _isHeadlineLoading = false; // 헤드라인 추천 등 긴 로딩

  // --- 음성 인식 변수 ---
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  String _recognizedWords = '';
  bool _isListening = false;
  Timer? _speechTimer;

  bool _isProcessing = false; // 생성 중 오버레이 표시 여부
  double _progressValue = 0.0;
  String _progressText = '';

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  bool _isSubmittingLead = false;

  @override
  void initState() {
    super.initState();
    _initializeQuestions();
    _initSpeech();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _speechToText.stop();
    _speechTimer?.cancel();
    _directInputController.dispose();
    super.dispose();
  }

  // ✅ [수정] 전체 인터뷰 + 설문 흐름을 포함하는 새로운 질문지
  void _initializeQuestions() {
    _questionnaire = {
      // --- 1부: 스마트팜 인터뷰 ---
      'sf_q1': Question(
        id: 'sf_q1',
        text: '{penName}님이 스마트팜에 관심을 갖게 된 계기와 동기가 있었나요? 상세하게 소개 부탁해도 될까요?',
        type: QuestionType.longText,
        needsEmpathy: true,
        nextQuestionId: 'sf_q2',
        exampleText:
            '친구가 운영하는 스마트팜에서 묘목에 물을 주는 모습과 센서 알람이 울리는 광경을 보고 앞으로 열리는 미래의 농가 모습이 확연하게 느껴졌고, 가능성을 선택하게 됨',
      ),
      'sf_q2': Question(
        id: 'sf_q2',
        text:
            '{penName}님, 논산시 스마트팜 시스템에서 가장 만족스러운 기능과 개선이 필요한 점은 무엇인가요?\n(만족사례와 개선요청 내용을 상세하게 작성해 주시면 새로운 정책과 제도에 반영될 수 있습니다)',
        type: QuestionType.longText,
        needsEmpathy: true,
        nextQuestionId: 'sf_q3',
      ),
      'sf_q3': Question(
        id: 'sf_q3',
        text:
            '청년 농업인으로서 N번 지원사업(정부·지자체 보조금, 창업 지원 등)을 활용한 경험이 있나요? 있다면 어떤 프로그램이 유익했나요? 경험한 내용 모두 작성해 주시면 활성화에 도움되도록 진행해 보겠습니다.',
        type: QuestionType.longText,
        needsEmpathy: true,
        nextQuestionId: 'sf_q4',
      ),
      'sf_q4': Question(
        id: 'sf_q4',
        text:
            '{penName}님, 논산시 현장에서 느끼는 정보·교육 격차(디지털 리터러시, 데이터 분석 역량 등)는 어떤 부분인가요?',
        type: QuestionType.longText,
        needsEmpathy: true,
        nextQuestionId: 'sf_q5',
        exampleText:
            '(예시) 스마트팜 관련 교육 프로그램이 있긴 하지만, 단기 강의 위주로 끝나버려서 실제 현장에서 부딪히는 문제를 해결하기엔 한계가 있습니다. 지속적으로 현장에서 맞춤형 컨설팅을 받을 수 있는 기회가 필요한 것 같습니다.',
      ),
      'sf_q5': Question(
        id: 'sf_q5',
        text:
            '스마트팜 운영 중 지역사회(커뮤니티)나 지자체 기관과 협업 사례가 있나요? (도움된 부분과 아쉬운 부분을 나눠서 작성해 주시기 바랍니다)',
        type: QuestionType.longText,
        needsEmpathy: true,
        nextQuestionId: 'sf_q6',
      ),
      'sf_q6': Question(
        id: 'sf_q6',
        text: '청년 스마트팜 활성화를 위해 지자체나 정부가 추가로 제공해야 할 정책·인프라는 어떤 것이 있을까요?',
        type: QuestionType.longText,
        needsEmpathy: true,
        nextQuestionId: 'sf_q7',
      ),
      'sf_q7': Question(
        id: 'sf_q7',
        text:
            '논산시 지역 내 청년 농업인 네트워크나 커뮤니티 활동은 스마트팜 운영에 어떤 영향을 주고 있나요? 생각나는대로 편하게 작성해 주세요.',
        type: QuestionType.longText,
        needsEmpathy: true,
        nextQuestionId: 'sf_q8',
      ),
      'sf_q8': Question(
        id: 'sf_q8',
        text:
            '5년 후 {penName}님 모습과 논산시 스마트팜의 모습은 어떠할 것이라고 예상하시나요?\n내모습:\n논산시 스마트팜 모습:',
        type: QuestionType.longText,
        needsEmpathy: true,
        nextQuestionId: 'summary_confirm',
      ),

      // --- 2부: 요약 및 신문 기사 생성 설문 ---
      'summary_confirm': Question(
        id: 'summary_confirm',
        text: '지금까지 진행한 인터뷰 내용을 요약해 볼게요. 확인해 보시겠어요?',
        type: QuestionType.buttonSelection,
        options: ['네, 요약 확인하기'],
      ),
      'img_q1_start': Question(
        id: 'img_q1_start',
        text: '5년 뒤, 중앙지 또는 지역지 신문기사를 출력합니다.',
        type: QuestionType.buttonSelection,
        options: ['네'],
        nextQuestionId: 'img_q2_headline',
      ),
      'img_q2_headline': Question(
        id: 'img_q2_headline',
        text: '신문기사 헤드라인을 추천해드릴까요?',
        type: QuestionType.directInputButton,
        options: ['네', '직접입력하기'],
        nextQuestionId: 'img_q3_hardship',
      ),
      'img_q3_hardship': Question(
        id: 'img_q3_hardship',
        text: '모험과 시련, 갈등 극복 등 고난의 과정이 포함되도록 할까요?',
        type: QuestionType.buttonSelection,
        options: ['네', '아니오'],
        nextQuestionId: 'img_q4_style',
      ),
      'img_q4_style': Question(
        id: 'img_q4_style',
        text: '신문기사의 그림체는 어떻게 하시겠어요?',
        type: QuestionType.buttonSelection,
        options: ['정치면', '경제면', '사회면', '오피니언', '지역사회', '광고', '만화'],
        nextQuestionId: 'img_q5_final_confirm',
      ),
      'img_q5_final_confirm': Question(
        id: 'img_q5_final_confirm',
        text: '신문기사 생성을 시작할까요?',
        type: QuestionType.buttonSelection,
        options: ['네! 시작해주세요.'],
      ),
    };

    _currentQuestion = _questionnaire['sf_q1']!;
    _askQuestion(_currentQuestion);
  }

  // ✅ [수정] 질문 객체 타입을 새로운 Question 모델로 변경
  void _askQuestion(Question question) {
    final penName = widget.userInfo['penName'] ?? '참여자';
    final questionText = question.text.replaceAll('{penName}', penName);

    setState(() {
      _messages.insert(
        0,
        ChatMessage(
          text: questionText,
          type: MessageType.bot,
          questionId: question.id,
          options: question.options,
          onOptionSelected: _handleAnswer, // 모든 버튼은 _handleAnswer 호출
        ),
      );
    });
    _scrollToBottom();
  }

  // ✅ [신규] 모든 답변 처리를 담당하는 중앙 컨트롤러 함수
  void _handleAnswer(String answer) async {
    if (_currentQuestion.type == QuestionType.directInputButton &&
        answer == '직접입력하기') {
      _addBotMessage(answer, type: MessageType.user); // '직접입력하기' 선택 기록
      setState(() {
        _showDirectInputField = true; // 입력창을 표시하도록 상태 변경
      });
      _scrollToBottom();
      return; // 다음 질문으로 넘어가지 않고 여기서 종료
    }

    // 0. UI 업데이트 (사용자 답변 표시 및 저장)
    _addBotMessage(answer, type: MessageType.user);
    _answers[_currentQuestion.id] = answer;
    _textController.clear();
    _directInputController.clear(); // 직접 입력창도 비워줌

    // ✅ [추가] 직접 입력창을 사용한 후에는 다시 숨김
    if (_showDirectInputField) {
      setState(() {
        _showDirectInputField = false;
      });
    }

    _scrollToBottom();

    // --- 1. 질문 ID에 따른 특별 분기 처리 ---

    // 1-1. 요약 확인 단계
    if (_currentQuestion.id == 'summary_confirm') {
      if (answer == '네, 요약 확인하기') {
        setState(() => _flowState = InterviewFlowState.summaryLoading);
        final summary = await _generateSummary();

        // 요약에 성공했을 때만 다음 로직 진행
        if (summary.isNotEmpty && mounted) {
          _lastGeneratedSummary = summary;
          _answers['summary'] = summary;

          _addBotMessage("요약 내용입니다:\n\n$summary");

          if (widget.userInfo['isLoggedIn'] ?? false) {
            // 로그인 사용자: 다음 설문으로
            setState(() => _flowState = InterviewFlowState.chatting);
            _currentQuestion = _questionnaire['img_q1_start']!;
            _askQuestion(_currentQuestion);
          } else {
            // 비로그인 사용자: 요약본 저장 후 종료 메시지
            await _submitFullInterviewData(_lastGeneratedSummary);
            _showFinalThankYouMessage(); // 여기서 상태가 'finished'로 바뀜
          }
        } else if (mounted) {
          // 요약 실패 시 바로 종료
          _showFinalThankYouMessage();
        }
      } else {
        // '아니요' 선택 시 요약 없이 저장 후 종료
        await _submitFullInterviewData(null);
        _showFinalThankYouMessage();
      }
      return; // 분기 처리가 끝났으므로 함수 종료
    }

    // 1-2. 헤드라인 추천 단계
    if (_currentQuestion.id == 'img_q2_headline' && answer == '네') {
      setState(() => _isHeadlineLoading = true);
      final headlines = await _fetchRecommendedHeadlines();
      setState(() => _isHeadlineLoading = false);

      _currentQuestion = Question(
        id: 'img_q2_headline_choice', // 임시 ID
        text: 'AI가 추천한 헤드라인입니다. 선택하시거나 직접 입력해주세요.',
        type: QuestionType.directInputButton,
        options: [...headlines, '직접입력하기'],
        nextQuestionId: 'img_q3_hardship',
      );
      _askQuestion(_currentQuestion);
      return;
    }

    // 1-3. 최종 생성 시작 단계
    if (_currentQuestion.id == 'img_q5_final_confirm' &&
        answer == '네! 시작해주세요.') {
      _answers.addAll(_imageGenConfig); // 설문 답변을 최종 답변 맵에 통합
      await _startNewspaperArticleGeneration();
      return;
    }

    // --- 2. 일반 다음 질문으로 이동 ---

    // 2-1. 공감 표현
    if (_currentQuestion.needsEmpathy) {
      setState(() => _isBotThinking = true);
      final empathy = await _getSmartFarmEmpathyResponse(
        _currentQuestion.text,
        answer,
        _questionnaire[_currentQuestion.nextQuestionId]?.text ?? "다음 질문",
      );
      setState(() => _isBotThinking = false);
      if (empathy.isNotEmpty) _addBotMessage(empathy);
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // 2-2. 다음 질문 ID 결정 및 질문
    String? nextQuestionId = _currentQuestion.nextQuestionId;
    // 헤드라인 선택 답변 저장
    if (_currentQuestion.id.startsWith('img_q2_headline')) {
      _imageGenConfig['headline'] = answer;
    } else if (_currentQuestion.id == 'img_q3_hardship') {
      _imageGenConfig['includeHardship'] = (answer == '네');
    } else if (_currentQuestion.id == 'img_q4_style') {
      _imageGenConfig['style'] = answer;
    }

    if (nextQuestionId != null && _questionnaire.containsKey(nextQuestionId)) {
      _currentQuestion = _questionnaire[nextQuestionId]!;
      _askQuestion(_currentQuestion);
    }
  }

  // ✅ [신규] 요약 생성 로직 함수
  Future<String> _generateSummary() async {
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-northeast3',
      ).httpsCallable('summarizeSmartFarmInterview');

      final conversationList =
          _answers.entries.where((entry) => entry.key.startsWith('sf_q')).map((
            entry,
          ) {
            final penName = widget.userInfo['penName'] ?? '참여자';
            final questionText =
                _questionnaire[entry.key]?.text.replaceAll(
                  '{penName}',
                  penName,
                ) ??
                '';
            return {
              'questionId': entry.key,
              'question': questionText,
              'answer': entry.value,
            };
          }).toList();

      final result = await callable.call({
        'conversation': conversationList,
        'userInfo': widget.userInfo,
      });
      return result.data['summary'] ?? "요약 생성에 실패했습니다.";
    } catch (e) {
      _addBotMessage("요약 중 오류가 발생했습니다: $e");
      return "";
    }
  }

  // ✅ [신규] 헤드라인 추천 요청 함수
  Future<List<String>> _fetchRecommendedHeadlines() async {
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-northeast3',
      ).httpsCallable('generateNewspaperHeadlines');
      final result = await callable.call({
        'userInfo': widget.userInfo,
        'summary': _lastGeneratedSummary,
        'futureVision': _answers['sf_q8'],
      });
      return List<String>.from(result.data['headlines']);
    } catch (e) {
      _addBotMessage("헤드라인 추천 중 오류가 발생했습니다.");
      return [];
    }
  }

  // ✅ [수정] ToddlerBook의 로직을 참조하여 재작성된 최종 생성 함수
  Future<void> _startNewspaperArticleGeneration() async {
    // 1. 생성 시작 및 초기 상태 설정
    setState(() {
      _isProcessing = true;
      _progressValue = 0.0;
      _progressText = '신문기사 생성을 준비하고 있어요...';
    });

    // 실제 서버 요청을 백그라운드에서 미리 시작
    final callable = FirebaseFunctions.instanceFor(
      region: 'asia-northeast3',
    ).httpsCallable('processNewspaperArticle');
    final creationFuture = callable.call({
      'userInfo': widget.userInfo,
      'summary': _lastGeneratedSummary,
      'imageGenConfig': _imageGenConfig,
    });

    try {
      // 2. 연출된 프로그레스 바 애니메이션
      await Future.delayed(const Duration(seconds: 1));
      setState(() {
        _progressValue = 0.3;
        _progressText = '헤드라인과 인터뷰 내용을 분석 중입니다...';
      });
      await Future.delayed(const Duration(seconds: 4));

      setState(() {
        _progressValue = 0.6;
        _progressText = 'AI가 기사 본문을 작성하고 있습니다...';
      });
      await Future.delayed(const Duration(seconds: 6));

      setState(() {
        _progressValue = 0.8;
        _progressText = '기사에 어울리는 이미지를 생성하고 있습니다...';
      });

      // 3. 실제 서버 요청이 완료될 때까지 대기
      final result = await creationFuture;
      final articleId = result.data?['articleId']; // 서버에서 articleId를 반환한다고 가정

      // 4. 완료 처리 및 페이지 이동
      setState(() {
        _progressValue = 1.0;
        _progressText = '완성!';
      });
      await Future.delayed(const Duration(seconds: 1));

      if (mounted) {
        // ✅ [수정] 홈이 아닌, 기사 목록 페이지로 이동
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const SmartFarmArticlePage()),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        // 에러 발생 시 생성 중단 및 이전 화면으로 복귀
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류가 발생하여 생성을 중단했습니다: ${e.message}')),
        );
        // 생성 실패 시 인터뷰 종료 상태로
        setState(() {
          _isProcessing = false;
          _flowState = InterviewFlowState.finished;
        });
      }
    } finally {
      if (mounted && _isProcessing) {
        // 정상 종료가 아닐 경우를 대비
        setState(() => _isProcessing = false);
      }
    }
  }

  void _addBotMessage(String text, {MessageType type = MessageType.bot}) {
    setState(() {
      _messages.insert(
        0,
        ChatMessage(text: text, type: type, questionId: 'bot_message'),
      );
    });
    _scrollToBottom();
  }

  Future<void> _submitFullInterviewData(String? summary) async {
    // 사용자가 '아니오'를 눌러도 대화 내용은 저장되어야 합니다.
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-northeast3',
      ).httpsCallable('submitSmartFarmInterview');

      final conversationList =
          _answers.entries.map((entry) {
            final penName = widget.userInfo['penName'] ?? '참여자';
            final questionText =
                _questionnaire[entry.key]?.text.replaceAll(
                  '{penName}',
                  penName,
                ) ??
                '';
            return {
              'questionId': entry.key,
              'question': questionText,
              'answer': entry.value,
            };
          }).toList();

      await callable.call({
        'userInfo': widget.userInfo,
        'conversation': conversationList,
        'summary': summary, // 요약본 (없으면 null)
      });
      debugPrint("✅ 인터뷰 데이터가 성공적으로 저장되었습니다.");
    } catch (e) {
      debugPrint("🔥 인터뷰 데이터 저장 실패: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('데이터 저장 중 오류가 발생했습니다.')));
      }
    }
  }

  // // ✅ [신규 추가] 개인정보를 제출하는 함수 (ClosingPage에서 가져옴)
  // Future<void> _submitLeadInfo() async {
  //   if (_formKey.currentState!.validate()) {
  //     setState(() => _isSubmittingLead = true);
  //     try {
  //       final callable = FirebaseFunctions.instanceFor(
  //         region: 'asia-northeast3',
  //       ).httpsCallable('submitSmartFarmLead');
  //       await callable.call({
  //         'name': _nameController.text,
  //         'phone': _phoneController.text,
  //         'email': _emailController.text,
  //       });
  //       _showFinalThankYouMessage(); // 성공 시 감사 메시지 표시
  //     } catch (e) {
  //       if (mounted)
  //         ScaffoldMessenger.of(
  //           context,
  //         ).showSnackBar(SnackBar(content: Text('제출 중 오류가 발생했습니다: $e')));
  //     } finally {
  //       if (mounted) setState(() => _isSubmittingLead = false);
  //     }
  //   }
  // }

  // ✅ [신규 추가] 최종 마무리 멘트를 채팅창에 표시하는 함수
  void _showFinalThankYouMessage() {
    _addBotMessage(
      "오늘 논산시 청년 스마트팜 발전 포럼 사전 인터뷰에 귀한 시간을 내어 참여해 주신 모든 분들께 진심으로 감사드립니다!\n여러분께서 채팅을 통해 솔직하게 나눠주신 생생한 경험과 소중한 의견 하나하나가 논산시 스마트팜의 미래를 위한 튼튼한 밑거름이 될 것이라고 확신합니다!\n솔직하게 응답 제출해 주신 현장데이터가 스마트팜 발전에 반영되도록 최선을 다하겠습니다.\n앞으로도 저희 논산시 청년 스마트팜에 변함없는 관심과 따뜻한 응원 부탁드리며,\n오늘 모두 정말 수고 많으셨습니다!",
    );
    setState(() => _flowState = InterviewFlowState.finished); // 종료 상태로 전환
  }

  Future<String> _getSmartFarmEmpathyResponse(
    String previousQuestion,
    String userAnswer,
    String nextQuestion,
  ) async {
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-northeast3',
      ).httpsCallable('generateSmartFarmEmpathyResponse');
      final result = await callable.call({
        'previousQuestion': previousQuestion,
        'userAnswer': userAnswer,
        'nextQuestion': nextQuestion,
      });
      return result.data['empathyText'] ?? '';
    } catch (e) {
      debugPrint('Error getting empathy response: $e');
      return ''; // 에러 발생 시 빈 문자열 반환
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients)
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
    });
  }

  // 음성 인식 관련 함수들은 수정 없이 그대로 유지합니다.
  void _initSpeech() async {
    _speechEnabled = await _speechToText.initialize();
    if (mounted) setState(() {});
  }

  void _startListening(StateSetter setState) {
    _recognizedWords = '';
    _speechToText.listen(
      onResult: (result) {
        setState(() => _recognizedWords = result.recognizedWords);
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
        if (mounted) Navigator.pop(context, _recognizedWords);
      }
    });
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
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.grey.shade200,
                        child: IconButton(
                          icon: Icon(Icons.close, color: Colors.grey.shade800),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
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

  void _showComingSoonDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('알림'),
            content: const Text('아직 준비 중인 서비스입니다.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('확인'),
              ),
            ],
          ),
    );
  }

  bool get _isLoading =>
      _isBotThinking ||
      _isHeadlineLoading ||
      _flowState == InterviewFlowState.summaryLoading;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('스마트팜 사전 인터뷰'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        centerTitle: true,
        elevation: 0.5,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  reverse: true,
                  // ✅ [수정] _isBotThinking 대신 _isLoading 사용
                  itemCount: _messages.length + (_isLoading ? 1 : 0),
                  itemBuilder: (context, index) {
                    // ✅ [수정] _isBotThinking 대신 _isLoading 사용
                    if (_isLoading && index == 0) {
                      // 각 로딩 상태에 맞는 UI를 순서대로 확인하여 표시
                      if (_flowState == InterviewFlowState.summaryLoading) {
                        return _buildSummaryLoadingIndicator();
                      }
                      if (_isHeadlineLoading) {
                        return _buildThinkingIndicator(
                          text: 'AI가 헤드라인을 추천하고 있어요...',
                        );
                      }
                      // 기본 로딩 (공감 표현 등)
                      return _buildThinkingIndicator();
                    }

                    // ✅ [수정] _isBotThinking 대신 _isLoading 사용
                    final messageIndex = index - (_isLoading ? 1 : 0);
                    return _buildChatMessage(_messages[messageIndex]);
                  },
                ),
              ),
              _buildBottomWidget(),
            ],
          ),
          if (_isProcessing) _buildCreationProgress(),
        ],
      ),
    );
  }

  // ✅ [참고] 로딩 텍스트를 바꿀 수 있도록 수정된 _buildThinkingIndicator
  Widget _buildThinkingIndicator({String text = "AI가 답변을 읽고 있어요..."}) {
    return _buildBotMessageContainer(
      Text(
        text,
        style: const TextStyle(
          fontStyle: FontStyle.italic,
          color: Colors.black54,
        ),
      ),
    );
  }

  // ✅ [수정] 새로운 아키텍처에 맞게 완전히 재작성된 함수
  Widget _buildBottomWidget() {
    // 1. 최종 단계(생성 중, 완료)에서는 특별한 UI를 보여주거나 아무것도 보여주지 않습니다.
    if (_flowState == InterviewFlowState.imageGenerationProcessing) {
      // 생성 중에는 하단 UI를 완전히 숨깁니다.
      return const SizedBox.shrink();
    }
    if (_flowState == InterviewFlowState.finished) {
      // 모든 과정이 끝나면 '홈으로' 버튼만 보여줍니다.
      return _buildGoHomeButton();
    }

    // 2. 대화 중(_flowState == chatting)일 때의 로직입니다.
    // 현재 질문의 타입에 따라 입력창의 활성화 여부와 힌트 텍스트가 결정됩니다.
    final bool isTextInputEnabled =
        _currentQuestion.type == QuestionType.longText &&
        !_isBotThinking &&
        !_isHeadlineLoading;

    final String hintText = isTextInputEnabled ? "답변을 입력하세요..." : " ";

    // 3. 항상 메시지 입력창을 반환하되, 상태에 따라 활성화/비활성화만 제어합니다.
    return _buildMessageInput(isTextInputEnabled, hintText);
  }

  // ✅ [신규 추가] 직접 입력 UI 위젯 (레퍼런스 코드와 동일)
  Widget _buildDirectInputWidget() {
    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.blue.withOpacity(0.5)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _directInputController,
                  decoration: const InputDecoration.collapsed(
                    hintText: "원하는 내용을 입력...",
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (text) {
                    if (text.isNotEmpty) _handleAnswer(text);
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send, color: Colors.blue),
                onPressed: () {
                  if (_directInputController.text.isNotEmpty) {
                    _handleAnswer(_directInputController.text);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ [신규 추가] 요청하신 디자인의 요약 로딩 인디케이터 위젯
  Widget _buildSummaryLoadingIndicator() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CircleAvatar(backgroundColor: Colors.grey),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI가 인터뷰 내용을 요약하고 있어요', // 텍스트 수정
                  style: TextStyle(fontSize: 16, color: Colors.black87),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: const LinearProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFF318FFF),
                    ), // 앱의 메인 컬러로 변경
                    backgroundColor: Colors.black12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ✅ [신규 추가] 모든 과정이 끝난 뒤 표시될 '홈으로' 버튼
  // '홈으로' 버튼 위젯 (기존 코드와 동일)
  // ✅ [수정] 버튼 텍스트 및 onPressed 기능 변경
  Widget _buildGoHomeButton() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      color: Colors.white,
      width: double.infinity, // 버튼 너비를 꽉 채우도록 설정
      child: SafeArea(
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF318FFF), // 파란색 버튼
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          onPressed: () {
            // 현재까지의 모든 화면을 스택에서 제거하고 로그인 페이지로 이동
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (context) => const LoginPage(),
              ), // LoginPage()로 이동
              (Route<dynamic> route) => false, // 모든 이전 경로를 제거
            );
          },
          child: const Text('홈으로 이동하기'),
        ),
      ),
    );
  }

  Widget _buildMessageInput(bool isEnabled, String hintText) {
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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              color: Colors.grey.shade600,
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  builder: (BuildContext context) {
                    return Container(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          ListTile(
                            leading: const Icon(Icons.audiotrack_outlined),
                            title: const Text('음성 파일 업로드'),
                            onTap: () {
                              Navigator.pop(context);
                              _showComingSoonDialog();
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.photo_camera_outlined),
                            title: const Text('사진 업로드'),
                            onTap: () {
                              Navigator.pop(context);
                              _showComingSoonDialog();
                            },
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
            IconButton(
              icon: Icon(Icons.mic, color: Colors.grey.shade600),
              onPressed: isEnabled ? _showVoiceInputDialog : null,
              disabledColor: Colors.grey.shade300,
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
                  maxLines: 5,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: hintText, // 👈 [수정] 파라미터로 받은 hintText 사용
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  enabled: isEnabled,
                  // 텍스트 입력 후 '완료' 버튼 눌렀을 때도 답변 제출
                  onSubmitted: isEnabled ? _handleAnswer : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              // 👈 [수정] _handleAnswer로 직접 호출하도록 단순화
              onTap:
                  isEnabled ? () => _handleAnswer(_textController.text) : null,
              child: CircleAvatar(
                radius: 20,
                backgroundColor:
                    isEnabled ? const Color(0xFF318FFF) : Colors.grey.shade300,
                child: const Icon(
                  Icons.arrow_upward,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ [신규 추가] 생성 진행률 오버레이 UI 위젯 (ToddlerBookPage 참조)
  Widget _buildCreationProgress() {
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              LinearProgressIndicator(
                value: _progressValue,
                backgroundColor: Colors.white.withOpacity(0.3),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF318FFF),
                ),
                minHeight: 10,
                borderRadius: BorderRadius.circular(5),
              ),
              const SizedBox(height: 20),
              Text(
                '${(_progressValue * 100).toInt()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _progressText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatMessage(ChatMessage message) {
    final bool isUser = message.type == MessageType.user;
    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: _buildMessageBubble(message),
      );
    } else {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(backgroundColor: Colors.grey),
          const SizedBox(width: 8),
          Flexible(child: _buildMessageBubble(message)),
        ],
      );
    }
  }

  Widget _buildBotMessageContainer(Widget child) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CircleAvatar(backgroundColor: Colors.grey),
        const SizedBox(width: 8),
        Flexible(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(20),
            ),
            child: child,
          ),
        ),
      ],
    );
  }

  // ✅ [신규 추가] 말풍선 안에 들어갈 버튼 생성 위젯
  Widget _buildOptionButtons(ChatMessage message) {
    return Wrap(
      spacing: 8.0,
      runSpacing: 8.0,
      children:
          message.options!.map((option) {
            return OutlinedButton(
              onPressed: () => message.onOptionSelected?.call(option),
              child: Text(option),
            );
          }).toList(),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isUser = message.type == MessageType.user;
    final question = _questionnaire[message.questionId];

    Color bubbleColor;
    Color textColor;
    switch (message.type) {
      case MessageType.user:
        bubbleColor = const Color(0xFF318FFF);
        textColor = Colors.white;
        break;
      case MessageType.botExample:
        bubbleColor = Colors.amber.shade100;
        textColor = Colors.black87;
        break;
      default:
        bubbleColor = Colors.grey.shade200;
        textColor = Colors.black87;
        break;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.text,
            style: TextStyle(fontSize: 16, height: 1.4, color: textColor),
          ),
          if (!isUser && question != null && question.exampleText != null)
            Padding(
              padding: const EdgeInsets.only(top: 10.0),
              child: InkWell(
                onTap:
                    () => _addBotMessage(
                      "예시) ${question.exampleText!}",
                      type: MessageType.botExample,
                    ),
                child: Text(
                  '예시보기',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.blue.shade800,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          if (message.options != null &&
              !_answers.containsKey(message.questionId))
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: _buildOptionButtons(message),
            ),
          if (_showDirectInputField &&
              message.questionId == _currentQuestion.id)
            _buildDirectInputWidget(),
        ],
      ),
    );
  }
}
