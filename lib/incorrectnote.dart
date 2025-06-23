import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // 날짜 포맷팅을 위해 import

import 'questions_common.dart';
import 'question_list.dart';
import 'appbar.dart';

class IncorrectNoteItem {
  final String id; // Firestore 문서 ID
  final DateTime savedAt;
  final String sourceExamId;
  final String originalQuestionNo;
  final String questionText;
  final Map<String, dynamic> fullQuestionData;

  IncorrectNoteItem({
    required this.id,
    required this.savedAt,
    required this.sourceExamId,
    required this.originalQuestionNo,
    required this.questionText,
    required this.fullQuestionData,
  });

  factory IncorrectNoteItem.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return IncorrectNoteItem(
      id: doc.id,
      savedAt: (data['savedAt'] as Timestamp).toDate(),
      sourceExamId: data['sourceExamId'] ?? '출처 없음',
      originalQuestionNo: data['originalQuestionNo'] ?? '번호 없음',
      questionText: data['questionText'] ?? '문제 내용 없음',
      fullQuestionData: Map<String, dynamic>.from(data['fullQuestionData'] ?? {}),
    );
  }
}

class IncorrectNotePage extends StatefulWidget {
  final String title;
  const IncorrectNotePage({super.key, required this.title});

  @override
  State<IncorrectNotePage> createState() => _IncorrectNotePageState();
}

// REVISED: QuestionStateMixin을 추가하여 문제 풀이 기능 활성화
class _IncorrectNotePageState extends State<IncorrectNotePage> with QuestionStateMixin<IncorrectNotePage> {
  // [수정] 원본 데이터 타입을 새로 만든 모델로 변경
  List<IncorrectNoteItem> _incorrectNotes = [];
  // [수정] Mixin이 사용할 실제 문제 목록 (다시 풀기용)
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
    _fetchIncorrectNotes();
  }

  // [수정] Firestore에서 오답노트 데이터를 가져오는 함수
  Future<void> _fetchIncorrectNotes() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() { _isLoading = false; _errorMessage = "로그인이 필요합니다."; });
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('incorrectNotes') // 'incorrectNotes' 컬렉션에서 조회
          .orderBy('savedAt', descending: true) // 저장된 시간순으로 정렬
          .get();

      if (mounted) {
        final notes = snapshot.docs
            .map((doc) => IncorrectNoteItem.fromFirestore(doc))
            .toList();

        // 불러온 데이터에서 다시 풀 문제 목록(계층 구조)을 구성합니다.
        // cleanNewlinesRecursive를 적용하여 UI에서 줄바꿈이 올바르게 표시되도록 합니다.
        final questionsToRematch = notes.map((note) {
          // 오답노트 페이지에서는 시험 ID를 다시 설정해주는 것이 좋습니다.
          setCurrentExamId(note.sourceExamId);
          return cleanNewlinesRecursive(note.fullQuestionData);
        }).toList();

        setState(() {
          _incorrectNotes = notes;
          _rematchQuestions = questionsToRematch;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "오답노트를 불러오는 중 오류가 발생했습니다: $e";
        });
      }
    }
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage.isNotEmpty) return Center(child: Text(_errorMessage, style: const TextStyle(color: Colors.red)));
    if (_rematchQuestions.isEmpty) return const Center(child: Text("오답노트에 등록된 문제가 없습니다."));

    // 이제 QuestionListView는 전체 문제 구조를 받아 렌더링합니다.
    return QuestionListView(
      questions: _rematchQuestions,
      getControllers: getControllersForQuestion,
      // 오답노트 페이지에서는 '다시 풀기' 기능을 위해 checkAnswer, tryAgain 등을 그대로 전달합니다.
      onCheckAnswer: (questionData, parentData) => checkAnswer(questionData, parentData),
      onTryAgain: tryAgain,
      submissionStatus: submissionStatus,
      userSubmittedAnswers: userSubmittedAnswers,
      aiGradingResults: aiGradingResults,

      // [신규] 오답노트 저장 관련 콜백/상태 전달
      // 오답노트 페이지 자체에서는 '오답노트에 추가' 기능이 필요 없으므로 빈 함수와 false를 전달합니다.
      onSaveToIncorrectNote: (_) async {},
      incorrectNoteSaveStatus: const {}, // 빈 맵 전달

      // [수정] 각 항목의 제목, 부제목 등을 구성하는 빌더
      leadingBuilder: (context, questionData, index) {
        // 여기서는 isCorrect 정보가 없으므로 기본 아이콘을 표시
        return const Icon(Icons.description_outlined, color: Colors.blueGrey);
      },
      titleBuilder: (context, questionData, index) {
        final note = _incorrectNotes[index];
        final sourceText = note.sourceExamId;
        final originalNo = note.originalQuestionNo;
        return Text('문제 (원본: $sourceText ${originalNo}번)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16));
      },
      subtitleBuilder: (context, questionData, index) {
        final note = _incorrectNotes[index];
        final formattedDate = DateFormat('yyyy년 MM월 dd일 HH:mm').format(note.savedAt.toLocal());
        // 최상위 문제의 텍스트만 미리보기로 보여줍니다.
        final previewText = (questionData['question'] as String? ?? '문제 내용 없음').split('\n').first;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(previewText, style: const TextStyle(fontSize: 15.0, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 5),
            Text("저장 일시: $formattedDate", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
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