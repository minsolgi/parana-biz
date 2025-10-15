import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

class QnAPage extends StatefulWidget {
  final Map<String, dynamic> userProfile;
  const QnAPage({super.key, required this.userProfile});

  @override
  State<QnAPage> createState() => _QnAPageState();
}

class _QnAPageState extends State<QnAPage> {
  // ✅ 상태 관리, 컨트롤러, 비즈니스 로직 관련 변수들은 전혀 수정되지 않았습니다.
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late final Map<String, Question> _questionnaire;
  late Question _currentQuestion;

  final Map<String, dynamic> _answers = {};
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isBotThinking = false;

  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  String _recognizedWords = '';
  bool _isListening = false;
  Timer? _speechTimer;

  bool _showDirectInputField = false;
  final TextEditingController _directInputController = TextEditingController();
  bool _showDirectStyleInputField = false;
  final TextEditingController _directStyleInputController =
      TextEditingController();
  bool _isGeneratingSummary = false;
  bool _isInitializing = true;

  // ✅ initState, dispose 및 모든 기능 함수들은 전혀 수정되지 않았습니다.
  @override
  void initState() {
    super.initState();
    // ✅ [수정] _initializeQuestions() 대신 아래 함수를 호출합니다.
    _loadOrStartNewMemoir();
    _initSpeech();
  }

  // ✅ [신규 추가] 저장된 회고록 데이터를 불러오거나 새로 시작하는 함수
  Future<void> _loadOrStartNewMemoir() async {
    final prefs = await SharedPreferences.getInstance();
    // ✅ 회고록은 'saved_memoir'라는 키로 저장합니다.
    final savedData = prefs.getString('saved_memoir');

    if (savedData != null && savedData.isNotEmpty) {
      // 저장된 내용이 있으면 사용자에게 물어봅니다.
      final wantToResume = await _showResumeDialog();
      if (wantToResume) {
        final savedAnswers = Map<String, dynamic>.from(jsonDecode(savedData));
        _restoreMemoirState(savedAnswers);
      } else {
        await _clearSavedData();
        _initializeQuestions();
      }
    } else {
      // 저장된 내용이 없으면 그냥 새로 시작합니다.
      _initializeQuestions();
    }

    if (mounted) {
      setState(() {
        _isInitializing = false;
      });
    }
  }

  // ✅ [신규 추가] '이어쓰기/새로쓰기' 선택 다이얼로그
  Future<bool> _showResumeDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: const Text('이어서 작성하시겠습니까?'),
            content: const Text('이전에 작성하던 회고록 내용이 있습니다.'),
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

