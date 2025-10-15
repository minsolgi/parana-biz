import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'smart_farm_article_detail.dart'; // 상세 페이지 import

class SmartFarmArticlePage extends StatefulWidget {
  const SmartFarmArticlePage({super.key});

  @override
  State<SmartFarmArticlePage> createState() => _SmartFarmArticlePageState();
}

class _SmartFarmArticlePageState extends State<SmartFarmArticlePage> {
  int? _previousArticleCount;

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
                  Icon(Icons.article_rounded, color: Colors.blueAccent),
                  SizedBox(width: 8),
                  Text('📰 기사 도착!'),
                ],
              ),
              content: const Text(
                '새로운 신문기사 생성이 완료되었습니다.',
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
      backgroundColor: Colors.grey.shade200, // 테마에 맞는 배경색으로 변경
      appBar: AppBar(
        title: const Text('나의 보도기사 목록'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream:
            FirebaseFirestore.instance
                .collection('newspaper_articles') // ✅ 컬렉션 이름 변경
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
            return const Center(child: Text('아직 생성된 신문기사가 없습니다.'));
          }

          final articleDocs = snapshot.data!.docs;
          final currentArticleCount = articleDocs.length;

          if (_previousArticleCount != null &&
              currentArticleCount > _previousArticleCount!) {
            _showCreationCompleteDialog();
          }
          _previousArticleCount = currentArticleCount;

          return _ArticlePager(articleDocs: articleDocs);
        },
      ),
    );
  }
}

class _ArticlePager extends StatefulWidget {
  final List<QueryDocumentSnapshot> articleDocs;
  const _ArticlePager({required this.articleDocs});

  @override
  State<_ArticlePager> createState() => __ArticlePagerState();
}

class __ArticlePagerState extends State<_ArticlePager> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const int itemsPerPage = 6; // 한 페이지에 더 많이 표시하도록 수정
    final int pageCount = (widget.articleDocs.length / itemsPerPage).ceil();

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
                  (startIndex + itemsPerPage > widget.articleDocs.length)
                      ? widget.articleDocs.length
                      : startIndex + itemsPerPage;
              final pageItems = widget.articleDocs.sublist(
                startIndex,
                endIndex,
              );

              return ListView.builder(
                // GridView 대신 ListView로 변경하여 가독성 향상
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: pageItems.length,
                itemBuilder: (context, index) {
                  return _ArticleCard(articleDoc: pageItems[index]);
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
                  icon: Icon(Icons.arrow_back_ios, color: Colors.grey.shade700),
                ),
                Text(
                  '${_currentPage + 1} / $pageCount',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
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
                  icon: Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ArticleCard extends StatelessWidget {
  final QueryDocumentSnapshot articleDoc;
  const _ArticleCard({required this.articleDoc});

  Future<void> _showDeleteConfirmDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('삭제 확인'),
          content: const Text('정말로 이 신문기사를 삭제하시겠습니까?'),
          actions: <Widget>[
            TextButton(
              child: const Text('아니오'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('예'),
              onPressed: () async {
                try {
                  // ✅ 신문기사 전용 삭제 함수 호출 (추후 생성 필요)
                  final callable = FirebaseFunctions.instance.httpsCallable(
                    'deleteNewspaperArticle',
                  );
                  await callable.call({'articleId': articleDoc.id});
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('신문기사가 삭제되었습니다.')),
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
    final articleData = articleDoc.data() as Map<String, dynamic>;
    final Timestamp createdAt = articleData['createdAt'] ?? Timestamp.now();
    final String dateString = DateFormat(
      'yyyy.MM.dd',
    ).format(createdAt.toDate());
    final String headline = articleData['headline'] ?? '제목 없음';

    return Card(
      // UI를 Card 위젯으로 변경하여 신문기사 목록 느낌을 강조
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          vertical: 12,
          horizontal: 16,
        ),
        title: Text(
          headline,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Text(
            dateString,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
          onPressed: () => _showDeleteConfirmDialog(context),
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (context) =>
                      SmartFarmArticleDetailPage(articleId: articleDoc.id),
            ),
          );
        },
      ),
    );
  }
}
