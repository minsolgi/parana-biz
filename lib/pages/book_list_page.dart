import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'book_detail_page.dart';

class BookListPage extends StatefulWidget {
  const BookListPage({super.key});

  @override
  State<BookListPage> createState() => _BookListPageState();
}

class _BookListPageState extends State<BookListPage> {
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
                  Text('🎉 회고록 도착!'),
                ],
              ),
              content: const Text(
                '새로운 회고록 생성이 완료되었습니다.',
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
      backgroundColor: const Color(0xffa1cff0),
      appBar: AppBar(
        title: const Text('나의 회고록 목록'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream:
            FirebaseFirestore.instance
                .collection('books')
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
                '아직 작성한 회고록이 없습니다.',
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
            onPageChanged: (page) {
              setState(() {
                _currentPage = page;
              });
            },
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

// ✅ 2. _BookCard 위젯 전체 수정
class _BookCard extends StatelessWidget {
  // bookData 대신 bookDoc을 받아서 문서 ID에 접근할 수 있도록 함
  final QueryDocumentSnapshot bookDoc;
  const _BookCard({super.key, required this.bookDoc});

  // 삭제 확인 대화상자를 띄우는 함수
  Future<void> _showDeleteConfirmDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('삭제 확인'),
          content: const Text('정말로 이 회고록을 삭제하시겠습니까?'),
          actions: <Widget>[
            TextButton(
              child: const Text('아니오'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('예'),
              onPressed: () async {
                try {
                  // Firestore에서 문서 삭제
                  await FirebaseFirestore.instance
                      .collection('books')
                      .doc(bookDoc.id)
                      .delete();

                  if (context.mounted) {
                    Navigator.of(context).pop(); // 대화상자 닫기
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('회고록이 삭제되었습니다.')),
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
    // bookDoc에서 실제 데이터 맵을 추출
    final bookData = bookDoc.data() as Map<String, dynamic>;

    final Timestamp createdAt = bookData['createdAt'] ?? Timestamp.now();
    final String dateString = DateFormat('M.d').format(createdAt.toDate());
    final String titlePreview = bookData['title'] ?? '제목 없음';
    final String period = bookData['rawQnA']?['start'] ?? '어린 시절';
    final String keywords = bookData['keywords'] ?? '';

    return Stack(
      children: [
        // 기존 카드 UI
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => BookDetailPage(bookData: bookData),
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
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  Text(
                    dateString,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    titlePreview.contains('회고록') ? '회고록' : '회고록',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (keywords.isNotEmpty)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.tag, size: 18, color: Colors.grey[700]),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            keywords,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.grey[800],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      '-',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
        // 시기 표시 태그
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xfff5a8a8).withOpacity(0.8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              period,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
        // ✅ 3. 삭제 버튼 추가
        Positioned(
          top: 4,
          right: 4,
          // Material 위젯으로 감싸서 렌더링 우선순위를 확보
          child: Material(
            color: Colors.transparent, // 배경색은 투명하게
            child: IconButton(
              icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
              onPressed: () {
                _showDeleteConfirmDialog(context);
              },
            ),
          ),
        ),
      ],
    );
  }
}
