import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'appbar.dart';
import 'ui_utils.dart';
import 'UserDataProvider.dart';
import 'main.dart';

class ChangePWPage extends StatefulWidget {
  const ChangePWPage({super.key, required this.title});

  final String title;

  @override
  State<ChangePWPage> createState() => _ChangePWPageState();
}

class _ChangePWPageState extends State<ChangePWPage> {
  late UserDataProvider userDataProvider;
  late UserDataProviderUtility utility;
  final _id = TextEditingController();
  final _email = TextEditingController();

  @override
  void initState() {
    super.initState();
    userDataProvider = Provider.of<UserDataProvider>(context, listen: false);
    utility = UserDataProviderUtility();
  }

  void _changePW() async {
    final String id = _id.text.trim();
    final String email = _email.text.trim();

    // ID 또는 이메일이 비어있는 경우 먼저 검사
    if (id.isEmpty || email.isEmpty) {
      showSnackBarMessage(context, 'ID와 E메일을 모두 입력해주세요.');
      return;
    }

    final ValidationResult result = await utility.validateAndChangePW(
      id: id,
      email: email,
      userDataProvider: userDataProvider,
    );

    if (!result.isSuccess) {
      showSnackBarMessage(context, result.message);
      return;
    }

    showSnackBarMessage(context, result.message); // 성공 메시지를 SnackBar로 표시

    await userDataProvider.logoutUser();
    // 비밀번호 재설정 이메일 전송 후에는 사용자에게 로그인 페이지로 돌아가도록 안내
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => MainPage(title: widget.title)),
          (Route<dynamic> route) => false,
    );

    _id.clear(); // ID 필드 초기화
    _email.clear(); // E메일 필드 초기화
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CSAppBar(title: widget.title),
      body: Column(
        children: [
          TextField(
            controller: _id,
            decoration: const InputDecoration(labelText: 'ID'),
          ),
          TextField(
            controller: _email,
            decoration: const InputDecoration(labelText: 'E-mail'),
          ),
          ElevatedButton(
            onPressed: () => _changePW(),
            child: Text('비밀번호 변경'),
          ),
        ],
      ),
    );
  }
}