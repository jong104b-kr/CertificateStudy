import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:collection/collection.dart';

import 'studydataupdater.dart';
import 'openaigraderservice.dart';

/// 문자열이 null이거나 비어있는지 확인하는 확장 함수
extension StringNullOrEmptyExtension on String? {
  bool get isNullOrEmpty => this == null || this!.trim().isEmpty;
}

/// 공통으로 사용하는 상태와 로직을 담은 Mixin
mixin QuestionStateMixin<T extends StatefulWidget> on State<T> {
  final Uuid uuid = const Uuid();
  final Map<String, List<TextEditingController>> controllers = {};
  final Map<String, bool?> submissionStatus = {};
  final Map<String, List<String>> userSubmittedAnswers = {};
  final Stopwatch _stopwatch = Stopwatch();
  bool _isResultSaved = false;

  String? _currentExamId;
  void setCurrentExamId(String examId) {
    _currentExamId = examId;
  }

  final OpenAiGraderService _graderService = OpenAiGraderService();
  final Map<String, GradingResult> aiGradingResults = {};

  // 각 State 클래스에서 자신의 질문 목록을 반환하도록 강제
  List<Map<String, dynamic>> get questions;

  // 각 State 클래스에서 자신의 질문 목록을 비우는 로직을 구현하도록 강제
  void clearQuestionsList();

  // --- [신규] 오답노트 저장 로직 ---
  final Map<String, bool> incorrectNoteSaveStatus = {};

  Future<void> addQuestionToIncorrectNote(Map<String, dynamic> questionData) async {
    if (_currentExamId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("시험 ID가 설정되지 않아 저장할 수 없습니다.")));
      return;
    }
    final String questionNo = questionData['no'] as String;
    setState(() => incorrectNoteSaveStatus[questionNo] = true); // 저장 시작 상태

    try {
      // 전체 문제 구조를 그대로 전달
      await FirestoreService.saveToIncorrectNote(
        sourceExamId: _currentExamId!,
        fullQuestionData: questionData,
      );

      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("'$questionNo'번 문제를 오답노트에 저장했습니다."))
        );
      }
    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("오답노트 저장에 실패했습니다: $e"))
        );
        // 실패 시 상태를 원래대로 돌릴 수 있습니다.
        setState(() => incorrectNoteSaveStatus.remove(questionNo));
      }
    }
  }

  void startTimer() {
    _stopwatch.reset();
    _stopwatch.start();
  }

  void stopTimer() {
    _stopwatch.stop();
  }

  @override
  void dispose() {
    controllers.values.forEach((controllerList) {
      for (var controller in controllerList) {
        controller.dispose();
      }
    });
    super.dispose();
  }

  List<TextEditingController> getControllersForQuestion(
      String uniqueDisplayId,
      int answerCount,
      ) {
    return controllers.putIfAbsent(uniqueDisplayId, () {
      final previousAnswers = userSubmittedAnswers[uniqueDisplayId] ?? [];
      return List.generate(answerCount, (index) {
        return TextEditingController(
          text: index < previousAnswers.length ? previousAnswers[index] : null,
        );
      });
    });
  }

  void clearAllAttemptStatesAndQuestions() {
    if (!mounted) return;
    setState(() {
      controllers.values.forEach((controllerList) {
        for (var controller in controllerList) {
          controller.clear();
        }
      });
      submissionStatus.clear();
      userSubmittedAnswers.clear();
      aiGradingResults.clear();
      _stopwatch.reset();
      _isResultSaved = false;
      incorrectNoteSaveStatus.clear();
      clearQuestionsList();
    });
  }

  Map<String, dynamic> cleanNewlinesRecursive(
      Map<String, dynamic> questionData,
      ) {
    Map<String, dynamic> cleanedData = {};
    cleanedData['uniqueDisplayId'] =
        questionData['uniqueDisplayId'] ?? uuid.v4();
    questionData.forEach((key, value) {
      if (key == 'uniqueDisplayId') return;
      if (value is String) {
        cleanedData[key] = value.replaceAll('\\n', '\n');
      } else if (value is List) {
        cleanedData[key] = value;
      } else if ((key == 'sub_questions' || key == 'sub_sub_questions') &&
          value is Map) {
        Map<String, dynamic> nestedCleanedMap = {};
        (value as Map<String, dynamic>).forEach((subKey, subValue) {
          if (subValue is Map<String, dynamic>) {
            nestedCleanedMap[subKey] = cleanNewlinesRecursive(subValue);
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

  Future<void> checkAnswer(
      Map<String, dynamic> questionData,
      Map<String, dynamic>? parentData,
      ) async {
    final String uniqueDisplayId = questionData['uniqueDisplayId'] as String;
    final answerControllers = controllers[uniqueDisplayId] ?? [];
    if (answerControllers.isEmpty ||
        answerControllers.every((c) => c.text.isNullOrEmpty)) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("답을 입력해주세요.")));
      return;
    }

    print("--- [checkAnswer 시작] (ID: ${uniqueDisplayId.substring(0, 5)}) ---");
    print("  - 문제 타입: ${questionData['type']}");
    if(parentData != null) print("  - 이 문제는 하위 문제입니다. (부모 문제 no: ${parentData['no']})");

    setState(() {
      submissionStatus[uniqueDisplayId] = null;
    });

    bool overallCorrect;
    List<String> userAnswers = answerControllers.map((c) => c.text).toList();

    if (questionData['type'] == '서술형') {
      print("  -> 서술형 채점 로직으로 진입했습니다. [순서 무관 로직 적용]");

      // 1. 사용자 답안 리스트를 가져와서 '알파벳순'으로 정렬합니다.
      userAnswers.sort();
      // 정렬된 답안을 번호를 붙여 하나의 문자열로 합칩니다.
      final userAnswerString = userAnswers
          .asMap()
          .entries
          .map((entry) => "(${entry.key + 1}) ${entry.value}")
          .join(' || ');

      // 2. 모범 답안도 똑같이 '알파벳순'으로 정렬합니다.
      final dynamic correctAnswerValue = questionData['answer'];
      String modelAnswerString = '';

      if (correctAnswerValue is List) {
        // List<dynamic>을 List<String>으로 안전하게 변환 후 정렬
        List<String> modelAnswersList = correctAnswerValue.map((e) => e.toString().trim()).toList();
        modelAnswersList.sort();
        // 정렬된 모범 답안을 번호를 붙여 하나의 문자열로 합칩니다.
        modelAnswerString = modelAnswersList
            .asMap()
            .entries
            .map((entry) => "(${entry.key + 1}) ${entry.value}")
            .join(' || ');
      } else if (correctAnswerValue is String) {
        modelAnswerString = correctAnswerValue; // 단일 답안은 정렬할 필요가 없습니다.
      }

      // --- [디버깅] AI에 보낼 정렬된 데이터 확인 ---
      print("  -> AI 채점 요청 데이터 (정렬됨):");
      print("    - 사용자 답안: $userAnswerString");
      print("    - 모범 답안: $modelAnswerString");

      // --- 기존의 AI 채점 및 저장 로직은 그대로 사용 ---
      try {
        num? scoreValue = questionData['fullscore'] ?? parentData?['fullscore'];
        final fullScore = (scoreValue)?.toInt() ?? 0;

        final result = await _graderService.gradeAnswer(
          question: questionData['question'] as String? ?? '',
          modelAnswer: modelAnswerString,   // 정렬된 모범 답안 사용
          userAnswer: userAnswerString,     // 정렬된 사용자 답안 사용
          fullScore: fullScore,
        );

        print("  -> AI 채점 응답 수신 성공! 점수: ${result.score}");

        overallCorrect = result.isCorrect;
        if (mounted) setState(() => aiGradingResults[uniqueDisplayId] = result);

      } catch (e) {
        print("  -> !!! AI 채점 중 오류 발생: $e");
        overallCorrect = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("채점 중 오류가 발생했습니다.")));
          setState(() => submissionStatus.remove(uniqueDisplayId));
        }
        return;
      }
    } else {
      final int requiredCount = questionData['isShufflable'] as int? ?? 1;
      final dynamic correctAnswerValue = questionData['answer'];

      final Set<String> correctAnswersSet;
      if (correctAnswerValue is List) {
        correctAnswersSet = correctAnswerValue.map((e) => e.toString().trim().toLowerCase()).toSet();
      } else if (correctAnswerValue is String) {
        correctAnswersSet = {correctAnswerValue.trim().toLowerCase()};
      } else {
        correctAnswersSet = {};
      }

      final Set<String> userAnswersSet = userAnswers.map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toSet();

      if (requiredCount == correctAnswersSet.length) {
        overallCorrect = const SetEquality().equals(correctAnswersSet, userAnswersSet);
      } else if (requiredCount < correctAnswersSet.length) {
        overallCorrect = userAnswersSet.length == requiredCount && userAnswersSet.every((answer) => correctAnswersSet.contains(answer));
      } else {
        overallCorrect = userAnswersSet.length == 1 && correctAnswersSet.contains(userAnswersSet.first);
      }

    }

    print("--- [checkAnswer] 최종 판정 ---");
    print("  - 이 문제의 정답 여부(overallCorrect)를 ${overallCorrect}(으)로 submissionStatus에 저장합니다.");

    if (mounted) {
        setState(() {
        userSubmittedAnswers[uniqueDisplayId] = userAnswers;
        submissionStatus[uniqueDisplayId] = overallCorrect;
      });
    }
  }

  void tryAgain(String uniqueDisplayId) {
    if (mounted) {
      setState(() {
        controllers[uniqueDisplayId]?.forEach((controller) => controller.clear());
        submissionStatus.remove(uniqueDisplayId);
        userSubmittedAnswers.remove(uniqueDisplayId);
        aiGradingResults.remove(uniqueDisplayId);
      });
    }
  }

  // --- [최종 채점 로직] ---

  /// 특정 문제 데이터 아래의 모든 최하위 문제(채점 대상)들을 재귀적으로 찾아 리스트로 반환합니다.
  List<Map<String, dynamic>> getAllLeafNodes(Map<String, dynamic> questionData) {
    final List<Map<String, dynamic>> leaves = [];

    final bool hasSubQuestions = questionData.containsKey('sub_questions') && questionData['sub_questions'] is Map && (questionData['sub_questions'] as Map).isNotEmpty;
    final bool hasSubSubQuestions = questionData.containsKey('sub_sub_questions') && questionData['sub_sub_questions'] is Map && (questionData['sub_sub_questions'] as Map).isNotEmpty;

    if (!hasSubQuestions && !hasSubSubQuestions) {
      final type = questionData['type'] as String?;
      if (type != null && type != '발문') {
        leaves.add(questionData);
      }
    } else {
      if (hasSubQuestions) {
        final subMap = questionData['sub_questions'] as Map<String, dynamic>;
        for (final subQuestion in subMap.values.whereType<Map<String, dynamic>>()) {
          leaves.addAll(getAllLeafNodes(subQuestion));
        }
      }
      if (hasSubSubQuestions) {
        final subSubMap = questionData['sub_sub_questions'] as Map<String, dynamic>;
        for (final subSubQuestion in subSubMap.values.whereType<Map<String, dynamic>>()) {
          leaves.addAll(getAllLeafNodes(subSubQuestion));
        }
      }
    }
    return leaves;
  }

  /// 사용자가 획득한 점수를 계산합니다.
  int calculateUserScore() {
    print("\n\n--- [calculateUserScore] 채점 시작 ---");
    int totalScore = 0;

    for (final questionData in questions) {
      final parentId = questionData['no'] ?? 'ID 없음';
      print("\n[상위 문제 처리 시작] 문제: $parentId");
      final bool hasChildren =
          (questionData.containsKey('sub_questions') && (questionData['sub_questions'] as Map).isNotEmpty) ||
              (questionData.containsKey('sub_sub_questions') && (questionData['sub_sub_questions'] as Map).isNotEmpty);

      if (hasChildren) {
        print("  -> 컨테이너 문제입니다. 하위 문제들을 확인합니다.");
        final List<Map<String, dynamic>> leafChildren = getAllLeafNodes(questionData);
        print("  -> 발견된 최하위 자식 문제 수: ${leafChildren.length}");
        if (leafChildren.isEmpty) {
          print("  -> 처리할 하위 문제가 없으므로 다음 상위 문제로 넘어갑니다.");
          continue;
        }

        bool allChildrenFullyCorrect = true; // 이 컨테이너가 완벽 정답인지 여부
        int partialScore = 0; // 하위 문제들의 점수 합계

        for (final leaf in leafChildren) {
          final uniqueId = leaf['uniqueDisplayId'] as String?;
          final leafNo = leaf['no'] ?? '하위 ID 없음';
          print("    - [하위 문제 검사] 문제: $leafNo (ID: ${uniqueId?.substring(0, 8)})");
          if (uniqueId == null) {
            allChildrenFullyCorrect = false;
            print("      -> uniqueId가 없어 '완벽한 정답'이 아님으로 처리.");
            continue;
          }

          final bool isCorrect = submissionStatus[uniqueId] ?? false;

          // --- [수정] 서술형 문제 채점 로직 변경 ---
          if (leaf['type'] == '서술형') {
            print("      -> '서술형'입니다. AI 채점 결과를 확인합니다.");
            final aiResult = aiGradingResults[uniqueId];
            final leafFullScore = (leaf['fullscore'] as num?)?.toInt() ?? 0;
            if (aiResult != null) {
              print("      -> AI 점수: ${aiResult.score} / 만점: $leafFullScore");
              partialScore += aiResult.score; // isCorrect 여부와 상관없이 AI 점수를 더함
              if (aiResult.score < leafFullScore) {
                allChildrenFullyCorrect = false; // 부분 점수면 완벽 정답은 아님
                print("      -> 부분 점수이므로 allChildrenFullyCorrect = false 로 변경");
              }
            } else {
              // AI 채점 결과가 없으면 오답 처리
              allChildrenFullyCorrect = false;
              print("      -> AI 채점 결과(aiResult)가 null이므로 allChildrenFullyCorrect = false 로 변경");
            }
          } else { // 서술형이 아닌 다른 문제 유형 (단답형 등)
            print("      -> isCorrect (submissionStatus 값): $isCorrect");
            if (isCorrect) {
              final leafScore = (leaf['fullscore'] as num?)?.toInt() ?? 0;
              partialScore += leafScore;
              print("      -> '단답형/계산형' 정답. 부분 점수(partialScore)에 +$leafScore");
            } else {
              allChildrenFullyCorrect = false;
              print("      -> 오답(isCorrect:false)이므로 allChildrenFullyCorrect = false 로 변경");
            }
          }
        }

        print("  -> 컨테이너 내 하위 문제 처리 완료.");
        print("  -> 계산된 부분 점수 합계(partialScore): $partialScore");
        print("  -> 모든 하위 문제 완벽 정답 여부(allChildrenFullyCorrect): $allChildrenFullyCorrect");

        if (allChildrenFullyCorrect) {
          final parentScore = (questionData['fullscore'] as num?)?.toInt() ?? 0;
          totalScore += parentScore;
          print("  -> [결과] '모두 완벽 정답'이므로 상위 문제 점수인 $parentScore 점을 더합니다.");
        } else {
          totalScore += partialScore;
          print("  -> [결과] '부분 정답/오답'이므로 계산된 부분 점수인 $partialScore 점을 더합니다.");
        }

      } else {
        print("  -> 독립형 문제입니다.");
        final uniqueId = questionData['uniqueDisplayId'] as String?;
        if (uniqueId == null) continue;

        // --- [수정] 독립 서술형 문제 채점 로직 변경 ---
        if (questionData['type'] == '서술형') {
          final aiResult = aiGradingResults[uniqueId];
          if (aiResult != null) {
            totalScore += aiResult.score; // isCorrect 여부와 상관없이 AI 점수를 더함
            print("  -> [결과] 독립 서술형. AI 점수 ${aiResult.score} 점을 더합니다.");
          } else {
            print("  -> 채점되지 않은 서술형 문제입니다.");
          }
        } else { // 독립 단답형/계산형 문제
          if (submissionStatus[uniqueId] ?? false) {
            final score = (questionData['fullscore'] as num?)?.toInt() ?? 0;
            totalScore += score;
            print("  -> [결과] 독립 단답형/계산형 정답. $score 점을 더합니다.");
          } else {
            print("  -> 오답이거나 채점되지 않은 문제입니다.");
          }
        }
      }
      print("[현재까지 총점]: $totalScore");
    }
    print("\n--- 채점 종료 --- 최종 총점: $totalScore");
    return totalScore;
  }

  /// 시험의 총점을 계산합니다.
  int calculateMaxScore() {
    int maxScore = 0;
    for (final questionData in questions) {
      if (questionData.containsKey('fullscore')) {
        final score = questionData['fullscore'];
        maxScore += (score is int ? score : int.tryParse(score.toString()) ?? 0);
      }
    }
    return maxScore;
  }

  /// 채점 결과를 다이얼로그로 표시합니다.
  Future<void> showGradingResult(
      BuildContext context, {
        required String examId,
        required String examTitle,
      }) async {
    stopTimer();

    final int userScore = calculateUserScore();
    final int maxScore = calculateMaxScore();

    // UI가 빌드된 후에 다이얼로그를 표시하도록 예약
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if(mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) {
            return StatefulBuilder(
              builder: (context, setDialogState) {
                return AlertDialog(
                  title: const Text('💯 채점 결과'),
                  content: SingleChildScrollView(
                    child: ListBody(
                      children: <Widget>[
                        Text('총점: $maxScore점\n획득 점수: $userScore점', style: const TextStyle(fontSize: 16, height: 1.5)),
                        const SizedBox(height: 8),
                        Text('총 소요 시간: ${_stopwatch.elapsed.inSeconds}초'),
                      ],
                    ),
                  ),
                  actions: <Widget>[
                    if (!_isResultSaved)
                      TextButton(
                        child: const Text('결과 저장하기'),
                        onPressed: () async {
                          final attemptsData = _buildAttemptsDataForSaving();
                          await FirestoreService.saveExamResult(
                            sourceExamId: examId,
                            examTitle: examTitle,
                            timeTaken: _stopwatch.elapsed.inSeconds,
                            totalScore: userScore,
                            attemptsData: attemptsData,
                          );
                          setDialogState(() => _isResultSaved = true);
                          if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('결과가 성공적으로 저장되었습니다.')));
                        },
                      ),
                    if (_isResultSaved)
                      TextButton(onPressed: null, child: const Text('저장 완료')),
                    TextButton(child: const Text('닫기'), onPressed: () => Navigator.of(dialogContext).pop()),
                  ],
                );
              },
            );
          },
        );
      }
    });
  }

  List<Map<String, dynamic>> _buildAttemptsDataForSaving() {
    print("--- [SAVE] 새로운 방식으로 attemptsData 생성을 시작합니다.");
    final List<Map<String, dynamic>> finalAttemptsData = [];

    // 1. 최상위 문제 목록을 기준으로 반복합니다.
    for (final parentQuestionData in questions) {
      // 2. 계층 구조를 보존하며 데이터를 깊은 복사합니다.
      final newFullQuestionData = json.decode(json.encode(parentQuestionData));

      // 재귀적으로 각 노드의 채점 결과를 업데이트하는 함수
      void updateNodeResults(Map<String, dynamic> node) {
        final uniqueId = node['uniqueDisplayId'] as String?;
        if (uniqueId != null) {
          final isCorrect = submissionStatus[uniqueId];
          final userAnswer = userSubmittedAnswers[uniqueId];
          final aiResult = aiGradingResults[uniqueId];

          node['isCorrect'] = isCorrect;
          node['userAnswer'] = userAnswer?.join(' || ') ?? '미제출';
          if (aiResult != null) {
            node['aiScore'] = aiResult.score;
            node['feedback'] = aiResult.explanation;
          }
        }

        // 하위 노드에 대해 재귀적으로 함수 호출
        if (node.containsKey('sub_questions') && node['sub_questions'] is Map) {
          (node['sub_questions'] as Map).values.forEach((subNode) {
            if (subNode is Map<String, dynamic>) updateNodeResults(subNode);
          });
        }
        if (node.containsKey('sub_sub_questions') && node['sub_sub_questions'] is Map) {
          (node['sub_sub_questions'] as Map).values.forEach((subSubNode) {
            if (subSubNode is Map<String, dynamic>) updateNodeResults(subSubNode);
          });
        }
      }

      // 3. 복사된 데이터의 모든 노드(자신 포함)에 채점 결과를 업데이트합니다.
      updateNodeResults(newFullQuestionData);

      // 4. 최상위 문제에 대한 'attempt' 맵을 구성합니다.
      final attempt = {
        'isCorrect': newFullQuestionData['isCorrect'],
        'userAnswer': newFullQuestionData['userAnswer'],
        'fullQuestionData': newFullQuestionData, // 계층 구조가 유지된 전체 데이터를 저장
        'score': newFullQuestionData['aiScore'] ?? (newFullQuestionData['isCorrect'] == true ? newFullQuestionData['fullscore'] : 0),
        'feedback': newFullQuestionData['feedback'],
      };

      finalAttemptsData.add(attempt);
    }

    print("--- [SAVE] 총 ${finalAttemptsData.length}개의 최상위 문제 결과가 생성되었습니다.");
    return finalAttemptsData;
  }
}

