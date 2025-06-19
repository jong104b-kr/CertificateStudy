import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'appbar.dart'; // 사용자 정의 AppBar (CSAppBar)
import 'dart:async';
import 'questions_common.dart'; // 공통 코드 임포트
import 'question_list.dart';

class PublishedExamPage extends StatefulWidget {
  final String title;
  const PublishedExamPage({super.key, required this.title});

  @override
  State<PublishedExamPage> createState() => _PublishedExamPageState();
}

// 1. QuestionStateMixin 적용
class _PublishedExamPageState extends State<PublishedExamPage> with QuestionStateMixin<PublishedExamPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _selectedYear;
  String? _selectedRound;
  String? _selectedGrade;

  List<String> _yearOptions = [];
  List<String> _filteredRoundOptions = [];
  List<String> _filteredGradeOptions = [];

  List<Map<String, String>> _parsedDocIds = [];

  bool _isLoadingOptions = true;
  bool _isLoadingQuestions = false;
  String _errorMessage = '';
  List<Map<String, dynamic>> _questions = [];

  // 2. Mixin의 abstract 멤버 구현
  @override
  List<Map<String, dynamic>> get questions => _questions;

  @override
  void clearQuestionsList() {
    _questions = [];
    _errorMessage = '';
  }

  @override
  void initState() {
    super.initState();
    _fetchAndParseDocumentIds();
  }

  // 3. 공통 메서드들(_getController, _clearAll, _dispose, _checkAnswer 등)은 모두 삭제됨

  Map<String, String>? _parseDocumentId(String docId) {
    final parts = docId.split('-');
    if (parts.length == 3) {
      return {'year': parts[0].trim(), 'round': parts[1].trim(), 'grade': parts[2].trim(), 'docId': docId};
    }
    return null;
  }

  Future<void> _fetchAndParseDocumentIds() async {
    if (!mounted) return;
    setState(() => _isLoadingOptions = true);
    _parsedDocIds.clear();
    _yearOptions.clear();
    final Set<String> years = {};

    try {
      final QuerySnapshot snapshot = await _firestore.collection('exam').get();
      if (!mounted) return;
      for (var doc in snapshot.docs) {
        final parsed = _parseDocumentId(doc.id);
        if (parsed != null) {
          _parsedDocIds.add(parsed);
          years.add(parsed['year']!);
        }
      }
      _yearOptions = years.toList()..sort((a, b) => b.compareTo(a));
      if (_yearOptions.isEmpty && mounted) _errorMessage = '시험 데이터를 찾을 수 없습니다.';
    } catch (e) {
      if (mounted) _errorMessage = '옵션 정보 로딩 중 오류: $e';
    } finally {
      if (mounted) setState(() => _isLoadingOptions = false);
    }
  }

  void _updateYearSelected(String? year) {
    if (!mounted) return;
    setState(() {
      _selectedYear = year; _selectedRound = null; _selectedGrade = null;
      _filteredRoundOptions = []; _filteredGradeOptions = [];
      clearAllAttemptStatesAndQuestions();
      if (year != null) {
        _filteredRoundOptions = _parsedDocIds.where((p) => p['year'] == year).map((p) => p['round']!).toSet().toList()..sort();
      }
    });
  }

  void _updateRoundSelected(String? round) {
    if (!mounted) return;
    setState(() {
      _selectedRound = round; _selectedGrade = null;
      _filteredGradeOptions = [];
      clearAllAttemptStatesAndQuestions();
      if (_selectedYear != null && round != null) {
        _filteredGradeOptions = _parsedDocIds.where((p) => p['year'] == _selectedYear && p['round'] == round).map((p) => p['grade']!).toSet().toList()..sort();
      }
    });
  }

  void _updateGradeSelected(String? grade) {
    if (!mounted) return;
    setState(() {
      _selectedGrade = grade;
      clearAllAttemptStatesAndQuestions();
    });
  }

  List<int> _parseQuestionNumberString(String? questionNoStr) {
    if (questionNoStr.isNullOrEmpty) return [99999, 99999];
    final parts = questionNoStr!.split('_');
    return [int.tryParse(parts[0]) ?? 99999, parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0];
  }

  Future<void> _fetchQuestions() async {
    if (_selectedYear == null || _selectedRound == null || _selectedGrade == null) {
      if (mounted) setState(() { _errorMessage = '모든 항목(년도, 회차, 등급)을 선택해주세요.'; clearQuestionsList(); });
      return;
    }
    if (mounted) setState(() { _isLoadingQuestions = true; _errorMessage = ''; clearAllAttemptStatesAndQuestions(); });

    final String documentId = '$_selectedYear-$_selectedRound-$_selectedGrade';
    try {
      final docSnapshot = await _firestore.collection('exam').doc(documentId).get();
      if (!mounted) return;
      if (docSnapshot.exists) {
        final docData = docSnapshot.data();
        if (docData != null) {
          List<Map<String, dynamic>> fetchedQuestions = [];
          List<String> sortedMainKeys = docData.keys.toList()..sort((a, b) => (int.tryParse(a) ?? 99999).compareTo(int.tryParse(b) ?? 99999));

          for (String mainKey in sortedMainKeys) {
            var mainValue = docData[mainKey];
            if (mainValue is Map<String, dynamic>) {
              Map<String, dynamic> questionData = Map<String, dynamic>.from(mainValue);
              questionData['sourceExamId'] = documentId;
              if (!questionData.containsKey('no') || (questionData['no'] as String?).isNullOrEmpty) {
                questionData['no'] = mainKey;
              }
              fetchedQuestions.add(cleanNewlinesRecursive(questionData)); // Mixin의 메서드 사용
            }
          }
          fetchedQuestions.sort((a, b) {
            final parsedA = _parseQuestionNumberString(a['no'] as String?);
            final parsedB = _parseQuestionNumberString(b['no'] as String?);
            int mainNoCompare = parsedA[0].compareTo(parsedB[0]);
            return mainNoCompare != 0 ? mainNoCompare : parsedA[1].compareTo(parsedB[1]);
          });
          _questions = fetchedQuestions;
        } else { _errorMessage = '시험 문서($documentId) 데이터를 가져올 수 없습니다.'; }
      } else { _errorMessage = '선택한 조건의 시험 문서($documentId)를 찾을 수 없습니다.'; }
    } catch (e, s) {
      if (mounted) _errorMessage = '문제를 불러오는 중 오류 발생.';
      print('Error fetching specific exam questions: $e\nStack: $s');
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

  // 5. 복잡했던 위젯 빌드 함수는 모두 삭제됨

  Widget _buildBody() {
    if (_isLoadingQuestions) return const Center(child: CircularProgressIndicator());
    if (_errorMessage.isNotEmpty && _questions.isEmpty) return Center(child: Text(_errorMessage, style: const TextStyle(color: Colors.red)));
    if (_questions.isEmpty) return Center(child: Padding(
      padding: const EdgeInsets.all(16.0),
      child: Text(_selectedYear == null ? '년도, 회차, 등급을 선택하고 시험지를 불러오세요.' : '선택한 조건의 문제가 없습니다.', textAlign: TextAlign.center),
    ));

    // REVISED: 공통 위젯 사용
    return QuestionListView(
      questions: _questions,
      getControllers: getControllersForQuestion,
      onCheckAnswer: (questionData, parentData) => checkAnswer(questionData, parentData),
      onTryAgain: tryAgain,
      submissionStatus: submissionStatus,
      userSubmittedAnswers: userSubmittedAnswers,
      aiGradingResults: aiGradingResults,
      titleBuilder: (context, questionData, index) {
        final originalNo = questionData['no'] as String?;
        return Text('${originalNo ?? "N/A"}번', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5));
      },
      subtitleBuilder: (context, questionData, index) {
        final questionText = questionData['question'] as String? ?? '';
        return questionText.isNotEmpty
            ? Padding(padding: const EdgeInsets.only(top: 5.0), child: Text(questionText, style: const TextStyle(fontSize: 15.0, color: Colors.black87, height: 1.4)))
            : null;
      },
    );
  }

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
                else ...[
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: '년도 선택', border: OutlineInputBorder()),
                    value: _selectedYear,
                    hint: const Text('출제 년도를 선택하세요'),
                    items: _yearOptions.map((y) => DropdownMenuItem(value: y, child: Text(y))).toList(),
                    onChanged: _updateYearSelected,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: '회차 선택', border: OutlineInputBorder()),
                    value: _selectedRound,
                    hint: const Text('회차를 선택하세요'),
                    disabledHint: _selectedYear == null ? const Text('년도를 먼저 선택하세요') : null,
                    items: _filteredRoundOptions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                    onChanged: _selectedYear == null ? null : _updateRoundSelected,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: '등급 선택', border: OutlineInputBorder()),
                    value: _selectedGrade,
                    hint: const Text('등급을 선택하세요'),
                    disabledHint: _selectedRound == null ? const Text('회차를 먼저 선택하세요') : null,
                    items: _filteredGradeOptions.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                    onChanged: _selectedRound == null ? null : _updateGradeSelected,
                  ),
                ],
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: (_selectedYear == null || _selectedRound == null || _selectedGrade == null || _isLoadingQuestions) ? null : _fetchQuestions,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), minimumSize: const Size(double.infinity, 44)),
                  child: _isLoadingQuestions ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)) : const Text('시험지 불러오기', style: TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: _questions.isNotEmpty
          ? FloatingActionButton.extended(
        onPressed: _showGradingResult, // 버튼 클릭 시 채점 결과 표시
        label: const Text('채점하기'),
        icon: const Icon(Icons.check_circle_outline),
        tooltip: '지금까지 푼 문제 채점하기',
      )
          : null, // 문제가 없으면 버튼을 표시하지 않음
    );
  }
}