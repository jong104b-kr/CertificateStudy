import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'changepw.dart';
import 'appbar.dart';
import 'ui_utils.dart';
import 'UserDataProvider.dart';

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
    final String id = _id.text.trim();
    final String pw = _pw.text.trim();
    final String email = _email.text.trim();
    final String newEmail = _newEmail.text.trim();

    if (id.isEmpty || pw.isEmpty || email.isEmpty || newEmail.isEmpty) {
      showSnackBarMessage(context, '모든 필드를 입력해주세요.');
      return;
    }

    // UserDataProvider의 로직을 호출합니다.
    final ValidationResult result = await utility.validateAndChangeEmail(
      id: id,
      pw: pw,
      email: email,
      newEmail: newEmail,
      userDataProvider: userDataProvider,
    );

    if (!mounted) return;

    // UserDataProvider가 반환한 메시지를 그대로 SnackBar에 표시합니다.
    showSnackBarMessage(context, result.message);

    // ▼▼▼ 핵심: UI는 로그아웃을 직접 호출하지 않습니다! ▼▼▼
    // 성공 시, 단순히 이전 화면으로 돌아가 사용자가 로그인 상태를 유지하도록 합니다.
    if (result.isSuccess) {
      _id.clear();
      _pw.clear();
      _email.clear();
      _newEmail.clear();
      Navigator.of(context).pop(); // 이전 화면(회원정보창)으로 돌아가기
    }
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