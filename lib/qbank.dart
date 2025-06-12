// file: qbank.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'appbar.dart'; // 사용자 정의 AppBar (CSAppBar)
import 'dart:async';
import 'dart:math'; // 랜덤 선택
import 'questions_common.dart'; // 공통 코드 임포트

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
                  decoration: const InputDecoration(
                    labelText: '랜덤 출제 문제 수 (예: 18)', border: OutlineInputBorder(), isDense: true,
                  ),
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
          if (_errorMessage.isNotEmpty && !_isLoadingOptions && _randomlySelectedQuestions.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0), child: Text(_errorMessage, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
          Expanded(
            child: _isLoadingQuestions
                ? const Center(child: CircularProgressIndicator())
                : _randomlySelectedQuestions.isEmpty
                ? Center(child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(_selectedGrade == null ? '먼저 등급과 문제 수를 선택하고 시험지를 생성하세요.' : '선택한 등급의 문제가 없거나, 문제 수가 유효하지 않습니다.', textAlign: TextAlign.center),
            ))
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              itemCount: _randomlySelectedQuestions.length,
              itemBuilder: (context, index) {
                final mainQuestionData = _randomlySelectedQuestions[index];
                final String pageOrderNo = "${index + 1}";
                final String? originalNo = mainQuestionData['no'] as String?;
                final String type = mainQuestionData['type'] as String? ?? '';
                final String questionTextForSubtitle = mainQuestionData['question'] as String? ?? '';
                final String uniqueId = mainQuestionData['uniqueDisplayId'] as String;
                final String sourceExamId = mainQuestionData['sourceExamId'] as String? ?? '출처 미상';

                String titleTypeDisplay = (type == "발문" || type.isEmpty) ? "" : " ($type)";
                String mainTitleText = '문제 $pageOrderNo (출처: $sourceExamId - 원본 ${originalNo ?? "N/A"}번)';

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6.0),
                  elevation: 1.5,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                  child: ExpansionTile(
                    key: ValueKey(uniqueId),
                    tilePadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    childrenPadding: EdgeInsets.zero,
                    title: Text(mainTitleText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5)),
                    subtitle: questionTextForSubtitle.isNotEmpty ? Padding(padding: const EdgeInsets.only(top: 5.0), child: Text(questionTextForSubtitle, style: const TextStyle(fontSize: 15.0, color: Colors.black87, height: 1.4))) : null,
                    initiallyExpanded: _randomlySelectedQuestions.length <= 3,
                    children: <Widget>[
                      // ===================[수정된 위젯 호출 1]===================
                      QuestionInteractiveDisplay(
                        questionData: mainQuestionData,
                        leftIndent: 16.0,
                        displayNoWithPrefix: "풀이$titleTypeDisplay",
                        questionTypeToDisplay: "",
                        showQuestionText: false,
                        getControllers: getControllersForQuestion, // REVISED
                        onCheckAnswer: checkAnswer,
                        onTryAgain: tryAgain,
                        submissionStatus: submissionStatus[uniqueId],
                        userSubmittedAnswers: userSubmittedAnswers[uniqueId], // REVISED
                      ),
                      // ==========================================================
                      Builder(builder: (context) {
                        List<Widget> subWidgets = [];
                        final dynamic subQuestionsField = mainQuestionData['sub_questions'];
                        if (subQuestionsField is Map<String, dynamic> && subQuestionsField.isNotEmpty) {
                          if (mainQuestionData.containsKey('answer') || (mainQuestionData['type'] != "발문" && subQuestionsField.isNotEmpty)) {
                            subWidgets.add(const Divider(height: 12, thickness: 0.5, indent: 16, endIndent: 16));
                          }

                          List<String> sortedSubKeys = subQuestionsField.keys.toList()..sort((a, b) => (int.tryParse(a) ?? 99999).compareTo(int.tryParse(b) ?? 99999));
                          int subOrderCounter = 0;
                          for (String subKey in sortedSubKeys) {
                            final dynamic subQuestionValue = subQuestionsField[subKey];
                            if (subQuestionValue is Map<String, dynamic>) {
                              subOrderCounter++;
                              final String subType = subQuestionValue['type'] as String? ?? '';
                              // ===================[수정된 위젯 호출 2]===================
                              subWidgets.add(QuestionInteractiveDisplay(
                                questionData: subQuestionValue,
                                leftIndent: 24.0,
                                displayNoWithPrefix: "($subOrderCounter)",
                                questionTypeToDisplay: (subType == "발문" || subType.isEmpty) ? "" : " ($subType)",
                                showQuestionText: true,
                                getControllers: getControllersForQuestion, // REVISED
                                onCheckAnswer: checkAnswer,
                                onTryAgain: tryAgain,
                                submissionStatus: submissionStatus[subQuestionValue['uniqueDisplayId']],
                                userSubmittedAnswers: userSubmittedAnswers[subQuestionValue['uniqueDisplayId']], // REVISED
                              ));
                              // ==========================================================

                              final dynamic subSubQuestionsField = subQuestionValue['sub_sub_questions'];
                              if (subSubQuestionsField is Map<String, dynamic> && subSubQuestionsField.isNotEmpty) {
                                List<String> sortedSubSubKeys = subSubQuestionsField.keys.toList()..sort((a,b) => (int.tryParse(a) ?? 99999).compareTo(int.tryParse(b) ?? 99999));
                                int subSubOrderCounter = 0;
                                for (String subSubKey in sortedSubSubKeys) {
                                  final dynamic subSubQValue = subSubQuestionsField[subSubKey];
                                  if (subSubQValue is Map<String, dynamic>) {
                                    subSubOrderCounter++;
                                    final String subSubType = subSubQValue['type'] as String? ?? '';
                                    // ===================[수정된 위젯 호출 3]===================
                                    subWidgets.add(QuestionInteractiveDisplay(
                                      questionData: subSubQValue,
                                      leftIndent: 32.0,
                                      displayNoWithPrefix: " - ($subSubOrderCounter)",
                                      questionTypeToDisplay: (subSubType == "발문" || subSubType.isEmpty) ? "" : " ($subSubType)",
                                      showQuestionText: true,
                                      getControllers: getControllersForQuestion, // REVISED
                                      onCheckAnswer: checkAnswer,
                                      onTryAgain: tryAgain,
                                      submissionStatus: submissionStatus[subSubQValue['uniqueDisplayId']],
                                      userSubmittedAnswers: userSubmittedAnswers[subSubQValue['uniqueDisplayId']], // REVISED
                                    ));
                                    // ==========================================================
                                  }
                                }
                              }
                            }
                          }
                        }
                        if (subWidgets.isEmpty && mainQuestionData['type'] == "발문" && !mainQuestionData.containsKey('answer')) {
                          return const Padding(padding: EdgeInsets.all(16.0), child: Text("하위 문제가 없습니다.", style: TextStyle(fontStyle: FontStyle.italic)));
                        }
                        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: subWidgets);
                      }),
                    ],
                  ),
                );
              },
            )
          ),
        ],
      ),
    );
  }
}