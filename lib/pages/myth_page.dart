import 'dart:async';
import 'package:flutter/material.dart';
// import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

enum QuestionType { buttonSelection, directInputButton, shortText, longText }

class Question {
  final String id;
  final String text;
  final QuestionType type;
  final List<String>? options;
  final bool needsEmpathy;
  final String? nextQuestionId;
  final Map<String, String>? nextQuestionIds;
  final String? exampleText;

  Question({
    required this.id,
    required this.text,
    this.type = QuestionType.longText,
    this.options,
    this.needsEmpathy = false,
    this.nextQuestionId,
    this.nextQuestionIds,
    this.exampleText,
  });
}

enum MessageType {
  user,
  bot,
  botExample, // botExample 포함
}

class ChatMessage {
  final String text;
  final MessageType type;
  final String questionId;
  final List<String>? options;
  final Function(String)? onOptionSelected;

  ChatMessage({
    required this.text,
    required this.type,
    required this.questionId,
    this.options,
    this.onOptionSelected,
  });
}

class MythPage extends StatefulWidget {
  final Map<String, dynamic> userProfile;
  final Map<String, dynamic> initialAnswers;

  const MythPage({
    super.key,
    required this.userProfile,
    required this.initialAnswers,
  });

  @override
  State<MythPage> createState() => _MythPageState();
}

