import 'package:flutter/material.dart';

import 'answers.dart';
import 'incorrectnote.dart';
import 'rematch.dart';
import 'appbar.dart';

class SolvedQuestionPage extends StatelessWidget {
  final String title; // 이전 페이지 제목을 받을 변수

  const SolvedQuestionPage({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CSAppBar(title: title),
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              ElevatedButton(
                onPressed: () {
                  // AnswersPage로 이동하면서 title 값을 전달
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AnswersPage(title: title),
                    ),
                  );
                },
                child: Text('정답체크'),
              ),
              ElevatedButton(
                onPressed: () {
                  // IncorrectNotePage로 이동하면서 title 값을 전달
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => IncorrectNotePage(title: title),
                    ),
                  );
                },
                child: Text('오답노트'),
              ),
            ],
          ),
          ElevatedButton(
            onPressed: () {
              // RematchPage로 이동하면서 title 값을 전달
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => RematchPage(title: title),
                ),
              );
            },
            child: Text('다시 풀어보기'),
          ),
        ]
      ),
    );
  }
}