/// 단일 문제의 인터랙티브 UI (TextField, 정답확인 등)를 생성하는 공통 위젯
class QuestionInteractiveDisplay extends StatefulWidget {
  final Map<String, dynamic> questionData;
  final double leftIndent;
  final String displayNoWithPrefix;
  final String questionTypeToDisplay;
  final bool showQuestionText;

  final List<TextEditingController> Function(String, int) getControllers;
  final void Function(Map<String, dynamic>, Map<String, dynamic>?)
  onCheckAnswer;
  final Map<String, dynamic>? parentQuestionData;
  final void Function(String) onTryAgain;
  final bool? submissionStatus;
  final List<String>? userSubmittedAnswers;

  final Map<String, GradingResult>? aiGradingResults;

  final Future<void> Function(Map<String, dynamic>) onSaveToIncorrectNote;
  final bool isSavedToIncorrectNote;

  const QuestionInteractiveDisplay({
    super.key,
    required this.questionData,
    required this.leftIndent,
    required this.displayNoWithPrefix,
    required this.questionTypeToDisplay,
    required this.showQuestionText,
    required this.getControllers,
    required this.onCheckAnswer,
    this.parentQuestionData,
    required this.onTryAgain,
    required this.submissionStatus,
    required this.userSubmittedAnswers,
    this.aiGradingResults,
    required this.onSaveToIncorrectNote,
    required this.isSavedToIncorrectNote,
  });

