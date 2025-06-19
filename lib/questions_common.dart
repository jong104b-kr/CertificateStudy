import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:collection/collection.dart';
import 'studydataupdater.dart';
import 'openaigraderservice.dart';
import 'dart:async';

/// 문자열이 null이거나 비어있는지 확인하는 확장 함수
extension StringNullOrEmptyExtension on String? {
  bool get isNullOrEmpty => this == null || this!.trim().isEmpty;
}

/// 두 페이지의 State 클래스에서 공통으로 사용하는 상태와 로직을 담은 Mixin
mixin QuestionStateMixin<T extends StatefulWidget> on State<T> {
  final Uuid uuid = const Uuid();
  final Map<String, List<TextEditingController>> controllers = {};
  final Map<String, bool?> submissionStatus = {};
  final Map<String, List<String>> userSubmittedAnswers = {};
  final Stopwatch _stopwatch = Stopwatch();
  bool _isResultSaved = false;

  String? _currentExamId; // 현재 시험의 출처 ID를 저장할 변수
  void setCurrentExamId(String examId) {
    _currentExamId = examId;
  }

  // [추가] AI 채점기와 결과 저장용 Map
  final OpenAiGraderService _graderService = OpenAiGraderService();
  final Map<String, GradingResult> aiGradingResults = {};

  // 각 State 클래스에서 자신의 질문 목록을 반환하도록 강제
  List<Map<String, dynamic>> get questions;

  // 각 State 클래스에서 자신의 질문 목록을 비우는 로직을 구현하도록 강제
  void clearQuestionsList();

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
      aiGradingResults.clear(); // [추가] AI 채점 결과도 초기화
      _stopwatch.reset(); // [추가] 스톱워치 초기화
      _isResultSaved = false; // [추가] 저장 상태 초기화
      clearQuestionsList();
    });
  }

  // [추가] 시험 결과 저장을 위한 데이터 생성 헬퍼 메서드
  List<Map<String, dynamic>> _buildAttemptsDataForSaving() {
    List<Map<String, dynamic>> attemptsData = [];
    // 모든 문제를 순회하며 풀이 기록을 생성합니다.
    // 여기서는 최상위 문제(parent)만 순회하지만, 필요 시 모든 leaf node를 순회하도록 수정할 수 있습니다.
    for (var questionData in questions) {
      final uniqueId = questionData['uniqueDisplayId'] as String;
      final userAnswerList = userSubmittedAnswers[uniqueId];
      final gradingResult = aiGradingResults[uniqueId];

      // 개별 문제의 정답 여부를 확인합니다.
      bool isCorrect = submissionStatus[uniqueId] ?? false;

      attemptsData.add({
        'originalQuestionNo': questionData['no']?.toString() ?? 'N/A',
        'isCorrect': isCorrect,
        'userAnswer': userAnswerList?.join(' || ') ?? '미제출',
        'fullQuestionData': questionData,
        'feedback': gradingResult?.explanation,
        'score':
            isCorrect ? (questionData['fullscore'] as num?)?.toInt() ?? 0 : 0,
      });
    }
    return attemptsData;
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
        // REVISED: 리스트도 그대로 통과시키도록 처리
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

  /// REVISED: 순서와 상관없이, 중복 입력을 허용하지 않는 Set 기반 정답 확인
  /// REVISED: 'N개 중 M개만 맞히면 정답' 시나리오를 처리하는 채점 로직
  Future<void> checkAnswer(
    Map<String, dynamic> questionData,
    Map<String, dynamic>? parentData,
  ) async {
    final String uniqueDisplayId = questionData['uniqueDisplayId'] as String;
    final answerControllers = controllers[uniqueDisplayId] ?? [];
    if (answerControllers.isEmpty ||
        answerControllers.every((c) => c.text.isNullOrEmpty)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("답을 입력해주세요.")));
      return;
    }

    // 채점 시작 전, UI에 로딩 상태를 알리고 싶다면 여기서 상태 변경 가능
    setState(() {
      submissionStatus[uniqueDisplayId] = null;
    }); // 예시: 로딩 상태

    bool overallCorrect;
    List<String> userAnswers = answerControllers.map((c) => c.text).toList();

    // 분기 1: 서술형 문제인 경우 AI 채점
    if (questionData['type'] == '서술형') {
      final userAnswer = userAnswers.first;
      final modelAnswer = questionData['answer'] as String? ?? '';
      final questionText = questionData['question'] as String? ?? '';
      num? scoreValue = questionData['fullscore'] ?? parentData?['fullscore'];
      final fullScore = (scoreValue)?.toInt() ?? 10;

      final result = await _graderService.gradeAnswer(
        question: questionText,
        modelAnswer: modelAnswer,
        userAnswer: userAnswer,
        fullScore: fullScore,
      );
      overallCorrect = result.isCorrect;

      if (mounted) setState(() => aiGradingResults[uniqueDisplayId] = result);

      FirestoreService.saveQuestionAttempt(
        questionData: questionData,
        userAnswer: userAnswer,
        isCorrect: overallCorrect,
        sourceExamId: _currentExamId!,
        score: result.score,
        feedback: result.explanation,
      );
    }
    // 분기 2: 그 외 모든 문제 (단답형, 계산형, 다중답변)
    else {
      final int requiredCount = questionData['isShufflable'] as int? ?? 1;
      final dynamic correctAnswerValue = questionData['answer'];

      // Firestore에서 가져온 정답(List 또는 String)을 Set으로 변환
      final Set<String> correctAnswersSet;
      if (correctAnswerValue is List) {
        correctAnswersSet =
            correctAnswerValue
                .map((e) => e.toString().trim().toLowerCase())
                .toSet();
      } else if (correctAnswerValue is String) {
        correctAnswersSet = {correctAnswerValue.trim().toLowerCase()};
      } else {
        correctAnswersSet = {}; // 정답이 없는 경우
      }

      // 사용자가 입력한 답안을 Set으로 변환 (중복 제거 및 공백 처리)
      final Set<String> userAnswersSet =
          userAnswers
              .map((e) => e.trim().toLowerCase())
              .where((e) => e.isNotEmpty)
              .toSet();

      // --- 채점 로직 ---
      // 1. "N개를 모두 맞춰야 하는 경우" (예: 정답 4개, 요구 4개)
      if (requiredCount == correctAnswersSet.length) {
        overallCorrect = const SetEquality().equals(
          correctAnswersSet,
          userAnswersSet,
        );
      }
      // 2. "M개 중 N개만 맞추면 되는 경우" (예: 정답 5개, 요구 4개)
      else if (requiredCount < correctAnswersSet.length) {
        overallCorrect =
            userAnswersSet.length == requiredCount &&
            userAnswersSet.every(
              (answer) => correctAnswersSet.contains(answer),
            );
      }
      // 3. 그 외의 경우 (기본: 단일 정답 비교)
      else {
        overallCorrect =
            userAnswersSet.length == 1 &&
            correctAnswersSet.contains(userAnswersSet.first);
      }

      FirestoreService.saveQuestionAttempt(
        questionData: questionData,
        userAnswer: userAnswers.join(' || '),
        isCorrect: overallCorrect,
        sourceExamId: _currentExamId!,
        score:
            overallCorrect
                ? (questionData['fullscore'] as num?)?.toInt() ?? 0
                : 0,
      );
    }

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
        controllers[uniqueDisplayId]?.forEach(
          (controller) => controller.clear(),
        );
        submissionStatus.remove(uniqueDisplayId);
        userSubmittedAnswers.remove(uniqueDisplayId);
        aiGradingResults.remove(uniqueDisplayId);
      });
    }
  }

  /// 특정 문제 데이터 아래의 모든 최하위 문제(채점 대상)들을 재귀적으로 찾아 리스트로 반환합니다.
  List<Map<String, dynamic>> getAllLeafNodes(
    Map<String, dynamic> questionData,
  ) {
    final List<Map<String, dynamic>> leaves = [];

    final bool hasSubQuestions =
        questionData.containsKey('sub_questions') &&
        questionData['sub_questions'] is Map &&
        (questionData['sub_questions'] as Map).isNotEmpty;
    final bool hasSubSubQuestions =
        questionData.containsKey('sub_sub_questions') &&
        questionData['sub_sub_questions'] is Map &&
        (questionData['sub_sub_questions'] as Map).isNotEmpty;

    if (!hasSubQuestions && !hasSubSubQuestions) {
      if (questionData.containsKey('fullscore')) {
        leaves.add(questionData);
      }
    } else {
      if (hasSubQuestions) {
        final subMap = questionData['sub_questions'] as Map<String, dynamic>;
        for (final subQuestion
            in subMap.values.whereType<Map<String, dynamic>>()) {
          leaves.addAll(getAllLeafNodes(subQuestion));
        }
      }
      if (hasSubSubQuestions) {
        final subSubMap =
            questionData['sub_sub_questions'] as Map<String, dynamic>;
        for (final subSubQuestion
            in subSubMap.values.whereType<Map<String, dynamic>>()) {
          leaves.addAll(getAllLeafNodes(subSubQuestion));
        }
      }
    }
    return leaves;
  }

  /// 사용자가 획득한 점수를 계산합니다.
  int calculateUserScore() {
    int totalScore = 0;
    for (final questionData in questions) {
      // Mixin의 'questions' getter 사용
      final bool hasChildren =
          (questionData.containsKey('sub_questions') &&
              (questionData['sub_questions'] as Map).isNotEmpty) ||
          (questionData.containsKey('sub_sub_questions') &&
              (questionData['sub_sub_questions'] as Map).isNotEmpty);

      if (hasChildren) {
        final List<Map<String, dynamic>> leafChildren = getAllLeafNodes(
          questionData,
        );
        if (leafChildren.isEmpty) continue;

        bool allChildrenCorrect = true;
        int partialScore = 0;

        for (final leaf in leafChildren) {
          final uniqueId = leaf['uniqueDisplayId'] as String?;
          if (uniqueId != null && submissionStatus[uniqueId] == true) {
            // Mixin의 'submissionStatus' 사용
            final score = leaf['fullscore'];
            partialScore +=
                (score is int ? score : int.tryParse(score.toString()) ?? 0);
          } else {
            allChildrenCorrect = false;
          }
        }

        if (allChildrenCorrect) {
          final parentScore = questionData['fullscore'];
          totalScore +=
              (parentScore is int
                  ? parentScore
                  : int.tryParse(parentScore.toString()) ?? 0);
        } else {
          totalScore += partialScore;
        }
      } else {
        final uniqueId = questionData['uniqueDisplayId'] as String?;
        if (uniqueId != null &&
            submissionStatus[uniqueId] == true &&
            questionData.containsKey('fullscore')) {
          final score = questionData['fullscore'];
          totalScore +=
              (score is int ? score : int.tryParse(score.toString()) ?? 0);
        }
      }
    }
    return totalScore;
  }

  /// 시험의 총점을 계산합니다.
  int calculateMaxScore() {
    int maxScore = 0;
    for (final questionData in questions) {
      // Mixin의 'questions' getter 사용
      if (questionData.containsKey('fullscore')) {
        final score = questionData['fullscore'];
        maxScore +=
            (score is int ? score : int.tryParse(score.toString()) ?? 0);
      }
    }
    return maxScore;
  }

  /// 채점 결과를 다이얼로그로 표시합니다.
  Future<void> showGradingResult(
    BuildContext context, {
    required String examId, // 시험을 식별할 고유 ID
    required String examTitle, // 저장될 시험 제목
  }) async {
    stopTimer(); // 채점 시 타이머 중지

    final int userScore = calculateUserScore();
    final int maxScore = calculateMaxScore();

    showDialog(
      context: context,
      barrierDismissible: false, // 다이얼로그 바깥을 눌러도 닫히지 않도록 설정
      builder: (BuildContext dialogContext) {
        // 다이얼로그 내부 상태(예: '저장 완료' 텍스트) 변경을 위해 StatefulBuilder 사용
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('💯 채점 결과'),
              content: SingleChildScrollView(
                child: ListBody(
                  children: <Widget>[
                    Text(
                      '총점: $maxScore점\n획득 점수: $userScore점',
                      style: const TextStyle(fontSize: 16, height: 1.5),
                    ),
                    const SizedBox(height: 8),
                    Text('총 소요 시간: ${_stopwatch.elapsed.inSeconds}초'),
                  ],
                ),
              ),
              actions: <Widget>[
                // '결과 저장하기' 버튼: 아직 저장되지 않았을 때만 활성화
                if (!_isResultSaved)
                  TextButton(
                    child: const Text('결과 저장하기'),
                    onPressed: () async {
                      // 1. 저장할 데이터 생성
                      final attemptsData = _buildAttemptsDataForSaving();

                      // 2. Firestore 서비스 호출
                      await FirestoreService.saveExamResult(
                        sourceExamId: examId,
                        examTitle: examTitle,
                        timeTaken: _stopwatch.elapsed.inSeconds,
                        totalScore: userScore,
                        // 전체 점수가 아닌 획득 점수를 저장
                        attemptsData: attemptsData,
                      );

                      // 3. UI 업데이트 및 피드백
                      setDialogState(() {
                        _isResultSaved = true;
                      });

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('결과가 성공적으로 저장되었습니다.')),
                        );
                      }
                    },
                  ),

                // 저장된 후에는 '저장 완료' 텍스트 버튼으로 변경
                if (_isResultSaved)
                  TextButton(
                    onPressed: null, // 비활성화
                    child: const Text('저장 완료'),
                  ),

                // '닫기' 버튼
                TextButton(
                  child: const Text('닫기'),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            );
          },
        );
      },
    );
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
        answerCount > 0 &&
        correctAnswers.isNotEmpty;

    List<TextEditingController>? controllers =
        isAnswerable
            ? widget.getControllers(uniqueDisplayId!, answerCount)
            : null;
    bool? currentSubmissionStatus =
        isAnswerable ? widget.submissionStatus : null;
    List<String>? userSubmittedAnswersForDisplay =
        isAnswerable ? widget.userSubmittedAnswers : null;

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
