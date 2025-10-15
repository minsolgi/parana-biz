import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'toddler_book_detail_page.dart'; // 상세 페이지 import

class ToddlerBookListPage extends StatefulWidget {
  const ToddlerBookListPage({super.key});

  @override
  State<ToddlerBookListPage> createState() => _ToddlerBookListPageState();
}

class _ToddlerBookListPageState extends State<ToddlerBookListPage> {
  int? _previousBookCount;

  void _showCreationCompleteDialog() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
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
                  Icon(Icons.celebration_rounded, color: Colors.amber),
                  SizedBox(width: 8),
                  Text('🎨 그림책 도착!'),
                ],
              ),
              content: const Text(
                '새로운 그림책 생성이 완료되었습니다.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              actionsAlignment: MainAxisAlignment.center,
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('확인'),
                ),
              ],
            );
          },
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: const Color(0xfffdeec9),
      appBar: AppBar(
        title: const Text('나의 그림책 목록'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream:
            FirebaseFirestore.instance
                .collection('toddler_books') // ✅ 컬렉션 이름 변경
                .where('ownerUid', isEqualTo: currentUserId)
                .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('데이터를 불러오는 데 실패했습니다.'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                '아직 만든 그림책이 없습니다.',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            );
          }

          final bookDocs = snapshot.data!.docs;
          final currentBookCount = bookDocs.length;

          if (_previousBookCount != null &&
              currentBookCount > _previousBookCount!) {
            _showCreationCompleteDialog();
          }
          _previousBookCount = currentBookCount;

          return _BookPager(bookDocs: bookDocs);
        },
      ),
    );
  }
}

class _BookPager extends StatefulWidget {
  final List<QueryDocumentSnapshot> bookDocs;
  const _BookPager({required this.bookDocs});

  @override
  State<_BookPager> createState() => __BookPagerState();
}

class __BookPagerState extends State<_BookPager> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const int itemsPerPage = 4;
    final int pageCount = (widget.bookDocs.length / itemsPerPage).ceil();

    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: pageCount,
            onPageChanged: (page) => setState(() => _currentPage = page),
            itemBuilder: (context, pageIndex) {
              final startIndex = pageIndex * itemsPerPage;
              final endIndex =
                  (startIndex + itemsPerPage > widget.bookDocs.length)
                      ? widget.bookDocs.length
                      : startIndex + itemsPerPage;
              final pageItems = widget.bookDocs.sublist(startIndex, endIndex);

              return GridView.builder(
                padding: const EdgeInsets.all(20),
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 20,
                  mainAxisSpacing: 20,
                  childAspectRatio: 0.8,
                ),
                itemCount: pageItems.length,
                itemBuilder: (context, index) {
                  return _BookCard(bookDoc: pageItems[index]);
                },
              );
            },
          ),
        ),
        if (pageCount > 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed:
                      _currentPage > 0
                          ? () => _pageController.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeIn,
                          )
                          : null,
                  icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                ),
                Text(
                  '${_currentPage + 1} / $pageCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed:
                      _currentPage < pageCount - 1
                          ? () => _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeIn,
                          )
                          : null,
                  icon: const Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BookCard extends StatelessWidget {
  final QueryDocumentSnapshot bookDoc;
  const _BookCard({required this.bookDoc});

  Future<void> _showDeleteConfirmDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('삭제 확인'),
          content: const Text('정말로 이 그림책을 삭제하시겠습니까?'),
          actions: <Widget>[
            TextButton(
              child: const Text('아니오'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('예'),
              onPressed: () async {
                try {
                  // ✅ 그림책 전용 삭제 함수 호출
                  final callable = FirebaseFunctions.instance.httpsCallable(
                    'deleteToddlerBook',
                  );
                  await callable.call({'bookId': bookDoc.id});

                  if (context.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('그림책이 삭제되었습니다.')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('삭제 중 오류가 발생했습니다: $e')),
                    );
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bookData = bookDoc.data() as Map<String, dynamic>;
    final Timestamp createdAt = bookData['createdAt'] ?? Timestamp.now();
    final String dateString = DateFormat('yy.MM.dd').format(createdAt.toDate());
    final String title = bookData['title'] ?? '제목 없음';

    return Stack(
      children: [
        // 카드 본문
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ToddlerBookDetailPage(bookId: bookDoc.id),
              ),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            // ✅ [수정] 중앙에 제목만 오도록 Column 내부를 단순화했습니다.
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 4, // 제목이 길 경우를 대비해 최대 4줄까지 허용
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ),
        // 날짜 표시
        Positioned(
          top: 12,
          left: 12,
          child: Text(
            dateString,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        // 삭제 버튼
        Positioned(
          top: 4,
          right: 4,
          child: Material(
            color: Colors.transparent,
            child: IconButton(
              icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
              onPressed: () => _showDeleteConfirmDialog(context),
            ),
          ),
        ),
      ],
    );
  }
}
