import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'appbar.dart'; // 사용자 정의 AppBar (CSAppBar)
import 'dart:async';
import 'dart:math'; // 랜덤 선택
import 'questions_common.dart'; // 공통 코드 임포트
import 'question_list.dart';

class QuestionBankPage extends StatefulWidget {
  final String title;
  const QuestionBankPage({super.key, required this.title});

  @override
  State<QuestionBankPage> createState() => _QuestionBankPageState();
}

// 1. QuestionStateMixin 적용
class _QuestionBankPageState extends State<QuestionBankPage> with QuestionStateMixin<QuestionBankPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _selectedGrade;
  int? _numberOfRandomQuestions;

  List<String> _gradeOptions = [];
  List<Map<String, String>> _parsedDocIds = [];

  bool _isLoadingOptions = true;
  bool _isLoadingQuestions = false;
  String _errorMessage = '';

  List<Map<String, dynamic>> _randomlySelectedQuestions = [];

  // 2. Mixin의 abstract 멤버 구현
  @override
  List<Map<String, dynamic>> get questions => _randomlySelectedQuestions;

  @override
  void clearQuestionsList() {
    _randomlySelectedQuestions = [];
    _errorMessage = '';
  }

  // initState는 페이지 고유 로직이므로 유지
  @override
  void initState() {
    super.initState();
    _fetchAndParseAllDocumentIdsForOptions();
  }

  // 3. 공통 메서드들(_getController, _clearAll, _dispose, _checkAnswer 등)은 모두 삭제됨

  Future<void> _fetchAndParseAllDocumentIdsForOptions() async {
    if (!mounted) return;
    setState(() => _isLoadingOptions = true);
    _parsedDocIds.clear();
    _gradeOptions.clear();
    final Set<String> grades = {};
    try {
      final snapshot = await _firestore.collection('exam').get();
      if (!mounted) return;
      for (var doc in snapshot.docs) {
        final parts = doc.id.split('-');
        if (parts.length >= 3) {
          String grade = parts.last.trim();
          _parsedDocIds.add({'docId': doc.id, 'grade': grade});
          grades.add(grade);
        } else {
          print("Warning: Could not parse grade from doc ID: ${doc.id}");
        }
      }
      _gradeOptions = grades.toList()..sort();
      if (_gradeOptions.isEmpty && mounted) _errorMessage = '등급 데이터를 찾을 수 없습니다.';
    } catch (e) {
      if (mounted) _errorMessage = '옵션 로딩 중 오류: $e';
    } finally {
      if (mounted) setState(() => _isLoadingOptions = false);
    }
  }

  void _updateSelectedGrade(String? grade) {
    if (!mounted) return;
    setState(() {
      _selectedGrade = grade;
      clearAllAttemptStatesAndQuestions();
    });
  }

  Future<void> _fetchAndGenerateRandomExam() async {
    if (_selectedGrade == null) {
      if (mounted) setState(() { _errorMessage = '먼저 등급을 선택해주세요.'; clearAllAttemptStatesAndQuestions(); });
      return;
    }
    if (_numberOfRandomQuestions == null || _numberOfRandomQuestions! <= 0) {
      if (mounted) setState(() { _errorMessage = '출제할 문제 수를 1 이상 입력해주세요.'; clearAllAttemptStatesAndQuestions(); });
      return;
    }
    if (mounted) setState(() { _isLoadingQuestions = true; _errorMessage = ''; clearAllAttemptStatesAndQuestions(); });

    List<Map<String, dynamic>> pooledMainQuestions = [];
    try {
      for (var docInfo in _parsedDocIds) {
        if (docInfo['grade'] == _selectedGrade) {
          final docSnapshot = await _firestore.collection('exam').doc(docInfo['docId']!).get();
          if (!mounted) return;
          if (docSnapshot.exists) {
            final docData = docSnapshot.data();
            if (docData != null) {
              List<String> sortedMainKeys = docData.keys.toList()..sort((a, b) => (int.tryParse(a) ?? 99999).compareTo(int.tryParse(b) ?? 99999));
              for (String mainKey in sortedMainKeys) {
                var mainValue = docData[mainKey];
                if (mainValue is Map<String, dynamic>) {
                  Map<String, dynamic> questionData = Map<String, dynamic>.from(mainValue);
                  questionData['sourceExamId'] = docInfo['docId']!;
                  if (!questionData.containsKey('no') || (questionData['no'] as String?).isNullOrEmpty) {
                    questionData['no'] = mainKey;
                  }
                  pooledMainQuestions.add(cleanNewlinesRecursive(questionData)); // Mixin의 메서드 사용
                }
              }
            }
          }
        }
      }

      if (pooledMainQuestions.isNotEmpty) {
        if (pooledMainQuestions.length <= _numberOfRandomQuestions!) {
          _randomlySelectedQuestions = List.from(pooledMainQuestions);
        } else {
          final random = Random();
          _randomlySelectedQuestions = List.generate(_numberOfRandomQuestions!, (_) {
            return pooledMainQuestions.removeAt(random.nextInt(pooledMainQuestions.length));
          });
        }
      } else { _errorMessage = "'$_selectedGrade' 등급에 해당하는 문제가 전체 시험 데이터에 없습니다."; }
    } catch (e, s) {
      _errorMessage = '문제 풀 구성 중 오류 발생.';
      print('Error generating random exam: $e\nStack: $s');
    } finally {
      if (mounted) setState(() => _isLoadingQuestions = false);
    }
  }

  // 4. 특정 문제 데이터 아래의 모든 최하위 문제(채점 대상)들을 재귀적으로 찾아 리스트로 반환합니다.
  List<Map<String, dynamic>> _getAllLeafNodes(Map<String, dynamic> questionData) {
    final List<Map<String, dynamic>> leaves = [];

    final bool hasSubQuestions = questionData.containsKey('sub_questions') && questionData['sub_questions'] is Map && (questionData['sub_questions'] as Map).isNotEmpty;
    final bool hasSubSubQuestions = questionData.containsKey('sub_sub_questions') && questionData['sub_sub_questions'] is Map && (questionData['sub_sub_questions'] as Map).isNotEmpty;

    if (!hasSubQuestions && !hasSubSubQuestions) {
      // 자식이 없으면 자기 자신이 최하위 문제(leaf)입니다.
      // 단, 채점 가능한 유형(예: fullscore가 있는 문제)만 추가하는 것이 좋습니다.
      if (questionData.containsKey('fullscore')) {
        leaves.add(questionData);
      }
    } else {
      // 자식이 있으면 자식들을 따라 재귀적으로 탐색합니다.
      if (hasSubQuestions) {
        final subMap = questionData['sub_questions'] as Map<String, dynamic>;
        for (final subQuestion in subMap.values.whereType<Map<String, dynamic>>()) {
          leaves.addAll(_getAllLeafNodes(subQuestion));
        }
      }
      if (hasSubSubQuestions) {
        final subSubMap = questionData['sub_sub_questions'] as Map<String, dynamic>;
        for (final subSubQuestion in subSubMap.values.whereType<Map<String, dynamic>>()) {
          leaves.addAll(_getAllLeafNodes(subSubQuestion));
        }
      }
    }
    return leaves;
  }

  // 5. 채점 관련 메서드

  int _calculateUserScore() {
    int totalScore = 0;
    // `questions` getter를 통해 각 페이지의 문제 목록을 가져옵니다.
    for (final questionData in questions) {
      final bool hasChildren = (questionData.containsKey('sub_questions') && (questionData['sub_questions'] as Map).isNotEmpty) ||
          (questionData.containsKey('sub_sub_questions') && (questionData['sub_sub_questions'] as Map).isNotEmpty);

      if (hasChildren) {
        // --- 컨테이너 문제 채점 로직 ---
        final List<Map<String, dynamic>> leafChildren = _getAllLeafNodes(questionData);
        if (leafChildren.isEmpty) continue; // 채점할 하위 문제가 없으면 건너뜀

        bool allChildrenCorrect = true;
        int partialScore = 0;

        for (final leaf in leafChildren) {
          final uniqueId = leaf['uniqueDisplayId'] as String?;
          if (uniqueId != null && submissionStatus[uniqueId] == true) {
            // 맞힌 문제의 점수를 부분 점수에 더해놓습니다.
            final score = leaf['fullscore'];
            partialScore += (score is int ? score : int.tryParse(score.toString()) ?? 0);
          } else {
            // 하나라도 틀리거나 안 푼 문제가 있으면 '모두 정답' 플래그를 false로 설정합니다.
            allChildrenCorrect = false;
          }
        }

        if (allChildrenCorrect) {
          // 모든 하위 문제를 맞혔다면, 상위 문제(컨테이너)의 fullscore를 부여합니다.
          final parentScore = questionData['fullscore'];
          totalScore += (parentScore is int ? parentScore : int.tryParse(parentScore.toString()) ?? 0);
        } else {
          // 일부만 맞혔다면, 맞힌 문제들의 점수 합(partialScore)을 부여합니다.
          totalScore += partialScore;
        }

      } else {
        // --- 독립 문제 채점 로직 ---
        final uniqueId = questionData['uniqueDisplayId'] as String?;
        if (uniqueId != null && submissionStatus[uniqueId] == true && questionData.containsKey('fullscore')) {
          final score = questionData['fullscore'];
          totalScore += (score is int ? score : int.tryParse(score.toString()) ?? 0);
        }
      }
    }
    return totalScore;
  }

  int _calculateMaxScore() {
    int maxScore = 0;
    // `questions` getter를 통해 각 페이지의 문제 목록을 가져옵니다.
    for (final questionData in questions) {
      // 컨테이너든 독립 문제든, 총점 계산 시에는 최상위 레벨 문제의 fullscore만 합산합니다.
      // 이것이 '하위 문제 합이 상위 점수를 초과해도 상위 점수만 인정' 규칙과 일치합니다.
      if (questionData.containsKey('fullscore')) {
        final score = questionData['fullscore'];
        maxScore += (score is int ? score : int.tryParse(score.toString()) ?? 0);
      }
    }
    return maxScore;
  }

  void _showGradingResult() {
    final int userScore = _calculateUserScore();
    final int maxScore = _calculateMaxScore();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('💯 채점 결과'),
          content: Text(
            '총점: $maxScore점\n획득 점수: $userScore점',
            style: const TextStyle(fontSize: 16, height: 1.5),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('확인'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildBody() {
    if (_isLoadingQuestions) return const Center(child: CircularProgressIndicator());
    if (_errorMessage.isNotEmpty && _randomlySelectedQuestions.isEmpty) return Center(child: Text(_errorMessage, style: const TextStyle(color: Colors.red)));
    if (_randomlySelectedQuestions.isEmpty) return Center(child: Padding(
      padding: const EdgeInsets.all(16.0),
      child: Text(_selectedGrade == null ? '먼저 등급과 문제 수를 선택하고 시험지를 생성하세요.' : '선택한 등급의 문제가 없거나, 문제 수가 유효하지 않습니다.', textAlign: TextAlign.center),
    ));

    // REVISED: 공통 위젯 사용
    return QuestionListView(
      questions: _randomlySelectedQuestions,
      getControllers: getControllersForQuestion,
      onCheckAnswer: (questionData, parentData) => checkAnswer(questionData, parentData),
      onTryAgain: tryAgain,
      submissionStatus: submissionStatus,
      userSubmittedAnswers: userSubmittedAnswers,
      aiGradingResults: aiGradingResults,
      titleBuilder: (context, questionData, index) {
        final pageOrderNo = "${index + 1}";
        final originalNo = questionData['no'] as String?;
        final sourceExamId = questionData['sourceExamId'] as String? ?? '출처 미상';
        return Text('문제 $pageOrderNo (출처: $sourceExamId - ${originalNo ?? "N/A"}번)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5));
      },
      subtitleBuilder: (context, questionData, index) {
        final questionText = questionData['question'] as String? ?? '';
        return questionText.isNotEmpty
            ? Padding(padding: const EdgeInsets.only(top: 5.0), child: Text(questionText, style: const TextStyle(fontSize: 15.0, color: Colors.black87, height: 1.4)))
            : null;
      },
    );
  }

  // 4. 복잡했던 위젯 빌드 함수들(_buildQuestionHierarchyWidgets, _buildQuestionInteractiveDisplay)은 모두 삭제됨

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CSAppBar(title: widget.title),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 8.0),
            child: Column(
              children: [
                if (_isLoadingOptions) const Center(child: CircularProgressIndicator())
                else DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: '등급 선택', border: OutlineInputBorder()),
                  value: _selectedGrade,
                  hint: const Text('풀어볼 등급을 선택하세요'),
                  items: _gradeOptions.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                  onChanged: _updateSelectedGrade,
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(labelText: '랜덤 출제 문제 수 (예: 18)', border: OutlineInputBorder(), isDense: true),
                  keyboardType: TextInputType.number,
                  onChanged: (value) => setState(() => _numberOfRandomQuestions = int.tryParse(value)),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: (_selectedGrade == null || _isLoadingQuestions || _numberOfRandomQuestions == null || _numberOfRandomQuestions! <= 0)
                      ? null : _fetchAndGenerateRandomExam,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), minimumSize: const Size(double.infinity, 44)),
                  child: _isLoadingQuestions ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)) : const Text('랜덤 시험지 생성', style: TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: _randomlySelectedQuestions.isNotEmpty
          ? FloatingActionButton.extended(
        onPressed: _showGradingResult, // 버튼 클릭 시 채점 결과 표시
        label: const Text('채점하기'),
        icon: const Icon(Icons.check_circle_outline),
        tooltip: '지금까지 푼 문제 채점하기',
      )
          : null, // 문제
    );
  }
}