import 'package:flutter/material.dart';

// 스낵바 메시지를 표시하는 헬퍼 함수
void showSnackBarMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}