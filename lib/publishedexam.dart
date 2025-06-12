import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'appbar.dart'; // 사용자 정의 AppBar (CSAppBar)
import 'dart:async';
// import 'dart:math'; // 랜덤 선택 기능이 아니므로 주석 처리 또는 삭제 가능
import 'package:uuid/uuid.dart'; // 고유 ID 생성을 위해 계속 사용
import 'studydataupdater.dart';

// String extension
extension StringNullOrEmptyExtension on String? {
  bool get isNullOrEmpty {
    return this == null || this!.trim().isEmpty;
  }
}

class PublishedExamPage extends StatefulWidget {
  final String title;
  const PublishedExamPage({super.key, required this.title});

  @override
  State<PublishedExamPage> createState() => _PublishedExamPageState();
}

class _PublishedExamPageState extends State<PublishedExamPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Uuid _uuid = Uuid(); // Uuid 인스턴스 유지

  // 선택된 값들을 저장할 변수 (PublishedExamPage 참조)
  String? _selectedYear;
  String? _selectedRound;
  String? _selectedGrade;

  // 동적으로 채워질 옵션 리스트 (PublishedExamPage 참조)
  List<String> _yearOptions = [];
  List<String> _filteredRoundOptions = [];
  List<String> _filteredGradeOptions = [];

  // 모든 문서 ID에서 추출한 파싱된 데이터 (PublishedExamPage 참조)
  // 예: [{'year': '2023', 'round': '1회차', 'grade': 'A등급', 'docId': '2023-1회차-A등급'}, ...]
  List<Map<String, String>> _parsedDocIds = [];

  bool _isLoadingOptions = true;
  bool _isLoadingQuestions = false; // 변수명 _isLoadingquestions -> _isLoadingQuestions (일관성)
  String _errorMessage = '';
  List<Map<String, dynamic>> _questions = []; // _randomlySelectedQuestions -> _questions

  final Map<String, TextEditingController> _controllers = {};
  final Map<String, List<TextEditingController>> _multiAnswerControllers = {};
  final Map<String, bool?> _submissionStatus = {};
  final Map<String, String> _userSubmittedAnswers = {};
  final Map<String, List<String>> _userSubmittedMultiAnswers = {};

  @override
  void initState() {
    super.initState();
    _fetchAndParseDocumentIds(); // 함수명 변경 및 로직 수정
  }

  @override
  void dispose() {
    _controllers.forEach((_, controller) => controller.dispose());
    _multiAnswerControllers.forEach((_, list) {
      for (var controller in list) {
        controller.dispose();
      }
    });
    super.dispose();
  }

  // --- 🔽 컨트롤러 관리 및 상태 초기화 함수들 🔽 ---
  TextEditingController _getControllerForQuestion(String uniqueDisplayId) {
    return _controllers.putIfAbsent(uniqueDisplayId, () => TextEditingController(text: _userSubmittedAnswers[uniqueDisplayId]));
  }

  void _clearAllAttemptStatesAndQuestions() {
    if (!mounted) return;
    setState(() {
      _controllers.values.forEach((c) => c.clear());
      _multiAnswerControllers.values.forEach((list) => list.forEach((c) => c.clear()));
      _submissionStatus.clear();
      _userSubmittedAnswers.clear();
      _userSubmittedMultiAnswers.clear();
      _questions = [];
      _errorMessage = '';
    });
  }

  void _tryAgain(String uniqueDisplayId) {
    if (mounted) {
      setState(() {
        _controllers[uniqueDisplayId]?.clear();
        _multiAnswerControllers[uniqueDisplayId]?.forEach((c) => c.clear());
        _submissionStatus.remove(uniqueDisplayId);
        _userSubmittedAnswers.remove(uniqueDisplayId);
        _userSubmittedMultiAnswers.remove(uniqueDisplayId);
      });
    }
  }

  // 문서 ID 파싱 함수 (PublishedExamPage 참조)
  Map<String, String>? _parseDocumentId(String docId) {
    final parts = docId.split('-');
    if (parts.length == 3) {
      return {
        'year': parts[0].trim(),
        'round': parts[1].trim(),
        'grade': parts[2].trim(),
        'docId': docId // 원래 문서 ID도 저장해두면 유용할 수 있음
      };
    }
    print('Warning: Could not parse document ID for options: $docId');
    return null;
  }

  // 옵션 로딩 함수 수정 (PublishedExamPage의 _fetchAndParseDocumentIds 참조)
  Future<void> _fetchAndParseDocumentIds() async {
    if (!mounted) return;
    setState(() {
      _isLoadingOptions = true;
      _errorMessage = '';
    });

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

      _yearOptions = years.toList()..sort((a, b) => b.compareTo(a)); // 최신년도부터 정렬

      if (_yearOptions.isEmpty && _parsedDocIds.isEmpty) {
        _errorMessage = '시험 데이터를 찾을 수 없습니다.';
      }
    } catch (e) {
      if (mounted) _errorMessage = '옵션 정보 로딩 중 오류: $e';
      print('Error fetching and parsing document IDs: $e');
    } finally {
      if (mounted) setState(() => _isLoadingOptions = false);
    }
  }

  // 년도 선택 시 회차 옵션 업데이트 (PublishedExamPage 참조)
  void _updateYearSelected(String? year) {
    if (!mounted) return;
    setState(() {
      _selectedYear = year;
      _selectedRound = null;
      _selectedGrade = null;
      _filteredRoundOptions = [];
      _filteredGradeOptions = [];
      _clearAllAttemptStatesAndQuestions();

      if (year != null) {
        final Set<String> rounds = {};
        for (var parsedId in _parsedDocIds) {
          if (parsedId['year'] == year) {
            rounds.add(parsedId['round']!);
          }
        }
        _filteredRoundOptions = rounds.toList()..sort();
      }
    });
  }

  // 회차 선택 시 등급 옵션 업데이트 (PublishedExamPage 참조)
  void _updateRoundSelected(String? round) {
    if (!mounted) return;
    setState(() {
      _selectedRound = round;
      _selectedGrade = null;
      _filteredGradeOptions = [];
      _clearAllAttemptStatesAndQuestions();

      if (_selectedYear != null && round != null) {
        final Set<String> grades = {};
        for (var parsedId in _parsedDocIds) {
          if (parsedId['year'] == _selectedYear && parsedId['round'] == round) {
            grades.add(parsedId['grade']!);
          }
        }
        _filteredGradeOptions = grades.toList()..sort();
      }
    });
  }

  // 등급 선택 시 상태 업데이트
  void _updateGradeSelected(String? grade) {
    if (!mounted) return;
    setState(() {
      _selectedGrade = grade;
      _clearAllAttemptStatesAndQuestions(); // 등급 변경 시 이전 문제/답변 초기화
    });
  }


  // _cleanNewlinesRecursive 함수는 기존 QuestionBankPage의 것을 그대로 사용 (유용함)
  Map<String, dynamic> _cleanNewlinesRecursive(Map<String, dynamic> questionData, Uuid uuidGenerator) {
    Map<String, dynamic> cleanedData = {};
    cleanedData['uniqueDisplayId'] = questionData['uniqueDisplayId'] ?? uuidGenerator.v4();
    questionData.forEach((key, value) {
      if (key == 'uniqueDisplayId') return;
      if (value is String) {
        cleanedData[key] = value.replaceAll('\\n', '\n');
      } else if ((key == 'sub_questions' || key == 'sub_sub_questions') && value is Map) {
        Map<String, dynamic> nestedCleanedMap = {};
        (value as Map<String, dynamic>).forEach((subKey, subValue) {
          if (subValue is Map<String, dynamic>) {
            nestedCleanedMap[subKey] = _cleanNewlinesRecursive(subValue, uuidGenerator);
          } else {
            nestedCleanedMap[subKey] = subValue;
          }
        });
        cleanedData[key] = nestedCleanedMap;
      } else {
        cleanedData[key] = value;
      }
    });
    return cleanedData;
  }

  // 문제 번호 문자열 파싱 함수 (PublishedExamPage 참조)
  List<int> _parseQuestionNumberString(String? questionNoStr) {
    if (questionNoStr.isNullOrEmpty) {
      return [99999, 99999];
    }
    final parts = questionNoStr!.split('_');
    int mainNo = int.tryParse(parts[0]) ?? 99999;
    int subNo = (parts.length > 1) ? (int.tryParse(parts[1]) ?? 0) : 0;
    return [mainNo, subNo];
  }

  // 특정 시험지 문제 로딩 함수 (PublishedExamPage의 _fetchquestions 참조 및 QuestionBankPage 로직 통합)
  Future<void> _fetchQuestions() async {
    if (_selectedYear == null || _selectedRound == null || _selectedGrade == null) {
      if (mounted) {
        setState(() {
          _errorMessage = '모든 항목(년도, 회차, 등급)을 선택해주세요.';
          _questions = [];
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingQuestions = true;
        _errorMessage = '';
        _clearAllAttemptStatesAndQuestions(); // 새 문제 로드 전 초기화
      });
    }

    final String documentId = '${_selectedYear}-${_selectedRound}-${_selectedGrade}';

    try {
      final DocumentSnapshot documentSnapshot =
      await _firestore.collection('exam').doc(documentId).get();
      if (!mounted) return;

      if (documentSnapshot.exists) {
        final Map<String, dynamic>? docData =
        documentSnapshot.data() as Map<String, dynamic>?;

        if (docData != null) {
          List<Map<String, dynamic>> fetchedQuestions = [];
          List<String> sortedMainKeys = docData.keys.toList();

          // Firestore 문서 내의 문제 키(필드명)를 기준으로 정렬 (예: "1", "2", "10")
          // PublishedExamPage의 _parsequestionNumberString는 'no' 필드 기준이므로,
          // 여기서는 필드명(mainKey)을 숫자로 변환하여 정렬합니다.
          // 만약 Firestore 문서의 문제 데이터 내에 'no' 필드가 있고 이를 기준으로 정렬하려면 해당 로직 적용 필요.
          // 여기서는 기존 QuestionBankPage의 키 정렬 방식을 유지하고, 추후 'no' 필드 정렬로 변경 가능.
          sortedMainKeys.sort((a, b) {
            final numA = int.tryParse(a) ?? double.infinity;
            final numB = int.tryParse(b) ?? double.infinity;
            return numA.compareTo(numB);
          });


          for (String mainKey in sortedMainKeys) {
            var mainValue = docData[mainKey];
            if (mainValue is Map<String, dynamic>) {
              Map<String, dynamic> questionData = Map<String, dynamic>.from(mainValue);
              // uniqueDisplayId, sourceExamId, 기본 'no' 값 설정 (QuestionBankPage 로직 활용)
              questionData['uniqueDisplayId'] = _uuid.v4(); // 각 문제에 고유 ID 부여
              questionData['sourceExamId'] = documentId; // 출처 문서 ID 저장
              if (!questionData.containsKey('no') || (questionData['no'] as String?).isNullOrEmpty) {
                questionData['no'] = mainKey; // Firestore 필드명을 기본 문제 번호로 사용
              }
              fetchedQuestions.add(_cleanNewlinesRecursive(questionData, _uuid));
            }
          }

          // 'no' 필드 기준으로 정렬 (PublishedExamPage의 정렬 로직 적용)
          // 이 정렬은 fetchedQuestions 리스트가 채워진 후에 수행
          fetchedQuestions.sort((a, b) {
            final String? noStrA = a['no'] as String?;
            final String? noStrB = b['no'] as String?;
            final List<int> parsedA = _parseQuestionNumberString(noStrA);
            final List<int> parsedB = _parseQuestionNumberString(noStrB);
            int mainNoCompare = parsedA[0].compareTo(parsedB[0]);
            if (mainNoCompare != 0) return mainNoCompare;
            return parsedA[1].compareTo(parsedB[1]);
          });


          if (fetchedQuestions.isNotEmpty) {
            _questions = fetchedQuestions;
          } else {
            _errorMessage = '문서($documentId) 내에 문제 데이터가 없거나 형식이 올바르지 않습니다.';
          }
        } else {
          _errorMessage = '시험 문서($documentId) 데이터를 가져올 수 없습니다 (data is null).';
        }
      } else {
        _errorMessage = '선택한 조건의 시험 문서($documentId)를 찾을 수 없습니다.';
      }
    } catch (e, s) {
      if (mounted) _errorMessage = '문제를 불러오는 중 오류 발생.';
      print('Error fetching specific exam questions: $e\nStack: $s');
      if (e is TypeError) {
        _errorMessage = '문제 데이터 타입 오류입니다. Firestore의 "no" 필드가 문자열인지, 앱 코드에서 올바르게 처리하는지 확인해주세요. 오류: $e';
      }
    } finally {
      if (mounted) setState(() => _isLoadingQuestions = false);
    }
  }


  // --- 🔽 정답 확인 로직 (단일/다중 모두 포함) 🔽 ---
  // 단일 답변 문제 채점
  void _checkAnswer(Map<String, dynamic> questionData) {
    final String uniqueDisplayId = questionData['uniqueDisplayId'] as String;
    final String correctAnswerText = questionData['answer'] as String? ?? "";
    final String questionType = questionData['type'] as String? ?? "";
    final String userAnswer = _controllers[uniqueDisplayId]?.text ?? "";
    bool isCorrect = userAnswer.trim().toLowerCase() == correctAnswerText.trim().toLowerCase();

    // 계산 문제 특별 처리 (필요시)
    if (questionType == "계산" && !isCorrect) { /* 기존과 동일 */ }

    if (mounted) {
      setState(() {
        _userSubmittedAnswers[uniqueDisplayId] = userAnswer;
        _submissionStatus[uniqueDisplayId] = isCorrect;
      });
    }
    FirestoreService.saveQuestionAttempt(questionData: questionData, userAnswer: userAnswer, isCorrect: isCorrect);
  }

  // 다중 답변 문제 채점
  void _checkMultiAnswer(Map<String, dynamic> questionData, int requiredCount) {
    final String uniqueDisplayId = questionData['uniqueDisplayId'];
    final Set<String> correctOptions = (questionData['answer'] as List).map((e) => e.toString().trim().toLowerCase()).toSet();
    final List<TextEditingController> controllers = _multiAnswerControllers[uniqueDisplayId]!;
    final List<String> userAnswers = controllers.map((c) => c.text.trim().toLowerCase()).where((text) => text.isNotEmpty).toList();

    bool isCorrect = false;
    if (userAnswers.toSet().length == userAnswers.length &&
        userAnswers.length == requiredCount &&
        userAnswers.every((answer) => correctOptions.contains(answer))) {
      isCorrect = true;
    }

    setState(() {
      _submissionStatus[uniqueDisplayId] = isCorrect;
      _userSubmittedMultiAnswers[uniqueDisplayId] = controllers.map((c) => c.text).toList();
    });
    FirestoreService.saveQuestionAttempt(questionData: questionData, userAnswer: controllers.map((c) => c.text.trim()).join(', '), isCorrect: isCorrect);
  }

  Widget _buildQuestionInteractiveDisplay({
    required Map<String, dynamic> questionData,
    required double leftIndent,
    required String displayNoWithPrefix,
    required bool showQuestionText,
  }) {
    final int multiAnswerCount = (questionData['isShufflable'] as num?)?.toInt() ?? 0;

    if (multiAnswerCount > 0) {
      // isShufflable 값이 1 이상이면 다중 답변 UI 호출
      return _buildMultiAnswerUI(
          questionData: questionData,
          requiredCount: multiAnswerCount,
          leftIndent: leftIndent,
          displayNoWithPrefix: displayNoWithPrefix,
          showQuestionText: showQuestionText
      );
    } else {
      // 아니면 기존 단일 답변 UI 호출
      return _buildSingleAnswerUI(
          questionData: questionData,
          leftIndent: leftIndent,
          displayNoWithPrefix: displayNoWithPrefix,
          showQuestionText: showQuestionText
      );
    }
  }

  // 기존의 단일 답변 UI 생성 위젯 (이름만 변경)
  Widget _buildSingleAnswerUI({
    required Map<String, dynamic> questionData,
    required double leftIndent,
    required String displayNoWithPrefix,
    required bool showQuestionText,
  }) {
    // _buildQuestionInteractiveDisplay의 기존 else 블록 로직 전체를 여기에 붙여넣기
    final String? uniqueDisplayId = questionData['uniqueDisplayId'] as String?;
    String questionTextContent = showQuestionText ? (questionData['question'] as String? ?? '질문 없음') : '';
    String? correctAnswerForDisplay = questionData['answer'] as String?;
    final String actualQuestionType = questionData['type'] as String? ?? '타입 정보 없음';
    String questionTypeToDisplay = (actualQuestionType == "발문" || actualQuestionType.isEmpty) ? "" : " ($actualQuestionType)";
    bool isAnswerable = (actualQuestionType == "단답형" || actualQuestionType == "계산" || actualQuestionType == "서술형") && correctAnswerForDisplay != null && uniqueDisplayId != null;

    TextEditingController? controller = isAnswerable ? _getControllerForQuestion(uniqueDisplayId!) : null;
    bool? currentSubmissionStatus = isAnswerable ? _submissionStatus[uniqueDisplayId!] : null;
    String? userSubmittedAnswerForDisplay = isAnswerable ? _userSubmittedAnswers[uniqueDisplayId!] : null;

    return Padding(
      padding: EdgeInsets.only(left: leftIndent, top: 8.0, bottom: 8.0, right: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showQuestionText)
            Text(
              '$displayNoWithPrefix ${questionTextContent}${questionTypeToDisplay}',
              textAlign: TextAlign.start,
              style: TextStyle(
                fontSize: 15,
                fontWeight: leftIndent == 0 && showQuestionText ? FontWeight.w600 : (leftIndent < 24.0 ? FontWeight.w500 : FontWeight.normal),
              ),
            )
          else if (displayNoWithPrefix.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: (isAnswerable ? 4.0 : 0)),
              child: Text(
                displayNoWithPrefix,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.blueGrey[700]),
              ),
            ),
          if (showQuestionText && isAnswerable) const SizedBox(height: 8.0),
          if (isAnswerable && controller != null && correctAnswerForDisplay != null) ...[
            if (!showQuestionText) const SizedBox(height: 4), // "풀이 (타입)"과 TextField 사이 간격
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
                if (currentSubmissionStatus == null) {
                  // *** 변경된 부분: 이제 questionData 전체를 넘겨줍니다. ***
                  _checkAnswer(questionData);
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
                  onPressed: currentSubmissionStatus == null
                      ? () {
                    FocusScope.of(context).unfocus();
                    // *** 변경된 부분: 이제 questionData 전체를 넘겨줍니다. ***
                    _checkAnswer(questionData);
                  }
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
          else if (correctAnswerForDisplay != null && actualQuestionType != "발문")
            Padding(
              padding: EdgeInsets.only(top: 4.0, left: (showQuestionText ? 0 : 8.0)),
              child: Text('정답: $correctAnswerForDisplay', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w500)),
            )
          else if (actualQuestionType != "발문" && correctAnswerForDisplay == null && showQuestionText)
              const Padding(
                padding: EdgeInsets.only(top: 4.0),
                child: Text("텍스트 정답이 제공되지 않는 유형입니다.", style: TextStyle(fontStyle: FontStyle.italic, fontSize: 13, color: Colors.grey)),
              )
        ],
      ),
    );
  }

  // 새로운 다중 답변 UI 생성 위젯
  Widget _buildMultiAnswerUI({
    required Map<String, dynamic> questionData,
    required int requiredCount,
    required double leftIndent,
    required String displayNoWithPrefix,
    required bool showQuestionText,
  }) {
    final String uniqueDisplayId = questionData['uniqueDisplayId'];
    String questionTextContent = showQuestionText ? (questionData['question'] as String? ?? '질문 없음') : '';
    final bool? submissionStatus = _submissionStatus[uniqueDisplayId];
    final List<dynamic> options = questionData['answer'] as List;

    final controllers = _multiAnswerControllers.putIfAbsent(uniqueDisplayId, () => List.generate(requiredCount, (index) => TextEditingController()));

    return Padding(
      padding: EdgeInsets.only(left: leftIndent, top: 8.0, bottom: 8.0, right: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showQuestionText)
            Text('$displayNoWithPrefix $questionTextContent (요구 답안: $requiredCount개)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          if (!showQuestionText)
            Text("$displayNoWithPrefix (요구 답안: $requiredCount개)", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.blueGrey[700])),
          const SizedBox(height: 8),

          for (int i = 0; i < requiredCount; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: TextField(
                controller: controllers[i],
                enabled: submissionStatus == null,
                decoration: InputDecoration(hintText: '${i + 1}번째 답안', border: const OutlineInputBorder(), isDense: true),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              ElevatedButton(
                onPressed: submissionStatus == null ? () { FocusScope.of(context).unfocus(); _checkMultiAnswer(questionData, requiredCount); } : null,
                child: Text(submissionStatus == null ? '정답 확인' : '채점 완료'),
              ),
              if (submissionStatus != null) TextButton(onPressed: () => _tryAgain(uniqueDisplayId), child: const Text('다시 풀기')),
            ],
          ),
          if (submissionStatus != null) ...[
            const SizedBox(height: 12),
            Text(submissionStatus ? '정답입니다! 👍' : '오답입니다. 👎', style: TextStyle(color: submissionStatus ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
            Text('입력한 답: ${_userSubmittedMultiAnswers[uniqueDisplayId]?.join(", ")}'),
            Text('모범 답안: ${options.join(", ")}'),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // AppBar 제목을 페이지 기능에 맞게 변경 가능 (예: "기출문제 Q-Bank")
      appBar: CSAppBar(title: widget.title),
      body: Column(
        children: [
          // --- 상단 컨트롤 UI ---
          Padding(
            padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 8.0),
            child: Column(
              children: [
                if (_isLoadingOptions) const Center(child: CircularProgressIndicator())
                else ...[
                  // 년도 선택 드롭다운
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: '년도 선택', border: OutlineInputBorder()),
                    value: _selectedYear,
                    hint: const Text('출제 년도를 선택하세요'),
                    items: _yearOptions.map((year) => DropdownMenuItem(value: year, child: Text(year))).toList(),
                    onChanged: _updateYearSelected,
                  ),
                  const SizedBox(height: 12),
                  // 회차 선택 드롭다운
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: '회차 선택', border: OutlineInputBorder()),
                    value: _selectedRound,
                    hint: const Text('회차를 선택하세요'),
                    disabledHint: _selectedYear == null ? const Text('년도를 먼저 선택하세요') : null,
                    items: _filteredRoundOptions.map((round) => DropdownMenuItem(value: round, child: Text(round))).toList(),
                    onChanged: _selectedYear == null ? null : _updateRoundSelected,
                  ),
                  const SizedBox(height: 12),
                  // 등급 선택 드롭다운
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: '등급 선택', border: OutlineInputBorder()),
                    value: _selectedGrade,
                    hint: const Text('등급을 선택하세요'),
                    disabledHint: _selectedRound == null ? const Text('회차를 먼저 선택하세요') : null,
                    items: _filteredGradeOptions.map((grade) => DropdownMenuItem(value: grade, child: Text(grade))).toList(),
                    onChanged: _selectedRound == null ? null : _updateGradeSelected,
                  ),
                ],
                const SizedBox(height: 12),
                ElevatedButton(
                  // 버튼 활성화 조건 변경
                  onPressed: (_selectedYear == null || _selectedRound == null || _selectedGrade == null || _isLoadingQuestions)
                      ? null
                      : _fetchQuestions, // 랜덤 시험지 생성 -> 특정 시험지 불러오기
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), minimumSize: const Size(double.infinity, 44)),
                  child: _isLoadingQuestions
                      ? const SizedBox(height:20, width:20, child:CircularProgressIndicator(color: Colors.white, strokeWidth: 3,))
                      : const Text('시험지 불러오기', style: TextStyle(fontSize: 16)), // 버튼 텍스트 변경
                ),
              ],
            ),
          ),
          if (_errorMessage.isNotEmpty && !_isLoadingOptions && _questions.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0), child: Text(_errorMessage, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),

          // --- 문제 목록 표시 ---
          Expanded(
            child: _isLoadingQuestions
                ? const Center(child: CircularProgressIndicator())
                : _questions.isEmpty // _randomlySelectedQuestions -> _questions
                ? Center(child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                  _selectedYear == null || _selectedRound == null || _selectedGrade == null
                      ? '년도, 회차, 등급을 선택하고 시험지를 불러오세요.'
                      : '선택한 조건의 문제가 없거나, 문제가 로드되지 않았습니다.',
                  textAlign: TextAlign.center),
            ))
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              itemCount: _questions.length, // _randomlySelectedQuestions -> _questions
              itemBuilder: (context, index) {
                final mainQuestionData = _questions[index]; // _randomlySelectedQuestions -> _questions
                final String pageOrderNo = "${index + 1}"; // 화면상 순번
                final String? originalNo = mainQuestionData['no'] as String?; // Firestore의 'no' 필드
                final String type = mainQuestionData['type'] as String? ?? '';
                final String questionTextForSubtitle = (mainQuestionData['question'] as String? ?? '');
                final String uniqueId = mainQuestionData['uniqueDisplayId'] as String; // 이미 할당됨
                final String sourceExamId = mainQuestionData['sourceExamId'] as String? ?? '출처 미상'; // 이미 할당됨

                // 주 문제 제목에서 형식 표시 제거 (답안 영역으로 이동했으므로)
                String mainTitleText = '문제 $pageOrderNo (출처: $sourceExamId - ${originalNo ?? "N/A"}번)';
                // 주 문제 답안 영역에 표시될 타입 (예: " (단답형)")
                String typeForAnswerArea = (type == "발문" || type.isEmpty) ? "" : " ($type)";

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6.0),
                  elevation: 1.5,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                  child: ExpansionTile(
                    key: ValueKey(uniqueId), // 고유키 사용
                    tilePadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    childrenPadding: EdgeInsets.zero,
                    title: Text(mainTitleText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5)),
                    subtitle: questionTextForSubtitle.isNotEmpty
                        ? Padding(
                      padding: const EdgeInsets.only(top: 5.0),
                      child: Text(questionTextForSubtitle, style: const TextStyle(fontSize: 15.0, color: Colors.black87, height: 1.4)),
                    )
                        : null,
                    initiallyExpanded: _questions.length <= 3, // 문제 수가 적으면 펼쳐서 보여줌
                    children: <Widget>[
                      // 주 문제의 답안/풀이 영역 + 형식 표시
                      _buildQuestionInteractiveDisplay(
                          questionData: mainQuestionData,
                          leftIndent: 16.0,
                          displayNoWithPrefix: "풀이${typeForAnswerArea}", // 형식 표시
                          showQuestionText: false // 주 문제 본문은 subtitle에 있으므로 false
                      ),
                      // 하위 문제들 (sub_questions)
                      Builder(builder: (context) {
                        List<Widget> subQuestionAndSubSubWidgets = [];
                        final dynamic subQuestionsField = mainQuestionData['sub_questions'];
                        if (subQuestionsField is Map<String, dynamic> && subQuestionsField.isNotEmpty) {
                          if (mainQuestionData.containsKey('answer') || (mainQuestionData['type'] != "발문" && (subQuestionsField).isNotEmpty )) {
                            subQuestionAndSubSubWidgets.add(const Divider(height: 12, thickness: 0.5, indent:16, endIndent:16));
                          }
                          Map<String, dynamic> subQuestionsMap = subQuestionsField;
                          List<String> sortedSubKeys = subQuestionsMap.keys.toList();
                          // 하위 문제 키 정렬 (숫자로 변환하여)
                          sortedSubKeys.sort((a, b) => (int.tryParse(a) ?? 99999).compareTo(int.tryParse(b) ?? 99999));

                          int subOrderCounter = 0;
                          for (String subKey in sortedSubKeys) {
                            final dynamic subQuestionValue = subQuestionsMap[subKey];
                            if (subQuestionValue is Map<String, dynamic>) {
                              subOrderCounter++;
                              String subQuestionOrderPrefix = "($subOrderCounter)";
                              // 각 하위 문제의 타입 가져오기
                              final String subTypeRaw = subQuestionValue['type'] as String? ?? '';
                              String subTypeDisplay = (subTypeRaw == "발문" || subTypeRaw.isEmpty) ? "" : " ($subTypeRaw)";

                              subQuestionAndSubSubWidgets.add(
                                  _buildQuestionInteractiveDisplay(
                                    questionData: Map<String, dynamic>.from(subQuestionValue),
                                    leftIndent: 24.0,
                                    displayNoWithPrefix: subQuestionOrderPrefix,
                                    showQuestionText: true, // 하위 문제는 본문과 타입 모두 표시
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
                                    // 각 하위-하위 문제의 타입 가져오기
                                    final String subSubTypeRaw = subSubQValue['type'] as String? ?? '';
                                    String subSubTypeDisplay = (subSubTypeRaw == "발문" || subSubTypeRaw.isEmpty) ? "" : " ($subSubTypeRaw)";

                                    subQuestionAndSubSubWidgets.add(
                                        _buildQuestionInteractiveDisplay(
                                          questionData: Map<String, dynamic>.from(subSubQValue),
                                          leftIndent: 32.0,
                                          displayNoWithPrefix: " - $subSubQDisplayNo",
                                          showQuestionText: true, // 하위-하위 문제도 본문과 타입 표시
                                        )
                                    );
                                  }
                                }
                              }
                            }
                          }
                        }
                        if (subQuestionAndSubSubWidgets.isEmpty && mainQuestionData['type'] == "발문" && !(mainQuestionData.containsKey('answer') && mainQuestionData['answer'] != null) ) {
                          return const Padding(padding: EdgeInsets.all(16.0), child: Text("하위 문제가 없습니다.", style: TextStyle(fontStyle: FontStyle.italic)));
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