import 'package:flutter/material.dart';
import 'appbar.dart';
import 'questions_common.dart';
import 'question_list.dart';
import 'studydatadownloader.dart';

class ExamSessionPage extends StatefulWidget {
  final String title;
  final String examtitle;
  final List<Map<String, dynamic>> initialQuestions; // 외부에서 받을 문제 리스트

  const ExamSessionPage({
    super.key,
    required this.title,
    required this.examtitle,
    required this.initialQuestions,
  });

  @override
  State<ExamSessionPage> createState() => _ExamSessionPageState();
}

class _ExamSessionPageState extends State<ExamSessionPage> with QuestionStateMixin<ExamSessionPage> {
  // Mixin이 사용할 질문 리스트
  List<Map<String, dynamic>> _questions = [];
  late final String _sessionExamId;

  // Mixin의 abstract 멤버 구현
  @override
  List<Map<String, dynamic>> get questions => _questions;

  @override
  void clearQuestionsList() {
    _questions = [];
  }

  @override
  void initState() {
    super.initState();
    final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    _sessionExamId = 'retry-${widget.examtitle.replaceAll(' ', '-')}-$timestamp';
    setCurrentExamId(_sessionExamId);
    _initializeQuestions();
  }

  void _initializeQuestions() {
    // 상태를 초기화하고,
    clearAllAttemptStatesAndQuestions();

    // 전달받은 문제 리스트를 state에 할당하고,
    _questions = widget.initialQuestions.map((q) => cleanNewlinesRecursive(q)).toList();

    // 타이머를 시작합니다.
    startTimer();

    // UI를 갱신합니다.
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CSAppBar(title: widget.title),
      body: _questions.isEmpty
          ? const Center(child: Text('표시할 문제가 없습니다.'))
          : QuestionListView( // 기존에 사용하던 공통 위젯 재활용
        questions: _questions,
        getControllers: getControllersForQuestion,
        onCheckAnswer: (questionData, parentData) => checkAnswer(questionData, parentData),
        onTryAgain: tryAgain,
        submissionStatus: submissionStatus,
        userSubmittedAnswers: userSubmittedAnswers,
        aiGradingResults: aiGradingResults,
        // titleBuilder, subtitleBuilder 등은 필요에 맞게 커스텀
        titleBuilder: (context, questionData, index) {
          final sourceText = questionData['sourceExamId'] as String? ?? '출처 없음';
          final originalNo = questionData['no'] as String?;
          return Text('$sourceText ${originalNo ?? "N/A"}번',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5));
        },
        subtitleBuilder: (context, questionData, index) {
          // 'questionData' 맵에서 'question' 키의 값을 가져옵니다.
          final questionText = questionData['question'] as String? ?? '';

          // 문제 텍스트가 있을 경우에만 화면에 표시합니다.
          return questionText.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: 5.0),
                  child: Text(
                    questionText,
                    style: const TextStyle(fontSize: 15.0, color: Colors.black87, height: 1.4),
                  ),
                )
              : null; // 텍스트가 없으면 아무것도 표시하지 않음
        },
      ),
      floatingActionButton: _questions.isNotEmpty
          ? FloatingActionButton.extended(
        onPressed: () {
          // final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
          showGradingResult(
            context,
            // 다시 푼 시험의 ID는 원본 제목에 'retry'와 타임스탬프를 붙여 구분
            examId: _sessionExamId,
            examTitle: '${widget.examtitle} (다시 풀기)',
          );
        },
        label: const Text('채점하기'),
        icon: const Icon(Icons.check_circle_outline),
      )
          : null,
    );
  }
}