class _MythPageState extends State<MythPage> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final Map<String, Question> _questionnaire;
  late Question _currentQuestion;
  final Map<String, dynamic> _answers = {};
  final List<ChatMessage> _messages = [];
  bool _isCreating = false; // _isLoading 대체
  bool _isBotThinking = false;
  bool _isGeneratingSummary = false;
  bool _isInitializing = true;
  bool _showDirectInputField = false;
  double _progressValue = 0.0;
  String _progressText = '';
  final TextEditingController _directInputController = TextEditingController();

  // ✅ '신화 만들기' 전용 상태 변수
  final Set<String> _selectedPlotElements = {}; // 4번(플롯) 복수 선택용
  final Set<String> _selectedCompositionElements = {};

  // SpeechToText 관련 변수 (toddler_book_page에서 가져옴)
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  String _recognizedWords = '';
  bool _isListening = false;
  Timer? _speechTimer;

  @override
  void initState() {
    super.initState();
    _answers.addAll(widget.initialAnswers);
    _initializeQuestions();
    _initSpeech();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _directInputController.dispose();
    super.dispose();
  }

  // ✅ [추가] '준비 중' 다이얼로그 함수 (toddler_book_page에서 가져옴)
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

  // ✅ [추가] SpeechToText 관련 함수들 (toddler_book_page에서 가져옴)
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

  void _initializeQuestions() {
    setState(() {
      _isInitializing = true;
      _messages.clear();
      _selectedPlotElements.clear();
      _selectedCompositionElements.clear();
    });

    _questionnaire = {
      // 'ask_myth_type': Question(
      //   id: 'ask_myth_type',
      //   text: '어떤 종류의 신화를 만들고 싶으신가요?',
      //   type: QuestionType.buttonSelection,
      //   options: [
      //     '기업 스토리',
      //     '개인 성장 스토리',
      //     '로컬 스토리',
      //     '국가/문화 에픽',
      //     '종교 에픽',
      //     '우주, 초자연 에픽',
      //   ],
      //   nextQuestionId: 'ask_composition_elements',
      // ),
      // 'ask_composition_elements': Question(
      //   id: 'ask_composition_elements',
      //   text: '이야기에 포함될 구성요소를 모두 선택해주세요. (복수 선택 가능)',
      //   type: QuestionType.buttonSelection,
      //   options: [
      //     '상징, 은유',
      //     '영웅 여정(모험)',
      //     '갈등, 시련, 해방',
      //     '공동체(가치, 전통, 연대)',
      //     '행동, 체험, 의식, 챌린지',
      //   ],
      //   nextQuestionId: 'ask_pen_name',
      // ),
      // 'ask_pen_name': Question(
      //   id: 'ask_pen_name',
      //   text: '사용하실 필명을 입력해주세요.',
      //   type: QuestionType.shortText,
      //   nextQuestionId: 'ask_basic_info',
      // ),
      // 'ask_basic_info': Question(
      //   id: 'ask_basic_info',
      //   text: '기본 정보를 알려주세요. 이야기에 깊이를 더해줄 거예요.',
      //   type: QuestionType.longText,
      //   exampleText: '예시)\n성별: 여성\n나이: 30대\n학력: 대졸\n직군: IT/개발자\n거주지: 대한민국 대전',
      //   nextQuestionId: 'ask_impact', // ✅ 기존 첫 질문으로 연결
      // ),
      'ask_impact': Question(
        id: 'ask_impact',
        text: '당신의 신화를 읽고 나면 독자들의 일상에 어떤 변화가 가능할까요?',
        type: QuestionType.longText,
        needsEmpathy: true, // ✅ 추가
        nextQuestionId: 'ask_helpfulness',
        exampleText:
            '예시) 우리 회사의 특별한 여정, 한 사람의 인생 전환점, 우리 동네의 숨겨진 보물, 우주의 탄생 이야기 등',
      ),
      'ask_helpfulness': Question(
        id: 'ask_helpfulness',
        text: '당신의 신화는 어떤 어려움에 처한 독자들에게 도움이 될까요?',
        type: QuestionType.longText,
        needsEmpathy: true, // ✅ 추가
        nextQuestionId: 'ask_protagonist_background',
      ),
      'ask_protagonist_background': Question(
        id: 'ask_protagonist_background',
        text: '이야기의 주인공(또는 중심이 되는 존재)과 주요 배경(장소, 시간대, 상황)을 상세하게 알려주세요.',
        type: QuestionType.longText,
        nextQuestionId: 'ask_plot_elements',
      ),
      'ask_plot_elements': Question(
        id: 'ask_plot_elements',
        text: '어떤 플롯을 중심으로 이야기를 구성할까요? (여러 개 선택 가능)',
        type: QuestionType.buttonSelection,
        options: ['마법적 균열', '내면 마주함', '한계 초월', '자기실현', '새로운 질서', '지속가능성'],
        nextQuestionId: 'ask_author_name',
      ),
      'ask_author_name': Question(
        id: 'ask_author_name',
        text: '당신의 신화는 다른 신화들과 어떤 차별점을 강조하고 싶나요?',
        type: QuestionType.longText,
        needsEmpathy: true,
        nextQuestionId: 'ask_values',
      ),
      'ask_values': Question(
        id: 'ask_values',
        text: '독자들은 당신의 신화에서 어떤 가치와 목표를 발견하게 되나요?',
        type: QuestionType.longText,
        needsEmpathy: true, // ✅ 추가
        nextQuestionId: 'ask_transformation',
      ),
      'ask_transformation': Question(
        id: 'ask_transformation',
        text: '주인공의 삶은 이전과 이후가 어떻게 달라지게 되나요?',
        type: QuestionType.longText,
        needsEmpathy: true, // ✅ 추가
        nextQuestionId: 'confirm_story',
      ),
      'confirm_story': Question(
        id: 'confirm_story',
        text: '답변을 바탕으로 생성된 스토리 초안입니다. 이대로 진행할까요?',
        type: QuestionType.buttonSelection,
        options: ['진행하기'], //수정하기 추가가능.
        nextQuestionId: 'ask_title',
      ),
      'ask_title': Question(
        id: 'ask_title',
        text: 'AI가 4개의 제목을 추천했습니다. 선택하거나 직접 입력해주세요.',
        type: QuestionType.directInputButton,
        options: [], // 동적으로 채워짐
        nextQuestionId: 'ask_author_intro',
      ),
      'ask_author_intro': Question(
        id: 'ask_author_intro',
        text: '저자 소개를 위한 핵심 키워드나 문장을 알려주세요.',
        type: QuestionType.shortText,
        needsEmpathy: true, // ✅ 추가
        exampleText: '예시) 따뜻한 마음으로 세상을 그리는 웹 개발자, 호기심 가득한 반려인의 친구',
        nextQuestionId: 'ask_final_message',
      ),
      'ask_final_message': Question(
        id: 'ask_final_message',
        text: '마지막으로 독자들에게 어떤 인사나 희망의 메시지를 남기고 싶으신가요?',
        needsEmpathy: true, // ✅ 추가
        type: QuestionType.longText,
        nextQuestionId: 'ask_style',
      ),
      // ✅ [추가] 누락되었던 '그림체 선택' 질문
      'ask_style': Question(
        id: 'ask_style',
        text: '이미지의 그림체는 어떻게 하시겠어요?',
        type: QuestionType.buttonSelection,
        options: [
          '신화풍', // '신화'에 어울리는 기본 옵션
          '유아용 동화책',
          '마블 애니메이션',
          '지브리 애니메이션',
          '전래동화풍',
          '안데르센풍',
          '앤서니 브라운풍',
          '이중섭풍',
          '박수근풍',
        ],
        nextQuestionId: 'final_confirm',
      ),
      'final_confirm': Question(
        id: 'final_confirm',
        text: '이제 당신의 신화를 책으로 엮을 시간입니다!',
        type: QuestionType.buttonSelection,
        options: ['나의 신화 만들기 시작'],
      ),
    };

    if (_answers.containsKey('ask_impact')) {
      // 이미 대화가 시작된 답변이 있으므로 -> 대화 내역을 복원합니다.
      _rebuildConversation();
    } else {
      // 대화 관련 답변이 없으므로 -> 새로운 대화를 시작합니다.
      _currentQuestion = _questionnaire['ask_impact']!;
      _askQuestion(_currentQuestion);
    }
    setState(() => _isInitializing = false);
  }

  void _rebuildConversation() {
    List<ChatMessage> restoredMessages = [];
    Question? lastAnsweredQuestion;

    // 1. 대화의 시작점인 'ask_impact' 질문부터 복원을 시작합니다.
    var tempQuestion = _questionnaire['ask_impact']!;

    // 2. 저장된 답변(_answers)이 없을 때까지 반복합니다.
    while (_answers.containsKey(tempQuestion.id)) {
      final questionId = tempQuestion.id;
      final answerText = _answers[questionId]!;

      // 3. 사용자 답변 말풍선을 먼저 추가합니다.
      restoredMessages.insert(
        0,
        ChatMessage(
          text: answerText,
          type: MessageType.user,
          questionId: questionId,
        ),
      );
      // 4. 그 위에 봇 질문 말풍선을 추가합니다.
      restoredMessages.insert(
        0,
        ChatMessage(
          text: tempQuestion.text,
          type: MessageType.bot,
          questionId: questionId,
          options: tempQuestion.options,
          onOptionSelected: (answer) => _handleAnswer(answer),
        ),
      );

      lastAnsweredQuestion = tempQuestion;

      // 5. 다음 질문으로 이동합니다.
      final String? nextId = tempQuestion.nextQuestionId;
      if (nextId == null || !_questionnaire.containsKey(nextId)) {
        break; // 다음 질문이 없으면 반복을 중단합니다.
      }
      tempQuestion = _questionnaire[nextId]!;
    }

    // 6. 복원된 모든 메시지를 화면에 표시하고, 다음 질문을 던집니다.
    setState(() {
      _messages.addAll(restoredMessages);

      if (lastAnsweredQuestion != null) {
        final nextId = lastAnsweredQuestion.nextQuestionId;
        if (nextId != null && _questionnaire.containsKey(nextId)) {
          _currentQuestion = _questionnaire[nextId]!;
          _askQuestion(_currentQuestion);
        }
      }
    });
  }

  void _askQuestion(Question question) {
    setState(() {
      _messages.insert(
        0,
        ChatMessage(
          text: question.text,
          type: MessageType.bot,
          questionId: question.id,
          options: question.options,
        ),
      );
    });
    _scrollToBottom();
  }

  // ✅ [수정] type 파라미터를 추가하여 MessageType.botExample을 받을 수 있도록 함
  void _addBotMessage(String text, {MessageType type = MessageType.bot}) {
    setState(() {
      _messages.insert(
        0,
        ChatMessage(text: text, type: type, questionId: 'bot_message'),
      );
    });
    _scrollToBottom();
  }

  // myth_page.dart -> _MythPageState 클래스 내부

  void _handleAnswer(String answer) async {
    // --- 복수 선택 토글 로직: UI 상태만 변경하고 함수 종료 ---
    if (_currentQuestion.id == 'ask_composition_elements') {
      setState(() {
        if (_selectedCompositionElements.contains(answer)) {
          _selectedCompositionElements.remove(answer);
        } else {
          _selectedCompositionElements.add(answer);
        }
      });
      return;
    }

    // --- 직접 입력 버튼 처리: UI 상태만 변경하고 함수 종료 ---
    if (_currentQuestion.type == QuestionType.directInputButton &&
        answer == '직접입력') {
      setState(() {
        _messages.insert(
          0,
          ChatMessage(
            text: answer,
            type: MessageType.user,
            questionId: _currentQuestion.id,
          ),
        );
        _showDirectInputField = true;
      });
      _scrollToBottom();
      return;
    }

    if (answer.trim().isEmpty &&
        _currentQuestion.type != QuestionType.buttonSelection)
      return;

    // --- 사용자 답변 UI 추가 및 데이터 저장 ---
    setState(() {
      _messages.insert(
        0,
        ChatMessage(
          text: answer,
          type: MessageType.user,
          questionId: _currentQuestion.id,
        ),
      );
      if (_showDirectInputField) _showDirectInputField = false;
    });
    _answers[_currentQuestion.id] = answer;
    await _saveProgress();
    _textController.clear();
    _scrollToBottom();

    // --- 공감 응답 처리 ---
    if (_currentQuestion.needsEmpathy) {
      setState(() => _isBotThinking = true);
      try {
        // 다음 질문 텍스트를 미리 준비
        final nextQuestionId = _currentQuestion.nextQuestionId;
        final nextQuestionText =
            (nextQuestionId != null &&
                    _questionnaire.containsKey(nextQuestionId))
                ? _questionnaire[nextQuestionId]!.text
                : "";

        // ✅ [수정] 3가지 정보를 모두 전달하여 헬퍼 함수 호출
        final empathyResponse = await _getMythEmpathyResponse(
          _currentQuestion.text, // 이전 질문 (현재 질문)
          answer, // 사용자 답변
          nextQuestionText, // 다음 질문
        );
        _addBotMessage(empathyResponse);
      } catch (e) {
        _addBotMessage("이야기를 잘 듣고 있어요. 계속 들려주세요.");
      } finally {
        if (mounted) setState(() => _isBotThinking = false);
      }
      await Future.delayed(const Duration(milliseconds: 700));
    }

    // --- 각 질문 단계에 따른 특별 액션 및 흐름 제어 ---
    final currentQuestionId = _currentQuestion.id;

    void proceedToNextQuestion() {
      final nextQuestionId = _currentQuestion.nextQuestionId;
      if (nextQuestionId != null &&
          _questionnaire.containsKey(nextQuestionId)) {
        _currentQuestion = _questionnaire[nextQuestionId]!;
        _askQuestion(_currentQuestion);
      }
    }

    try {
      switch (currentQuestionId) {
        case 'ask_final_scene':
          setState(() => _isGeneratingSummary = true);
          final result = await FirebaseFunctions.instanceFor(
            region: 'asia-northeast3',
          ).httpsCallable('generateMythStory').call({'qnaData': _answers});
          _answers['full_story'] = result.data['fullStory'];
          _currentQuestion = Question(
            id: 'confirm_story',
            text:
                "${_questionnaire['confirm_story']!.text}\n\n\"${_answers['full_story']}\"",
            type: QuestionType.buttonSelection,
            options: _questionnaire['confirm_story']!.options,
            nextQuestionId: 'ask_title',
          );
          _askQuestion(_currentQuestion);
          break;

        case 'confirm_story':
          if (answer == '진행하기') {
            setState(() => _isBotThinking = true);
            final result = await FirebaseFunctions.instanceFor(
              region: 'asia-northeast3',
            ).httpsCallable('generateMythTitle').call({
              'fullStory': _answers['full_story'],
            });
            final List<String> suggestedTitles = List<String>.from(
              result.data['titles'] ?? [],
            );
            _currentQuestion = Question(
              id: 'ask_title',
              text: _questionnaire['ask_title']!.text,
              type: QuestionType.directInputButton,
              options: [...suggestedTitles, '직접입력'],
              nextQuestionId: 'ask_author_intro',
            );
            _askQuestion(_currentQuestion);
          } else if (answer == '수정하기') {
            final currentStory = _answers['full_story'] as String?;
            if (currentStory != null) {
              final newStory = await _showEditStoryDialog(currentStory);
              if (newStory != null && mounted) {
                setState(() {
                  _answers['full_story'] = newStory;
                  final lastBotMessageIndex = _messages.indexWhere(
                    (m) => m.type != MessageType.user,
                  );
                  if (lastBotMessageIndex != -1) {
                    final originalQuestion = _questionnaire['confirm_story']!;
                    _messages[lastBotMessageIndex] = ChatMessage(
                      text: "${originalQuestion.text}\n\n\"$newStory\"",
                      type: MessageType.bot,
                      questionId: originalQuestion.id,
                      options: originalQuestion.options,
                      onOptionSelected: (answer) => _handleAnswer(answer),
                    );
                  }
                });
              }
            }
          }
          break;

        case 'ask_title':
          _answers['title'] = answer;
          proceedToNextQuestion();
          break;

        case 'ask_author_intro':
          setState(() => _isBotThinking = true);
          final authorIntro = await _generateAuthorIntro(answer);
          _answers['author_intro'] = authorIntro;
          _addBotMessage("AI가 다음과 같은 저자 소개를 만들었어요:\n\n\"$authorIntro\"");
          proceedToNextQuestion();
          break;

        case 'final_confirm':
          if (answer == '나의 신화 만들기 시작') _submitMythBook();
          break;

        default:
          proceedToNextQuestion();
          break;
      }
    } catch (e) {
      _addBotMessage("오류가 발생했습니다: ${e.toString()}");
    } finally {
      if (mounted)
        setState(() {
          _isBotThinking = false;
          _isGeneratingSummary = false;
        });
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

  // ✅ [추가] 최종 제출 및 프로그레스 바 처리 함수 (toddler_book_page에서 가져와 수정)
  void _submitMythBook() async {
    setState(() {
      _isCreating = true;
      _progressValue = 0.0;
      _progressText = '당신의 신화를 엮을 준비를 하고 있어요...';
    });

    final callable = FirebaseFunctions.instanceFor(
      region: 'asia-northeast3',
    ).httpsCallable('processMythBook');
    final creationFuture = callable.call({'qnaData': _answers});

    try {
      await Future.delayed(const Duration(seconds: 1));
      setState(() {
        _progressValue = 0.5;
        _progressText = '이야기의 조각들을 모으고 있어요...';
      });
      await Future.delayed(const Duration(seconds: 10));

      setState(() {
        _progressValue = 0.7;
        _progressText = '장면에 맞는 이미지를 그리고 있어요...';
      });
      await Future.delayed(const Duration(seconds: 5));

      setState(() {
        _progressValue = 0.95;
        _progressText = '마지막으로 책을 엮고 있어요...';
      });

      await creationFuture; // 실제 서버 작업 완료 대기

      setState(() {
        _progressValue = 1.0;
        _progressText = '완성!';
      });
      await Future.delayed(const Duration(seconds: 1));

      if (mounted) {
        // TODO: myth_list_page.dart가 만들어지면 아래 코드를 활성화하세요.
        /*
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const MythListPage(),
          ),
        );
        */
        // 임시로 홈으로 이동
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류가 발생하여 생성을 중단했습니다: ${e.message}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  // ✅ [추가] 프로그레스 바 UI를 그리는 위젯 (toddler_book_page에서 가져옴)
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
                  Colors.deepPurple,
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
                  color: Colors.white.withOpacity(0.8),
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

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return Scaffold(
        appBar: AppBar(title: const Text('나의 신화 만들기')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    bool isTextInputEnabled =
        !_isCreating &&
        !_isBotThinking &&
        !_showDirectInputField &&
        !_isGeneratingSummary &&
        (_currentQuestion.type == QuestionType.shortText ||
            _currentQuestion.type == QuestionType.longText);

    String hintText = "버튼을 선택해주세요.";
    if (_isBotThinking || _isGeneratingSummary) {
      hintText = "잠시만 기다려주세요...";
    } else if (isTextInputEnabled) {
      hintText = "여기에 답변을 입력하세요...";
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text(
          '나의 신화 만들기',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
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
                  itemCount:
                      _messages.length +
                      (_isBotThinking ? 1 : 0) +
                      (_isGeneratingSummary ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_isGeneratingSummary && index == 0)
                      return _buildSummaryLoadingIndicator();
                    if (_isBotThinking && index == 0)
                      return _buildThinkingIndicator();
                    final messageIndex =
                        index -
                        (_isBotThinking ? 1 : 0) -
                        (_isGeneratingSummary ? 1 : 0);
                    return _buildChatMessage(_messages[messageIndex]);
                  },
                ),
              ),
              _buildMessageInput(isTextInputEnabled, hintText),
            ],
          ),
          if (_isCreating) _buildCreationProgress(),
        ],
      ),
    );
  }

  // ✅ [추가] '저자 소개' 생성 함수를 호출하는 헬퍼
  Future<String> _generateAuthorIntro(String keywords) async {
    final callable = FirebaseFunctions.instanceFor(
      region: 'asia-northeast3',
    ).httpsCallable('generateAuthorIntro');
    final result = await callable.call({'keywords': keywords});
    return result.data['authorIntro'] ?? '저자 소개 생성에 실패했습니다.';
  }

  // ✅ [추가] '신화' 전용 공감 함수를 호출하는 헬퍼 함수
  Future<String> _getMythEmpathyResponse(
    String previousQuestion,
    String userAnswer,
    String nextQuestion,
  ) async {
    final callable = FirebaseFunctions.instanceFor(
      region: 'asia-northeast3',
    ).httpsCallable('generateMythEmpathyResponse');

    final result = await callable.call({
      'previousQuestion': previousQuestion,
      'userAnswer': userAnswer,
      'nextQuestion': nextQuestion,
    });
    return result.data['empathyText'] ?? '그렇군요. 흥미로운 이야기네요.';
  }

  // ✅ [추가] 스토리 수정을 위한 다이얼로그를 띄우는 함수
  Future<String?> _showEditStoryDialog(String currentStory) async {
    final TextEditingController storyController = TextEditingController(
      text: currentStory,
    );

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('스토리 수정하기'),
          content: SizedBox(
            width: double.maxFinite,
            child: TextField(
              controller: storyController,
              maxLines: 10,
              autofocus: true,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(storyController.text);
              },
              child: const Text('저장'),
            ),
          ],
        );
      },
    );
  }

  // ✅ [추가] 이어쓰기/새로쓰기 로직을 처리하는 함수
  // Future<void> _loadOrStartNewMyth() async {
  //   final prefs = await SharedPreferences.getInstance();
  //   final savedData = prefs.getString('saved_myth');

  //   if (savedData != null && savedData.isNotEmpty) {
  //     final wantToResume = await _showResumeDialog();
  //     if (wantToResume && mounted) {
  //       final savedAnswers = Map<String, dynamic>.from(jsonDecode(savedData));
  //       _restoreMythState(savedAnswers);
  //     } else {
  //       await _clearSavedData();
  //       _initializeQuestions();
  //     }
  //   } else {
  //     _initializeQuestions();
  //   }

  //   if (mounted) {
  //     setState(() {
  //       _isInitializing = false;
  //     });
  //   }
  // }

  // // ✅ [추가] 이어쓰기 확인 다이얼로그
  // Future<bool> _showResumeDialog() async {
  //   final result = await showDialog<bool>(
  //     context: context,
  //     barrierDismissible: false,
  //     builder:
  //         (context) => AlertDialog(
  //           title: const Text('이어서 작성하시겠습니까?'),
  //           content: const Text('이전에 작성하던 신화 내용이 있습니다.'),
  //           actions: [
  //             TextButton(
  //               onPressed: () => Navigator.of(context).pop(false),
  //               child: const Text('새로 쓰기'),
  //             ),
  //             ElevatedButton(
  //               onPressed: () => Navigator.of(context).pop(true),
  //               child: const Text('이어 쓰기'),
  //             ),
  //           ],
  //         ),
  //   );
  //   return result ?? false;
  // }

  // // ✅ [추가] 저장된 상태를 복원하는 함수
  // void _restoreMythState(Map<String, dynamic> savedAnswers) {
  //   _initializeQuestions();

  //   setState(() {
  //     _messages.clear();
  //     _answers.addAll(savedAnswers);

  //     Question? lastAnsweredQuestion;
  //     List<ChatMessage> restoredMessages = [];

  //     // '신화 만들기'의 첫 질문부터 시작
  //     var tempQuestion = _questionnaire['ask_myth_type']!;

  //     while (savedAnswers.containsKey(tempQuestion.id)) {
  //       final questionId = tempQuestion.id;
  //       final answerText = savedAnswers[questionId]!;

  //       // 사용자 답변 말풍선 추가
  //       restoredMessages.insert(
  //         0,
  //         ChatMessage(
  //           text: answerText,
  //           type: MessageType.user,
  //           questionId: questionId,
  //         ),
  //       );
  //       // 봇 질문 말풍선 추가
  //       restoredMessages.insert(
  //         0,
  //         ChatMessage(
  //           text: tempQuestion.text,
  //           type: MessageType.bot,
  //           questionId: questionId,
  //           options: tempQuestion.options,
  //           onOptionSelected: (answer) => _handleAnswer(answer),
  //         ),
  //       );

  //       lastAnsweredQuestion = tempQuestion;

  //       final String? nextId = tempQuestion.nextQuestionId;
  //       if (nextId == null || !_questionnaire.containsKey(nextId)) {
  //         break;
  //       }
  //       tempQuestion = _questionnaire[nextId]!;
  //     }

  //     _messages.addAll(restoredMessages);

  //     // 마지막으로 답변했던 질문의 다음 질문을 다시 물어봄
  //     if (lastAnsweredQuestion != null) {
  //       final nextId = lastAnsweredQuestion.nextQuestionId;
  //       if (nextId != null && _questionnaire.containsKey(nextId)) {
  //         _currentQuestion = _questionnaire[nextId]!;
  //         _askQuestion(_currentQuestion);
  //       }
  //     }
  //   });
  // }

  // ✅ [추가] 진행 상황을 저장하는 함수
  Future<void> _saveProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_myth', jsonEncode(_answers));
  }

  // // ✅ [추가] 저장된 데이터를 삭제하는 함수
  // Future<void> _clearSavedData() async {
  //   final prefs = await SharedPreferences.getInstance();
  //   await prefs.remove('saved_myth');
  // }

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
                // 버튼을 누르면 하단 시트가 올라옵니다.
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
                        mainAxisSize: MainAxisSize.min, // content 크기에 맞게 높이 조절
                        children: <Widget>[
                          ListTile(
                            leading: const Icon(Icons.audiotrack_outlined),
                            title: const Text('음성 파일 업로드'),
                            onTap: () {
                              Navigator.pop(context); // 하단 시트 닫기
                              _showComingSoonDialog(); // 준비 중 알림창 띄우기
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.photo_camera_outlined),
                            title: const Text('사진 업로드'),
                            onTap: () {
                              Navigator.pop(context); // 하단 시트 닫기
                              _showComingSoonDialog(); // 준비 중 알림창 띄우기
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
              icon: Icon(
                Icons.mic,
                color: const Color.fromRGBO(117, 117, 117, 1),
              ),
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
                    hintText: hintText,
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  enabled: isEnabled,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap:
                  isEnabled ? () => _handleAnswer(_textController.text) : null,
              child: CircleAvatar(
                radius: 20,
                backgroundColor:
                    isEnabled ? Colors.deepPurple : Colors.grey.shade300,
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

  Widget _buildSummaryLoadingIndicator() {
    return _buildBotMessageContainer(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '동화책 내용을 빠르게 생성하고 있어요',
            style: TextStyle(fontSize: 16, color: Colors.black87),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: const LinearProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              backgroundColor: Colors.black12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThinkingIndicator() {
    return _buildBotMessageContainer(
      const Text(
        'AI가 답변을 읽고 있어요...',
        style: TextStyle(fontStyle: FontStyle.italic, color: Colors.black54),
      ),
    );
  }

  // 메시지 종류에 따라 아바타와 말풍선을 조합하는 최상위 위젯
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
          CircleAvatar(backgroundColor: Colors.grey.shade400),
          const SizedBox(width: 8),
          Flexible(child: _buildMessageBubble(message)),
        ],
      );
    }
  }

  // 봇 메시지 컨테이너를 위한 래퍼 위젯
  Widget _buildBotMessageContainer(Widget child) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(backgroundColor: Colors.grey.shade400),
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

  Widget _buildMessageBubble(ChatMessage message) {
    Color bubbleColor;
    Color textColor;
    switch (message.type) {
      case MessageType.user:
        bubbleColor = Colors.deepPurple; // '신화' 테마 색상
        textColor = Colors.white;
        break;
      case MessageType.botExample:
        bubbleColor = Colors.yellow.shade100;
        textColor = Colors.black87;
        break;
      default:
        bubbleColor = Colors.grey.shade200;
        textColor = Colors.black87;
        break;
    }

    final isUser = message.type == MessageType.user;
    final question = !isUser ? _questionnaire[message.questionId] : null;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
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
          if (question != null && question.exampleText != null)
            Padding(
              padding: const EdgeInsets.only(top: 10.0),
              child: InkWell(
                onTap:
                    () => _addBotMessage(
                      "예시:\n${question.exampleText!}",
                      type: MessageType.botExample,
                    ),
                child: Text(
                  '예시보기',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade800,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          // ✅ [수정] 버튼을 그리는 부분에 '구성요소' 질문 조건 추가
          if (message.options != null &&
              message.options!.isNotEmpty &&
              !_answers.containsKey(message.questionId)) ...[
            const SizedBox(height: 12),
            if (message.questionId == 'ask_plot_elements')
              _buildPlotSelectionUI(message)
            // ✅ [추가] '구성요소' 질문일 때도 복수 선택 UI를 호출
            else if (message.questionId == 'ask_composition_elements')
              _buildCompositionSelectionUI(message)
            else
              _buildOptionButtons(message),
          ],
          if (_showDirectInputField &&
              (message.questionId == 'ask_theme' ||
                  message.questionId == 'ask_title'))
            _buildDirectInputWidget(
              _directInputController,
              message.questionId == 'ask_theme'
                  ? '원하는 주제를 입력...'
                  : '원하는 제목을 입력...',
            ),
        ],
      ),
    );
  }

  Widget _buildCompositionSelectionUI(ChatMessage message) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          children:
              message.options!.map((option) {
                final isSelected = _selectedCompositionElements.contains(
                  option,
                );
                return OutlinedButton(
                  onPressed: () {
                    setState(() {
                      if (isSelected) {
                        _selectedCompositionElements.remove(option);
                      } else {
                        _selectedCompositionElements.add(option);
                      }
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                        isSelected ? Colors.white : Colors.deepPurple,
                    backgroundColor:
                        isSelected ? Colors.deepPurple : Colors.transparent,
                    side: const BorderSide(color: Colors.deepPurple),
                    shape: const StadiumBorder(),
                  ),
                  child: Text(option),
                );
              }).toList(),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () {
            if (_selectedCompositionElements.isNotEmpty) {
              final combined = _selectedCompositionElements.join(', ');
              _answers['ask_composition_elements'] = combined;
              _selectedCompositionElements.clear();
              // ✅ '선택 완료' 버튼만이 _handleAnswer를 호출하여 다음 질문으로 넘어갑니다.
              _handleAnswer(combined);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
          ),
          child: const Text('선택 완료'),
        ),
      ],
    );
  }

  Widget _buildPlotSelectionUI(ChatMessage message) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          children:
              message.options!.map((option) {
                final isSelected = _selectedPlotElements.contains(option);
                return OutlinedButton(
                  // ✅ [수정] 개별 버튼은 이제 _handleAnswer를 호출하지 않고,
                  // 오직 setState를 통해 화면의 선택/해제 상태만 변경합니다.
                  onPressed: () {
                    setState(() {
                      if (isSelected) {
                        _selectedPlotElements.remove(option);
                      } else {
                        _selectedPlotElements.add(option);
                      }
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                        isSelected ? Colors.white : Colors.deepPurple,
                    backgroundColor:
                        isSelected ? Colors.deepPurple : Colors.transparent,
                    side: const BorderSide(color: Colors.deepPurple),
                    shape: const StadiumBorder(),
                  ),
                  child: Text(option),
                );
              }).toList(),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () {
            if (_selectedPlotElements.isNotEmpty) {
              final combined = _selectedPlotElements.join(', ');
              _answers['ask_plot_elements'] = combined;
              _selectedPlotElements.clear();
              // ✅ '선택 완료' 버튼만이 _handleAnswer를 호출하여 다음 질문으로 넘어갑니다.
              _handleAnswer(combined);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
          ),
          child: const Text('선택 완료'),
        ),
      ],
    );
  }

  // 일반 버튼 선택 UI
  Widget _buildOptionButtons(ChatMessage message) {
    return Wrap(
      spacing: 8.0,
      runSpacing: 8.0,
      children:
          message.options!.map((option) {
            return OutlinedButton(
              onPressed: () => _handleAnswer(option),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blue,
                side: const BorderSide(color: Colors.blue),
                shape: const StadiumBorder(),
              ),
              child: Text(option),
            );
          }).toList(),
    );
  }

  // 직접 입력 UI (말풍선 내)
  Widget _buildDirectInputWidget(
    TextEditingController controller,
    String hintText,
  ) {
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
                  controller: controller,
                  decoration: InputDecoration.collapsed(hintText: hintText),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (text) => _handleAnswer(text),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send, color: Colors.blue),
                onPressed: () => _handleAnswer(controller.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
