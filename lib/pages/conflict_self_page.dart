import 'package:flutter/material.dart';
import 'after_interview_info.dart';

class ConflictSelfPage extends StatefulWidget {
  const ConflictSelfPage({super.key});

  @override
  State<ConflictSelfPage> createState() => _ConflictSelfPageState();
}

class _ConflictSelfPageState extends State<ConflictSelfPage> {
  final List<String> _questions = [
    '생산성 증가가 되지 않고 초과근무가 많아진 기업',
    '직장내 갈등으로 직원들의 협업이 안되는 기업',
    '최근 이직율이 높아진 기업',
    '직원 이탈로 인한 노무비가 증가가 된 기업',
    '외부 요인없이 생산성이 감소한 기업',
    '조직원의 갈등요인으로 인한 시간낭비 증가 기업',
    '직장인의 스트레스와 갈등의 빈도가 높은 기업',
  ];

  final List<String> _descriptions = [
    'Australian Journal of Business and Management Research 등에 의하면 갈등교육을 이수한 조직에서 평균 22%의 생산성이 향상되었다고 함',
    '2021년 로빈쇼트 박사는 갈등교육을 통하여 95%가 긍정적인 갈등해결에 도움을 받고있다고 함',
    '2012년 콜롬비아 대학교에서 48.8%가 갈등 등으로 좋지 않은 기업문화를 통해서 높은 이직율을 보인다고 연구함',
    '2023년 갈등통계(잭플린)에 따르면 직원 이탈로 인한 채용 및 업무 손실이 50% 증가했으며, 관리자와 시급자의 급여 손실도 각각 18개월, 6개월 발생함.',
    '2023년 갈등통계(잭플린)의 보고에서 조직갈등으로 인한 업무처리 기간 증가 등의 이유로 18%의 생산성이 감소하였다고 함',
    '2023년 갈등통계(잭플린)의 보고에서 직장인의 40%가 갈등으로 인한 시간낭비를 겪고 있다고 함',
    '2023년 갈등통계(잭플린)의 보고에서 일상에 있는 직원 중 34%가 갈등을 겪으며, 34%가 직장 스트레스로 인해 갈등이 발생된다고 함',
  ];

  late List<bool> _isChecked;

  late List<bool> _isExpanded;

  @override
  void initState() {
    super.initState();
    _isChecked = List<bool>.filled(_questions.length, false);
    _isExpanded = List<bool>.filled(_questions.length, false);
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _showResultDialog(String resultText) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('자가진단 결과', textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                resultText,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, height: 1.5),
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              const Text(
                '해당 내용에 대한 세부적인 정보가 궁금하신가요?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            // '아니오' 버튼
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // 1. 다이얼로그 닫기
                Navigator.of(context).pop(); // 2. 자가진단 페이지 닫기
              },
              child: const Text('아니오'),
            ),
            // '예' 버튼
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(); // 다이얼로그 닫기
                // 새로운 정보 입력 페이지로 이동
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AfterInterviewInfoPage(),
                  ),
                );
              },
              child: const Text('예'),
            ),
          ],
        );
      },
    );
  }

  void _calculateResult() {
    final checkedCount = _isChecked.where((item) => item == true).length;
    String resultText;

    if (checkedCount >= 5) {
      resultText = '[5개 이상 체크]\n인식 컨트롤 불가능한 상태이며 빠른 시간 내 갈등 진단과 교육이 필요함.';
    } else if (checkedCount >= 3) {
      resultText = '[3개 이상 체크]\n기업의 경쟁력 확보와 각종 손실비용을 위해서 점검이 필요함.';
    } else {
      resultText = '[3개 미만 체크]\n자가 방법으로 갈등을 해소하는 방법이 형성되어 있으나 기업 성장을 위한 도입 권장';
    }

    _showResultDialog(resultText);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('갈등관리 자가진단표'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '현재 조직 상태에 해당하는 항목을\n모두 선택해주세요.',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Card(
                elevation: 2.0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListView.separated(
                  itemCount: _questions.length,
                  separatorBuilder:
                      (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    return ExpansionTile(
                      key: ValueKey('${index}_${_isExpanded[index]}'),
                      initiallyExpanded: _isExpanded[index],
                      onExpansionChanged: (bool expanded) {
                        setState(() {
                          _isExpanded[index] = expanded;
                        });
                      },
                      title: Text(_questions[index]),
                      leading: Checkbox(
                        value: _isChecked[index],
                        onChanged: (bool? value) {
                          setState(() {
                            _isChecked[index] = value ?? false;
                            _isExpanded[index] = _isChecked[index];
                          });
                        },
                        activeColor: Colors.green,
                      ),
                      children: <Widget>[
                        Container(
                          color: Colors.green.withOpacity(0.05),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 12.0,
                          ),
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _descriptions[index],
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _calculateResult,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[600],
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              child: const Text('결과 보기'),
            ),
          ],
        ),
      ),
    );
  }
}
