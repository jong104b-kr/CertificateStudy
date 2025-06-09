import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'changepw.dart';
import 'appbar.dart';
import 'ui_utils.dart';
import 'UserDataProvider.dart';
import 'main.dart';

class ModifyAccountPage extends StatefulWidget {
  const ModifyAccountPage({super.key, required this.title});

  final String title;

  @override
  State<ModifyAccountPage> createState() => _ModifyAccountPageState();
}

class _ModifyAccountPageState extends State<ModifyAccountPage> {
  late UserDataProvider userDataProvider;
  late UserDataProviderUtility utility;
  final _id = TextEditingController();
  final _pw = TextEditingController();
  final _email = TextEditingController();
  final _newEmail = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    userDataProvider = Provider.of<UserDataProvider>(context, listen: false);
    utility = UserDataProviderUtility();
  }

  void _changeEmail() async {
    final userDataProvider = Provider.of<UserDataProvider>(context, listen: false);
    final String id = _id.text.trim();
    final String pw = _pw.text.trim();
    final String email = _email.text.trim();
    final String newEmail = _newEmail.text.trim();

    if (id.isEmpty || pw.isEmpty || email.isEmpty || newEmail.isEmpty) {
      showSnackBarMessage(context, '모든 필드를 입력해주세요.');
      return; // 유효성 검사 실패 시 함수 종료
    }
    // 여기까지 통과하면 최소한 필드가 비어있지는 않음

    // 기존의 비즈니스 로직 유효성 검사는 UserDataProviderUtility 내부에서 계속 수행됩니다.
    final ValidationResult result = await utility.validateAndChangeEmail( // 반환 타입이 ValidationResult
      id: id,
      pw: pw,
      email: email,
      newEmail: newEmail,
      userDataProvider: userDataProvider,
    );

    if (!result.isSuccess) {
      showSnackBarMessage(context, result.message);
      return;
    }

    showSnackBarMessage(context, '새 E메일 주소로 확인 링크를 보냈습니다. 링크를 클릭하여 E메일 변경을 완료해주세요.');

    await userDataProvider.logoutUser();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => MainPage(title: widget.title), // 로그인 페이지로 이동
      ),
      (Route<dynamic> route) => false,
    );

    _id.clear();
    _pw.clear();
    _email.clear();
    _newEmail.clear();
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
            controller: _pw,
            obscureText: true,
            decoration: const InputDecoration(labelText: '비밀번호'),
          ),
          TextField(
            controller: _email,
            decoration: const InputDecoration(labelText: '기존의 E-mail'),
          ),
          TextField(
            controller: _newEmail,
            decoration: const InputDecoration(labelText: '변경할 E-mail'),
          ),
          ElevatedButton(
            onPressed: () => _changeEmail(),
            child: Text('E메일 주소 변경'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChangePWPage(title: widget.title),
                ),
              );
            },
            child: Text('비밀번호 재설정 페이지로'),
          ),
        ],
      ),
    );
  }
}