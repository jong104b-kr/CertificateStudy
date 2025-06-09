import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'register.dart';
import 'home.dart';
import 'appbar.dart';
import 'UserDataProvider.dart';
import 'ui_utils.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // runApp() 호출 전에 위젯 바인딩 초기화

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final userDataProvider = UserDataProvider();

  runApp(
    ChangeNotifierProvider.value(
      value: userDataProvider,
      child: const CertificateStudy(),
    ),
  );
}

class CertificateStudy extends StatelessWidget {
  const CertificateStudy({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '서술형도 한다 - AiffelThon 과제',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MainPage(title: '서술형도 한다'),
      // 이 위치의 "서술형도 한다" 가 AppBar에 출력되는 문구입니다.
      // 다른 페이지의 AppBar에선 title이라는 변수명으로 호출됩니다.
    );
  }
}

class MainPage extends StatefulWidget {
  final String title;

  const MainPage({super.key, required this.title});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final id_input = TextEditingController();
  final pw_input = TextEditingController();

  void _processLogin(BuildContext context) async {
    String id = id_input.text.trim();
    String pw = pw_input.text.trim();

    final userDataProvider = Provider.of<UserDataProvider>(context, listen: false);
    final userDataProviderUtility = UserDataProviderUtility();

    // ID와 비밀번호 입력 필드 검사
    if (id.isEmpty || pw.isEmpty) {
      showSnackBarMessage(context, 'ID와 비밀번호를 모두 입력해주세요.');
      return;
    }

    // UserDataProviderUtility를 통해 ID 기반 로그인 유효성 검사 및 처리 시도
    final ValidationResult result = await userDataProviderUtility.validateAndLoginById(
      id: id,
      pw: pw,
      userDataProvider: userDataProvider,
    );

    print('I/flutter: [LoginProcess] 로그인 결과 isSuccess: ${result.isSuccess}, 메시지: ${result.message}');

    if (!result.isSuccess) {
      showSnackBarMessage(
          context, result.message); // ValidationResult에서 반환된 메시지 사용
      return;
    }

    showSnackBarMessage(context, result.message); // ValidationResult에서 반환된 실패 메시지 사용

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => HomePage(title: widget.title)), // 로그인 성공 후 이동할 메인 페이지
          (Route<dynamic> route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CSAppBar(title: widget.title),
      body: Column(
        children: [
          Image(image: AssetImage('assets/images/logo.png')),
          TextField(
            controller: id_input,
            decoration: InputDecoration(labelText: 'ID : ')
          ),
          TextField(
            controller: pw_input,
            obscureText: true,
            decoration: InputDecoration(labelText: 'PW : ')
          ),
          Row( // 버튼들을 가로로 배치
            mainAxisAlignment: MainAxisAlignment.spaceAround, // 버튼 사이에 공간을 줌
            children: [
              ElevatedButton(
                onPressed: () {
                  _processLogin(context);
                },
                child: Text('로그인'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => RegisterPage(title: widget.title),
                    ),
                  );
                },
                child: Text('계정 만들기 / 찾기'),
              ),
            ],
          ),
        ]
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
