import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AfterInterviewInfoPage extends StatefulWidget {
  const AfterInterviewInfoPage({super.key});

  @override
  State<AfterInterviewInfoPage> createState() => _AfterInterviewInfoPageState();
}

class _AfterInterviewInfoPageState extends State<AfterInterviewInfoPage> {
  // Form을 제어하기 위한 GlobalKey
  final _formKey = GlobalKey<FormState>();

  // 각 입력 필드를 위한 컨트롤러
  final _companyNameController = TextEditingController();
  final _phoneNumberController = TextEditingController();
  final _contactNameController = TextEditingController();

  bool _isLoading = false;

  // 정보 제출 함수
  Future<void> _submitInfo() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      final user = FirebaseAuth.instance.currentUser;
      final String? requesterUid = user?.uid;

      try {
        await FirebaseFirestore.instance.collection('conflict_leads').add({
          'companyName': _companyNameController.text,
          'phoneNumber': _phoneNumberController.text,
          'contactName': _contactNameController.text,
          'requesterUid': requesterUid, // uid가 없으면 null이 저장됨
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('정보가 성공적으로 제출되었습니다. 감사합니다.')),
          );
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } catch (e) {
        // ... (에러 처리)
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    _phoneNumberController.dispose();
    _contactNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('추가 정보 입력')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '솔루션 제공을 위해 아래 정보를 입력해주세요.',
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 24),
              // 기업명 입력 필드
              TextFormField(
                controller: _companyNameController,
                decoration: const InputDecoration(
                  labelText: '기업명',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '기업명을 입력해주세요.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // 전화번호 입력 필드
              TextFormField(
                controller: _phoneNumberController,
                decoration: const InputDecoration(
                  labelText: '전화번호',
                  border: OutlineInputBorder(),
                  hintText: '010-1234-5678',
                ),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '전화번호를 입력해주세요.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // 담당자명 입력 필드
              TextFormField(
                controller: _contactNameController,
                decoration: const InputDecoration(
                  labelText: '담당자명',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '담당자명을 입력해주세요.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),
              // 제출 버튼
              ElevatedButton(
                onPressed: _isLoading ? null : _submitInfo,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                ),
                child:
                    _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('제출하기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
