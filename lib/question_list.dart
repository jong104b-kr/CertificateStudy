import 'package:flutter/material.dart';
import 'openaigraderservice.dart';

/// 문제 목록을 표시하는 공통 ListView 위젯
class QuestionListView extends StatelessWidget {
  /// 표시할 질문 목록
  final List<Map<String, dynamic>> questions;

  /// Mixin으로부터 전달받는 콜백 함수 및 상태
  final List<TextEditingController> Function(String, int) getControllers;
  final void Function(Map<String, dynamic>, Map<String, dynamic>?) onCheckAnswer;
  final void Function(String) onTryAgain;
  final Map<String, bool?> submissionStatus;
  final Map<String, List<String>> userSubmittedAnswers;

  /// AI 채점 결과를 받을 변수 선언
  final Map<String, GradingResult>? aiGradingResults;

  /// 오답노트 저장을 위한 콜백과 상태 추가
  final Future<void> Function(Map<String, dynamic>) onSaveToIncorrectNote;
  final Map<String, bool> incorrectNoteSaveStatus;

  /// 각 페이지의 특성에 맞게 UI를 커스터마이징하기 위한 빌더 함수들
  final Widget Function(BuildContext context, Map<String, dynamic> questionData, int index) titleBuilder;
  final Widget? Function(BuildContext context, Map<String, dynamic> questionData, int index)? subtitleBuilder;
  final Widget? Function(BuildContext context, Map<String, dynamic> questionData, int index)? leadingBuilder;

