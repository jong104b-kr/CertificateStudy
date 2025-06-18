import 'package:flutter/material.dart';
import 'questions_common.dart';
import 'openaigraderservice.dart';

/// 문제 목록을 표시하는 공통 ListView 위젯
class QuestionListView extends StatelessWidget {
  /// 표시할 질문 목록
  final List<Map<String, dynamic>> questions;

  /// Mixin으로부터 전달받는 콜백 함수 및 상태
  final List<TextEditingController> Function(String, int) getControllers;
  final void Function(Map<String, dynamic>) onCheckAnswer;
  final void Function(String) onTryAgain;
  final Map<String, bool?> submissionStatus;
  final Map<String, List<String>> userSubmittedAnswers;

  /// AI 채점 결과를 받을 변수 선언
  final Map<String, GradingResult>? aiGradingResults;

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
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      itemCount: questions.length,
      itemBuilder: (context, index) {
        final mainQuestionData = questions[index];
        final uniqueId = mainQuestionData['uniqueDisplayId'] as String;
        final type = mainQuestionData['type'] as String? ?? '';

        final subQuestionsField = mainQuestionData['sub_questions'];
        final bool hasSubQuestions = subQuestionsField is Map<String, dynamic> && subQuestionsField.isNotEmpty;

        final List<Widget> expansionTileChildren = [
          const Divider(height: 1, thickness: 1),
          QuestionInteractiveDisplay(
            questionData: mainQuestionData,
            leftIndent: 16.0,
            displayNoWithPrefix: "풀이",
            questionTypeToDisplay: hasSubQuestions
                ? ""
                : ((type == "발문" || type.isEmpty) ? "" : " ($type)"),
            showQuestionText: false,
            getControllers: getControllers,
            onCheckAnswer: onCheckAnswer,
            onTryAgain: onTryAgain,
            submissionStatus: submissionStatus[uniqueId],
            userSubmittedAnswers: userSubmittedAnswers[uniqueId],
            aiGradingResults: aiGradingResults, //
          ),
        ];

        // 하위 문제 (sub_questions) 처리
        if (hasSubQuestions) {
          List<String> sortedSubKeys = subQuestionsField.keys.toList()
            ..sort((a, b) => (int.tryParse(a) ?? 99999).compareTo(int.tryParse(b) ?? 99999));
          int subOrderCounter = 0;
          for (String subKey in sortedSubKeys) {
            final subQuestionValue = subQuestionsField[subKey];
            if (subQuestionValue is Map<String, dynamic>) {
              subOrderCounter++;
              final String subType = subQuestionValue['type'] as String? ?? '';
              expansionTileChildren.add(QuestionInteractiveDisplay(
                questionData: subQuestionValue,
                leftIndent: 24.0,
                displayNoWithPrefix: "($subOrderCounter)",
                questionTypeToDisplay: (subType == "발문" || subType.isEmpty) ? "" : " ($subType)",
                showQuestionText: true,
                getControllers: getControllers,
                onCheckAnswer: onCheckAnswer,
                onTryAgain: onTryAgain,
                submissionStatus: submissionStatus[subQuestionValue['uniqueDisplayId']],
                userSubmittedAnswers: userSubmittedAnswers[subQuestionValue['uniqueDisplayId']],
                aiGradingResults: aiGradingResults,
              ));

              // NEW: 하위-하위 문제 (sub_sub_questions) 처리 로직 추가
              final subSubQuestionsField = subQuestionValue['sub_sub_questions'];
              if (subSubQuestionsField is Map<String, dynamic> && subSubQuestionsField.isNotEmpty) {
                List<String> sortedSubSubKeys = subSubQuestionsField.keys.toList()
                  ..sort((a,b) => (int.tryParse(a) ?? 99999).compareTo(int.tryParse(b) ?? 99999));
                int subSubOrderCounter = 0;
                for (String subSubKey in sortedSubSubKeys) {
                  final subSubQValue = subSubQuestionsField[subSubKey];
                  if (subSubQValue is Map<String, dynamic>) {
                    subSubOrderCounter++;
                    final String subSubType = subSubQValue['type'] as String? ?? '';
                    expansionTileChildren.add(QuestionInteractiveDisplay(
                      questionData: subSubQValue,
                      leftIndent: 32.0, // 들여쓰기 추가
                      displayNoWithPrefix: " - ($subSubOrderCounter)",
                      questionTypeToDisplay: (subSubType == "발문" || subSubType.isEmpty) ? "" : " ($subSubType)",
                      showQuestionText: true,
                      getControllers: getControllers,
                      onCheckAnswer: onCheckAnswer,
                      onTryAgain: onTryAgain,
                      submissionStatus: submissionStatus[subSubQValue['uniqueDisplayId']],
                      userSubmittedAnswers: userSubmittedAnswers[subSubQValue['uniqueDisplayId']],
                      aiGradingResults: aiGradingResults, // [수정] 3. 하위-하위 문제에 전달
                    ));
                  }
                }
              }
            }
          }
        }

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
            children: expansionTileChildren,
          ),
        );
      },
    );
  }
}