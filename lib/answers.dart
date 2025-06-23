import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import 'appbar.dart';

/// incorrectNotes 컬렉션의 문서를 Dart 객체로 변환하는 모델 클래스
class IncorrectNoteItem {
  final String id;
  final DateTime savedAt;
  final String sourceExamId;
  final String originalQuestionNo;
  final Map<String, dynamic> fullQuestionData;

  IncorrectNoteItem({
    required this.id,
    required this.savedAt,
    required this.sourceExamId,
    required this.originalQuestionNo,
    required this.fullQuestionData,
  });

  factory IncorrectNoteItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return IncorrectNoteItem(
      id: doc.id,
      savedAt: (data['savedAt'] as Timestamp).toDate(),
      sourceExamId: data['sourceExamId'] ?? '출처 없음',
      originalQuestionNo: data['originalQuestionNo'] ?? '번호 없음',
      fullQuestionData: data['fullQuestionData'] ?? {},
    );
  }
}

class AnswersPage extends StatefulWidget {
  final String title;
  const AnswersPage({super.key, required this.title});

  @override
  State<AnswersPage> createState() => _AnswersPageState();
}

class _AnswersPageState extends State<AnswersPage> {
  List<IncorrectNoteItem> _notes = [];
  bool _isLoading = true;
  String _errorMessage = '';

  final Map<String, bool> _isExpanded = {};

  @override
  void initState() {
    super.initState();
    _fetchIncorrectNotes();
  }

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
          .collection('incorrectNotes')
          .orderBy('savedAt', descending: true)
          .get();

      if (mounted) {
        final notes = snapshot.docs
            .map((doc) => IncorrectNoteItem.fromFirestore(doc))
            .toList();

        setState(() {
          _notes = notes;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "오답노트 데이터를 불러오는 중 오류가 발생했습니다: $e";
        });
      }
    }
  }

  /// 이 함수는 변경 없이 그대로 사용합니다.
  List<Widget> _buildQuestionAndAnswerWidgetsRecursive(Map<String, dynamic> questionNode, double leftIndent) {
    final List<Widget> widgets = [];
    final type = questionNode['type'] as String?;
    final questionText = questionNode['question'] as String? ?? '';
    final questionNo = questionNode['no'] as String? ?? '';
    final answer = questionNode['answer'];

    String displayNo = questionNo;
    if (questionNo.contains('_')) {
      displayNo = questionNo.split('_').last;
    }

    widgets.add(
        Padding(
          padding: EdgeInsets.only(left: leftIndent, top: 8.0, bottom: 4.0),
          child: Text(
            '$displayNo. $questionText',
            style: TextStyle(
              fontSize: 15,
              color: Colors.black87,
              fontWeight: leftIndent == 0 ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        )
    );

    if (type != '발문' && answer != null) {
      String displayableAnswer = (answer is List) ? answer.join(' || ') : answer.toString();
      widgets.add(
          Padding(
            padding: EdgeInsets.only(left: leftIndent + 16.0, bottom: 8.0),
            child: Text(
              '정답: $displayableAnswer',
              style: const TextStyle(fontSize: 14.5, color: Colors.blue, fontWeight: FontWeight.bold),
            ),
          )
      );
    }

    if (questionNode.containsKey('sub_questions') && questionNode['sub_questions'] is Map) {
      final subQuestions = questionNode['sub_questions'] as Map<String, dynamic>;
      final sortedKeys = subQuestions.keys.toList()..sort((a,b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
      for (var key in sortedKeys) {
        if(subQuestions[key] is Map<String, dynamic>) {
          widgets.addAll(_buildQuestionAndAnswerWidgetsRecursive(subQuestions[key], leftIndent + 8.0));
        }
      }
    }

    if (questionNode.containsKey('sub_sub_questions') && questionNode['sub_sub_questions'] is Map) {
      final subSubQuestions = questionNode['sub_sub_questions'] as Map<String, dynamic>;
      final sortedKeys = subSubQuestions.keys.toList()..sort((a,b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
      for (var key in sortedKeys) {
        if(subSubQuestions[key] is Map<String, dynamic>) {
          widgets.addAll(_buildQuestionAndAnswerWidgetsRecursive(subSubQuestions[key], leftIndent + 16.0));
        }
      }
    }

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CSAppBar(title: widget.title),
      body: _buildBody(),
    );
  }

  // --- [수정된 함수] ---
  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage.isNotEmpty) return Center(child: Text(_errorMessage, style: const TextStyle(color: Colors.red)));
    if (_notes.isEmpty) return const Center(child: Text("오답노트에 저장된 문제가 없습니다."));

    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: _notes.length,
      itemBuilder: (context, index) {
        final note = _notes[index];
        final questionData = note.fullQuestionData;
        final bool isExpanded = _isExpanded[note.id] ?? false;

        final sourceText = note.sourceExamId;
        final originalNo = note.originalQuestionNo;
        final formattedDate = DateFormat('yyyy년 MM월 dd일 HH:mm').format(note.savedAt.toLocal());
        final previewText = (questionData['question'] as String? ?? '문제 내용 없음').split('\n').first;

        final List<Widget> childrenWidgets = [];
        if (isExpanded) {
          final subQuestions = questionData['sub_questions'];

          if (subQuestions is Map<String, dynamic> && subQuestions.isNotEmpty) {
            final sortedKeys = subQuestions.keys.toList()..sort((a,b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
            for (var key in sortedKeys) {
              if (subQuestions[key] is Map<String, dynamic>) {
                childrenWidgets.addAll(_buildQuestionAndAnswerWidgetsRecursive(subQuestions[key], 0));
              }
            }
          }
          else {
            final type = questionData['type'] as String?;
            final answer = questionData['answer'];
            if (type != '발문' && answer != null) {
              String displayableAnswer = (answer is List) ? answer.join(' || ') : answer.toString();
              childrenWidgets.add(
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      '정답: $displayableAnswer',
                      style: const TextStyle(fontSize: 14.5, color: Colors.blue, fontWeight: FontWeight.bold),
                    ),
                  )
              );
            }
          }
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12.0),
          elevation: 2,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => setState(() => _isExpanded[note.id] = !isExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. leading: 아이콘
                      const Padding(
                        padding: EdgeInsets.only(top: 4.0, right: 16.0),
                        child: Icon(Icons.description_outlined, color: Colors.blueGrey),
                      ),
                      // 2. title & subtitle
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('문제 (원본: $sourceText ${originalNo}번)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 4),
                            Text(previewText, style: const TextStyle(fontSize: 15.0, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 5),
                            Text("저장 일시: $formattedDate", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          ],
                        ),
                      ),
                      // 3. trailing: 펼침/접힘 아이콘
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
                      ),
                    ],
                  ),

                  // --- 펼쳤을 때만 보이는 영역 ---
                  if (isExpanded && childrenWidgets.isNotEmpty) ...[
                    const Divider(height: 24.0, thickness: 1.0),
                    // 디테일한 문제+정답 내용은 패딩을 주어 구분
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: childrenWidgets,
                      ),
                    ),
                  ]
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}