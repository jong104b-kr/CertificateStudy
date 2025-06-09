import 'package:flutter/material.dart';

import 'appbar.dart';

class AnswersPage extends StatelessWidget {
  final String title; // 이전 페이지 제목을 받을 변수

  const AnswersPage({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CSAppBar(title: title),
      body: const Center(
        child: Text(
          '정답체크 화면입니다.',
          style: TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}