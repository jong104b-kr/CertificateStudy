import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // 날짜 포맷팅을 위해 import

import 'studydatadownloader.dart'; // 방금 만든 모델 import
import 'appbar.dart'; // 기존에 사용하시던 AppBar

class AnswersPage extends StatefulWidget {
  final String title;
  const AnswersPage({super.key, required this.title});

  @override
  State<AnswersPage> createState() => _AnswersPageState();
}

class _AnswersPageState extends State<AnswersPage> {
  List<QuestionAttempt> _attempts = [];
  bool _isLoading = true;
  String _errorMessage = '';

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

        setState(() {
          _attempts = attempts;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CSAppBar(title: "내가 푼 문제 목록"),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage.isNotEmpty) {
      return Center(child: Text(_errorMessage, style: const TextStyle(color: Colors.red)));
    }

    if (_attempts.isEmpty) {
      return const Center(child: Text("아직 푼 문제가 없습니다."));
    }

    // 데이터가 성공적으로 로드된 경우 ListView를 표시
    return ListView.builder(
      itemCount: _attempts.length,
      itemBuilder: (context, index) {
        final attempt = _attempts[index];
        final formattedDate = DateFormat('yyyy년 MM월 dd일 HH:mm').format(attempt.solvedAt);

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. 문제 출처 및 날짜
                Text(
                  "${attempt.sourceExamId} (원본 ${attempt.originalQuestionNo}번)",
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Text(
                  formattedDate,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),

                // 2. 문제 내용
                Text(
                  attempt.questionText,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 12),

                // 3. 정답/오답 여부 및 답안 비교
                Row(
                  children: [
                    Icon(
                      attempt.isCorrect ? Icons.check_circle : Icons.cancel,
                      color: attempt.isCorrect ? Colors.green : Colors.red,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("내 답안: ${attempt.userAnswer}", style: const TextStyle(fontSize: 14)),
                          Text("실제 정답: ${attempt.correctAnswer}", style: const TextStyle(fontSize: 14, color: Colors.blue)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}