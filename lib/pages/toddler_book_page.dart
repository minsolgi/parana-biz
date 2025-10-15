import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'toddler_book_list_page.dart';
import 'dart:convert';

// ✅ 아래 모델 및 Enum 클래스들은 기능 로직이므로 전혀 수정되지 않았습니다.
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

enum MessageType { user, bot, botExample }

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

class ToddlerBookPage extends StatefulWidget {
  final Map<String, dynamic> userProfile;
  // 2. 생성자 이름도 함께 변경
  const ToddlerBookPage({super.key, required this.userProfile});

  @override
  // 3. State 클래스 이름도 변경
  State<ToddlerBookPage> createState() => _ToddlerBookPageState();
}

class _ToddlerBookPageState extends State<ToddlerBookPage> {
  // ✅ 상태 관리, 컨트롤러, 비즈니스 로직 관련 변수들은 전혀 수정되지 않았습니다.
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late final Map<String, Question> _questionnaire;
  late Question _currentQuestion;

  final Map<String, dynamic> _answers = {};
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isBotThinking = false;
  double _progressValue = 0.0; // 0.0 ~ 1.0 사이의 값
  String _progressText = '';

  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  String _recognizedWords = '';
  bool _isListening = false;
  Timer? _speechTimer;

  bool _showDirectInputField = false;
  final TextEditingController _directInputController = TextEditingController();
  // bool _showDirectStyleInputField = false;
  final TextEditingController _directStyleInputController =
      TextEditingController();
  bool _isGeneratingSummary = false;
  bool _isInitializing = true;

  final Set<String> _selectedPurposes = {};

  // ✅ initState, dispose 및 모든 기능 함수들은 전혀 수정되지 않았습니다.
  @override
  void initState() {
    super.initState();
    // ✅ [수정] _initializeQuestions() 대신 아래 함수를 호출합니다.
    _loadOrStartNewToddlerBook();
    _initSpeech();
  }

  // ✅ [신규 추가] 저장된 회고록 데이터를 불러오거나 새로 시작하는 함수
  Future<void> _loadOrStartNewToddlerBook() async {
    // 함수 이름 변경
    final prefs = await SharedPreferences.getInstance();
    final savedData = prefs.getString('saved_toddler_book');

    if (savedData != null && savedData.isNotEmpty) {
      final wantToResume = await _showResumeDialog();
      if (wantToResume) {
        final savedAnswers = Map<String, dynamic>.from(jsonDecode(savedData));
        _restoreToddlerBookState(savedAnswers);
      } else {
        await _clearSavedData();
        _initializeQuestions();
      }
    } else {
      _initializeQuestions();
    }

    if (mounted) {
      setState(() {
        _isInitializing = false;
      });
    }
  }

  Future<String?> _showEditStoryDialog(String currentStory) async {
    // TextField를 제어하기 위한 컨트롤러
    final TextEditingController storyController = TextEditingController(
      text: currentStory,
    );

    return showDialog<String>(
      context: context,
      barrierDismissible: false, // 바깥 영역을 눌러도 닫히지 않게 설정
      builder: (context) {
        return AlertDialog(
          title: const Text('스토리 수정하기'),
          // TextField가 너무 커지는 것을 방지하기 위해 SizedBox로 감싸기
          content: SizedBox(
            width: double.maxFinite,
            child: TextField(
              controller: storyController,
              maxLines: 10, // 여러 줄 입력 가능
              autofocus: true, // 다이얼로그가 뜨면 바로 키보드 활성화
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(), // 아무것도 반환하지 않고 닫기
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () {
                // 수정된 텍스트를 반환하며 닫기
                Navigator.of(context).pop(storyController.text);
              },
              child: const Text('저장'),
            ),
          ],
        );
      },
    );
  }

  // ✅ [신규 추가] '이어쓰기/새로쓰기' 선택 다이얼로그
  Future<bool> _showResumeDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: const Text('이어서 작성하시겠습니까?'),
            content: const Text('이전에 작성하던 그림책 내용이 있습니다.'),
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

