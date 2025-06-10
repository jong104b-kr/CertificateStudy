import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // 문제 풀이 시도 기록을 저장하는 함수
static Future<void> saveQuestionAttempt({
    required Map<String, dynamic> questionData,
    required String userAnswer,
    required bool isCorrect,
  }) async {
    // 현재 로그인한 사용자를 가져옵니다.
    final User? currentUser = _auth.currentUser;
    if (currentUser == null) {
      print("사용자가 로그인하지 않았습니다. 풀이 기록을 저장할 수 없습니다.");
      return; // 로그인하지 않은 경우 함수 종료
    }

    // 데이터베이스에 저장할 맵(Map) 데이터 생성
    final attemptData = {
      'userId': currentUser.uid,
      'solvedAt': FieldValue.serverTimestamp(), // 서버 시간 기준 현재 시각
      'isCorrect': isCorrect,
      'userAnswer': userAnswer,

      // 문제 출처 정보
      'sourceExamId': questionData['sourceExamId'] ?? '출처 정보 없음',
      'originalQuestionNo': questionData['no'] ?? '원본 번호 없음',

      // 문제 원본 정보 (복습 시 문제 내용을 다시 불러올 필요 없도록 저장)
      'questionText': questionData['question'] ?? '질문 내용 없음',
      'correctAnswer': questionData['answer'] ?? '정답 정보 없음',
      'questionType': questionData['type'] ?? '타입 정보 없음',

      // 나중에 상세 복습 기능을 위해 전체 문제 데이터를 저장할 수도 있습니다.
      // 'fullQuestionData': questionData,
    };

    try {
      // users -> 현재사용자ID -> solvedQuestions 컬렉션에 새로운 문서로 기록 추가
      await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('solvedQuestions')
          .add(attemptData); // add()를 사용하면 고유한 문서 ID가 자동으로 생성됩니다.

      print("풀이 기록이 성공적으로 저장되었습니다.");
    } catch (e) {
      print("풀이 기록 저장 중 오류 발생: $e");
    }
  }
}