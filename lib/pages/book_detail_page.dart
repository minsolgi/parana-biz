import 'package:flutter/material.dart';

class BookDetailPage extends StatefulWidget {
  final Map<String, dynamic> bookData;
  const BookDetailPage({super.key, required this.bookData});

  @override
  State<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends State<BookDetailPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String title = widget.bookData['title'] ?? '제목 없음';
    final List<dynamic> pages =
        widget.bookData['pages'] as List<dynamic>? ?? [];

    return PopScope(
      canPop: false,
      onPopInvoked: (bool didPop) {
        if (didPop) return;
        Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: const Color(0xffa1cff0),
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
                          // ✅ 2. 이미지가 텍스트보다 먼저 오도록 순서 변경
                          if (imageUrl != null && imageUrl.trim().isNotEmpty)
                            _buildImage(imageUrl),

                          // 이미지와 텍스트 사이에 간격 추가
                          if ((text != null && text.trim().isNotEmpty) &&
                              (imageUrl != null && imageUrl.trim().isNotEmpty))
                            const SizedBox(height: 24),

                          // 텍스트
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

            if (pages.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 8.0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // 왼쪽 화살표 버튼
                    IconButton(
                      icon: const Icon(Icons.arrow_circle_left_outlined),
                      iconSize: 48,
                      // 첫 페이지일 경우 비활성화 색상 적용
                      color: Colors.white.withOpacity(
                        _currentPage > 0 ? 1.0 : 0.3,
                      ),
                      onPressed:
                          _currentPage > 0
                              ? () {
                                _pageController.previousPage(
                                  duration: const Duration(milliseconds: 400),
                                  curve: Curves.easeInOut,
                                );
                              }
                              : null, // 첫 페이지일 경우 버튼 비활성화
                    ),
                    // 페이지 번호
                    Text(
                      '${_currentPage + 1} / ${pages.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    // 오른쪽 화살표 버튼
                    IconButton(
                      icon: const Icon(Icons.arrow_circle_right_outlined),
                      iconSize: 48,
                      // 마지막 페이지일 경우 비활성화 색상 적용
                      color: Colors.white.withOpacity(
                        _currentPage < pages.length - 1 ? 1.0 : 0.3,
                      ),
                      onPressed:
                          _currentPage < pages.length - 1
                              ? () {
                                _pageController.nextPage(
                                  duration: const Duration(milliseconds: 400),
                                  curve: Curves.easeInOut,
                                );
                              }
                              : null, // 마지막 페이지일 경우 버튼 비활성화
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