  void _showComingSoonDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('알림'),
            content: const Text('준비 중 입니다.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('확인'),
              ),
            ],
          ),
    );
  }

  void _initializeQuestions() {
    // ✅ [수정] 새로운 질문지로 전체 교체
    _questionnaire = {
      'start_toddler': Question(
        id: 'start_toddler',
        text: '안녕하세요! 먼저 본인의 정보를 선택해주세요.',
        type: QuestionType.buttonSelection,
        options: ['교사', '아동', '일반 사용자', '한국어 학습'],
        nextQuestionId: 'ask_reason',
      ),
      'ask_reason': Question(
        id: 'ask_reason',
        text: '그림동화책을 생성하게 된 계기를 알려주세요.',
        type: QuestionType.longText,
        needsEmpathy: true,
        nextQuestionId: 'ask_theme',
        exampleText:
            '예시1) 손주와 함께 시간을 보내고 싶어서\n예시2) 아이들의 이야기를 그려주고 싶어서\n예시3) 한국어 공부에 도움을 받고 싶어서',
      ),
      'ask_theme': Question(
        id: 'ask_theme',
        text: '어떤 주제를 그림책에 담고 싶으신가요?',
        type: QuestionType.directInputButton, // 직접 입력 버튼 타입
        options: [
          '소중한 나',
          '가족',
          '우리 동네 모습',
          '자연과 더불어 살기',
          '내가 만난 친구',
          '교통 생활',
          '다양한 놀이',
          '도구',
          '환경과 자연',
          '대화(말, 언어)',
          '건강(나의 몸, 마음)',
          '직접입력',
        ],
        needsEmpathy: true,
        nextQuestionId: 'ask_purpose',
      ),
      'ask_purpose': Question(
        id: 'ask_purpose',
        text: '그림책에 어떤 가치를 담고 싶으신가요? (여러 개 선택 가능)',
        type: QuestionType.buttonSelection,
        needsEmpathy: true,
        options: ['배려', '존중', '효도', '질서', '협력', '나눔', '공존'],
        nextQuestionId: 'ask_characters_in_book',
      ),
      'ask_characters_in_book': Question(
        id: 'ask_characters_in_book',
        text: '그림책의 주인공에 대하여 상세하게 알려주시겠어요?',
        type: QuestionType.longText,
        needsEmpathy: true,
        nextQuestionId: 'ask_background',
        exampleText:
            'Tip! 이름, 나이, 성별, 성격, 특징 등을 자세히 작성해주시면 결과가 잘 나와요.\n\n예시1) 이름은 꽁이에요. 검정색과 흰색이 섞여있는 새끼고양이. 밤마다 울곤해요. 엄마랑 형제들이랑 헤어진지 3일 되었어요.\n예시2) 이름은 경민이, 남자에요. 초등학생 2학년이고 대한민국 금산에 살아요. 축구를 좋아하고 개구쟁이라는 별명이 있어요.',
      ),
      'ask_background': Question(
        id: 'ask_background',
        text: '배경정보를 상세하게 입력하시면 원하시는 그림책에 가까워질거에요.',
        type: QuestionType.longText,
        nextQuestionId: 'ask_hardship',
        exampleText:
            '예시) 봄바람이 차가운 3월에 캐나다에 사는 용이 이모와 동생들이 대전 우리집에 왔어요. 이모부는 외국인인데 한국말을 참 잘하세요. 동생들과 국립과학관에 갈 준비를 하고 있었어요.',
      ),
      'ask_hardship': Question(
        id: 'ask_hardship',
        text: '그림책의 내용에 모험과 갈등을 포함한 고난이나 역경의 내용을 포함하도록 할까요?',
        type: QuestionType.buttonSelection,
        options: ['Yes', 'No'],
        nextQuestionId: 'confirm_story',
      ),
      'confirm_story': Question(
        id: 'confirm_story',
        text: '상상하신 그림책 줄거리를 만들어 보았어요. 이대로 생성을 진행할까요?',
        type: QuestionType.buttonSelection,
        options: ['진행하기', '수정하기'],
        nextQuestionId: 'ask_style',
      ),
      'ask_style': Question(
        id: 'ask_style',
        text: '이미지의 그림체는 어떻게 하시겠어요?',
        type: QuestionType.buttonSelection,
        options: [
          '유아용 동화책',
          '마블 애니메이션',
          '지브리 애니메이션',
          '전래동화풍',
          '안데르센풍',
          '앤서니 브라운풍',
          '이중섭풍',
          '박수근풍',
        ],
        nextQuestionId: 'ask_title',
      ),
      'ask_title': Question(
        id: 'ask_title',
        text: 'AI가 추천한 제목이에요. 마음에 드시나요?', // 동적으로 변경될 텍스트
        type: QuestionType.directInputButton, // 직접 입력 허용
        options: ['이 제목으로 할게요', '직접입력'],
        nextQuestionId: 'final_confirm',
      ),
      'final_confirm': Question(
        id: 'final_confirm',
        text: '이제 그림책을 생성해볼게요! ...',
        type: QuestionType.buttonSelection,
        options: ['그림책 생성 시작'],
      ),
    };
    _currentQuestion = _questionnaire['start_toddler']!;
    _askQuestion(_currentQuestion);
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _directInputController.dispose();
    _directStyleInputController.dispose();
    _speechToText.stop();
    _speechTimer?.cancel();
    super.dispose();
  }

  void _initSpeech() async {
    try {
      _speechEnabled = await _speechToText.initialize();
    } catch (e) {
      _speechEnabled = false;
    }
    if (mounted) {
      setState(() {});
    }
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

  void _askQuestion(Question question) {
    setState(() {
      _messages.insert(
        0,
        ChatMessage(
          text: question.text,
          type: MessageType.bot,
          questionId: question.id,
          options: question.options,
          onOptionSelected: (answer) => _handleAnswer(answer),
        ),
      );
    });
    _scrollToBottom();
  }

  // ✅ [신규 추가] 저장된 답변으로 회고록 상태를 복원하는 함수
  void _restoreToddlerBookState(Map<String, dynamic> savedAnswers) {
    _initializeQuestions();

    setState(() {
      _messages.clear();
      _answers.addAll(savedAnswers);

      Question? lastAnsweredQuestion;
      List<ChatMessage> restoredMessages = [];

      var tempQuestion = _questionnaire['start_toddler']!;
      while (true) {
        final questionId = tempQuestion.id;

        if (savedAnswers.containsKey(questionId)) {
          final answerText = savedAnswers[questionId]!;

          // ✅ [수정] insert(0, ...)를 사용하여 올바른 순서로 복원합니다.
          restoredMessages.insert(
            0,
            ChatMessage(
              text: answerText,
              type: MessageType.user,
              questionId: questionId,
            ),
          );
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

          String? nextId =
              tempQuestion.nextQuestionIds != null
                  ? tempQuestion.nextQuestionIds![answerText]
                  : tempQuestion.nextQuestionId;

          if (nextId == null || !_questionnaire.containsKey(nextId)) {
            break;
          }
          tempQuestion = _questionnaire[nextId]!;
        } else {
          break;
        }
      }

      _messages.addAll(restoredMessages);

      if (lastAnsweredQuestion != null) {
        String? nextId =
            lastAnsweredQuestion.nextQuestionIds != null
                ? lastAnsweredQuestion
                    .nextQuestionIds![_answers[lastAnsweredQuestion.id]]
                : lastAnsweredQuestion.nextQuestionId;

        if (nextId != null && _questionnaire.containsKey(nextId)) {
          _currentQuestion = _questionnaire[nextId]!;
          _askQuestion(_currentQuestion);
        } else {
          // 모든 질문에 답변한 상태
        }
      }
    });
  }

  // toddler_book_page.dart 의 _ToddlerBookPageState 내부

  // toddler_book_page.dart

  void _handleAnswer(String answer) async {
    if (_currentQuestion.id == 'start_toddler' &&
        (answer == '아동' || answer == '한국어 학습')) {
      _showComingSoonDialog();
      return;
    }

    // '직접입력' 버튼은 사용자 입력을 기다립니다.
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

    // ✅ [핵심 수정] '수정하기' 로직과 일반 답변 로직을 분리하여 처리합니다.
    if (_currentQuestion.id == 'confirm_story' && answer == '수정하기') {
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

          // 수정 완료 후에는 다시 '진행하기'/'수정하기' 버튼을 보여주며 대기합니다.
          // 바로 다음으로 넘어가려면 아래 주석 처리된 코드를 활성화하세요.
          /*
        final nextQuestionId = _currentQuestion.nextQuestionId;
        if (nextQuestionId != null && _questionnaire.containsKey(nextQuestionId)) {
          _currentQuestion = _questionnaire[nextQuestionId]!;
          _askQuestion(_currentQuestion);
        }
        */
        }
      }
      return; // '수정하기' 버튼 자체에 대한 처리는 여기서 종료
    }

    if (answer.trim().isEmpty &&
        _currentQuestion.type != QuestionType.buttonSelection)
      return;

    // 모든 사용자 답변은 UI에 추가되고 저장됩니다.
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

    // 8번 질문 - 전체 스토리 생성 단계
    if (_currentQuestion.id == 'ask_hardship') {
      setState(() => _isGeneratingSummary = true);
      try {
        final callable = FirebaseFunctions.instanceFor(
          region: 'asia-northeast3',
        ).httpsCallable('generateToddlerBookSummary');
        final result = await callable.call({'qnaData': _answers});
        final String fullStory = result.data['summary'];

        setState(() => _isGeneratingSummary = false);
        _answers['full_story'] = fullStory;

        final originalQuestion = _questionnaire['confirm_story']!;
        final confirmationQuestion = Question(
          id: originalQuestion.id,
          text: "${originalQuestion.text}\n\n\"$fullStory\"",
          type: originalQuestion.type,
          options: originalQuestion.options,
          nextQuestionId: originalQuestion.nextQuestionId,
        );
        _currentQuestion = confirmationQuestion;
        _askQuestion(_currentQuestion);
      } catch (e) {
        setState(() => _isGeneratingSummary = false);
        _addBotMessage("죄송합니다. 스토리 생성에 실패했습니다.");
      }
      return;
    }
    if (_currentQuestion.id == 'ask_style') {
      setState(() => _isBotThinking = true); // 로딩 인디케이터 표시
      try {
        final callable = FirebaseFunctions.instanceFor(
          region: 'asia-northeast3',
        ).httpsCallable('generateBookTitle');
        final result = await callable.call({
          'fullStory': _answers['full_story'],
        });
        final String suggestedTitle = result.data['title'];

        setState(() => _isBotThinking = false);
        _answers['title'] = suggestedTitle; // 추천 제목을 우선 저장

        // AI가 추천한 제목을 포함하여 질문을 던짐
        final titleQuestion = _questionnaire['ask_title']!;
        _currentQuestion = Question(
          id: titleQuestion.id,
          text: "${titleQuestion.text}\n\n\"$suggestedTitle\"",
          type: titleQuestion.type,
          options: titleQuestion.options,
          nextQuestionId: titleQuestion.nextQuestionId,
        );
        _askQuestion(_currentQuestion);
      } catch (e) {
        setState(() => _isBotThinking = false);
        _addBotMessage("죄송합니다. 제목 추천에 실패했습니다. 직접 입력해주세요.");
        // 실패 시에도 직접 입력할 수 있도록 다음 질문으로 넘어감
        _currentQuestion = _questionnaire['ask_title']!;
        _askQuestion(_currentQuestion);
      }
      return; // 여기서 함수 종료
    }

    if (_currentQuestion.needsEmpathy) {
      setState(() => _isBotThinking = true);
      final empathyResponse = await _getEmpathyResponse(answer);
      setState(() => _isBotThinking = false);
      if (empathyResponse.isNotEmpty) _addBotMessage(empathyResponse);
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // ✅ [추가] '제목 선택' 질문에 대한 답변을 'title' 키에 저장하는 로직
    if (_currentQuestion.id == 'ask_title') {
      if (answer != '이 제목으로 할게요') {
        _answers['title'] = answer;
      }
    }

    if (answer == '그림책 생성 시작') {
      _submitToddlerBook(_answers, _answers['full_story'] as String?);
      return;
    }

    // 다음 질문으로 이동
    final String? nextQuestionId = _currentQuestion.nextQuestionId;
    if (nextQuestionId != null && _questionnaire.containsKey(nextQuestionId)) {
      _currentQuestion = _questionnaire[nextQuestionId]!;
      _askQuestion(_currentQuestion);
    }
  }

  // ✅ [신규 추가] 진행 상황을 저장하는 함수
  Future<void> _saveProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_toddler_book', jsonEncode(_answers));
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

  Future<String> _getEmpathyResponse(String userAnswer) async {
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-northeast3',
      ).httpsCallable('generateEmpathyResponse');
      final result = await callable.call({'userAnswer': userAnswer});
      return result.data['empathyText'] ?? '그렇군요.';
    } catch (e) {
      return '이야기를 잘 듣고 있어요. 계속 들려주세요.';
    }
  }

  // ... _ToddlerBookPageState 클래스 내부의 다른 함수들 아래에 추가 ...

  // // ✅ [신규 추가] 그림동화책 스토리 요약을 요청하는 함수
  // Future<String> _getToddlerBookSummary(String storyText) async {
  //   if (storyText.trim().isEmpty) {
  //     return "요약할 내용이 없어요.";
  //   }
  //   try {
  //     // 👇 'generateToddlerBookSummary' 라는 이름의 새 백엔드 함수 호출
  //     final callable = FirebaseFunctions.instanceFor(
  //       region: 'asia-northeast3',
  //     ).httpsCallable('generateToddlerBookSummary');
  //     final result = await callable.call({'storyText': storyText});
  //     return result.data['summary'] ?? "요약 생성에 실패했습니다.";
  //   } catch (e) {
  //     return "요약 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.";
  //   }
  // }

  void _submitToddlerBook(
    Map<String, dynamic> qnaData,
    String? fullStory,
  ) async {
    // 1. 생성 시작 및 초기 상태 설정
    setState(() {
      _isLoading = true;
      _progressValue = 0.0;
      _progressText = '그림책 생성을 준비하고 있어요...';
    });

    // 실제 서버 요청을 백그라운드에서 미리 시작
    final callable = FirebaseFunctions.instanceFor(
      region: 'asia-northeast3',
    ).httpsCallable('processToddlerBook');
    final creationFuture = callable.call({
      'qnaData': qnaData,
      'fullStory': fullStory,
    });

    try {
      // 2. 연출된 프로그레스 바 애니메이션
      await Future.delayed(const Duration(seconds: 1));
      setState(() {
        _progressValue = 0.5;
        _progressText = '이야기를 구성하고 있어요...';
      });
      await Future.delayed(const Duration(seconds: 10));

      setState(() {
        _progressValue = 0.7;
        _progressText = '장면에 어울리는 그림을 그리고 있어요... (1/4)';
      });
      await Future.delayed(const Duration(seconds: 5));

      setState(() {
        _progressValue = 0.9;
        _progressText = '멋진 그림을 완성하고 있어요... (2/4)';
      });
      await Future.delayed(const Duration(seconds: 5));

      setState(() {
        _progressValue = 0.95;
        _progressText = '마지막으로 책을 엮고 있어요... (3/4)';
      });

      // 3. 실제 서버 요청이 완료될 때까지 대기
      await creationFuture;

      // 4. 완료 처리 및 페이지 이동
      setState(() {
        _progressValue = 1.0;
        _progressText = '완성! (4/4)';
      });
      await Future.delayed(const Duration(seconds: 1));
      await _clearSavedData();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const ToddlerBookListPage()),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        // 에러 발생 시 생성 중단 및 이전 화면으로 복귀
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류가 발생하여 생성을 중단했습니다: ${e.message}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _clearSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_toddler_book');
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

  // == 🚀 UI 부분만 디자인에 맞게 전면 수정되었습니다 ==
  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return Scaffold(
        appBar: AppBar(title: const Text('AI 그림동화책 만들기')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    bool isTextInputEnabled =
        !_isLoading &&
        !_isBotThinking &&
        !_showDirectInputField &&
        !_isGeneratingSummary &&
        (_currentQuestion.type == QuestionType.shortText ||
            _currentQuestion.type == QuestionType.longText);

    String hintText = "버튼을 선택해주세요.";
    if (_isBotThinking || _isGeneratingSummary) {
      hintText = "잠시만 기다려주세요...";
    } else if (isTextInputEnabled) {
      hintText = "여기에 입력하세요...";
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text(
          'AI 그림동화책 만들기',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        centerTitle: true,
        elevation: 0.5,
      ),
      body: Stack(
        children: [
          // 1. 배경 이미지
          SizedBox.expand(
            child: Opacity(
              opacity: 0.3,
              child: Image.asset(
                'assets/toddler_backG.png',
                width: MediaQuery.of(context).size.width,
                fit: BoxFit.cover,
              ),
            ),
          ),

          // 2. 채팅 UI와 프로그레스 바 UI
          SafeArea(
            child: Column(
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
                      if (_isGeneratingSummary && index == 0) {
                        return _buildSummaryLoadingIndicator();
                      }
                      if (_isBotThinking && index == 0) {
                        return _buildThinkingIndicator();
                      }
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
          ),

          // 3. 프로그레스 바 (채팅 UI 위에 겹쳐짐)
          if (_isLoading) _buildCreationProgress(),
        ],
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
                    isEnabled
                        ? const Color.fromARGB(255, 255, 142, 0)
                        : Colors.grey.shade300,
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

  // 새롭게 디자인된 인디케이터
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
        bubbleColor = const Color.fromARGB(255, 255, 162, 0);
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

    final bool isUser = message.type == MessageType.user;
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
          if (message.options != null &&
              message.options!.isNotEmpty &&
              !_answers.containsKey(message.questionId)) ...[
            const SizedBox(height: 12),
            if (message.questionId == 'ask_purpose')
              _buildPurposeSelectionUI(message)
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

  Widget _buildPurposeSelectionUI(ChatMessage message) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          children:
              message.options!.map((option) {
                final isSelected = _selectedPurposes.contains(option);
                return OutlinedButton(
                  onPressed: () {
                    // ✅ '선택 완료'와 분리: 이 버튼들은 오직 화면의 선택 상태만 변경합니다.
                    setState(() {
                      if (isSelected) {
                        _selectedPurposes.remove(option);
                      } else {
                        _selectedPurposes.add(option);
                      }
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isSelected ? Colors.white : Colors.blue,
                    backgroundColor:
                        isSelected ? Colors.blue : Colors.transparent,
                    side: const BorderSide(color: Colors.blue),
                    shape: const StadiumBorder(),
                  ),
                  child: Text(option),
                );
              }).toList(),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () {
            if (_selectedPurposes.isNotEmpty) {
              final String combinedPurposes = _selectedPurposes.join(', ');
              // ✅ '선택 완료' 버튼만이 _handleAnswer를 호출하여 다음으로 넘어갑니다.
              _handleAnswer(combinedPurposes);
              _selectedPurposes.clear();
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF318FFF),
            foregroundColor: Colors.white,
          ),
          child: const Text('선택 완료'),
        ),
      ],
    );
  }

  // ✅ [추가] 프로그레스 바 오버레이 UI를 만드는 함수
  Widget _buildCreationProgress() {
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 1. 프로그레스 바
              LinearProgressIndicator(
                value: _progressValue,
                backgroundColor: Colors.white.withOpacity(0.3),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                minHeight: 10,
                borderRadius: BorderRadius.circular(5),
              ),
              const SizedBox(height: 20),
              // 2. 퍼센테이지 텍스트
              Text(
                '${(_progressValue * 100).toInt()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              // 3. 상태 메시지 텍스트
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

  // 일반 버튼 선택 UI
  Widget _buildOptionButtons(ChatMessage message) {
    return Wrap(
      spacing: 8.0,
      runSpacing: 8.0,
      children:
          message.options!.map((option) {
            // ✅ [수정] onOptionSelected를 직접 호출하는 대신 _handleAnswer를 사용합니다.
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

  // 그림체 선택 UI (가로 스크롤)
  // qna_page.dart

  // Widget _buildStyleSelection(ChatMessage message) {
  //   final imagePathMap = {
  //     '사실적': 'assets/realistic.png',
  //     '스케치': 'assets/sketch.png',
  //     '수채화': 'assets/watercolor.png',
  //     '유채화': 'assets/oil_painting.png',
  //     '애니메이션풍': 'assets/animation.png',
  //     '디즈니풍': 'assets/disney.png',
  //   };

  //   return SizedBox(
  //     height: 120,
  //     child: ListView.separated(
  //       scrollDirection: Axis.horizontal,
  //       itemCount: message.options!.length,
  //       itemBuilder: (context, index) {
  //         final option = message.options![index];
  //         final imagePath = imagePathMap[option];

  //         return GestureDetector(
  //           onTap: () => message.onOptionSelected?.call(option),
  //           child: Container(
  //             width: 100,
  //             decoration: BoxDecoration(
  //               border: Border.all(color: Colors.blue),
  //               borderRadius: BorderRadius.circular(12),
  //             ),
  //             child: Column(
  //               children: [
  //                 Expanded(
  //                   child: Container(
  //                     margin: const EdgeInsets.all(4),
  //                     child: ClipRRect(
  //                       borderRadius: BorderRadius.circular(8),
  //                       child:
  //                           imagePath != null
  //                               ? Image.asset(
  //                                 imagePath,
  //                                 fit: BoxFit.cover,
  //                                 errorBuilder:
  //                                     (context, error, stackTrace) => Container(
  //                                       color: Colors.grey.shade300,
  //                                     ),
  //                               )
  //                               : Container(color: Colors.grey.shade300),
  //                     ),
  //                   ),
  //                 ),
  //                 Padding(
  //                   padding: const EdgeInsets.symmetric(vertical: 8.0),
  //                   child: Text(
  //                     option,
  //                     style: const TextStyle(color: Colors.black),
  //                   ),
  //                 ),
  //               ],
  //             ),
  //           ),
  //         );
  //       },
  //       separatorBuilder: (context, index) => const SizedBox(width: 10),
  //     ),
  //   );
  // }

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
