import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'modifyaccount.dart';
import 'appbar.dart';
import 'deleteaccount.dart';
import 'UserDataProvider.dart';


class AccountInfoPage extends StatefulWidget {
  final String title;

  const AccountInfoPage({super.key, required this.title});

  @override
  State<AccountInfoPage> createState() => _AccountInfoPageState();
}

class _AccountInfoPageState extends State<AccountInfoPage> {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CSAppBar(title: widget.title), // widget.title로 접근
      body: Column(
        children: [
          // UserDataProvider의 변경을 수신 대기하는 Consumer 위젯을 사용하여
          // ID와 E메일 텍스트만 업데이트되도록 합니다.
          Consumer<UserDataProvider>(
            builder: (context, userDataProvider, child) {
              final String? email = userDataProvider.loggedInUserEmail;
              return Column( // 여러 텍스트 위젯을 포함하기 위해 Column으로 감쌉니다.
                crossAxisAlignment: CrossAxisAlignment.start, // 텍스트를 왼쪽 정렬
                children: [
                  FutureBuilder<String?>( // FutureBuilder로 ID를 비동기적으로 로드하여 표시
                    future: userDataProvider.loggedInUserId, // UserDataProvider에서 loggedInId Future를 가져옵니다.
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        // 데이터 로딩 중
                        return const Text("ID : 불러오는 중...");
                      } else if (snapshot.hasError) {
                        // 오류 발생 시
                        return Text("ID : 오류 발생 (${snapshot.error})");
                      } else if (snapshot.hasData && snapshot.data != null) {
                        // 데이터가 성공적으로 로드되었을 때
                        return Text("ID : ${snapshot.data}");
                      } else {
                        // 데이터가 없거나 로그인되지 않은 경우
                        return const Text("ID : 로그인되지 않음");
                      }
                    },
                  ),
                  // E메일은 동기적으로 사용 가능
                  Text("E메일 : ${email ?? '불러오는 중...'}"), // email이 null일 경우 대비
                ],
              );
            },
          ),
          const Text(
            '회원정보창입니다. 이 자리에 본인의 학습 내역이 들어올 예정입니다.',
          ),
          Text(
            '현재 수정 및 탈퇴 기능은 작동하지 않음을 유의하십시오!',
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ModifyAccountPage(title: widget.title), // ModifyPage로 변경된 이름 사용
                    ),
                  );
                },
                child: const Text('수정'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => DeleteAccountPage(title: widget.title),
                    ),
                  );
                },
                child: const Text('탈퇴'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}