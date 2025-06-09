// home.dart 파일 전체 (최종 수정본, 다시 확인)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'main.dart';
import 'newexam.dart';
import 'solvedq.dart';
import 'community.dart';
import 'appbar.dart';
import 'UserDataProvider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'ui_utils.dart';

class HomePage extends StatefulWidget {
  final String title;

  const HomePage({super.key, required this.title});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // initState에서 Provider를 통해 UserDataProvider를 가져올 것이므로,
  late UserDataProvider _userDataProvider; // 이 변수도 이제 필요합니다.

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // initState에서는 listen: false로 Provider 인스턴스만 가져옵니다.
        _userDataProvider = Provider.of<UserDataProvider>(context, listen: false);

      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UserDataProvider>(
      builder: (context, userDataProvider, child) {
        final bool isLoggedIn = userDataProvider.isLoggedIn;
        final User? currentUser = userDataProvider.currentUser;

        print('>>> HomePage build: isLoggedIn = $isLoggedIn');
        if (isLoggedIn) {
          userDataProvider.loggedInUserId.then((id) {
            print('>>> HomePage build: loggedInUserId (resolved) = $id');
          });
        }
        print('>>> HomePage build: loggedInUserEmail = ${userDataProvider.loggedInUserEmail}');

        return Scaffold(
          appBar: CSAppBar(title: widget.title),
          body: Column(
            children: [
              if (isLoggedIn && currentUser != null)
                Column(
                  children: [
                    FutureBuilder<String?>(
                      future: userDataProvider.loggedInUserId,
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.data != null) {
                          return Text('환영합니다, ${snapshot.data}님!');
                        }
                        return Container();
                      },
                    ),
                    if (!currentUser.emailVerified) // E메일이 인증되지 않았다면
                      Column(
                        children: [
                          Text('E메일 인증이 필요합니다!\n아래 버튼을 눌러 인증 메일을 다시 전송하십시오.'),
                          ElevatedButton(
                            onPressed: () async {
                              await currentUser.sendEmailVerification();
                              if (mounted) {
                                showSnackBarMessage(context, '인증 E메일을 다시 보냈습니다. 메일을 확인해주세요.');
                              }
                              // 메일 재전송 후, 강제 로그아웃하여 다음 로그인 시 인증 상태를 새로고침
                              // 기존 reload 로직 대신 로그아웃 후 메인 페이지로 이동합니다.
                              await _userDataProvider.logoutUser(); // UserDataProvider의 로그아웃 메서드 호출
                              if (mounted) {
                                showSnackBarMessage(context, '인증 확인을 위해 로그아웃되었습니다. 다시 로그인해주세요.');
                                Navigator.pushAndRemoveUntil( // 메인 페이지로 이동
                                  context,
                                  MaterialPageRoute(builder: (context) => MainPage(title: widget.title)),
                                      (Route<dynamic> route) => false,
                                );
                              }
                            },
                            child: Text('인증 E메일 다시 보내기'),
                          ),
                          Text('위 버튼을 누르면 로그아웃됩니다.'),
                        ],
                      )
                    else // E메일이 인증되었다면
                      Text('E메일이 인증되었습니다.\nE메일 : ${userDataProvider.loggedInUserEmail}'),
                  ],
                )
              else // 로그인되지 않은 상태
                Text('로그인이 필요합니다.'),
              Text('회원정보창입니다. 이 자리에 본인의 학습 내역이 들어올 예정입니다.'),
              Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => NewExamPage(title: widget.title),
                          ),
                        );
                      },
                      child: Text('새 문제 풀어보기'),
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
                  ]
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CommunityPage(title: widget.title),
                    ),
                  );
                },
                child: Text('커뮤니티'),
              ),
            ],
          ),
        );
      },
    );
  }

  /*
  // _HomePageState 내부에 정의된 private 메서드
  Future<void> _callEmailVerificationReload() async {
    if (!mounted) {
      print('W/flutter: _callEmailVerificationReload: 위젯이 마운트되지 않았습니다.');
      return;
    }

    // UserDataProvider의 메서드를 호출하여 Firebase 인증 상태를 새로고침합니다.
    await _userDataProvider.reloadAndCheckEmailVerification(); // _userDataProvider 사용

    // UserDataProvider가 notifyListeners를 이미 호출했으므로, Consumer는 이 위젯을 리빌드할 것입니다.
    // setState를 명시적으로 호출하여 _HomePageState 자체도 리빌드되도록 하여 UI 업데이트를 강제합니다.
    setState(() {
      // setState 내부에서는 아무것도 변경할 필요가 없습니다. 단순히 rebuild를 트리거하는 용도입니다.
    });

    // 스낵바 메시지는 이제 reloadAndCheckEmailVerification 메서드 내부에서 UserDataProvider가 처리합니다.
    // (또는 여기에서 updatedUser를 다시 가져와 처리할 수도 있습니다.)
    User? updatedUser = _userDataProvider.currentUser; // 최신 사용자 정보

    if (mounted) { // SnackBar를 띄우기 전에 위젯이 마운트되었는지 확인
      if (updatedUser != null && updatedUser.emailVerified) {
        showSnackBarMessage(context, 'E메일 인증이 성공적으로 확인되었습니다!');
      } else {
        showSnackBarMessage(context, '아직 E메일이 인증되지 않았습니다. 메일을 확인해주세요.');
      }
    }
  }
  */
}