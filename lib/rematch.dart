import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // 날짜 포맷팅을 위해 import

import 'studydatadownloader.dart';
import 'questions_common.dart';
import 'question_list.dart';
import 'appbar.dart';

class RematchPage extends StatefulWidget {
  final String title;
  const RematchPage({super.key, required this.title});

  @override
  State<RematchPage> createState() => _RematchPageState();
}

// REVISED: QuestionStateMixin을 추가하여 문제 풀이 기능 활성화
class _RematchPageState extends State<RematchPage> with QuestionStateMixin<RematchPage> {
  List<QuestionAttempt> _attempts = []; // 원본 데이터

  // REVISED: Mixin이 사용할 실제 문제 목록 (다시 풀기용)
  List<Map<String, dynamic>> _rematchQuestions = [];

  bool _isLoading = true;
  String _errorMessage = '';

  // REVISED: Mixin의 abstract 멤버 구현
  @override
  List<Map<String, dynamic>> get questions => _rematchQuestions;

  @override
  void clearQuestionsList() {
    // 이 페이지에서는 목록을 비우는 기능은 필요 없으므로 비워둡니다.
    // 또는 새로고침 로직을 추가할 수 있습니다.
  }

  @override
  void initState() {
    super.initState();
    _fetchSolvedQuestions();
  }

  Future<void> _fetchSolvedQuestions() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "로그인이 필요합니다.";
        });
      }
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('solvedQuestions')
          .orderBy('solvedAt', descending: true) // 최신순으로 정렬
          .get();

      if (mounted) {
        final attempts = snapshot.docs
            .map((doc) => QuestionAttempt.fromFirestore(doc))
            .toList();

        // REVISED: 불러온 데이터에서 다시 풀 문제 목록을 구성합니다.
        final questionsToRematch = attempts.map((attempt) {
          // cleanNewlinesRecursive를 다시 적용하여 UI에서 줄바꿈이 올바르게 표시되도록 합니다.
          return cleanNewlinesRecursive(attempt.fullQuestionData);
        }).toList();

        setState(() {
          _attempts = attempts;
          _rematchQuestions = questionsToRematch;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "데이터를 불러오는 중 오류가 발생했습니다: $e";
        });
      }
    }
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage.isNotEmpty) return Center(child: Text(_errorMessage, style: const TextStyle(color: Colors.red)));
    if (_rematchQuestions.isEmpty) return const Center(child: Text("다시 풀 문제가 없습니다."));

    // REVISED: 공통 위젯 호출 부분을 역할에 맞게 재구성
    return QuestionListView(
      questions: _rematchQuestions,
      getControllers: getControllersForQuestion,
      onCheckAnswer: (data) => checkAnswer(data),
      onTryAgain: tryAgain,
      submissionStatus: submissionStatus,
      userSubmittedAnswers: userSubmittedAnswers,
      aiGradingResults: aiGradingResults,

      // 1. leadingBuilder: 이제 자신의 역할인 아이콘 생성만 담당
      leadingBuilder: (context, questionData, index) {
        final originalAttempt = _attempts[index];
        return Icon(
          originalAttempt.isCorrect ? Icons.check_circle : Icons.cancel,
          color: originalAttempt.isCorrect ? Colors.green : Colors.red,
        );
      },

      // 2. titleBuilder: 아이콘 로직이 빠지고 제목 텍스트만 생성하여 간결해짐
      titleBuilder: (context, questionData, index) {
        final originalNo = questionData['no'] as String?;
        return Text('문제 ${index + 1} (원본 ${originalNo ?? "N/A"}번)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16));
      },

      // 3. subtitleBuilder: 기존과 동일
      subtitleBuilder: (context, questionData, index) {
        final originalAttempt = _attempts[index];
        final questionText = questionData['question'] as String? ?? '';
        final formattedDate = DateFormat('yyyy년 MM월 dd일 HH:mm').format(originalAttempt.solvedAt.toLocal());
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(questionText, style: const TextStyle(fontSize: 15.0, color: Colors.black87, height: 1.4)),
            const SizedBox(height: 5),
            Text("최근 풀이: $formattedDate", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CSAppBar(title: widget.title),
      body: _buildBody(),
    );
  }
}