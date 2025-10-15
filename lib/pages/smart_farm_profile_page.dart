import 'package:flutter/material.dart';
import 'smart_farm_interview_page.dart';

// CustomToggleButtons 위젯은 수정 없이 그대로 사용합니다.
class CustomToggleButtons extends StatelessWidget {
  final List<String> labels;
  final List<bool> isSelected;
  final Function(int) onPressed;

  const CustomToggleButtons({
    super.key,
    required this.labels,
    required this.isSelected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ToggleButtons(
      isSelected: isSelected,
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(8),
      selectedColor: Colors.white,
      fillColor: const Color(0xFF318FFF),
      children:
          labels
              .map(
                (label) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(label),
                ),
              )
              .toList(),
    );
  }
}

class SmartFarmProfilePage extends StatefulWidget {
  final bool isLoggedIn;
  const SmartFarmProfilePage({super.key, this.isLoggedIn = false});

  @override
  State<SmartFarmProfilePage> createState() => _SmartFarmProfilePageState();
}

class _SmartFarmProfilePageState extends State<SmartFarmProfilePage> {
  final _formKey = GlobalKey<FormState>();

  final _penNameController = TextEditingController();
  final _ageController = TextEditingController();
  final _educationController = TextEditingController();
  final _residenceController = TextEditingController();
  final _workplaceController = TextEditingController();

  List<bool> _genderSelection = [true, false];

  // ✅ [수정] 단일 선택(String)에서 복수 선택(List<String>)으로 변경
  List<String> _selectedAffiliations = [];

  final List<String> _affiliationOptions = [
    '논산시 청년스마트팜 운영 농가',
    '스마트팜 벤처·스타트업 창업자',
    '농업기술센터 스마트팜 종사자',
    '지역청년농업인 커뮤니티 리더',
    '광역 지자체 산하기관 종사자',
    '건양대 RISE 혁신허브 종사자',
    '귀농·귀촌 관심자',
    '청년스마트팜 관심자(만20세~45세)',
    '스마트플랫폼기술인관리협회',
    '기타',
  ];

  @override
  void dispose() {
    _penNameController.dispose();
    _ageController.dispose();
    _educationController.dispose();
    _residenceController.dispose();
    _workplaceController.dispose();
    super.dispose();
  }

  void _submitProfile() {
    if (_formKey.currentState!.validate()) {
      final profileData = {
        'penName': _penNameController.text,
        'gender': _genderSelection[0] ? '남자' : '여자',
        'age': _ageController.text,
        'education': _educationController.text,
        'residence': _residenceController.text,
        'workplace': _workplaceController.text,
        'affiliations': _selectedAffiliations,
        'isLoggedIn': widget.isLoggedIn,
      };

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SmartFarmInterviewPage(userInfo: profileData),
        ),
      );
    }
  }

  // ✅ [신규 추가] 소속 선택 다이얼로그를 표시하는 함수
  Future<void> _showAffiliationDialog() async {
    // 다이얼로그 내에서 임시로 사용할 선택 목록
    final tempSelected = List<String>.from(_selectedAffiliations);

    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) {
        // 다이얼로그 내의 상태 관리를 위해 StatefulBuilder 사용
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('소속 선택 (최대 2개)'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _affiliationOptions.length,
                  itemBuilder: (context, index) {
                    final option = _affiliationOptions[index];
                    final isChecked = tempSelected.contains(option);
                    return CheckboxListTile(
                      title: Text(option),
                      value: isChecked,
                      onChanged: (bool? value) {
                        setDialogState(() {
                          if (value == true) {
                            if (tempSelected.length < 2) {
                              tempSelected.add(option);
                            } else {
                              // 2개 초과 선택 시 알림
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('최대 2개까지만 선택할 수 있습니다.'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            }
                          } else {
                            tempSelected.remove(option);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('취소'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, tempSelected),
                  child: const Text('확인'),
                ),
              ],
            );
          },
        );
      },
    );

    // 사용자가 '확인'을 눌렀을 때만 상태 업데이트
    if (result != null) {
      setState(() {
        _selectedAffiliations = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final buttonStyle = ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF318FFF),
      foregroundColor: Colors.white,
      minimumSize: const Size(double.infinity, 56),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('참여자 정보 입력'),
        // ✅ [추가] AppBar 스타일 통일
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ✅ [복구] 각 TextFormField에 decoration 속성을 다시 추가했습니다.
              TextFormField(
                controller: _penNameController,
                decoration: const InputDecoration(
                  labelText: '필명 & 닉네임',
                  border: OutlineInputBorder(),
                ),
                validator:
                    (value) =>
                        (value == null || value.isEmpty) ? '필수 항목입니다.' : null,
              ),
              const SizedBox(height: 16),
              CustomToggleButtons(
                labels: const ['남자', '여자'],
                isSelected: _genderSelection,
                onPressed: (index) {
                  setState(() {
                    for (int i = 0; i < _genderSelection.length; i++) {
                      _genderSelection[i] = i == index;
                    }
                  });
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _ageController,
                decoration: const InputDecoration(
                  labelText: '나이',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number, // 나이는 숫자 키패드 사용
                validator:
                    (value) =>
                        (value == null || value.isEmpty) ? '필수 항목입니다.' : null,
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
                        (value == null || value.isEmpty) ? '필수 항목입니다.' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _residenceController,
                decoration: const InputDecoration(
                  labelText: '거주지',
                  border: OutlineInputBorder(),
                  hintText: '예) 충남 논산시',
                ),
                validator:
                    (value) =>
                        (value == null || value.isEmpty)
                            ? '거주지를 입력해주세요.'
                            : null,
              ),
              const SizedBox(height: 24),
              const Text(
                '사업장',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _workplaceController,
                decoration: const InputDecoration(
                  labelText: '사업장 주소 (해당 시)',
                  border: OutlineInputBorder(),
                  hintText: '예) 충남 논산시',
                ),
              ),
              const SizedBox(height: 24),
              FormField<List<String>>(
                initialValue: _selectedAffiliations,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '소속을 1개 이상 선택해주세요.';
                  }
                  return null;
                },
                builder: (formFieldState) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: _showAffiliationDialog,
                        child: InputDecorator(
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            labelText: '소속 선택 (최대 2개)', // labelText로 변경
                            errorText: formFieldState.errorText,
                          ),
                          child:
                              _selectedAffiliations.isEmpty
                                  ? const Text('') // 비어있을 땐 아무것도 표시 안함
                                  : Text(_selectedAffiliations.join(', ')),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _submitProfile,
                style: buttonStyle,
                child: const Text('다음으로'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
