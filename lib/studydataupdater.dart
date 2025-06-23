import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

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

    } catch (e) {
      print("시험 결과 저장 중 오류 발생: $e");
    }
  }

  /// 문제 세트(최상위 문제와 모든 하위 문제)를 오답노트에 저장합니다.
  static Future<void> saveToIncorrectNote({
    required String sourceExamId,
    required Map<String, dynamic> fullQuestionData, // 계층 구조 전체 데이터
  }) async {
    final User? currentUser = _auth.currentUser;
    if (currentUser == null) {
      print("사용자가 로그인하지 않았습니다. 오답노트에 저장할 수 없습니다.");
      return;
    }

    // 오답노트에 저장할 데이터 구조
    final noteData = {
      'userId': currentUser.uid,
      'savedAt': FieldValue.serverTimestamp(), // 저장 시점
      'sourceExamId': sourceExamId,
      'originalQuestionNo': fullQuestionData['no'] ?? '원본 번호 없음',
      'questionText': fullQuestionData['question'] ?? '질문 내용 없음',
      'fullQuestionData': fullQuestionData, // 전체 문제 데이터 저장
    };

    try {
      // 'users/{userId}/incorrectNotes' 컬렉션에 문서를 추가합니다.
      // 문서 ID를 중복 저장을 방지하기 위해 sourceExamId와 question 'no'를 조합하여 사용
      final docId = '${sourceExamId}_${fullQuestionData['no']}';
      await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('incorrectNotes')
          .doc(docId) // 중복 등록 방지를 위해 docId 지정
          .set(noteData); // 동일 ID가 있으면 덮어씁니다.

      print("오답노트에 성공적으로 저장되었습니다. (ID: $docId)");
    } catch (e) {
      print("오답노트 저장 중 오류 발생: $e");
      // 사용자에게 피드백을 줄 수 있도록 예외를 다시 던질 수 있습니다.
      throw Exception("오답노트 저장에 실패했습니다.");
    }
  }
}