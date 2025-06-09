import 'package:flutter/material.dart';

import 'appbar.dart';

class QnABBSPage extends StatelessWidget {
  final String title; // 이전 페이지 제목을 받을 변수

  const QnABBSPage({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CSAppBar(title: title),
      body: const Center(
        child: Text(
          '질문게시판이 들어올 자리입니다.',
          style: TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}