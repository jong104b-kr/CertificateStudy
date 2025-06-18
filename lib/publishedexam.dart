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

  // 3. 채점 관련 메서드

  // 사용자가 맞춘 문제의 총점을 계산하는 메서드
  int _calculateUserScore() {
    int totalScore = 0;
    // QuestionStateMixin의 submissionStatus를 사용
    for (int i = 0; i < _questions.length; i++) {
      // 1. 현재 인덱스에 해당하는 문제 데이터를 가져옵니다.
      final questionData = _questions[i];
      // 2. 해당 문제의 고유 ID(key로 사용될 값)를 가져옵니다.
      final String? uniqueId = questionData['uniqueDisplayId'] as String?;

      // uniqueId가 있고, 해당 ID로 submissionStatus 맵을 조회했을 때 결과가 true이면 정답으로 처리합니다.
      if (uniqueId != null && submissionStatus[uniqueId] == true) {
        final score = questionData['fullscore']; // fullscore 값 가져오기

        // 점수 타입에 따라 안전하게 더하기
        if (score is int) {
          totalScore += score;
        } else if (score is String) {
          totalScore += int.tryParse(score) ?? 0;
        }
      }
    }
    return totalScore;
  }

  // 시험지의 총점을 계산하는 메서드
  int _calculateMaxScore() {
    int maxScore = 0;
    for (final questionData in _questions) {
      final score = questionData['fullscore'];
      if (score is int) {
        maxScore += score;
      } else if (score is String) {
        maxScore += int.tryParse(score) ?? 0;
      }
    }
    return maxScore;
  }

  // 채점 결과를 다이얼로그로 보여주는 메서드
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
      onCheckAnswer: checkAnswer,
      onTryAgain: tryAgain,
      submissionStatus: submissionStatus,
      userSubmittedAnswers: userSubmittedAnswers,
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