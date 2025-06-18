import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static Future<void> saveQuestionAttempt({
    required Map<String, dynamic> questionData,
    required String userAnswer,
    required bool isCorrect,
    int? score,
    String? feedback,
  }) async {
    final User? currentUser = _auth.currentUser;
    if (currentUser == null) {
      print("사용자가 로그인하지 않았습니다. 풀이 기록을 저장할 수 없습니다.");
      return;
    }

    final dynamic answer = questionData['answer'];
    final attemptData = {
      'userId': currentUser.uid,
      'solvedAt': FieldValue.serverTimestamp(),
      'isCorrect': isCorrect,
      'userAnswer': userAnswer,
      'sourceExamId': questionData['sourceExamId'] ?? '출처 정보 없음',
      'originalQuestionNo': questionData['no'] ?? '원본 번호 없음',
      'questionText': questionData['question'] ?? '질문 내용 없음',
      'correctAnswer': (answer is List)
          ? answer
          : (answer?.toString() ?? '정답 정보 없음'),
      'questionType': questionData['type'] ?? '타입 정보 없음',

      // REVISED: 다시 풀기 기능을 위해 문제의 전체 데이터를 저장합니다.
      'fullQuestionData': questionData,
      'score': score,
      'feedback': feedback,
    };

    try {
      await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('solvedQuestions')
          .add(attemptData);

      print("풀이 기록이 성공적으로 저장되었습니다.");
    } catch (e) {
      print("풀이 기록 저장 중 오류 발생: $e");
    }
  }
}