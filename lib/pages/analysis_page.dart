// lib/pages/analysis_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AnalysisPage extends StatefulWidget {
  const AnalysisPage({super.key});

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
      setState(() {
        _userData = doc.data();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('데이터 불러오기 오류: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_userData == null) {
      return const Scaffold(body: Center(child: Text('사용자 정보를 불러올 수 없습니다.')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('📊 내 데이터 분석')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Text('👤 사용자 정보', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text('이름: ${_userData!['penName'] ?? '이름 없음'}'),
            Text('이메일: ${_userData!['email'] ?? '없음'}'),
            const SizedBox(height: 20),

            const Divider(),

            Text(
              '📘 나의 회고록 데이터',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            FutureBuilder<QuerySnapshot>(
              future:
                  FirebaseFirestore.instance
                      .collection('books')
                      .where(
                        'ownerUid',
                        isEqualTo: FirebaseAuth.instance.currentUser?.uid,
                      )
                      .get(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Text('아직 생성된 회고록이 없습니다.');
                }

                final books = snapshot.data!.docs;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children:
                      books.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        return Card(
                          child: ListTile(
                            title: Text(data['title'] ?? '제목 없음'),
                            subtitle: Text(
                              data['createdAt']?.toDate().toString() ?? '',
                            ),
                          ),
                        );
                      }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
