import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static Future<void> saveQuestionAttempt({
    required String sourceExamId,
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
      'sourceExamId': sourceExamId,
      'originalQuestionNo': questionData['no'] ?? '원본 번호 없음',
      'questionText': questionData['question'] ?? '질문 내용 없음',
      'correctAnswer': (answer is List)
          ? answer
          : (answer?.toString() ?? '정답 정보 없음'),
      'questionType': questionData['type'] ?? '타입 정보 없음',
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

  /// 시험 한 세트의 전체 결과를 저장합니다.
  static Future<void> saveExamResult({
    required String sourceExamId,
    required String examTitle,
    required int timeTaken,
    required int totalScore,
    required List<Map<String, dynamic>> attemptsData, // 개별 문제 풀이 결과 리스트
  }) async {
    final User? currentUser = _auth.currentUser;
    if (currentUser == null) {
      print("사용자가 로그인하지 않았습니다. 시험 결과를 저장할 수 없습니다.");
      return;
    }

    // 1. 저장할 ExamResult 데이터 모델을 구성합니다.
    final examResultDoc = {
      'userId': currentUser.uid,
      'sourceExamId': sourceExamId,
      'examTitle': examTitle,
      'solvedAt': FieldValue.serverTimestamp(), // 서버 시간 기준으로 저장
      'timeTaken': timeTaken,
      'totalScore': totalScore,
      'totalQuestions': attemptsData.length,
      'correctCount': attemptsData.where((a) => a['isCorrect'] == true).length,
      'attempts': attemptsData, // 문제 풀이 기록 리스트를 그대로 포함
    };

    try {
      // 2. 'users/{userId}/examResults' 컬렉션에 새로운 문서를 추가합니다.
      await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('examResults')
          .add(examResultDoc);

      print("시험 결과 세트가 성공적으로 저장되었습니다.");

      // (선택 사항) 개별 문제 기록도 기존처럼 저장하고 싶다면 여기서 반복문 실행
      // for (var attempt in attemptsData) {
      //   saveQuestionAttempt(
      //     questionData: attempt['fullQuestionData'],
      //     userAnswer: attempt['userAnswer'],
      //     isCorrect: attempt['isCorrect'],
      //   );
      // }

    } catch (e) {
      print("시험 결과 저장 중 오류 발생: $e");
    }
  }
}