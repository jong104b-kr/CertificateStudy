import 'package:cloud_firestore/cloud_firestore.dart';

class QuestionAttempt {
  final String userId;
  final DateTime solvedAt; // Firestore의 Timestamp를 DateTime으로 변환하여 사용
  final bool isCorrect;
  final String userAnswer;
  final String sourceExamId;
  final String originalQuestionNo;
  final String questionText;
  final String correctAnswer;
  final String questionType;

  QuestionAttempt({
    required this.userId,
    required this.solvedAt,
    required this.isCorrect,
    required this.userAnswer,
    required this.sourceExamId,
    required this.originalQuestionNo,
    required this.questionText,
    required this.correctAnswer,
    required this.questionType,
  });

  // Firestore DocumentSnapshot으로부터 ProblemAttempt 객체를 생성하는 factory 생성자
  factory QuestionAttempt.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    return QuestionAttempt(
      userId: data['userId'] ?? '',
      // Firestore의 Timestamp 타입은 toDate()를 통해 Dart의 DateTime으로 변환
      solvedAt: (data['solvedAt'] as Timestamp).toDate(),
      isCorrect: data['isCorrect'] ?? false,
      userAnswer: data['userAnswer'] ?? '답안 없음',
      sourceExamId: data['sourceExamId'] ?? '출처 없음',
      originalQuestionNo: data['originalQuestionNo'] ?? '번호 없음',
      questionText: data['questionText'] ?? '문제 내용 없음',
      correctAnswer: data['correctAnswer'] ?? '정답 정보 없음',
      questionType: data['questionType'] ?? '타입 없음',
    );
  }
}