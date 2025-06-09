import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'main.dart';
import 'UserDataProvider.dart';
import 'appbar.dart';
import 'ui_utils.dart';

class DeleteAccountPage extends StatefulWidget {
  const DeleteAccountPage({super.key, required this.title});
  final String title;

  @override
  State<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends State<DeleteAccountPage> {
  late UserDataProvider userDataProvider;
  late UserDataProviderUtility utility;
  final _id = TextEditingController();
  final _email = TextEditingController();
  final _pw = TextEditingController();

  @override
  void initState() {
    super.initState();
    userDataProvider = Provider.of<UserDataProvider>(context, listen: false);
    utility = UserDataProviderUtility();
  }

  void _deleteAccount(BuildContext context) async {
    final id = _id.text.trim();
    final email = _email.text.trim();
    final pw = _pw.text.trim();

    if (id.isEmpty || email.isEmpty || pw.isEmpty) {
      showSnackBarMessage(context, '모든 정보를 입력해주세요.');
      return; // 유효성 검사 실패 시 함수 종료
    }

    final ValidationResult result = await utility.validateAndDeleteUser(
      id: id,
      email: email,
      pw: pw,
      userDataProvider: userDataProvider,
    );

    if (!result.isSuccess) {
      showSnackBarMessage(context, result.message);
      return;
    }

    showSnackBarMessage(context, result.message); // 성공 메시지를 SnackBar로 표시

    _id.clear(); // ID 필드 초기화
    _email.clear(); // E메일 필드 초기화
    _pw.clear(); // 비밀번호 필드 초기화

    // 탈퇴 이메일 전송 후에는 사용자에게 로그인 페이지로 돌아가도록 안내
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => MainPage(title: widget.title)),
          (Route<dynamic> route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CSAppBar(title: widget.title),
      body: Column(
        children: [
          TextField(controller: _id, decoration: const InputDecoration(labelText: 'ID')),
          TextField(
            controller: _pw,
            obscureText: true,
            decoration: const InputDecoration(labelText: '비밀번호'),
          ),
          TextField(controller: _email, decoration: const InputDecoration(labelText: 'E-mail')),
          ElevatedButton(
            onPressed: () => _deleteAccount(context),
            child: const Text('회원 탈퇴'),
          ),
        ],
      ),
    );
  }
}
