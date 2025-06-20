import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'appbar.dart';
import 'dart:async';
import 'dart:math';
import 'questions_common.dart';
import 'question_list.dart';

class QuestionBankPage extends StatefulWidget {
  final String title;
  const QuestionBankPage({super.key, required this.title});

  @override
  State<QuestionBankPage> createState() => _QuestionBankPageState();
}

class _QuestionBankPageState extends State<QuestionBankPage> with QuestionStateMixin<QuestionBankPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _selectedGrade;
  int? _numberOfRandomQuestions;

  List<String> _gradeOptions = [];
  List<Map<String, String>> _parsedDocIds = [];

  bool _isLoadingOptions = true;
  bool _isLoadingQuestions = false;
  String _errorMessage = '';
  String? _sessionExamId;

  List<Map<String, dynamic>> _randomlySelectedQuestions = [];

  @override
  List<Map<String, dynamic>> get questions => _randomlySelectedQuestions;

  @override
  void clearQuestionsList() {
    if(mounted) setState(() {
      _randomlySelectedQuestions = [];
      _errorMessage = '';
    });
  }

  @override
  void initState() {
    super.initState();
    _fetchAndParseAllDocumentIdsForOptions();
  }

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

    _sessionExamId = '문제은행-$_selectedGrade-${DateTime.now().millisecondsSinceEpoch}';
    setCurrentExamId(_sessionExamId!);

    List<Map<String, dynamic>> pooledMainQuestions = [];
    try {
      for (var docInfo in _parsedDocIds) {
        if (docInfo['grade'] == _selectedGrade) {
          final docSnapshot = await _firestore.collection('exam').doc(docInfo['docId']!).get();
          if (!mounted) return;
          if (docSnapshot.exists) {
            final docData = docSnapshot.data();
            if (docData != null) {
              for (String mainKey in docData.keys) {
                var mainValue = docData[mainKey];
                if (mainValue is Map<String, dynamic>) {
                  Map<String, dynamic> questionData = Map<String, dynamic>.from(mainValue);
                  questionData['sourceExamId'] = docInfo['docId']!;
                  if (!questionData.containsKey('no') || (questionData['no'] as String?).isNullOrEmpty) {
                    questionData['no'] = mainKey;
                  }
                  pooledMainQuestions.add(cleanNewlinesRecursive(questionData));
                }
              }
            }
          }
        }
      }

      if (pooledMainQuestions.isNotEmpty) {
        final random = Random();
        final tempList = List<Map<String, dynamic>>.from(pooledMainQuestions);
        tempList.shuffle(random);
        final countToTake = _numberOfRandomQuestions! < tempList.length ? _numberOfRandomQuestions! : tempList.length;
        _randomlySelectedQuestions = tempList.sublist(0, countToTake);
        if(mounted) setState(() => startTimer());
      } else { _errorMessage = "'$_selectedGrade' 등급에 해당하는 문제가 전체 시험 데이터에 없습니다."; }
    } catch (e, s) {
      _errorMessage = '문제 풀 구성 중 오류 발생.';
      print('Error generating random exam: $e\nStack: $s');
    } finally {
      if (mounted) setState(() => _isLoadingQuestions = false);
    }
  }

  Widget _buildBody() {
    if (_isLoadingQuestions) return const Center(child: CircularProgressIndicator());
    if (_errorMessage.isNotEmpty && _randomlySelectedQuestions.isEmpty) return Center(child: Text(_errorMessage, style: const TextStyle(color: Colors.red)));
    if (_randomlySelectedQuestions.isEmpty) return const Center(child: Padding(
      padding: EdgeInsets.all(16.0),
      child: Text('등급과 문제 수를 선택하고 시험지를 생성하세요.', textAlign: TextAlign.center),
    ));

    return QuestionListView(
      questions: _randomlySelectedQuestions,
      getControllers: getControllersForQuestion,
      onCheckAnswer: checkAnswer,
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
        onPressed: () {
          // Mixin에 있는 showGradingResult 함수를 직접 호출
          showGradingResult(
            context,
            examId: _sessionExamId!,
            examTitle: '문제은행 $_selectedGrade 시험 (${DateTime.now().toString().substring(5, 16)} 응시)',
          );
        },
        label: const Text('채점하기'),
        icon: const Icon(Icons.check_circle_outline),
        tooltip: '지금까지 푼 문제 채점하기',
      )
          : null,
    );
  }
}