  void _initializeQuestions() {
    final penName = widget.userProfile['penName'] ?? '사용자';
    // 디자인에 맞게 일부 텍스트 수정, 로직은 그대로 유지
    _questionnaire = {
      'start': Question(
        id: 'start',
        text:
            '안녕하세요, $penName 님!\n회고록을 쉽게 만들 수 있도록 AI가 도와드릴게요.\n어떤 추억을 그림책으로 만들어 볼까요?\n아래 버튼에서 선택해주세요.',
        type: QuestionType.directInputButton,
        options: [
          '출생',
          '유아유치',
          '초중고',
          '대학군대취업',
          '연애결혼자녀',
          '중장년',
          '퇴직노년',
          '직접입력',
        ],
        nextQuestionId: 'ask_has_characters',
      ),
      'ask_has_characters': Question(
        id: 'ask_has_characters',
        text: '$penName 님을 제외한 등장인물이 등장하나요?',
        type: QuestionType.buttonSelection,
        options: ['네, 등장해요', '아니요, 저 혼자예요'], // 디자인에 맞게 옵션 텍스트 수정
        nextQuestionIds: {
          '네, 등장해요': 'ask_character_info',
          '아니요, 저 혼자예요': 'ask_character_info_for_no',
        },
      ),
      // --- 'Yes' 분기 ---
      'ask_character_info': Question(
        id: 'ask_character_info',
        text: '회고 당시, 등장인물의 정보와 특징을 입력해주세요:',
        type: QuestionType.shortText,
        nextQuestionId: 'ask_background_info',
        exampleText:
            '초등학교 3학년 때 단짝이었던 친구 철수는 항상 웃음이 많았습니다. 짧은 검정색 머리였고, 안경을 쓰고있었습니다.',
      ),
      'ask_background_info': Question(
        id: 'ask_background_info',
        text: '회고 당시, 배경(장소적 특징)을 알려주세요:',
        type: QuestionType.shortText,
        nextQuestionId: 'ask_meaning_yes_char',
        exampleText:
            '그 장소는 초등학교 였고, 운동회 날이었습니다. 시골에 있어서 넓은 운동장을 가진 학교였습니다. 그리고 여름이여서 매우 더웠던 기억이...',
      ),
      'ask_meaning_yes_char': Question(
        id: 'ask_meaning_yes_char',
        text: '이 회고록 생성이 귀하에게 어떤 의미가 있나요?',
        needsEmpathy: true,
        nextQuestionId: 'ask_story_yes_char',
        exampleText: '이번 회고록 생성을 통해, 철수와의 추억을 떠올려보고 싶습니다.',
      ),
      'ask_story_yes_char': Question(
        id: 'ask_story_yes_char',
        text: '그 당시의 이야기를 상세하게 작성해주세요.',
        needsEmpathy: true,
        nextQuestionId: 'ask_message_to_char',
        exampleText:
            '그 날은 여름이었어요. 철수랑 제가 함께 학교에서 운동회를 하는 날이였죠. 철수는 저와 가장 친한 친구였기 때문에 저와 같은 팀이었어요. 그 때 박깨기를 이기기위해...',
      ),
      'ask_message_to_char': Question(
        id: 'ask_message_to_char',
        text: '등장인물에게 어떤 메세지를 전하고 싶으세요?',
        needsEmpathy: true,
        nextQuestionId: 'ask_recipient_yes_char',
        exampleText: '내 친한 친구였던 철수야. 너에게 정말 고마웠다. 오랫만에 만나서 밥이라도 먹으면 좋겠다.',
      ),
      'ask_recipient_yes_char': Question(
        id: 'ask_recipient_yes_char',
        text: '이 회고록 출판물을 어느 분에게 전하고 싶으세요? 어떤 이유 일까요?',
        needsEmpathy: true,
        nextQuestionId: 'confirm_content_yes_char',
        exampleText: '내 친구 철수에게, 오랫만에 안부를 전하고 싶어서.',
      ),
      'confirm_content_yes_char': Question(
        id: 'confirm_content_yes_char',
        text: '회고록의 요약본입니다. 이 내용으로 계속 진행할까요?',
        type: QuestionType.buttonSelection,
        options: ['네, 계속 진행할게요', '아니요, 수정할래요'],
        nextQuestionId: 'ask_style_yes_char',
      ),
      'ask_style_yes_char': Question(
        id: 'ask_style_yes_char',
        text: '생성 이미지의 그림체/화풍은 어떻게 하시겠어요?',
        type: QuestionType.directInputButton,
        options: ['사실적', '스케치', '수채화', '유채화', '애니메이션풍', '디즈니풍'],
        nextQuestionId: 'confirm_final_yes_char',
      ),
      'confirm_final_yes_char': Question(
        id: 'confirm_final_yes_char',
        text:
            '이제 회고록을 생성할 수 있어요!\n완성된 회고록은 회고록 보기에서 볼 수 있어요.\n아래 버튼을 눌러 회고록 생성을 시작해주세요.',
        type: QuestionType.buttonSelection,
        options: ['회고록 생성 시작'],
      ),

      // --- 'No' 분기 ---
      'ask_character_info_for_no': Question(
        id: 'ask_character_info_for_no',
        text: '회고 당시, 귀하의 특징을 입력해주세요:',
        type: QuestionType.shortText,
        nextQuestionId: 'ask_background_info_for_no',
        exampleText: '저는 군대에서 매우 짧은 반삭머리였고, 군복을 입고있었습니다. 전체적으로 근육질의 체형이였죠.',
      ),
      'ask_background_info_for_no': Question(
        id: 'ask_background_info_for_no',
        text: '회고 당시, 배경(장소적 특징)을 알려주세요:',
        type: QuestionType.shortText,
        nextQuestionId: 'ask_meaning_no_char',
        exampleText:
            '장소는 군 막사였습니다. 막사는 2층건물로 되어있었고, 부대 앞은 군용차량들이 쭉 대기하고 있었죠. 여름이어서 너무 더웠던 기억도 납니다.',
      ),
      'ask_meaning_no_char': Question(
        id: 'ask_meaning_no_char',
        text: '이 회고록 생성 작업이 귀하에게 어떤 의미가 있나요?',
        needsEmpathy: true,
        nextQuestionId: 'ask_story_no_char',
        exampleText: '그 당시에 너무 자랑스러웠던 제 모습이 떠올라서 그 기억을 남기고 싶습니다.',
      ),
      'ask_story_no_char': Question(
        id: 'ask_story_no_char',
        text: '그때의 이야기를 상세하게 말씀해주세요.',
        needsEmpathy: true,
        nextQuestionId: 'ask_recipient_no_char',
        exampleText:
            '그 날은 제가 부대에서 대표로 수상을 하던 날이었습니다. 저는 늘 솔선수범이었고, 체력과 전투력 모두 뛰어났습니다. 그래서 각종 군대회에서 1등도하여 ....',
      ),
      'ask_recipient_no_char': Question(
        id: 'ask_recipient_no_char',
        text: '이 회고록 출판물을 누구에게 전하고 싶으세요? 어떤 이유 일까요?\n(예시: 나, 가족, 친구)',
        needsEmpathy: true,
        nextQuestionId: 'ask_final_message_no_char',
        exampleText: '나에게 전해주고 싶습니다. 왜냐하면 그 당시의 자랑스러웠던 제 모습을 기억하고 싶거든요.',
      ),
      'ask_final_message_no_char': Question(
        id: 'ask_final_message_no_char',
        text: '회고록에 남기고 싶은 메세지를 적어주세요.',
        needsEmpathy: true,
        nextQuestionId: 'confirm_content_no_char',
        exampleText: '길동아, 군대에서도 늘 이겨나간 것 처럼 앞으로도 인생을 잘 이겨나가길 바란다.',
      ),
      'confirm_content_no_char': Question(
        id: 'confirm_content_no_char',
        text: '회고록의 요약본입니다. 이 내용으로 계속 진행할까요?',
        type: QuestionType.buttonSelection,
        options: ['네, 계속 진행할게요', '아니요, 수정할래요'],
        nextQuestionId: 'ask_style_no_char',
      ),
      'ask_style_no_char': Question(
        id: 'ask_style_no_char',
        text: '생성 이미지의 그림체/화풍은 어떻게 하시겠어요?',
        type: QuestionType.directInputButton,
        options: ['사실적', '스케치', '수채화', '유채화', '애니메이션풍', '디즈니풍'],
        nextQuestionId: 'confirm_final_no_char',
      ),
      'confirm_final_no_char': Question(
        id: 'confirm_final_no_char',
        text:
            '이제 회고록을 생성할 수 있어요!\n완성된 회고록은 회고록 보기에서 볼 수 있어요.\n아래 버튼을 눌러 회고록 생성을 시작해주세요.',
        type: QuestionType.buttonSelection,
        options: ['회고록 생성 시작'],
      ),
    };

    _currentQuestion = _questionnaire['start']!;
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
  void _restoreMemoirState(Map<String, dynamic> savedAnswers) {
    _initializeQuestions();

    setState(() {
      _messages.clear();
      _answers.addAll(savedAnswers);

      Question? lastAnsweredQuestion;
      List<ChatMessage> restoredMessages = [];

      var tempQuestion = _questionnaire['start']!;
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

  void _handleAnswer(String answer) async {
    if (answer.trim().isEmpty &&
        _currentQuestion.type != QuestionType.buttonSelection)
      return;

    if (_currentQuestion.type == QuestionType.directInputButton) {
      if (answer == '직접입력') {
        setState(() {
          _messages.insert(
            0,
            ChatMessage(
              text: answer,
              type: MessageType.user,
              questionId: _currentQuestion.id,
            ),
          );

          if (_currentQuestion.id == 'start') {
            _showDirectInputField = true;
          } else {
            _showDirectStyleInputField = true;
          }
        });
        _scrollToBottom();
        return;
      }
    }

    setState(() {
      _messages.insert(
        0,
        ChatMessage(
          text: answer,
          type: MessageType.user,
          questionId: _currentQuestion.id,
        ),
      );

      if (_showDirectInputField) {
        _showDirectInputField = false;
        _directInputController.clear();
      }
      if (_showDirectStyleInputField) {
        _showDirectStyleInputField = false;
        _directStyleInputController.clear();
      }
    });
    _answers[_currentQuestion.id] = answer;
    await _saveProgress();
    _textController.clear();
    _scrollToBottom();

    final summaryTriggerIds = [
      'ask_recipient_yes_char',
      'ask_final_message_no_char',
    ];

    if (summaryTriggerIds.contains(_currentQuestion.id)) {
      setState(() => _isGeneratingSummary = true);
      _scrollToBottom();

      try {
        final summaryData = await _getMemoirSummary();
        final String summary = summaryData['summary'] ?? '요약을 생성하지 못했습니다.';
        final String fullStory = summaryData['fullStory'] ?? '';
        _answers['fullStory'] = fullStory;

        String? nextQuestionId = _currentQuestion.nextQuestionId;
        if (nextQuestionId != null &&
            _questionnaire.containsKey(nextQuestionId)) {
          Question nextQuestion = _questionnaire[nextQuestionId]!;
          final confirmationQuestion = Question(
            id: nextQuestion.id,
            text: "회고록의 요약본입니다. 이 내용으로 계속 진행할까요?\n\n\"$summary\"",
            type: nextQuestion.type,
            options: nextQuestion.options,
            nextQuestionId: nextQuestion.nextQuestionId,
            nextQuestionIds: nextQuestion.nextQuestionIds,
          );
          setState(() => _isGeneratingSummary = false);
          _currentQuestion = confirmationQuestion;
          _askQuestion(_currentQuestion);
        }
      } catch (e) {
        setState(() => _isGeneratingSummary = false);
        _addBotMessage("죄송합니다. 회고록 요약 생성에 실패했어요.");
      }
      return;
    }

    if (_currentQuestion.needsEmpathy) {
      setState(() => _isBotThinking = true);
      _scrollToBottom();
      final empathyResponse = await _getEmpathyResponse(answer);
      setState(() => _isBotThinking = false);
      _addBotMessage(empathyResponse);
      await Future.delayed(const Duration(milliseconds: 500));
    }

    String? nextQuestionId;
    // '네, 등장해요' 또는 '아니요, 저 혼자예요' 와 같은 답변을 처리
    if (_currentQuestion.id == 'ask_has_characters') {
      nextQuestionId = _currentQuestion.nextQuestionIds![answer];
    } else if (_currentQuestion.nextQuestionIds != null) {
      // 'Yes', 'No' 와 같은 일반적인 버튼 답변 처리
      String mappedAnswer =
          answer == '네, 계속 진행할게요'
              ? 'Yes'
              : (answer == '아니요, 수정할래요' ? 'No' : answer);
      nextQuestionId = _currentQuestion.nextQuestionIds![mappedAnswer];
    } else {
      nextQuestionId = _currentQuestion.nextQuestionId;
    }

    if (nextQuestionId != null && _questionnaire.containsKey(nextQuestionId)) {
      _currentQuestion = _questionnaire[nextQuestionId]!;
      // '아니요, 수정할래요'를 선택한 경우, 이전 질문으로 돌아가는 로직 추가
      if (answer == '아니요, 수정할래요') {
        // 이 부분은 서비스 정책에 따라 어떤 질문으로 돌아갈지 정의해야 합니다.
        // 여기서는 예시로 'start'로 돌아갑니다.
        _currentQuestion = _questionnaire['start']!;
      }
      _askQuestion(_currentQuestion);
    } else {
      if (answer == "회고록 생성 시작") {
        _submitAnswers();
      }
    }
  }

  // ✅ [신규 추가] 진행 상황을 저장하는 함수
  Future<void> _saveProgress() async {
    final prefs = await SharedPreferences.getInstance();
    // ✅ _answers 맵을 String으로 변환하여 'saved_memoir' 키로 저장
    await prefs.setString('saved_memoir', jsonEncode(_answers));
  }

  Future<Map<String, dynamic>> _getMemoirSummary() async {
    final callable = FirebaseFunctions.instanceFor(
      region: 'asia-northeast3',
    ).httpsCallable('generateMemoirSummary');
    final result = await callable.call({'qnaData': _answers});
    return Map<String, dynamic>.from(result.data);
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

  void _submitAnswers() async {
    setState(() => _isLoading = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('로그인이 필요합니다.')));
      }
      setState(() => _isLoading = false);
      return;
    }

    final Map<String, dynamic> qnaMap = Map<String, dynamic>.from(_answers);
    qnaMap['penName'] = widget.userProfile['penName'] ?? '익명';
    qnaMap['age'] = widget.userProfile['age'] ?? '비공개';
    qnaMap['gender'] = widget.userProfile['gender'] ?? '비공개';

    final storyToSend = qnaMap.remove('fullStory');

    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-northeast3',
      ).httpsCallable('processMemoir');

      callable.call({'qnaData': qnaMap, 'fullStory': storyToSend ?? ''});
      await _clearSavedData();
      if (context.mounted) {
        Navigator.pop(context, true);
      }
    } on FirebaseFunctionsException catch (e) {
      if (context.mounted) {
        setState(() => _isLoading = false);
        Navigator.pop(context, false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('요청 실패: ${e.message}')));
      }
    }
  }

  Future<void> _clearSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_memoir');
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
        appBar: AppBar(title: const Text('AI 회고록 만들기')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    bool isTextInputEnabled =
        !_isLoading &&
        !_isBotThinking &&
        !_showDirectInputField &&
        !_showDirectStyleInputField &&
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
          'AI 회고록 만들기',
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
                  // ✅ reverse: true가 핵심입니다. 리스트를 아래부터 위로 쌓습니다.
                  reverse: true,
                  itemCount:
                      _messages.length +
                      (_isBotThinking ? 1 : 0) +
                      (_isGeneratingSummary ? 1 : 0),
                  itemBuilder: (context, index) {
                    // ✅ 인디케이터 로직은 index가 0일 때만 확인하면 되므로 단순해집니다.
                    if (_isGeneratingSummary && index == 0) {
                      return _buildSummaryLoadingIndicator();
                    }
                    if (_isBotThinking && index == 0) {
                      return _buildThinkingIndicator();
                    }

                    // ✅ _messages 리스트를 뒤집지 않고 그대로 사용해야 올바른 순서로 표시됩니다.
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
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 24),
                    Text(
                      '작성해주신 내용을 바탕으로\n회고록을 생성 중입니다.\n\n1분 정도 소요됩니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
                    isEnabled ? const Color(0xff007AFF) : Colors.grey.shade300,
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
            '회고록을 빠르게 요약하고 있어요',
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
        bubbleColor = const Color(0xFF34C759);
        textColor = Colors.white;
        break;
      case MessageType.botExample:
        bubbleColor = Colors.yellow.shade100;
        textColor = Colors.black87;
        break;
      default: // MessageType.bot
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
            if (question?.id == 'ask_style_yes_char' ||
                question?.id == 'ask_style_no_char')
              _buildStyleSelection(message)
            else
              _buildOptionButtons(message),
          ],
          if (_showDirectInputField && message.questionId == 'start')
            _buildDirectInputWidget(_directInputController, '원하는 시기를 입력...'),
          if (_showDirectStyleInputField &&
              (message.questionId == 'ask_style_yes_char' ||
                  message.questionId == 'ask_style_no_char'))
            _buildDirectInputWidget(
              _directStyleInputController,
              '원하는 그림체를 영어로 입력...',
            ),
        ],
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
            return OutlinedButton(
              onPressed: () => message.onOptionSelected?.call(option),
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

  Widget _buildStyleSelection(ChatMessage message) {
    final imagePathMap = {
      '사실적': 'assets/realistic.png',
      '스케치': 'assets/sketch.png',
      '수채화': 'assets/watercolor.png',
      '유채화': 'assets/oil_painting.png',
      '애니메이션풍': 'assets/animation.png',
      '디즈니풍': 'assets/disney.png',
    };

    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: message.options!.length,
        itemBuilder: (context, index) {
          final option = message.options![index];
          final imagePath = imagePathMap[option];

          return GestureDetector(
            onTap: () => message.onOptionSelected?.call(option),
            child: Container(
              width: 100,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.blue),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child:
                            imagePath != null
                                ? Image.asset(
                                  imagePath,
                                  fit: BoxFit.cover,
                                  errorBuilder:
                                      (context, error, stackTrace) => Container(
                                        color: Colors.grey.shade300,
                                      ),
                                )
                                : Container(color: Colors.grey.shade300),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      option,
                      style: const TextStyle(color: Colors.black),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        separatorBuilder: (context, index) => const SizedBox(width: 10),
      ),
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