  const QuestionListView({
    super.key,
    required this.questions,
    required this.getControllers,
    required this.onCheckAnswer,
    required this.onTryAgain,
    required this.submissionStatus,
    required this.userSubmittedAnswers,
    required this.titleBuilder,
    this.subtitleBuilder,
    this.leadingBuilder,
    this.aiGradingResults,
    required this.onSaveToIncorrectNote,
    required this.incorrectNoteSaveStatus,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      itemCount: questions.length,
      itemBuilder: (context, index) {
        final mainQuestionData = questions[index];
        final uniqueId = mainQuestionData['uniqueDisplayId'] as String;
        final questionNo = mainQuestionData['no'] as String? ?? '';
        final isSaved = incorrectNoteSaveStatus[questionNo] ?? false;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6.0),
          elevation: 1.5,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
          child: ExpansionTile(
            key: ValueKey(uniqueId),
            tilePadding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            childrenPadding: EdgeInsets.zero,
            leading: leadingBuilder?.call(context, mainQuestionData, index),
            title: titleBuilder(context, mainQuestionData, index),
            subtitle: subtitleBuilder?.call(context, mainQuestionData, index),
            initiallyExpanded: questions.length <= 5,
            // --- [수정] trailing 속성을 사용하여 오답노트 버튼 구현 ---
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 최상위 문제에만 오답노트 버튼 표시
                TextButton(
                  onPressed: isSaved ? null : () => onSaveToIncorrectNote(mainQuestionData),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: isSaved ? Colors.grey[200] : null,
                  ),
                  child: Row(
                    children: [
                      Icon(isSaved ? Icons.check_circle_outline : Icons.add_task_outlined, size: 16, color: isSaved ? Colors.green : Colors.blue),
                      const SizedBox(width: 4),
                      Text(isSaved ? '저장됨' : '오답노트', style: TextStyle(fontSize: 12, color: isSaved ? Colors.black54 : Colors.blue)),
                    ],
                  ),
                ),
                // 기존의 확장/축소 아이콘
                const Icon(Icons.expand_more),
              ],
            ),
            children: _buildExpansionChildren(context, mainQuestionData),
          ),
        );
      },
    );
  }

  // ExpansionTile의 children을 생성하는 헬퍼 함수
  List<Widget> _buildExpansionChildren(BuildContext context, Map<String, dynamic> parentQuestionData) {
    List<Widget> children = [
      const Divider(height: 1, thickness: 1),
      _buildInteractiveDisplayForNode(context, parentQuestionData, parentQuestionData, 16.0, "풀이", false)
    ];

    // 하위 문제 처리
    final dynamic subQuestions = parentQuestionData['sub_questions'];
    if (subQuestions is Map<String, dynamic> && subQuestions.isNotEmpty) {
      final sortedKeys = subQuestions.keys.toList()..sort((a,b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
      int subCounter = 0;
      for (var key in sortedKeys) {
        final subQData = subQuestions[key];
        if (subQData is Map<String, dynamic>) {
          subCounter++;
          children.add(_buildInteractiveDisplayForNode(context, subQData, parentQuestionData, 24.0, "($subCounter)", true));

          // 하위-하위 문제 처리
          final dynamic subSubQuestions = subQData['sub_sub_questions'];
          if (subSubQuestions is Map<String, dynamic> && subSubQuestions.isNotEmpty) {
            final sortedSubSubKeys = subSubQuestions.keys.toList()..sort((a,b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
            int subSubCounter = 0;
            for (var subSubKey in sortedSubSubKeys) {
              final subSubQData = subSubQuestions[subSubKey];
              if (subSubQData is Map<String, dynamic>) {
                subSubCounter++;
                children.add(_buildInteractiveDisplayForNode(context, subSubQData, parentQuestionData, 32.0, "- ($subSubCounter)", true));
              }
            }
          }
        }
      }
    }
    return children;
  }

  // 각 문제 노드에 대한 인터랙티브 UI를 생성하는 공통 함수
  Widget _buildInteractiveDisplayForNode(BuildContext context, Map<String, dynamic> questionData, Map<String, dynamic>? parentData, double indent, String prefix, bool showText) {
    final type = questionData['type'] as String? ?? '';
    final uniqueId = questionData['uniqueDisplayId'] as String;
    final scoreValue = questionData['fullscore'] ?? parentData?['fullscore'];
    final scoreString = scoreValue != null ? '${scoreValue}점' : '';
    final String typeAndScoreString;
    if (type.isEmpty) {
      typeAndScoreString = ""; // 타입이 없으면 아무것도 표시하지 않습니다.
    } else {
      typeAndScoreString = ' ($type - $scoreString)'; // 예: (서술형 - 4점)
    }

    return QuestionInteractiveDisplay(
      questionData: questionData,
      leftIndent: indent,
      displayNoWithPrefix: prefix,
      questionTypeToDisplay: typeAndScoreString,
      showQuestionText: showText,
      getControllers: getControllers,
      onCheckAnswer: onCheckAnswer,
      parentQuestionData: parentData,
      onTryAgain: onTryAgain,
      submissionStatus: submissionStatus[uniqueId],
      userSubmittedAnswers: userSubmittedAnswers[uniqueId],
      aiGradingResults: aiGradingResults,
    );
  }
}


// --- 🔽 주요 수정이 이루어진 위젯 🔽 ---

/// 단일 문제의 인터랙티브 UI (TextField, 정답확인 등)를 생성하는 공통 위젯
class QuestionInteractiveDisplay extends StatelessWidget {
  final Map<String, dynamic> questionData;
  final double leftIndent;
  final String displayNoWithPrefix;
  final String questionTypeToDisplay;
  final bool showQuestionText;

  final List<TextEditingController> Function(String, int) getControllers;
  final void Function(Map<String, dynamic>, Map<String, dynamic>?) onCheckAnswer;
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
    this.submissionStatus,
    this.userSubmittedAnswers,
    this.aiGradingResults,
  });

  @override
  Widget build(BuildContext context) {
    final String? uniqueDisplayId = questionData['uniqueDisplayId'] as String?;
    final String actualQuestionType = questionData['type'] as String? ?? '타입 정보 없음';

    final int answerCount = questionData['isShufflable'] as int? ?? 1;
    final dynamic answerValue = questionData['answer'];

    List<String> correctAnswers = [];
    if (answerValue != null) {
      if (answerValue is List) {
        correctAnswers = answerValue.map((e) => e.toString().trim()).toList();
      } else if (answerValue is String) {
        correctAnswers = [answerValue.trim()];
      }
    }

    String questionTextContent = showQuestionText ? (questionData['question'] as String? ?? '질문 없음') : '';
    bool isAnswerable = (actualQuestionType == "단답형" || actualQuestionType == "계산" || actualQuestionType == "서술형") && uniqueDisplayId != null;

    List<TextEditingController>? controllers = isAnswerable ? getControllers(uniqueDisplayId!, answerCount) : null;

    return Padding(
      padding: EdgeInsets.only(left: leftIndent, top: 8.0, bottom: 8.0, right: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 질문 텍스트 표시
          if (showQuestionText)
            Text('${displayNoWithPrefix} ${questionTextContent}${questionTypeToDisplay}', textAlign: TextAlign.start)
          else if (displayNoWithPrefix.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: (isAnswerable ? 4.0 : 0)),
              child: Text('${displayNoWithPrefix}${questionTypeToDisplay}', style: TextStyle(fontWeight: FontWeight.w500, color: Colors.blueGrey[700])),
            ),

          if (showQuestionText && isAnswerable) const SizedBox(height: 8.0),

          // 답변 가능 영역
          if (isAnswerable && controllers != null) ...[
            if (!showQuestionText) const SizedBox(height: 4),
            // 정답 입력 필드들
            Column(
              children: List.generate(answerCount, (index) =>
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: TextField(
                      controller: controllers[index],
                      enabled: submissionStatus == null,
                      decoration: InputDecoration(
                        hintText: answerCount > 1 ? '정답 ${index + 1} 입력...' : '정답 입력...',
                        border: const OutlineInputBorder(), isDense: true,
                      ),
                      onSubmitted: (value) { if (submissionStatus == null) onCheckAnswer(questionData, parentQuestionData); },
                    ),
                  )
              ),
            ),
            const SizedBox(height: 8),
            // 버튼 영역
            Row(
              children: [
                ElevatedButton(
                  onPressed: submissionStatus == null ? () { FocusScope.of(context).unfocus(); onCheckAnswer(questionData, parentQuestionData); } : null,
                  child: Text(submissionStatus == null ? '정답 확인' : '채점 완료'),
                ),
                if (submissionStatus != null)
                  TextButton(onPressed: () => onTryAgain(uniqueDisplayId!), child: const Text('다시 풀기')),
              ],
            ),
            // 채점 결과 표시 영역
            if (submissionStatus != null) ...[
              const SizedBox(height: 8),
              if (actualQuestionType == "서술형")
                _buildAiGradingResult(context, uniqueDisplayId!)
              else
                _buildStandardGradingResult(correctAnswers),
            ],
          ]
          // 답변 불가능하지만 정답이 있는 경우
          else if (correctAnswers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text('정답: ${correctAnswers.join(" || ")}', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w500)),
            )
        ],
      ),
    );
  }

  // AI 채점 결과 위젯
  Widget _buildAiGradingResult(BuildContext context, String uniqueId) {
    final result = aiGradingResults?[uniqueId];
    if (result == null) return const Text('AI 채점 결과를 불러오는 중...');

    num? scoreValue = questionData['fullscore'] ?? parentQuestionData?['fullscore'];
    final int maxScore = (scoreValue)?.toInt() ?? 10;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'AI 채점 결과: ${result.score}점 / $maxScore점',
          style: TextStyle(color: result.isCorrect ? Colors.green : Colors.orange, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text('입력한 답안: ${
            (userSubmittedAnswers?.asMap().entries.map((e) => "(${e.key + 1}) ${e.value}").join(' || ')) ?? ''
        }'),
        const SizedBox(height: 4),
        Text('채점 근거: ${result.explanation}'),
      ],
    );
  }

  // --- 🔽 [수정된 부분] 일반/다중 답변 결과 표시 위젯 🔽 ---
  Widget _buildStandardGradingResult(List<String> correctAnswers) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          submissionStatus == true ? '정답입니다! 👍' : '오답입니다. 👎',
          style: TextStyle(color: submissionStatus == true ? Colors.green : Colors.red, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        // 내 답안과 모범 답안을 한 번에 보여주어 비교하기 쉽게 함
        Text('내 답안: ${userSubmittedAnswers?.join(" || ") ?? '미입력'}'),
        Text('모범 답안: ${correctAnswers.join(" || ")}'),
      ],
    );
  }
}