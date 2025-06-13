import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:collection/collection.dart';
import 'studydataupdater.dart';
import 'openaigraderservice.dart';

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

  // [추가] AI 채점기와 결과 저장용 Map
  final OpenAiGraderService _graderService = OpenAiGraderService();
  final Map<String, GradingResult> aiGradingResults = {};

  // 각 State 클래스에서 자신의 질문 목록을 반환하도록 강제
  List<Map<String, dynamic>> get questions;
  // 각 State 클래스에서 자신의 질문 목록을 비우는 로직을 구현하도록 강제
  void clearQuestionsList();

  @override
  void dispose() {
    controllers.values.forEach((controllerList) {
      for (var controller in controllerList) {
        controller.dispose();
      }
    });
    super.dispose();
  }

  List<TextEditingController> getControllersForQuestion(String uniqueDisplayId, int answerCount) {
    return controllers.putIfAbsent(uniqueDisplayId, () {
      final previousAnswers = userSubmittedAnswers[uniqueDisplayId] ?? [];
      return List.generate(answerCount, (index) {
        return TextEditingController(text: index < previousAnswers.length ? previousAnswers[index] : null);
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
      clearQuestionsList();
    });
  }

  Map<String, dynamic> cleanNewlinesRecursive(Map<String, dynamic> questionData) {
    Map<String, dynamic> cleanedData = {};
    cleanedData['uniqueDisplayId'] = questionData['uniqueDisplayId'] ?? uuid.v4();
    questionData.forEach((key, value) {
      if (key == 'uniqueDisplayId') return;
      if (value is String) {
        cleanedData[key] = value.replaceAll('\\n', '\n');
      } else if (value is List) { // REVISED: 리스트도 그대로 통과시키도록 처리
        cleanedData[key] = value;
      } else if ((key == 'sub_questions' || key == 'sub_sub_questions') && value is Map) {
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
  Future<void> checkAnswer(Map<String, dynamic> questionData) async {
    final String uniqueDisplayId = questionData['uniqueDisplayId'] as String;
    final answerControllers = controllers[uniqueDisplayId] ?? [];
    if (answerControllers.isEmpty || answerControllers.first.text.isNullOrEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("답을 입력해주세요.")));
      return;
    }

    // 채점 시작 전, UI에 로딩 상태를 알리고 싶다면 여기서 상태 변경 가능
    // setState(() { submissionStatus[uniqueDisplayId] = null; }); // 예시: 로딩 상태

    bool overallCorrect;
    List<String> userAnswers = answerControllers.map((c) => c.text).toList();

    // [분기 시작] 문제 유형에 따라 채점 방식 변경
    if (questionData['type'] == '서술형') {
      // --- AI 채점 로직 (서술형 문제) ---
      final userAnswer = userAnswers.first; // 서술형은 첫 번째 답변만 사용
      final modelAnswer = questionData['answer'] as String? ?? '';
      final questionText = questionData['question'] as String? ?? '';
      final fullScore = (questionData['fullscore'] as num?)?.toInt() ?? 10;

      final result = await _graderService.gradeAnswer(
        question: questionText,
        modelAnswer: modelAnswer,
        userAnswer: userAnswer,
        fullScore: fullScore,
      );

      overallCorrect = result.isCorrect;

      if (mounted) {
        setState(() {
          aiGradingResults[uniqueDisplayId] = result; // AI 채점 결과 저장
        });
      }

      FirestoreService.saveQuestionAttempt(
        questionData: questionData,
        userAnswer: userAnswer,
        isCorrect: overallCorrect,
        score: result.score, // AI가 채점한 점수 저장
        feedback: result.explanation, // AI의 채점 근거 저장
      );

    } else {
      // --- 기존 채점 로직 (단답형, 계산형 등) ---
      final int requiredAnswerCount = questionData['isShufflable'] as int? ?? 1;
      final dynamic answerValue = questionData['answer'];

      List<String> correctAnswers = [];
      if (answerValue is List) {
        correctAnswers = answerValue.map((e) => e.toString().trim()).toList();
      } else if (answerValue is String) {
        correctAnswers = [answerValue.trim()];
      }

      if (correctAnswers.isEmpty) return;

      final correctSet = correctAnswers.map((e) => e.toLowerCase()).toSet();
      final userSet = userAnswers.map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toSet();

      if (requiredAnswerCount < correctSet.length) {
        overallCorrect = (userSet.length == requiredAnswerCount) && userSet.every((e) => correctSet.contains(e));
      } else {
        overallCorrect = const SetEquality().equals(correctSet, userSet);
      }

      FirestoreService.saveQuestionAttempt(
        questionData: questionData,
        userAnswer: userAnswers.join(' || '),
        isCorrect: overallCorrect,
        // 기존 로직에서는 fullscore를 isCorrect일 때만 부여
        score: overallCorrect ? (questionData['fullscore'] as num?)?.toInt() ?? 0 : 0,
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
        controllers[uniqueDisplayId]?.forEach((controller) => controller.clear());
        submissionStatus.remove(uniqueDisplayId);
        userSubmittedAnswers.remove(uniqueDisplayId);
        aiGradingResults.remove(uniqueDisplayId);
      });
    }
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
  final void Function(Map<String, dynamic>) onCheckAnswer;
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
    required this.onTryAgain,
    required this.submissionStatus,
    required this.userSubmittedAnswers,
    this.aiGradingResults,
  });

  @override
  State<QuestionInteractiveDisplay> createState() => _QuestionInteractiveDisplayState();
}

class _QuestionInteractiveDisplayState extends State<QuestionInteractiveDisplay> {
  @override
  Widget build(BuildContext context) {
    final String? uniqueDisplayId = widget.questionData['uniqueDisplayId'] as String?;
    final String actualQuestionType = widget.questionData['type'] as String? ?? '타입 정보 없음';

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
      questionTextContent = widget.questionData['question'] as String? ?? '질문 내용 없음';
    }

    bool isAnswerable = (actualQuestionType == "단답형" || actualQuestionType == "계산" || actualQuestionType == "서술형") &&
        uniqueDisplayId != null &&
        answerCount > 0 &&
        correctAnswers.isNotEmpty;

    List<TextEditingController>? controllers = isAnswerable ? widget.getControllers(uniqueDisplayId!, answerCount) : null;
    bool? currentSubmissionStatus = isAnswerable ? widget.submissionStatus : null;
    List<String>? userSubmittedAnswersForDisplay = isAnswerable ? widget.userSubmittedAnswers : null;

    return Padding(
      padding: EdgeInsets.only(left: widget.leftIndent, top: 8.0, bottom: 8.0, right: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showQuestionText)
            Text(
              '${widget.displayNoWithPrefix} ${questionTextContent}${widget.questionTypeToDisplay}',
              textAlign: TextAlign.start,
              style: TextStyle(
                fontSize: 15,
                fontWeight: widget.leftIndent == 0 && widget.showQuestionText ? FontWeight.w600 : (widget.leftIndent < 24.0 ? FontWeight.w500 : FontWeight.normal),
              ),
            )
          else if (widget.displayNoWithPrefix.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: (isAnswerable ? 4.0 : 0)),
              child: Text(
                widget.displayNoWithPrefix,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.blueGrey[700]),
              ),
            ),

          if (widget.showQuestionText && isAnswerable) const SizedBox(height: 8.0),

          if (isAnswerable && controllers != null && correctAnswers.isNotEmpty) ...[
            if (!widget.showQuestionText) const SizedBox(height: 4),
            Column(
              children: List.generate(answerCount, (index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    children: [
                      if (answerCount > 1) Text("(${index + 1}) ", style: const TextStyle(fontWeight: FontWeight.bold)),
                      Expanded(
                        child: TextField(
                          controller: controllers[index],
                          enabled: currentSubmissionStatus == null,
                          decoration: InputDecoration(
                            hintText: '정답 ${index + 1} 입력...',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          ),
                          onChanged: (text) { if (currentSubmissionStatus == null) setState(() {}); },
                          onSubmitted: (value) { if (currentSubmissionStatus == null) widget.onCheckAnswer(widget.questionData); },
                          maxLines: actualQuestionType == "서술형" ? null : 1,
                          keyboardType: actualQuestionType == "서술형" ? TextInputType.multiline : TextInputType.text,
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
                  onPressed: currentSubmissionStatus == null ? () { FocusScope.of(context).unfocus(); widget.onCheckAnswer(widget.questionData); } : null,
                  child: Text(currentSubmissionStatus == null ? '정답 확인' : '채점 완료'),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), textStyle: const TextStyle(fontSize: 13)),
                ),
                if (currentSubmissionStatus != null && uniqueDisplayId != null) ...[
                  const SizedBox(width: 8),
                  TextButton(onPressed: () => widget.onTryAgain(uniqueDisplayId), child: const Text('다시 풀기')),
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
                      if (result == null) return const Text('AI 채점 결과를 불러오는 중...');

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AI 채점 결과: ${result.score}점 / ${widget.questionData['fullscore'] ?? 10}점',
                            style: TextStyle(
                                color: result.isCorrect ? Colors.green : Colors.orange,
                                fontWeight: FontWeight.bold
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text('입력한 답안: ${userSubmittedAnswersForDisplay?.first ?? ''}'),
                          const SizedBox(height: 4),
                          Text('채점 근거: ${result.explanation}'),
                        ],
                      );
                    }
                )
              ] else ...[
                // --- 기존 정답/오답 표시 (단답형 등) ---
                Text(
                  currentSubmissionStatus == true ? '정답입니다! 👍' : '오답입니다. 👎',
                  style: TextStyle(color: currentSubmissionStatus == true ? Colors.green : Colors.red, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                for (int i=0; i < correctAnswers.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0, top: 2.0),
                    child: Text(
                        "(${i + 1}) 입력: ${userSubmittedAnswersForDisplay != null && i < userSubmittedAnswersForDisplay.length ? userSubmittedAnswersForDisplay[i] : '미입력'} / 정답: ${correctAnswers[i]}"
                    ),
                  ),
              ],
            ],
          ]
          else if (correctAnswers.isNotEmpty && actualQuestionType != "발문")
            Padding(
              padding: EdgeInsets.only(top: 4.0, left: (widget.showQuestionText ? 0 : 8.0)),
              child: Text('정답: ${correctAnswers.join(" || ")}', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w500)),
            )
          else if (actualQuestionType != "발문" && correctAnswers.isEmpty && widget.showQuestionText)
              const Padding(
                padding: EdgeInsets.only(top: 4.0),
                child: Text("텍스트 정답이 제공되지 않는 유형입니다.", style: TextStyle(fontStyle: FontStyle.italic, fontSize: 13, color: Colors.grey)),
              )
        ],
      ),
    );
  }
}