  @override
  State<QuestionInteractiveDisplay> createState() =>
      _QuestionInteractiveDisplayState();
}

class _QuestionInteractiveDisplayState
    extends State<QuestionInteractiveDisplay> {
  @override
  Widget build(BuildContext context) {
    final String? uniqueDisplayId =
        widget.questionData['uniqueDisplayId'] as String?;
    final String actualQuestionType =
        widget.questionData['type'] as String? ?? '타입 정보 없음';

    // REVISED: isShufflable 값으로 정답 개수 판단
    final int answerCount = widget.questionData['isShufflable'] as int? ?? 1;
    final dynamic answerValue = widget.questionData['answer'];

    // REVISED: isShufflable 값에 따라 answer 필드를 List 또는 String으로 처리하여 정답 리스트 생성
    List<String> correctAnswers = [];
    if (answerValue != null) {
      if (answerCount > 1 && answerValue is List) {
        correctAnswers = answerValue.map((e) => e.toString().trim()).toList();
      } else if (answerValue is String) {
        correctAnswers = [answerValue.trim()];
      }
    }

    String questionTextContent = "";
    if (widget.showQuestionText) {
      questionTextContent =
          widget.questionData['question'] as String? ?? '질문 내용 없음';
    }

    bool isAnswerable =
        (actualQuestionType == "단답형" ||
            actualQuestionType == "계산" ||
            actualQuestionType == "서술형") &&
        uniqueDisplayId != null &&
        answerCount > 0;

    List<TextEditingController>? controllers =
        isAnswerable
            ? widget.getControllers(uniqueDisplayId!, answerCount)
            : null;
    bool? currentSubmissionStatus =
        isAnswerable ? widget.submissionStatus : null;
    List<String>? userSubmittedAnswersForDisplay =
        isAnswerable ? widget.userSubmittedAnswers : null;

    final bool isTopLevelQuestion = widget.leftIndent == 0 && widget.parentQuestionData == null;

    return Padding(
      padding: EdgeInsets.only(
        left: widget.leftIndent,
        top: 8.0,
        bottom: 8.0,
        right: 8.0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- [수정] 최상위 문제일 경우, 문제 텍스트와 오답노트 버튼을 함께 표시 ---
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.showQuestionText)
                      Text(
                        '${widget.displayNoWithPrefix} ${questionTextContent}${widget.questionTypeToDisplay}',
                        textAlign: TextAlign.start,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight:
                          widget.leftIndent == 0 && widget.showQuestionText
                              ? FontWeight.w600
                              : (widget.leftIndent < 24.0
                              ? FontWeight.w500
                              : FontWeight.normal),
                        ),
                      )
                    else if (widget.displayNoWithPrefix.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(bottom: (isAnswerable ? 4.0 : 0)),
                        child: Text(
                          '${widget.displayNoWithPrefix}${widget.questionTypeToDisplay}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Colors.blueGrey[700],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // [신규] '오답노트에 등록' 버튼
              if (isTopLevelQuestion) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  icon: Icon(
                    widget.isSavedToIncorrectNote ? Icons.check_circle : Icons.add_circle_outline,
                    size: 18,
                  ),
                  label: Text(
                    widget.isSavedToIncorrectNote ? '저장됨' : '오답노트',
                    style: TextStyle(fontSize: 13),
                  ),
                  onPressed: widget.isSavedToIncorrectNote
                      ? null // 이미 저장되었으면 비활성화
                      : () => widget.onSaveToIncorrectNote(widget.questionData),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    backgroundColor: widget.isSavedToIncorrectNote ? Colors.grey[200] : null,
                  ),
                ),
              ],
            ],
          ),

          if (widget.showQuestionText && isAnswerable)
            const SizedBox(height: 8.0),

          if (isAnswerable &&
              controllers != null &&
              correctAnswers.isNotEmpty) ...[
            if (!widget.showQuestionText) const SizedBox(height: 4),
            Column(
              children: List.generate(answerCount, (index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    children: [
                      if (answerCount > 1)
                        Text(
                          "(${index + 1}) ",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      Expanded(
                        child: TextField(
                          controller: controllers[index],
                          enabled: currentSubmissionStatus == null,
                          decoration: InputDecoration(
                            hintText: '정답 ${index + 1} 입력...',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 12,
                            ),
                          ),
                          onChanged: (text) {
                            if (currentSubmissionStatus == null)
                              setState(() {});
                          },
                          onSubmitted: (value) {
                            if (currentSubmissionStatus == null)
                              widget.onCheckAnswer(
                                widget.questionData,
                                widget.parentQuestionData,
                              );
                          },
                          maxLines: actualQuestionType == "서술형" ? null : 1,
                          keyboardType:
                              actualQuestionType == "서술형"
                                  ? TextInputType.multiline
                                  : TextInputType.text,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                ElevatedButton(
                  onPressed:
                      currentSubmissionStatus == null
                          ? () {
                            FocusScope.of(context).unfocus();
                            widget.onCheckAnswer(
                              widget.questionData,
                              widget.parentQuestionData,
                            );
                          }
                          : null,
                  child: Text(
                    currentSubmissionStatus == null ? '정답 확인' : '채점 완료',
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                ),
                if (currentSubmissionStatus != null &&
                    uniqueDisplayId != null) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => widget.onTryAgain(uniqueDisplayId),
                    child: const Text('다시 풀기'),
                  ),
                ],
              ],
            ),
            if (currentSubmissionStatus != null) ...[
              const SizedBox(height: 8),
              if (actualQuestionType == "서술형") ...[
                // --- AI 채점 결과 표시 (서술형) ---
                Builder(
                  builder: (context) {
                    final result = widget.aiGradingResults?[uniqueDisplayId];
                    if (result == null)
                      return const Text('AI 채점 결과를 불러오는 중...');

                    // [수정] 만점(maxScore) 계산 로직 추가
                    num? scoreValue = widget.questionData['fullscore'];
                    if (scoreValue == null &&
                        widget.parentQuestionData != null) {
                      scoreValue = widget.parentQuestionData!['fullscore'];
                    }
                    final int maxScore = (scoreValue)?.toInt() ?? 10;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI 채점 결과: ${result.score}점 / $maxScore점',
                          style: TextStyle(
                            color:
                                result.isCorrect ? Colors.green : Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '입력한 답안: ${userSubmittedAnswersForDisplay?.first ?? ''}',
                        ),
                        const SizedBox(height: 4),
                        Text('채점 근거: ${result.explanation}'),
                      ],
                    );
                  },
                ),
              ] else ...[
                // --- 기존 정답/오답 표시 (단답형 등) ---
                Text(
                  currentSubmissionStatus == true ? '정답입니다! 👍' : '오답입니다. 👎',
                  style: TextStyle(
                    color:
                        currentSubmissionStatus == true
                            ? Colors.green
                            : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                for (int i = 0; i < correctAnswers.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0, top: 2.0),
                    child: Text(
                      "(${i + 1}) 입력: ${userSubmittedAnswersForDisplay != null && i < userSubmittedAnswersForDisplay.length ? userSubmittedAnswersForDisplay[i] : '미입력'} / 정답: ${correctAnswers[i]}",
                    ),
                  ),
              ],
            ],
          ] else if (correctAnswers.isNotEmpty && actualQuestionType != "발문")
            Padding(
              padding: EdgeInsets.only(
                top: 4.0,
                left: (widget.showQuestionText ? 0 : 8.0),
              ),
              child: Text(
                '정답: ${correctAnswers.join(" || ")}',
                style: const TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          else if (actualQuestionType != "발문" &&
              correctAnswers.isEmpty &&
              widget.showQuestionText)
            const Padding(
              padding: EdgeInsets.only(top: 4.0),
              child: Text(
                "텍스트 정답이 제공되지 않는 유형입니다.",
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  fontSize: 13,
                  color: Colors.grey,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
