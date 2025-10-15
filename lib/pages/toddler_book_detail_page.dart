import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ToddlerBookDetailPage extends StatefulWidget {
  final String bookId;

  const ToddlerBookDetailPage({super.key, required this.bookId});

  @override
  State<ToddlerBookDetailPage> createState() => _ToddlerBookDetailPageState();
}

class _ToddlerBookDetailPageState extends State<ToddlerBookDetailPage> {
  // ✅ PageController와 페이지 상태 변수를 State의 멤버로 선언
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // ✅ 데이터를 담을 변수와 로딩 상태 변수 추가
  Map<String, dynamic>? _bookData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // ✅ initState에서 데이터를 한 번만 불러옵니다.
    _fetchBookData();
  }

  Future<void> _fetchBookData() async {
    try {
      final doc =
          await FirebaseFirestore.instance
              .collection('toddler_books')
              .doc(widget.bookId)
              .get();
      if (doc.exists) {
        if (mounted) {
          setState(() {
            _bookData = doc.data();
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 로딩 중이거나 데이터가 없을 때의 UI
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_bookData == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('그림책을 불러올 수 없거나 삭제되었습니다.')),
      );
    }

    final String title = _bookData!['title'] ?? '제목 없음';
    final List<dynamic> pages = _bookData!['pages'] as List<dynamic>? ?? [];

    return PopScope(
      canPop: false,
      onPopInvoked: (bool didPop) {
        if (didPop) return;
        Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: const Color(0xfffdeec9),
        appBar: AppBar(
          title: Text(title),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: pages.length,
                onPageChanged: (page) {
                  setState(() {
                    _currentPage = page;
                  });
                },
                itemBuilder: (context, index) {
                  final pageData = pages[index] as Map<String, dynamic>;
                  final String? text = pageData['text'];
                  final String? imageUrl = pageData['imageUrl'];

                  return _buildContentCard(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (imageUrl != null && imageUrl.trim().isNotEmpty)
                            _buildImage(imageUrl),
                          if ((text != null && text.trim().isNotEmpty) &&
                              (imageUrl != null && imageUrl.trim().isNotEmpty))
                            const SizedBox(height: 24),
                          if (text != null && text.trim().isNotEmpty)
                            Text(
                              text,
                              style: const TextStyle(fontSize: 17, height: 1.8),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            // ✅ 이제 이 로직은 안정적으로 동작합니다.
            if (pages.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 8.0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_circle_left_outlined),
                      iconSize: 48,
                      color: Colors.black.withOpacity(
                        _currentPage > 0 ? 0.7 : 0.2,
                      ),
                      onPressed:
                          _currentPage > 0
                              ? () {
                                _pageController.previousPage(
                                  duration: const Duration(milliseconds: 400),
                                  curve: Curves.easeInOut,
                                );
                              }
                              : null,
                    ),
                    Text(
                      '${_currentPage + 1} / ${pages.length}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_circle_right_outlined),
                      iconSize: 48,
                      color: Colors.black.withOpacity(
                        _currentPage < pages.length - 1 ? 0.7 : 0.2,
                      ),
                      onPressed:
                          _currentPage < pages.length - 1
                              ? () {
                                _pageController.nextPage(
                                  duration: const Duration(milliseconds: 400),
                                  curve: Curves.easeInOut,
                                );
                              }
                              : null,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentCard({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildImage(String imageUrl) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          imageUrl,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return const Center(child: CircularProgressIndicator());
          },
          errorBuilder: (context, error, stackTrace) {
            return const Center(
              child: Column(
                children: [
                  Icon(Icons.broken_image, size: 50, color: Colors.grey),
                  SizedBox(height: 8),
                  Text('이미지를 불러올 수 없습니다.'),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
