import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'modifyaccount.dart';
import 'appbar.dart';
import 'deleteaccount.dart';
import 'UserDataProvider.dart';
import 'solvedq.dart';


class AccountInfoPage extends StatefulWidget {
  final String title;

  const AccountInfoPage({super.key, required this.title});

  @override
  State<AccountInfoPage> createState() => _AccountInfoPageState();
}

class _AccountInfoPageState extends State<AccountInfoPage> {
  // 1. Future를 저장할 상태 변수를 선언합니다.
  late Future<String?> _userIdFuture;

  @override
  void initState() {
    super.initState();
    // 2. initState에서 딱 한 번만 Future를 생성하여 변수에 할당합니다.
    // Provider.of를 사용하되, listen: false로 설정하여 불필요한 리빌드를 방지합니다.
    final userDataProvider = Provider.of<UserDataProvider>(context, listen: false);
    _userIdFuture = userDataProvider.loggedInUserId;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CSAppBar(title: widget.title),
      body: Column(
        children: [
          // E메일은 UserDataProvider의 변경에 따라 계속 업데이트되어야 하므로 Consumer를 유지합니다.
          Consumer<UserDataProvider>(
            builder: (context, userDataProvider, child) {
              final String? email = userDataProvider.loggedInUserEmail;
              return Text("E메일 : ${email ?? '불러오는 중...'}"); // email이 null일 경우 대비
            },
          ),
          // ID를 표시하는 FutureBuilder는 Consumer 바깥으로 빼거나,
          // Consumer 안에 두더라도 initState에서 생성한 Future를 사용합니다.
          FutureBuilder<String?>(
            // 3. build 메소드가 몇 번이 호출되든, 항상 initState에서 생성한 Future를 사용합니다.
            future: _userIdFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Text("ID : 불러오는 중...");
              } else if (snapshot.hasError) {
                return Text("ID : 오류 발생 (${snapshot.error})");
              } else if (snapshot.hasData && snapshot.data != null) {
                return Text("ID : ${snapshot.data}");
              } else {
                return const Text("ID : 로그인되지 않음");
              }
            },
          ),
          const
          Text(
            '현재 수정 및 탈퇴 기능은 작동하지 않음을 유의하십시오!',
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SolvedQuestionPage(title: widget.title),
                ),
              );
            },
            child: Text('지난 문제 둘러보기'),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ModifyAccountPage(title: widget.title),
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