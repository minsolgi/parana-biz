import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'myth_page.dart';

class MythSetupPage extends StatefulWidget {
  final Map<String, dynamic> userProfile;
  const MythSetupPage({super.key, required this.userProfile});

  @override
  State<MythSetupPage> createState() => _MythSetupPageState();
}

class _MythSetupPageState extends State<MythSetupPage> {
  final _formKey = GlobalKey<FormState>();

  String? _selectedMythType;
  final Set<String> _selectedCompositionElements = {};
  final _penNameController = TextEditingController();
  final _genderController = TextEditingController();
  final _ageController = TextEditingController();
  final _educationController = TextEditingController();
  final _jobController = TextEditingController();
  final _residenceController = TextEditingController();

  final List<String> _mythTypeOptions = [
    '기업 스토리',
    '개인 성장 스토리',
    '로컬 스토리',
    '국가/문화 에픽',
    '종교 에픽',
    '우주, 초자연 에픽',
  ];
  final List<String> _compositionElementOptions = [
    '상징, 은유',
    '영웅 여정(모험)',
    '갈등, 시련, 해방',
    '공동체(가치, 전통, 연대)',
    '행동, 체험, 의식, 챌린지',
  ];

  @override
  void initState() {
    super.initState();
    // ✅ 페이지가 열리자마자 저장된 데이터가 있는지 확인합니다.
    _checkResumeData();
  }

  Future<void> _checkResumeData() async {
    final prefs = await SharedPreferences.getInstance();
    final savedData = prefs.getString('saved_myth');

    if (savedData != null && savedData.isNotEmpty && mounted) {
      final wantToResume = await _showResumeDialog();
      if (wantToResume) {
        // '이어쓰기' 선택 시, 저장된 데이터로 바로 대화 페이지로 이동
        final savedAnswers = Map<String, dynamic>.from(jsonDecode(savedData));
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder:
                (context) => MythPage(
                  userProfile: widget.userProfile,
                  initialAnswers: savedAnswers,
                ),
          ),
        );
      } else {
        // '새로 쓰기' 선택 시, 기존 데이터 삭제
        await prefs.remove('saved_myth');
      }
    }
  }

  // ✅ [추가] 이어쓰기 확인 다이얼로그
  Future<bool> _showResumeDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: const Text('이어서 작성하시겠습니까?'),
            content: const Text('이전에 작성하던 신화 내용이 있습니다.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('새로 쓰기'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('이어 쓰기'),
              ),
            ],
          ),
    );
    return result ?? false;
  }

  @override
  void dispose() {
    _penNameController.dispose();
    _genderController.dispose();
    _ageController.dispose();
    _educationController.dispose();
    _jobController.dispose();
    _residenceController.dispose();
    super.dispose();
  }

  void _startConversation() {
    if (_formKey.currentState!.validate()) {
      final basicInfo =
          '''
성별: ${_genderController.text}
나이: ${_ageController.text}
학력: ${_educationController.text}
직군 + 맡은 업무: ${_jobController.text}
거주지(사전 셋팅): ${_residenceController.text}
'''.trim();

      final initialAnswers = {
        'ask_myth_type': _selectedMythType,
        'ask_composition_elements': _selectedCompositionElements.join(', '),
        'ask_pen_name': _penNameController.text,
        'ask_basic_info': basicInfo,
      };

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder:
              (context) => MythPage(
                userProfile: widget.userProfile,
                initialAnswers: initialAnswers,
              ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('신화 정보 입력')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 신화 유형 (Dropdown)
              DropdownButtonFormField<String>(
                value: _selectedMythType,
                hint: const Text('신화 유형 선택'),
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items:
                    _mythTypeOptions.map((type) {
                      return DropdownMenuItem(value: type, child: Text(type));
                    }).toList(),
                onChanged: (value) => setState(() => _selectedMythType = value),
                validator: (value) => value == null ? '신화 유형을 선택해주세요.' : null,
              ),
              const SizedBox(height: 24),

              // 2. 구성요소 (Chips)
              const Text(
                '구성요소 (중복 선택)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8.0,
                children:
                    _compositionElementOptions.map((element) {
                      final isSelected = _selectedCompositionElements.contains(
                        element,
                      );
                      return ChoiceChip(
                        label: Text(element),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _selectedCompositionElements.add(element);
                            } else {
                              _selectedCompositionElements.remove(element);
                            }
                          });
                        },
                      );
                    }).toList(),
              ),
              const SizedBox(height: 24),

              // 3. 필명
              TextFormField(
                controller: _penNameController,
                decoration: const InputDecoration(
                  labelText: '필명',
                  border: OutlineInputBorder(),
                ),
                validator:
                    (value) =>
                        (value == null || value.isEmpty) ? '필명을 입력해주세요.' : null,
              ),
              const SizedBox(height: 24),

              // ✅ [수정] 4. 기본정보 입력 필드를 개별로 분리
              const Text(
                '기본정보',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _genderController,
                decoration: const InputDecoration(
                  labelText: '성별',
                  border: OutlineInputBorder(),
                ),
                validator:
                    (value) =>
                        (value == null || value.isEmpty) ? '성별을 입력해주세요.' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _ageController,
                decoration: const InputDecoration(
                  labelText: '나이',
                  border: OutlineInputBorder(),
                ),
                validator:
                    (value) =>
                        (value == null || value.isEmpty) ? '나이를 입력해주세요.' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _educationController,
                decoration: const InputDecoration(
                  labelText: '학력',
                  border: OutlineInputBorder(),
                ),
                validator:
                    (value) =>
                        (value == null || value.isEmpty) ? '학력을 입력해주세요.' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _jobController,
                decoration: const InputDecoration(
                  labelText: '직군 + 맡은 업무',
                  border: OutlineInputBorder(),
                ),
                validator:
                    (value) =>
                        (value == null || value.isEmpty) ? '직군을 입력해주세요.' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _residenceController,
                decoration: const InputDecoration(
                  labelText: '거주지 (사전 셋팅)',
                  border: OutlineInputBorder(),
                ),
                validator:
                    (value) =>
                        (value == null || value.isEmpty)
                            ? '거주지를 입력해주세요.'
                            : null,
              ),
              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: _startConversation,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                ),
                child: const Text('대화 시작하기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
