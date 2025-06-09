import 'package:flutter/material.dart';

import 'publishedexam.dart';
import 'qbank.dart';
import 'appbar.dart';

class NewExamPage extends StatefulWidget {
  final String title; // 이전 페이지 제목을 받을 변수

  const NewExamPage({super.key, required this.title});

  @override
  State<NewExamPage> createState() => _NewExamPageState();
}

class _NewExamPageState extends State<NewExamPage> {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CSAppBar(title: widget.title),
      body: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          ElevatedButton(
            onPressed: () {
              // PublishedExam으로 이동하면서 title 값을 전달
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PublishedExamPage(title: widget.title),
                ),
              );
            },
            child: Text('기출문제'),
          ),
          ElevatedButton(
            onPressed: () {
              // QnABBSPage로 이동하면서 title 값을 전달
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => QuestionBankPage(title: widget.title),
                ),
              );
            },
            child: Text('문제은행'),
          ),
        ]
      ),
    );
  }
}