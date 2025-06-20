import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // 날짜 포맷팅을 위해 pubspec.yaml에 intl 추가 필요
import 'appbar.dart'; // 기존에 사용하시던 AppBar
import 'retryexam.dart'; // 2단계에서 만들 파일

class RematchPage extends StatefulWidget {
  final String title;
  const RematchPage({super.key, required this.title});

  @override
  State<RematchPage> createState() => _RematchPageState();
}

class _RematchPageState extends State<RematchPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<QuerySnapshot<Map<String, dynamic>>>? _resultsStream;

  @override
  void initState() {
    super.initState();
    final User? currentUser = _auth.currentUser;
    if (currentUser != null) {
      _resultsStream = _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('examResults')
          .orderBy('solvedAt', descending: true) // 최신순으로 정렬
          .snapshots();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CSAppBar(title: widget.title),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _resultsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('저장된 시험 결과가 없습니다.'));
          }
          if (snapshot.hasError) {
            return const Center(child: Text('결과를 불러오는 중 오류가 발생했습니다.'));
          }

          final results = snapshot.data!.docs;

          return ListView.builder(
            itemCount: results.length,
            itemBuilder: (context, index) {
              final resultData = results[index].data();
              final String examtitle = resultData['examTitle'] ?? '제목 없음';
              final int score = resultData['totalScore'] ?? 0;
              final Timestamp solvedAt = resultData['solvedAt'] ?? Timestamp.now();
              final formattedDate = DateFormat('yyyy년 MM월 dd일 HH:mm').format(solvedAt.toDate());

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  title: Text(examtitle, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('$formattedDate\n점수: $score점'),
                  isThreeLine: true,
                  trailing: ElevatedButton(
                    child: const Text('다시 풀기'),
                    // 3단계에서 이 부분을 완성합니다.
                    onPressed: () {
                      // 1. 선택한 결과 문서에서 'attempts' 리스트를 가져옵니다.
                      final List<dynamic> attempts = resultData['attempts'] ?? [];

                      // 2. 각 attempt에서 문제 원본 데이터('fullQuestionData')만 추출하여
                      final List<Map<String, dynamic>> questionsToRetry = attempts
                          .map((attempt) => Map<String, dynamic>.from(attempt['fullQuestionData']))
                          .toList();

                      // 3. 만약 문제가 없다면 사용자에게 알립니다.
                      if (questionsToRetry.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('다시 풀 문제가 없습니다.')),
                        );
                        return;
                      }

                      // 4. Navigator.push를 사용하여 ExamSessionPage로 이동하면서,
                      //    시험 제목과 방금 만든 문제 리스트를 파라미터로 전달합니다.
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ExamSessionPage(
                            title: widget.title,
                            examtitle: examtitle,
                            initialQuestions: questionsToRetry,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}