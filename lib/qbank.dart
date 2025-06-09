import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'appbar.dart'; // 사용자 정의 AppBar (CSAppBar)
import 'dart:async';
import 'dart:math'; // 랜덤 선택
import 'package:uuid/uuid.dart'; // 고유 ID 생성을 위해 추가

// String extension for isNullOrEmpty (Dart 2.12+ 에서는 ?.isEmpty 로 충분)
// 하지만 null일 경우를 위해 확장 함수가 더 안전할 수 있습니다.
extension StringNullOrEmptyExtension on String? {
  bool get isNullOrEmpty {
    return this == null || this!.trim().isEmpty;
  }
}

class QuestionBankPage extends StatefulWidget {
  final String title;
  const QuestionBankPage({super.key, required this.title});

  @override
  State<QuestionBankPage> createState() => _QuestionBankPageState();
}

class _QuestionBankPageState extends State<QuestionBankPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Uuid _uuid = Uuid();

  String? _selectedGrade;
  int? _numberOfRandomQuestions;

  List<String> _gradeOptions = [];
  List<Map<String, String>> _parsedDocIds = []; // 문서 ID와 파싱된 정보 저장

  bool _isLoadingOptions = true;
  bool _isLoadingQuestions = false;
  String _errorMessage = '';

  List<Map<String, dynamic>> _randomlySelectedQuestions = [];

  final Map<String, TextEditingController> _controllers = {};
  final Map<String, bool?> _submissionStatus = {};
  final Map<String, String> _userSubmittedAnswers = {};

  @override
  void initState() {
    super.initState();
    _fetchAndParseAllDocumentIdsForOptions();
  }

  TextEditingController _getControllerForQuestion(String uniqueDisplayId) {
    return _controllers.putIfAbsent(uniqueDisplayId, () {
      return TextEditingController(text: _userSubmittedAnswers[uniqueDisplayId]);
    });
  }

  void _clearAllAttemptStatesAndQuestions() {
    if (!mounted) return;
    setState(() {
      _controllers.values.forEach((controller) => controller.clear());
      _submissionStatus.clear();
      _userSubmittedAnswers.clear();
      _randomlySelectedQuestions = [];
      _errorMessage = ''; // 오류 메시지도 초기화
    });
  }

  @override
  void dispose() {
    _controllers.forEach((_, controller) => controller.dispose());
    super.dispose();
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
          _parsedDocIds.add({'docId': doc.id, 'grade': grade}); // Firestore 문서 ID도 저장
          grades.add(grade);
        } else {
          print("Warning: Could not parse grade from doc ID: ${doc.id}");
        }
      }
      _gradeOptions = grades.toList()..sort();
      if (_gradeOptions.isEmpty && mounted) _errorMessage = '등급 데이터를 찾을 수 없습니다.';
    } catch (e) {
      if (mounted) _errorMessage = '옵션 로딩 중 오류: $e';
      print('Error fetching all document IDs for options: $e');
    } finally {
      if (mounted) setState(() => _isLoadingOptions = false);
    }
  }

  void _updateSelectedGrade(String? grade) {
    if (!mounted) return;
    setState(() {
      _selectedGrade = grade;
      _clearAllAttemptStatesAndQuestions();
    });
  }

  Map<String, dynamic> _cleanNewlinesRecursive(Map<String, dynamic> questionData, Uuid uuidGenerator) {
    Map<String, dynamic> cleanedData = {};

    // 현재 레벨의 문제에 uniqueDisplayId가 없으면 생성하여 할당
    cleanedData['uniqueDisplayId'] = questionData['uniqueDisplayId'] ?? uuidGenerator.v4();
    questionData.forEach((key, value) {
      if (key == 'uniqueDisplayId') return; // 이미 위에서 처리했으므로 건너뜀
      if (value is String) {
        cleanedData[key] = value.replaceAll('\\n', '\n');
      } else if ((key == 'sub_questions' || key == 'sub_sub_questions') && value is Map) {
        Map<String, dynamic> nestedCleanedMap = {};
        (value as Map<String, dynamic>).forEach((subKey, subValue) {
          if (subValue is Map<String, dynamic>) {
            // 재귀 호출 시에도 uuidGenerator 전달
            nestedCleanedMap[subKey] = _cleanNewlinesRecursive(subValue, uuidGenerator);
          } else {
            nestedCleanedMap[subKey] = subValue;
          }
        });
        cleanedData[key] = nestedCleanedMap;
      }
      else {
        cleanedData[key] = value; // 'no', 'question', 'answer', 'type' 등 다른 필드 복사
      }
    });
    return cleanedData;
  }


  Future<void> _fetchAndGenerateRandomExam() async {
    if (_selectedGrade == null) {
      if (mounted) setState(() { _errorMessage = '먼저 등급을 선택해주세요.'; _clearAllAttemptStatesAndQuestions(); });
      return;
    }
    if (_numberOfRandomQuestions == null || _numberOfRandomQuestions! <= 0) {
      if (mounted) setState(() { _errorMessage = '출제할 문제 수를 1 이상 입력해주세요.'; _clearAllAttemptStatesAndQuestions(); });
      return;
    }
    if (mounted) setState(() { _isLoadingQuestions = true; _errorMessage = ''; _clearAllAttemptStatesAndQuestions(); });

    List<Map<String, dynamic>> pooledMainQuestions = [];
    try {
      for (var docInfo in _parsedDocIds) { // _parsedDocIds에 docId와 grade가 이미 있음
        if (docInfo['grade'] == _selectedGrade) {
          final docSnapshot = await _firestore.collection('exam').doc(docInfo['docId']!).get();
          if (!mounted) return;
          if (docSnapshot.exists) {
            final docData = docSnapshot.data();
            if (docData != null) {
              List<String> sortedMainKeys = docData.keys.toList();
              sortedMainKeys.sort((a, b) => (int.tryParse(a) ?? 99999).compareTo(int.tryParse(b) ?? 99999));
              for (String mainKey in sortedMainKeys) {
                var mainValue = docData[mainKey];
                if (mainValue is Map<String, dynamic>) {
                  Map<String, dynamic> questionData = Map<String, dynamic>.from(mainValue);
                  questionData['uniqueDisplayId'] = _uuid.v4();
                  questionData['sourceExamId'] = docInfo['docId']!; // 출처(문서ID) 저장
                  if (!questionData.containsKey('no') || (questionData['no'] as String?).isNullOrEmpty) {
                    questionData['no'] = mainKey;
                  }
                  pooledMainQuestions.add(_cleanNewlinesRecursive(questionData, _uuid));
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
          List<Map<String, dynamic>> tempList = List.from(pooledMainQuestions);
          for (int i = 0; i < _numberOfRandomQuestions!; i++) {
            if (tempList.isEmpty) break;
            int randomIndex = random.nextInt(tempList.length);
            _randomlySelectedQuestions.add(tempList.removeAt(randomIndex));
          }
        }
        if (_randomlySelectedQuestions.isEmpty && _numberOfRandomQuestions! > 0) {
          _errorMessage = '문제를 가져왔으나, 랜덤 선택 결과 문제가 없습니다.';
        }
      } else { _errorMessage = "'$_selectedGrade' 등급에 해당하는 문제가 전체 시험 데이터에 없습니다."; }
    } catch (e, s) {
      _errorMessage = '문제 풀 구성 중 오류 발생.';
      print('Error generating random exam: $e\nStack: $s');
    }
    finally { if (mounted) setState(() => _isLoadingQuestions = false); }
  }

  void _checkAnswer(String uniqueDisplayId, String correctAnswerText, String questionType) {
    final userAnswer = _controllers[uniqueDisplayId]?.text ?? "";
    String processedUserAnswer = userAnswer.trim();
    String processedCorrectAnswer = correctAnswerText.trim();
    bool isCorrect = processedUserAnswer.toLowerCase() == processedCorrectAnswer.toLowerCase();

    if (questionType == "계산" && !isCorrect) {
      RegExp numberAndUnitExtractor = RegExp(r"([0-9\.]+)\s*(\[.*?\])?");
      Match? userAnswerMatch = numberAndUnitExtractor.firstMatch(processedUserAnswer);
      Match? correctAnswerMatch = numberAndUnitExtractor.firstMatch(processedCorrectAnswer);
      if (userAnswerMatch != null && correctAnswerMatch != null) {
        String userAnswerVal = userAnswerMatch.group(1) ?? "";
        String correctAnswerVal = correctAnswerMatch.group(1) ?? "";
        if (double.tryParse(userAnswerVal) != null && double.tryParse(correctAnswerVal) != null) {
          isCorrect = (double.parse(userAnswerVal) - double.parse(correctAnswerVal)).abs() < 0.0001;
        } else { isCorrect = userAnswerVal == correctAnswerVal; }
      }
    }
    if (mounted) {
      setState(() {
        _userSubmittedAnswers[uniqueDisplayId] = userAnswer;
        _submissionStatus[uniqueDisplayId] = isCorrect;
      });
    }
  }

  void _tryAgain(String uniqueDisplayId) {
    if (mounted) {
      setState(() {
        _controllers[uniqueDisplayId]?.clear();
        _submissionStatus.remove(uniqueDisplayId);
        _userSubmittedAnswers.remove(uniqueDisplayId);
      });
    }
  }

  // 각 레벨의 문제를 그리는 재귀적 헬퍼 함수
  List<Widget> _buildQuestionHierarchyWidgets({
    required Map<String, dynamic> currentQuestionData,
    required double currentIndent,
    required String currentOrderPrefix, // 예: "1.", "(a)", "i)"
    required int depth,
  }) {
    List<Widget> widgets = [];
    final String questionType = currentQuestionData['type'] as String? ?? '';
    final bool showActualQuestionText = depth > 0 || // 하위, 하위-하위는 질문 표시
        (questionType != "발문" || currentQuestionData.containsKey('answer')); // 주 문제도 발문+답변없음 아니면 표시 (또는 풀이영역이므로 항상 false)


    // _buildQuestionInteractiveDisplay 호출 시 파라미터 전달
    widgets.add(_buildQuestionInteractiveDisplay(
      questionData: currentQuestionData,
      leftIndent: currentIndent, // _buildQuestionHierarchyWidgets의 currentIndent가 여기에 매핑됨
      displayNoWithPrefix: currentOrderPrefix, // currentOrderPrefix가 여기에 매핑됨
      questionTypeToDisplay: (questionType == "발문" || questionType.isEmpty) ? "" : " ($questionType)", // 여기서 계산하여 전달
      showQuestionText: showActualQuestionText, // 여기서 계산하여 전달
    ));

    // 하위 문제 처리 로직 (childrenKeyToUse 결정 및 재귀 호출)
    String? childrenKey;
    if (depth == 0) childrenKey = 'sub_questions';
    else if (depth == 1) childrenKey = 'sub_sub_questions';

    if (childrenKey != null && currentQuestionData.containsKey(childrenKey)) {
      final dynamic childrenField = currentQuestionData[childrenKey];
      if (childrenField is Map<String, dynamic> && childrenField.isNotEmpty) {
        Map<String, dynamic> childrenMap = childrenField;
        List<String> sortedChildKeys = childrenMap.keys.toList();
        sortedChildKeys.sort((a, b) => (int.tryParse(a) ?? 99999).compareTo(int.tryParse(b) ?? 99999));

        int childOrderCounter = 0;
        for (String childKeyInMap in sortedChildKeys) {
          final dynamic childQuestionValue = childrenMap[childKeyInMap];
          if (childQuestionValue is Map<String, dynamic>) {
            childOrderCounter++;
            String childDisplayOrderPrefix = "";
            if (depth == 0) childDisplayOrderPrefix = "($childOrderCounter)";
            else if (depth == 1) childDisplayOrderPrefix = "  ㄴ ($childOrderCounter)";

            widgets.addAll(_buildQuestionHierarchyWidgets(
              currentQuestionData: Map<String, dynamic>.from(childQuestionValue),
              currentIndent: currentIndent + 8.0, // 다음 레벨 들여쓰기 (Padding 내부이므로 상대적)
              currentOrderPrefix: childDisplayOrderPrefix,
              depth: depth + 1,
              // showQuestionTextForThisLevel: true, // 이 파라미터는 _buildQuestionHierarchyWidgets에만 필요
            ));
          }
        }
      }
    }
    return widgets;
  }


  // 단일 문제의 인터랙티브 UI (TextField, 정답확인 등)를 생성하는 위젯
  Widget _buildQuestionInteractiveDisplay({
    required Map<String, dynamic> questionData,
    required double leftIndent,
    required String displayNoWithPrefix, // 예: "1.", "(1)", "ㄴ (a)" 등 (질문 텍스트는 여기서 포함 안 함)
    required String questionTypeToDisplay,   // 예: " (단답형)", " (계산)", 또는 "" (발문이거나 타입 없는 경우)
    required bool showQuestionText,          // 이 위젯 내에서 문제의 'question' 필드 내용을 표시할지 여부
  }) {
    final String? uniqueDisplayId = questionData['uniqueDisplayId'] as String?;

    String questionTextContent = "";
    if (showQuestionText) {
      questionTextContent = questionData['question'] as String? ?? '질문 내용 없음';
    }

    String? correctAnswerForDisplay = questionData['answer'] as String?;
    final String actualQuestionType = questionData['type'] as String? ?? '타입 정보 없음';

    bool isAnswerable = (actualQuestionType == "단답형" || actualQuestionType == "계산" || actualQuestionType == "서술형") &&
        correctAnswerForDisplay != null &&
        uniqueDisplayId != null;

    TextEditingController? controller = isAnswerable ? _getControllerForQuestion(uniqueDisplayId!) : null;
    bool? currentSubmissionStatus = isAnswerable ? _submissionStatus[uniqueDisplayId!] : null;
    String? userSubmittedAnswerForDisplay = isAnswerable ? _userSubmittedAnswers[uniqueDisplayId!] : null;

    return Padding(
      padding: EdgeInsets.only(left: leftIndent, top: 8.0, bottom: 8.0, right: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. e질문 텍스트 표시 (showQuestionTxt 플래그에 따라)
          if (showQuestionText)
            Text(
              '$displayNoWithPrefix ${questionTextContent}${questionTypeToDisplay}',
              textAlign: TextAlign.start,
              style: TextStyle(
                fontSize: 15,
                fontWeight: leftIndent == 0 && showQuestionText ? FontWeight.w600 : (leftIndent < 24.0 ? FontWeight.w500 : FontWeight.normal),
              ),
            )
          else if (displayNoWithPrefix.isNotEmpty) // showQuestionText가 false여도, 접두사("└ (풀이)" 등)가 있다면 표시
            Padding(
              padding: EdgeInsets.only(bottom: (isAnswerable ? 4.0 : 0)), // 답변 UI가 바로 나오면 간격, 아니면 0
              child: Text(
                displayNoWithPrefix,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.blueGrey[700]),
              ),
            ),

          // 질문 텍스트와 답변 UI 사이 간격 (둘 다 표시될 경우)
          if (showQuestionText && isAnswerable)
            const SizedBox(height: 8.0),

          // 2. 답변 가능 문제에 대한 UI (TextField, 버튼, 피드백)
          if (isAnswerable && controller != null && correctAnswerForDisplay != null) ...[
            const SizedBox(height: 4), // 풀이 제목과 TextField 사이 간격 (showQuestionText가 false일 때를 위함)
            TextField(
              controller: controller,
              enabled: currentSubmissionStatus == null,
              decoration: InputDecoration(
                hintText: '정답을 입력하세요...',
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                suffixIcon: (controller.text.isNotEmpty && currentSubmissionStatus == null)
                    ? IconButton(icon: const Icon(Icons.clear, size: 20), onPressed: () { controller.clear(); if(mounted) setState((){});} )
                    : null,
              ),
              onChanged: (text) { if (currentSubmissionStatus == null && mounted) setState(() {}); },
              onSubmitted: (value) {
                if (currentSubmissionStatus == null && uniqueDisplayId != null && correctAnswerForDisplay != null) {
                  _checkAnswer(uniqueDisplayId, correctAnswerForDisplay, actualQuestionType);
                }
              },
              maxLines: actualQuestionType == "서술형" ? null : 1,
              keyboardType: actualQuestionType == "서술형" ? TextInputType.multiline : TextInputType.text,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                ElevatedButton(
                  onPressed: currentSubmissionStatus == null && uniqueDisplayId != null && correctAnswerForDisplay != null
                      ? () { FocusScope.of(context).unfocus(); _checkAnswer(uniqueDisplayId, correctAnswerForDisplay, actualQuestionType); }
                      : null,
                  child: Text(currentSubmissionStatus == null ? '정답 확인' : '채점 완료'),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), textStyle: const TextStyle(fontSize: 13)),
                ),
                if (currentSubmissionStatus != null && uniqueDisplayId != null) ...[
                  const SizedBox(width: 8),
                  TextButton(onPressed: () => _tryAgain(uniqueDisplayId), child: const Text('다시 풀기')),
                ],
              ],
            ),
            if (currentSubmissionStatus != null && correctAnswerForDisplay != null) ...[
              const SizedBox(height: 8),
              Text(
                currentSubmissionStatus == true ? '정답입니다! 👍' : '오답입니다. 👎',
                style: TextStyle(color: currentSubmissionStatus == true ? Colors.green : Colors.red, fontWeight: FontWeight.bold),
              ),
              Text('입력한 답: ${userSubmittedAnswerForDisplay ?? ""}'),
              Text('실제 정답: $correctAnswerForDisplay'),
            ],
          ]
          // 3. 답변 불가능하지만 정답이 있는 경우 (예: 그림 문제의 설명 답안)
          else if (correctAnswerForDisplay != null && actualQuestionType != "발문")
            Padding(
              padding: EdgeInsets.only(top: 4.0, left: (showQuestionText ? 0 : 8.0)), // 질문 텍스트 없을땐 들여쓰기
              child: Text('정답: $correctAnswerForDisplay', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w500)),
            )
          // 4. 답변 불가능하고 정답도 없는 경우 (단, 발문이 아닐 때 + 질문이 표시되었을 때만 이 메시지)
          else if (actualQuestionType != "발문" && correctAnswerForDisplay == null && showQuestionText)
              const Padding(
                padding: EdgeInsets.only(top: 4.0),
                child: Text("텍스트 정답이 제공되지 않는 유형입니다.", style: TextStyle(fontStyle: FontStyle.italic, fontSize: 13, color: Colors.grey)),
              )
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CSAppBar(title: widget.title),
      body: Column(
        children: [
          // --- 상단 컨트롤 UI ---
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
                  decoration: InputDecoration(
                    labelText: '랜덤 출제 문제 수 (예: 18)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    if (mounted) setState(() { _numberOfRandomQuestions = int.tryParse(value); });
                  },
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: (_selectedGrade == null || _isLoadingQuestions || _numberOfRandomQuestions == null || _numberOfRandomQuestions! <=0)
                      ? null
                      : _fetchAndGenerateRandomExam,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), minimumSize: Size(double.infinity, 44)),
                  child: _isLoadingQuestions
                      ? const SizedBox(height:20, width:20, child:CircularProgressIndicator(color: Colors.white, strokeWidth: 3,))
                      : const Text('랜덤 시험지 생성', style: TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ),
          if (_errorMessage.isNotEmpty && !_isLoadingOptions && _randomlySelectedQuestions.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0), child: Text(_errorMessage, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),

          // --- 문제 목록 표시 ---
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
                final String questionTextForSubtitle = (mainQuestionData['question'] as String? ?? '');
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
                    // 요청 6: 하위 문제 칸 왼쪽 정렬을 위해 expandedCrossAxisAlignment 추가
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    // childrenPadding을 0으로 설정하고, 각 _buildQuestionInteractiveDisplay에서 leftIndent로 제어
                    childrenPadding: EdgeInsets.zero,
                    title: Text(mainTitleText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5)),
                    subtitle: questionTextForSubtitle.isNotEmpty
                        ? Padding(
                      padding: const EdgeInsets.only(top: 5.0),
                      child: Text(questionTextForSubtitle, style: TextStyle(fontSize: 15.0, color: Colors.black87, height: 1.4)),
                    )
                        : null,
                    initiallyExpanded: _randomlySelectedQuestions.length <= 3,
                    children: <Widget>[ // ExpansionTile의 children은 항상 List<Widget>
                      // 요청 1 & 5: 주 문제 반복 해결 및 주 문제 풀이 영역
                      // _buildQuestionWidgetsRecursive를 직접 호출하지 않고,
                      // 주 문제의 풀이 부분과 하위 문제 부분을 명시적으로 구성
                      _buildQuestionInteractiveDisplay(
                        questionData: mainQuestionData,
                        leftIndent: 16.0, // ExpansionTile children 기본 들여쓰기
                        displayNoWithPrefix: "풀이${titleTypeDisplay}", // 주 문제의 풀이 영역임을 명시
                        questionTypeToDisplay: titleTypeDisplay,
                        showQuestionText: false
                      ),
                      // 하위 문제들 (sub_questions)
                      Builder(builder: (context) { // Builder를 사용하여 로컬 변수 사용
                        List<Widget> subQuestionAndSubSubWidgets = [];
                        final dynamic subQuestionsField = mainQuestionData['sub_questions'];
                        if (subQuestionsField is Map<String, dynamic> && subQuestionsField.isNotEmpty) {
                          if (mainQuestionData.containsKey('answer') || (mainQuestionData['type'] != "발문" && (subQuestionsField).isNotEmpty )) {
                            subQuestionAndSubSubWidgets.add(const Divider(height: 12, thickness: 0.5, indent:16, endIndent:16));
                          }
                          Map<String, dynamic> subQuestionsMap = subQuestionsField;
                          List<String> sortedSubKeys = subQuestionsMap.keys.toList();
                          sortedSubKeys.sort((a, b) => (int.tryParse(a) ?? 99999).compareTo(int.tryParse(b) ?? 99999));

                          int subOrderCounter = 0;
                          for (String subKey in sortedSubKeys) {
                            final dynamic subQuestionValue = subQuestionsMap[subKey];
                            if (subQuestionValue is Map<String, dynamic>) {
                              subOrderCounter++;
                              String subQuestionOrderPrefix = "($subOrderCounter)";

                              // 각 하위 문제에 대해 _buildQuestionInteractiveDisplay 직접 호출 (재귀 대신)
                              final String SubType = subQuestionValue['type'] as String? ?? '';
                              String subtitleTypeDisplay = (SubType == "발문" || SubType.isEmpty) ? "" : " ($SubType)";
                              subQuestionAndSubSubWidgets.add(
                                  _buildQuestionInteractiveDisplay(
                                    questionData: Map<String, dynamic>.from(subQuestionValue),
                                    leftIndent: 24.0, // 하위 문제 들여쓰기 (16 + 8)
                                    displayNoWithPrefix: subQuestionOrderPrefix,
                                    questionTypeToDisplay: subtitleTypeDisplay,
                                    showQuestionText: true,
                                  )
                              );

                              // 하위-하위 문제 처리 (sub_sub_questions)
                              final dynamic subSubQuestionsField = subQuestionValue['sub_sub_questions'];
                              if (subSubQuestionsField is Map<String, dynamic> && subSubQuestionsField.isNotEmpty) {
                                Map<String, dynamic> subSubQuestionsMap = subSubQuestionsField;
                                List<String> sortedSubSubKeys = subSubQuestionsMap.keys.toList();
                                sortedSubSubKeys.sort((a,b) => (int.tryParse(a) ?? 99999).compareTo(int.tryParse(b) ?? 99999));

                                int subSubOrderCounter = 0;
                                for (String subSubKey in sortedSubSubKeys) {
                                  final dynamic subSubQValue = subSubQuestionsMap[subSubKey];
                                  if (subSubQValue is Map<String, dynamic>) {
                                    subSubOrderCounter++;
                                    String subSubQDisplayNo = "($subSubOrderCounter)";

                                    final String subSubType = subSubQValue['type'] as String? ?? '';
                                    String subSubtitleTypeDisplay = (subSubType == "발문" || subSubType.isEmpty) ? "" : " ($subSubType)";
                                    subQuestionAndSubSubWidgets.add(
                                        _buildQuestionInteractiveDisplay(
                                          questionData: Map<String, dynamic>.from(subSubQValue),
                                          leftIndent: 32.0, // 하위-하위 문제 들여쓰기 (24 + 8)
                                          displayNoWithPrefix: " - $subSubQDisplayNo",
                                          questionTypeToDisplay: subSubtitleTypeDisplay,
                                          showQuestionText: true,
                                        )
                                    );
                                  }
                                }
                              }
                            }
                          }
                        }
                        if (subQuestionAndSubSubWidgets.isEmpty && mainQuestionData['type'] == "발문" && !(mainQuestionData.containsKey('answer') && mainQuestionData['answer'] != null) ) {
                          return Padding(padding: EdgeInsets.all(16.0), child: Text("하위 문제가 없습니다.", style: TextStyle(fontStyle: FontStyle.italic)));
                        }
                        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: subQuestionAndSubSubWidgets);
                      })
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}