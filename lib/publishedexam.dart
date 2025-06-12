// file: publishedexam.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'appbar.dart'; // 사용자 정의 AppBar (CSAppBar)
import 'dart:async';
import 'questions_common.dart'; // 공통 코드 임포트

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

  // 4. 복잡했던 위젯 빌드 함수는 모두 삭제됨

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
          if (_errorMessage.isNotEmpty && !_isLoadingOptions && _questions.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0), child: Text(_errorMessage, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
          Expanded(
            child: _isLoadingQuestions
                ? const Center(child: CircularProgressIndicator())
                : _questions.isEmpty
                ? Center(child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(_selectedYear == null ? '년도, 회차, 등급을 선택하고 시험지를 불러오세요.' : '선택한 조건의 문제가 없습니다.', textAlign: TextAlign.center),
            ))
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              itemCount: _questions.length,
              itemBuilder: (context, index) {
                final mainQuestionData = _questions[index];
                final String pageOrderNo = "${index + 1}";
                final String? originalNo = mainQuestionData['no'] as String?;
                final String type = mainQuestionData['type'] as String? ?? '';
                final String questionTextForSubtitle = mainQuestionData['question'] as String? ?? '';
                final String uniqueId = mainQuestionData['uniqueDisplayId'] as String;
                final String sourceExamId = mainQuestionData['sourceExamId'] as String? ?? '출처 미상';

                String typeForAnswerArea = (type == "발문" || type.isEmpty) ? "" : " ($type)";
                String mainTitleText = '${originalNo ?? "N/A"}번';

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
                    initiallyExpanded: _questions.length <= 3,
                    children: <Widget>[
                      // ===================[수정된 위젯 호출 1]===================
                      QuestionInteractiveDisplay(
                        questionData: mainQuestionData,
                        leftIndent: 16.0,
                        displayNoWithPrefix: "풀이$typeForAnswerArea",
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