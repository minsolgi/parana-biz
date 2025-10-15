import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class SmartFarmArticleDetailPage extends StatefulWidget {
  final String articleId;

  const SmartFarmArticleDetailPage({super.key, required this.articleId});

  @override
  State<SmartFarmArticleDetailPage> createState() =>
      _SmartFarmArticleDetailPageState();
}

class _SmartFarmArticleDetailPageState
    extends State<SmartFarmArticleDetailPage> {
  Map<String, dynamic>? _articleData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchArticleData();
  }

  Future<void> _fetchArticleData() async {
    try {
      final doc =
          await FirebaseFirestore.instance
              .collection('newspaper_articles') // ✅ 컬렉션 이름 변경
              .doc(widget.articleId)
              .get();
      if (doc.exists && mounted) {
        setState(() {
          _articleData = doc.data();
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_articleData == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('기사를 불러올 수 없거나 삭제되었습니다.')),
      );
    }

    final String headline = _articleData!['headline'] ?? '제목 없음';
    final String body = _articleData!['body'] ?? '내용 없음';
    final String? imageUrl = _articleData!['imageUrl'];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(headline, maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: SingleChildScrollView(
        // ✅ PageView 대신 SingleChildScrollView 사용
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. 헤드라인
            Text(
              headline,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),

            // 2. 대표 이미지
            if (imageUrl != null && imageUrl.isNotEmpty) _buildImage(imageUrl),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 24),

            // 3. 기사 본문
            Text(
              body,
              style: const TextStyle(
                fontSize: 17,
                height: 1.8,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage(String imageUrl) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.hide_image_outlined, size: 50, color: Colors.grey),
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
