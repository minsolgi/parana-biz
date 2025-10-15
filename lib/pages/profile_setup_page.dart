import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'home_page.dart';

class ProfileSetupPage extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  const ProfileSetupPage({super.key, this.initialData});

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage> {
  // ✅ 상태 관리 변수 및 컨트롤러는 전혀 수정되지 않았습니다.
  final _penNameController = TextEditingController();
  final _ageController = TextEditingController();
  String? _selectedGender;

  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  // ✅ initState 로직은 그대로 유지됩니다.
  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _penNameController.text = widget.initialData!['penName'] ?? '';
      _ageController.text =
          widget.initialData!['age']?.toString() ?? ''; // age가 숫자로 올 경우를 대비
      _selectedGender = widget.initialData!['gender'];
    }
  }

  // ✅ dispose 로직은 그대로 유지됩니다.
  @override
  void dispose() {
    _penNameController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  // ✅ 핵심 기능인 _saveProfile 함수는 전혀 수정되지 않았습니다.
  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_selectedGender == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('남자/여자 중 선택해주세요.')));
      return;
    }

    setState(() => _isLoading = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'penName': _penNameController.text,
        'age': _ageController.text,
        'gender': _selectedGender,
        'email': user.email,
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('프로필이 저장되었습니다.')));

        if (widget.initialData == null) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomePage()),
          );
        } else {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('정보 저장에 실패했습니다: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // == 🚀 UI 부분만 디자인에 맞게 전면 수정되었습니다 ==
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          '프로필 입력',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        surfaceTintColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '프로필 정보를 입력해주세요',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 32),
                        _buildTextField(
                          label: '필명(작가명)',
                          controller: _penNameController,
                          hintText: '회고록의 필명을 입력해주세요.',
                          validator:
                              (value) => value!.isEmpty ? '필명을 입력해주세요.' : null,
                        ),
                        const SizedBox(height: 24),
                        _buildTextField(
                          label: '나이',
                          controller: _ageController,
                          hintText: '나이를 숫자로만 입력해주세요.',
                          keyboardType: TextInputType.number,
                          validator:
                              (value) => value!.isEmpty ? '나이를 입력해주세요.' : null,
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          '남/녀',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildGenderSelector(),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF318FFF),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: _saveProfile,
                    child: const Text('저장하기'),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  // 입력 필드를 위한 헬퍼 위젯
  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required String hintText,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(color: Colors.grey),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.grey),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.blue, width: 2),
            ),
          ),
          keyboardType: keyboardType,
          validator: validator,
        ),
      ],
    );
  }

  // 성별 선택을 위한 헬퍼 위젯
  Widget _buildGenderSelector() {
    return Row(
      children: [
        Expanded(child: _genderButton('남자')),
        const SizedBox(width: 16),
        Expanded(child: _genderButton('여자')),
      ],
    );
  }

  Widget _genderButton(String gender) {
    final isSelected = _selectedGender == gender;
    return OutlinedButton(
      onPressed: () {
        setState(() {
          _selectedGender = gender;
        });
      },
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 56),
        backgroundColor:
            isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent,
        side: BorderSide(
          color: isSelected ? Colors.blue : Colors.grey.shade300,
          width: isSelected ? 2 : 1,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        gender,
        style: TextStyle(
          fontSize: 16,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.blue : Colors.black87,
        ),
      ),
    );
  }
}
