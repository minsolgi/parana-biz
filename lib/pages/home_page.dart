import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';
import 'qna_page.dart';
import 'profile_setup_page.dart';
import 'myth_setup_page.dart';
import 'smart_farm_greeting_page.dart';
import 'analysis_page.dart';
import 'book_list_page.dart';
import 'toddler_book_list_page.dart';
import 'myth_list_page.dart';
import 'smart_farm_article_page.dart';
import 'interview_selection_dialog.dart';
import 'toddler_book_page.dart';
import 'conflict_self_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _penName = '사용자';
  bool _isLoading = true;
  int _currentIndex = 0;

  final bool _isUnderMaintenance = false;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final profileData = await _getUserProfile(user.uid);
      if (mounted) {
        setState(() {
          _penName = profileData?['penName'] ?? '사용자';
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<Map<String, dynamic>?> _getUserProfile(String uid) async {
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    return doc.data();
  }

  String _formatDuration(int totalSeconds) {
    final duration = Duration(seconds: totalSeconds);
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  void _showMaintenanceDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('서비스 점검 안내', textAlign: TextAlign.center),
          content: const Text(
            '현재 서비스 개선 중에 있습니다.\n나중에 다시 이용 부탁드립니다.\n불편을 드려 죄송합니다.',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              child: const Text('확인'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  void _showCooldownDialog(BuildContext context, int remainingSeconds) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('⏳ 잠시 후 이용해주세요', textAlign: TextAlign.center),
          content: Text(
            "저희 서비스는 10분 단위로 사용이 가능합니다.\n${_formatDuration(remainingSeconds)} 뒤에 회고록을 사용할 수 있습니다.",
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              child: const Text('확인'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  void _showCompletionNotice(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_outline, color: Colors.green),
              SizedBox(width: 8),
              Text('접수 완료'),
            ],
          ),
          content: const Text(
            "회고록을 생성 중입니다. \n1분 뒤에 생성이 완료됩니다.\n잠시 후에 '회고록 보기'를 확인해주세요.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 30,
                  vertical: 12,
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('확인'),
            ),
          ],
        );
      },
    );
  }

  void _showLibrarySelectionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('나의 서재', textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.auto_stories_outlined),
                title: const Text('나의 회고록'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const BookListPage(),
                    ),
                  );
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.photo_album_outlined),
                title: const Text('나의 그림책'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ToddlerBookListPage(),
                    ),
                  );
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('나의 신화'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const MythListPage(),
                    ),
                  );
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.newspaper_outlined),
                title: const Text('신문보도기사'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SmartFarmArticlePage(),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleCreateBook() async {
    if (_isUnderMaintenance) {
      _showMaintenanceDialog(context);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-northeast3',
      ).httpsCallable('checkCooldownStatus');
      final result = await callable.call();

      if (mounted) {
        final bool onCooldown = result.data['onCooldown'];
        if (onCooldown) {
          final int remainingTime = result.data['remainingTime'];
          _showCooldownDialog(context, remainingTime);
        } else {
          final profileData = await _getUserProfile(user.uid);
          if (mounted) {
            final navResult = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => QnAPage(userProfile: profileData ?? {}),
              ),
            );
            if (navResult == true && mounted) {
              _showCompletionNotice(context);
            }
          }
        }
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('오류가 발생했습니다: ${e.message}')));
      }
    }
  }

  void _onItemTapped(int index) async {
    if (_currentIndex == index && index == 0) return;

    if (index != 1) {
      setState(() {
        _currentIndex = index;
      });
    }

    if (index == 1) {
      _showLibrarySelectionDialog(context);
    } else if (index == 2) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final profileData = await _getUserProfile(user.uid);
        if (mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProfileSetupPage(initialData: profileData),
            ),
          );
          _loadUserProfile();
        }
      }
      setState(() => _currentIndex = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints viewportConstraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: viewportConstraints.maxHeight,
                ),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 20),
                            if (_isLoading)
                              const Center(child: CircularProgressIndicator())
                            else
                              RichText(
                                text: TextSpan(
                                  style: const TextStyle(
                                    fontSize: 24,
                                    color: Colors.black,
                                    height: 1.4,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: '$_penName님',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const TextSpan(text: ' 안녕하세요'),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 8),
                            const Text(
                              '파라나 베타 서비스 입니다. \nAI와 추억을 책으로 만들어보세요.',
                              style: TextStyle(
                                fontSize: 24,
                                color: Colors.black,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 30),
                            // ✅ 이미지가 다시 들어가는 부분
                            Center(
                              child: Image.asset(
                                'assets/stockImage.jpg', // 이미지 파일 경로
                                height: 200, // 원하는 높이 설정
                              ),
                            ),
                            const SizedBox(height: 30),

                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF318FFF),
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 200),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onPressed: _handleCreateBook,
                              child: const Text('AI 회고록 만들기'),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.deepPurple,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 200),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onPressed: () async {
                                final user = FirebaseAuth.instance.currentUser;
                                if (user == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('로그인이 필요합니다.'),
                                    ),
                                  );
                                  return;
                                }
                                final profileData = await _getUserProfile(
                                  user.uid,
                                );
                                if (mounted) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (context) => MythSetupPage(
                                            userProfile: profileData ?? {},
                                          ),
                                    ),
                                  );
                                }
                              },
                              child: const Text('기업 신화 생성하기'),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2E8B57),
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 200),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (context) =>
                                            const SmartFarmGreetingPage(),
                                  ),
                                );
                              },
                              child: const Text('스마트팜 대표님을 위한 신문 아카이브'),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Align(
                          alignment: Alignment.bottomRight,
                          child: TextButton(
                            onPressed: () async {
                              const url = 'https://parana-v2.web.app/';
                              if (await canLaunchUrl(Uri.parse(url))) {
                                await launchUrl(Uri.parse(url));
                              } else {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('URL을 열 수 없습니다: $url'),
                                    ),
                                  );
                                }
                              }
                            },
                            child: const Text(
                              'Parana의 다른 서비스 바로가기 >',
                              style: TextStyle(
                                color: Colors.blue,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '홈'),
          BottomNavigationBarItem(
            icon: Icon(Icons.auto_stories_outlined),
            label: '나의 서재',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.apps), label: '내 프로필'),
        ],
      ),
    );
  }
}
