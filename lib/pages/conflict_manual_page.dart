import 'package:flutter/material.dart';

class ConflictManualPage extends StatefulWidget {
  const ConflictManualPage({super.key});

  @override
  State<ConflictManualPage> createState() => _ConflictManualPageState();
}

class _ConflictManualPageState extends State<ConflictManualPage> {
  // 페이지 컨트롤러와 이미지 목록 초기화
  final PageController _pageController = PageController();
  final List<String> _imagePaths = List.generate(
    8,
    (index) => 'assets/conflict_image_${index + 1}.png',
  );
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 전체적인 톤을 주황색으로 변경
      backgroundColor: Colors.orange.shade50,
      appBar: AppBar(
        title: const Text(
          '갈등 관리 메뉴얼',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        centerTitle: true,
        elevation: 0.5,
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: _imagePaths.length,
              onPageChanged: (page) {
                setState(() {
                  _currentPage = page;
                });
              },
              itemBuilder: (context, index) {
                return _buildImageCard(_imagePaths[index]);
              },
            ),
          ),
          if (_imagePaths.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back_ios_new,
                      // 아이콘 색상 변경
                      color:
                          _currentPage > 0
                              ? Colors.orange.shade800
                              : Colors.grey.shade400,
                    ),
                    onPressed:
                        _currentPage > 0
                            ? () => _pageController.previousPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                            )
                            : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Text(
                      '${_currentPage + 1} / ${_imagePaths.length}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.arrow_forward_ios,
                      // 아이콘 색상 변경
                      color:
                          _currentPage < _imagePaths.length - 1
                              ? Colors.orange.shade800
                              : Colors.grey.shade400,
                    ),
                    onPressed:
                        _currentPage < _imagePaths.length - 1
                            ? () => _pageController.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                            )
                            : null,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // 이미지 카드 UI를 위한 헬퍼 위젯
  Widget _buildImageCard(String imagePath) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.asset(
          imagePath,
          fit: BoxFit.contain, // 이미지가 잘리지 않고 카드 안에 꽉 차도록 설정
          // 이미지를 불러오지 못했을 경우를 대비한 에러 처리
          errorBuilder: (context, error, stackTrace) {
            return const Center(
              child: Text(
                '이미지를 불러올 수 없습니다.',
                style: TextStyle(color: Colors.red),
              ),
            );
          },
        ),
      ),
    );
  }
}
