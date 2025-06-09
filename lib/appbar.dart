import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'UserDataProvider.dart';
import 'main.dart';
import 'account.dart';


class CSAppBar extends StatefulWidget implements PreferredSizeWidget {
  final String title;

  const CSAppBar({super.key, required this.title});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  State<CSAppBar> createState() => _CSAppBarState();
}

class _CSAppBarState extends State<CSAppBar> { // State 클래스 생성
  @override
  void initState() {
    super.initState();
    // !!! 중요: 이 부분이 핵심 로직입니다. !!!
    // 현재 프레임 렌더링이 완료된 직후에 실행될 콜백을 예약합니다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 위젯이 여전히 위젯 트리에 마운트되어 있는지 확인합니다.
      if (mounted) {
        // Provider.of를 사용하여 UserDataProvider 인스턴스를 가져온 후 notifyListeners()를 호출합니다.
        // listen: false는 이 Provider.of 호출 자체가 위젯을 리빌드하지 않도록 합니다 (여기서는 notifyListeners만 목적).
        Provider.of<UserDataProvider>(context, listen: false).notifyListeners();
        print('>>> _CSAppBarState initState: addPostFrameCallback - notifyListeners() 호출됨.');
      }
    });
  }
  @override
  Widget build(BuildContext context) {

    final userDataProvider = Provider.of<UserDataProvider>(context);
    final bool isLoggedIn = userDataProvider.isLoggedIn;

    print('CSAppBar 빌드 중: isLoggedIn = $isLoggedIn');

    // 디버그 print 문 추가
    print('CSAppBar 빌드 중: isLoggedIn = $isLoggedIn');
    print('현재 로그인된 사용자 ID: ${userDataProvider.loggedInUserId.toString()}'); // Future이므로 toString()으로 일단 출력
    print('현재 로그인된 사용자 이메일: ${userDataProvider.loggedInUserEmail}');

    return AppBar(
      backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      title: Text(widget.title),
      actions: <Widget>[
        Consumer<UserDataProvider>( // Consumer 위젯 추가
          builder: (context, userDataProvider, child) {
            final bool isLoggedIn = userDataProvider.isLoggedIn;

            // 디버그 print 문 (Consumer 내부)
            print('Consumer in CSAppBar rebuild: isLoggedIn = $isLoggedIn');
            print('Consumer in CSAppBar rebuild: loggedInEmail = ${userDataProvider.loggedInUserEmail}');

            if (isLoggedIn) {
              // 로그인 상태일 때만 loggedInId 디버그 print 실행
              userDataProvider.loggedInUserId.then((id) {
                print('Consumer in _CSAppBarState: loggedInId (resolved) = $id');
              });
              return Row(
                  children: [
                    ElevatedButton(
                        child: const Text('로그아웃'),
                        onPressed: () async {
                          await userDataProvider.logoutUser(); // Consumer의 userDataProvider 사용
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('로그아웃 되었습니다.')),
                          );
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                              builder: (context) => MainPage(title: widget.title),
                            ),
                            (Route<dynamic> route) => false,
                          );
                        }
                    ),
                    ElevatedButton(
                        child: const Text('회원정보'),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => AccountInfoPage(title: widget.title),
                            ),
                          );
                        }
                    ),
                  ]
              );
            } else {
              // 로그인되지 않은 상태에서는 아무것도 표시하지 않거나, 다른 위젯 표시
              return Container(); // 빈 컨테이너 반환
            }
          },
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}