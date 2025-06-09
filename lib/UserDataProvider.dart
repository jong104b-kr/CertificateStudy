import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Firebase 인증
import 'package:cloud_firestore/cloud_firestore.dart'; // Firestore 데이터베이스
import 'dart:convert';
import 'package:http/http.dart' as http;

// ValidationResult 클래스는 유효성 검사 결과를 반환하기 위한 헬퍼 클래스입니다.
class ValidationResult {
  final bool isSuccess;
  final String message;

  ValidationResult.success(String validatedResult)
      : isSuccess = true,
        message = validatedResult;

  ValidationResult.failure(String errorMessage)
      : isSuccess = false,
        message = errorMessage;
}

// UserDataProvider 클래스는 Firebase Authentication 및 Cloud Firestore와 상호작용하여
// 사용자 인증 및 회원 정보를 관리합니다.
class UserDataProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 현재 로그인된 Firebase 사용자 객체를 저장합니다.
  User? _currentUser;
  User? get currentUser => _currentUser;

  bool get isLoggedIn => _currentUser != null;

  // 새로 추가된 부분: 현재 로그인된 사용자의 ID를 반환합니다. (Firestore에 저장된 사용자 지정 ID)
  Future<String?> get loggedInUserId async { // Future<String?>와 async 추가
    if (_currentUser != null) {
      // Firestore에서 현재 사용자의 UID에 해당하는 문서의 'id' 필드를 조회합니다.
      final docSnapshot = await _firestore.collection('users').doc(_currentUser!.uid).get();
      if (docSnapshot.exists) {
        // 문서가 존재하면 해당 문서의 'id' 필드 값을 String?으로 캐스팅하여 반환합니다.
        return docSnapshot.data()?['id'] as String?;
      }
    }
    return null; // 로그인되지 않았거나, Firestore에 ID가 없는 경우 null 반환
  }

  // 새로 추가된 부분: 현재 로그인된 사용자의 이메일 주소를 반환합니다. (Firebase Authentication에 저장된 이메일)
  String? get loggedInUserEmail => _currentUser?.email;

  // UserDataProvider 생성자:
  // Firebase 인증 상태 변화를 실시간으로 구독하여 _currentUser를 업데이트하고 UI에 알립니다.
  UserDataProvider() {
    // userChanges는 로그인/로그아웃 뿐만 아니라, 사용자 토큰이 갱신될 때 (예: 이메일 변경 완료 후)도 이벤트를 발생시켜 더 효과적입니다.
    _auth.userChanges().listen((User? user) async {
      _currentUser = user;

      if (user != null) {
        // 이메일 변경과 같은 외부 작업 후 앱으로 돌아왔을 때 최신 상태를 반영하기 위해
        // Firebase 서버로부터 최신 사용자 정보를 강제로 가져옵니다.
        await user.reload();
        // reload() 후에는 _auth.currentUser를 다시 할당하여 최신 user 객체를 사용해야 합니다.
        user = _auth.currentUser;
        _currentUser = user;

        // reload 후 사용자가 null이 될 수 있는 예외적인 경우를 처리합니다.
        if (user == null) {
          notifyListeners();
          return;
        }

        // Firestore에서 현재 사용자의 문서 참조를 가져옵니다.
        final userDocRef = _firestore.collection('users').doc(user.uid);
        final docSnapshot = await userDocRef.get();

        if (docSnapshot.exists) {
          final firestoreData = docSnapshot.data();
          final firestoreEmail = firestoreData?['email'] as String?;

          // Firebase Auth의 이메일과 Firestore의 이메일이 다른지 확인합니다.
          if (firestoreEmail != null && firestoreEmail != user.email) {
            print('Firebase Auth와 Firestore 간 E메일 불일치 감지. 동기화를 시작합니다.');
            print('Auth E메일: ${user.email}, Firestore E메일: $firestoreEmail');

            // Firestore의 이메일을 Auth의 최신 이메일로 업데이트합니다.
            try {
              await userDocRef.update({'email': user.email});
              print('✅ Firestore E메일이 성공적으로 업데이트되었습니다: ${user.email}');
            } catch (e) {
              print('❗️ Firestore E메일 업데이트 중 오류 발생: $e');
            }
          }
        }
      }

      // 상태 변경을 UI에 알립니다.
      notifyListeners();
    });
  }

  /// Firestore에서 주어진 사용자 지정 ID에 해당하는 이메일 주소를 조회합니다.
  /// 이메일/비밀번호 기반 Firebase 인증을 위해 ID에 연결된 이메일이 필요할 때 사용됩니다.
  Future<String?> findEmailById(String id) async {
    try {
      // 'users' 컬렉션에서 'id' 필드가 주어진 id와 일치하는 문서를 찾습니다.
      // limit(1)을 사용하여 첫 번째 일치하는 문서만 가져와 효율성을 높입니다.
      final querySnapshot = await _firestore.collection('users')
          .where('id', isEqualTo: id)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        // 문서가 존재하면 해당 문서의 'email' 필드 값을 반환합니다.
        return querySnapshot.docs.first.data()['email'];
      }
      // 해당 ID의 사용자를 찾을 수 없으면 null을 반환합니다.
      return null;
    } catch (e) {
      // 오류 발생 시 콘솔에 출력하고 null을 반환합니다.
      print('ID로 이메일을 찾는 중 오류 발생: $e');
      return null;
    }
  }

  /// 회원가입 함수: ID, 비밀번호, 이메일을 매개변수로 받습니다.
  /// Firebase Authentication으로 계정을 생성하고, Firestore에 추가 사용자 정보를 저장합니다.
  Future<ValidationResult> registerUser(String id, String pw, String email) async {
    try {
      // 1. Firebase Authentication으로 계정 생성 시도 (이메일과 비밀번호 사용)
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: pw, // 비밀번호 변수명 'pw' 사용
      );
      User? user = userCredential.user;

      if (user != null) {
        // 2. 계정 생성 성공 시, Firestore에 사용자 지정 ID 및 이메일 저장
        // Firebase UID를 문서 ID로 사용하여 각 사용자의 고유성을 보장합니다.
        await _firestore.collection('users').doc(user.uid).set({
          'id': id, // 사용자에게 보여지는 ID (Firestore에 저장)
          'email': email, // Firebase Authentication의 이메일과 동일하게 저장
          // 필요한 경우 다른 사용자 정보도 여기에 추가할 수 있습니다.
        });
        try {
          print('I/flutter: [AuthEmail] E메일 인증 메일 발송 시도: ${user.email}');
          await user.sendEmailVerification();
          print('I/flutter: [AuthEmail] E메일 인증 메일 발송 요청 성공');
          return ValidationResult.success('회원가입 성공!\nID : $id\nE-mail : $email\nE메일 인증 링크를 확인해주세요.');
        } on FirebaseAuthException catch (e) {
          // sendEmailVerification에서만 발생하는 too-many-requests 오류 처리
          print('E/flutter: [AuthEmail] FirebaseAuthException 발생 (sendEmailVerification): ${e.code} - ${e.message}');
          if (e.code == 'too-many-requests') {
            // 회원가입은 성공했으니, 이메일 발송 실패만 안내
            return ValidationResult.failure('회원가입은 성공했지만, 인증 이메일 발송 요청이 너무 많습니다.\n잠시 후 앱에서 "인증 메일 재전송"을 시도해주세요.');
          }
          // 기타 sendEmailVerification 관련 오류 (이 경우 회원가입은 성공한 상태)
          print('E/flutter: [AuthEmail] 일반 오류 발생 (sendEmailVerification): $e');
          return ValidationResult.failure('회원가입 성공! 하지만 인증 이메일 발송 중 오류가 발생했습니다: ${e.message}');
        }
      } else {
        // user 객체가 null인 경우 (매우 드물지만 안전을 위해)
        return ValidationResult.failure('회원가입에 실패했습니다: 사용자 정보 없음');
      }
    } on FirebaseAuthException catch (e) {
      // Firebase Authentication 관련 오류 처리
      print('E/flutter: [Auth] 회원가입 FirebaseAuthException: ${e.code} - ${e.message}');
      if (e.code == 'weak-password') {
        return ValidationResult.failure('비밀번호가 너무 약합니다.');
      } else if (e.code == 'email-already-in-use') {
        return ValidationResult.failure('이미 사용 중인 이메일입니다.');
      } else if (e.code == 'invalid-email') {
        return ValidationResult.failure('유효하지 않은 이메일 형식입니다.');
      } else if (e.code == 'too-many-requests') { // 이 부분의 too-many-requests는 계정 생성 자체가 차단된 경우 (흔치 않음)
        return ValidationResult.failure('너무 많은 회원가입 요청이 발생했습니다. 잠시 후 다시 시도해주세요.');
      }
      return ValidationResult.failure('회원가입 오류: ${e.message}');
    } catch (e) {
      // 기타 예상치 못한 오류 처리
      print('E/flutter: [Auth] 회원가입 일반 오류: $e');
      return ValidationResult.failure('알 수 없는 오류 발생: $e');
    }
  }

  /// 로그인 함수: ID와 비밀번호를 매개변수로 받습니다.
  /// 먼저 ID에 해당하는 이메일을 찾은 후, 해당 이메일과 비밀번호로 Firebase 인증을 시도합니다.
  Future<ValidationResult> loginUser(String id, String pw) async {
    // 1. 주어진 ID에 해당하는 이메일 주소를 Firestore에서 조회합니다.
    String? email = await findEmailById(id);

    // 2. 이메일 주소를 찾을 수 없으면 로그인 실패를 반환합니다.
    if (email == null) {
      return ValidationResult.failure('해당 ID의 사용자를 찾을 수 없습니다.');
    }

    try {
      // 3. 찾은 이메일 주소와 입력된 비밀번호로 Firebase Authentication을 통해 로그인 시도
      await _auth.signInWithEmailAndPassword(email: email, password: pw); // 비밀번호 변수명 'pw' 사용
      // 로그인 성공 시 _currentUser가 자동으로 업데이트되고 notifyListeners 호출됨
      return ValidationResult.success('로그인 성공');
    } on FirebaseAuthException catch (e) {
      // Firebase Authentication 관련 오류 처리
      print('E/flutter: [Login] FirebaseAuthException 발생: ${e.code} - ${e.message}'); // 상세 로그 추가
      if (e.code == 'user-not-found' || e.code == 'wrong-password') {
        // Firebase는 ID가 아닌 이메일/비밀번호 불일치로 에러를 반환하므로,
        // 사용자에게는 일반적인 메시지를 제공하는 것이 좋습니다.
        return ValidationResult.failure('잘못된 ID 또는 비밀번호입니다.');
      } else if (e.code == 'invalid-email') {
        return ValidationResult.failure('유효하지 않은 이메일 형식입니다. (내부 오류)');
      } else if (e.code == 'user-disabled') {
        return ValidationResult.failure('이 계정은 비활성화되었습니다.');
      } else if (e.code == 'too-many-requests') {
        return ValidationResult.failure('너무 많은 로그인 시도가 발생했습니다. 잠시 후 다시 시도해주세요.');
      }
      return ValidationResult.failure('로그인 오류: ${e.message}');
    } catch (e) {
      // 기타 예상치 못한 오류 처리
      print('E/flutter: [Login] 알 수 없는 오류 발생: $e'); // 상세 로그 추가
      return ValidationResult.failure('알 수 없는 오류 발생: $e');
    }
  }

  /// 로그아웃 함수
  Future<void> logoutUser() async {
    await _auth.signOut();
    print('Logout completed. isLoggedIn = $isLoggedIn'); // 디버그 print
    notifyListeners();
    // _currentUser가 자동으로 null로 업데이트되고 notifyListeners 호출됨
  }

  /// Firestore에서 사용자 지정 ID의 중복 여부를 확인합니다.
  Future<bool> isIdAlreadyTaken(String id) async {
    try {
      final querySnapshot = await _firestore.collection('users')
          .where('id', isEqualTo: id)
          .limit(1) // 첫 번째 일치하는 문서만 필요하므로 제한합니다.
          .get();
      return querySnapshot.docs.isNotEmpty; // 문서가 존재하면 중복된 ID입니다.
    } catch (e) {
      print('ID 중복 확인 중 오류 발생: $e');
      return true; // 오류 발생 시 안전하게 중복으로 간주 (또는 다른 오류 처리)
    }
  }

  Future<void> reloadAndCheckEmailVerification() async {
    User? user = _auth.currentUser;
    if (user != null) {
      print('I/flutter: [EmailVerifyCheck] reload 전: ${user.emailVerified}');
      await user.reload(); // Firebase 서버에서 최신 사용자 정보를 가져옵니다.
      user = _auth.currentUser; // reload() 후에는 _auth.currentUser를 다시 가져와야 최신 정보가 반영됩니다.
      if (user != null) {
        print('I/flutter: [EmailVerifyCheck] reload 후: ${user.emailVerified}');
        if (user.emailVerified) {
          print('I/flutter: [EmailVerifyCheck] 이메일이 성공적으로 인증되었습니다. 이제 이메일 인증 필요 없음.');
          // 사용자에게 이메일 인증이 완료되었음을 알리는 스낵바 또는 UI 변경
          // (예: showSnackBarMessage(context, '이메일 인증이 완료되었습니다!'))
          // 필요하다면 UI 업데이트를 위해 notifyListeners() 호출 (이미 되어 있을 것임)
        } else {
          print('I/flutter: [EmailVerifyCheck] 이메일이 아직 인증되지 않았습니다. 다시 시도해주세요.');
          // 사용자에게 아직 인증되지 않았음을 알림
        }
      } else {
        print('W/flutter: [EmailVerifyCheck] reload 후 user가 null이 됨. (로그아웃되었을 수 있음)');
      }
    } else {
      print('W/flutter: [EmailVerifyCheck] 현재 로그인된 user가 없음. (로그인 필요)');
    }
    notifyListeners(); // UI 업데이트를 위해 호출
  }

  /// **비밀번호 재설정 이메일 전송 함수**
  /// 입력된 ID와 E메일을 매개변수로 받아 Firebase 비밀번호 재설정 이메일을 보냅니다.
  Future<ValidationResult> changePW(String id, String email) async {
    /// ChangePW 메소드는 비밀번호 찾기 기능을 겸하기 때문에
    /// 로그인되지 않은 상태에서도 유효성 검사를 할 수 있도록 맞췄습니다.
    //
    // 1. Firestore에서 주어진 ID에 해당하는 실제 이메일 주소를 조회합니다.
    String? storedEmail = await findEmailById(id);

    // 2. ID를 찾을 수 없거나 (storedEmail == null),
    //    ID는 있지만 입력된 이메일과 Firestore에 저장된 이메일이 일치하지 않는 경우
    if (storedEmail == null) {
      return ValidationResult.failure('해당 ID의 사용자를 찾을 수 없습니다.');
    }
    if (storedEmail != email) {
      return ValidationResult.failure('입력하신 ID와 E메일이 일치하지 않습니다. 다시 확인해주세요.');
    }

    try {
      // 3. 검증된 이메일 주소로 Firebase Authentication의 비밀번호 재설정 이메일 전송
      print('I/flutter: [PWReset] 비밀번호 재설정 메일 발송 시도: $email');
      await _auth.sendPasswordResetEmail(email: email);
      print('I/flutter: [PWReset] 비밀번호 재설정 메일 발송 요청 성공');
      return ValidationResult.success('비밀번호 재설정 이메일을 $email (으)로 보냈습니다. 받은 편지함을 확인해주세요.');
    } on FirebaseAuthException catch (e) {
      // Firebase Authentication 관련 오류 처리
      print('E/flutter: [PWReset] FirebaseAuthException 발생 (sendPasswordResetEmail): ${e.code} - ${e.message}');
      if (e.code == 'user-not-found' || e.code == 'invalid-email') {
        // sendPasswordResetEmail은 실제로 user-not-found를 반환하지 않고,
        // 단순히 이메일을 보내지 않는 경우가 많지만, 안전을 위해 포함합니다.
        // 위에 Firestore 검증을 통해 대부분 걸러지겠지만, 만약을 대비합니다.
        return ValidationResult.failure('입력하신 E메일로 등록된 사용자가 없습니다.');
      }   else if (e.code == 'too-many-requests') {
        return ValidationResult.failure('너무 많은 비밀번호 재설정 요청이 발생했습니다. 잠시 후 다시 시도해주세요.');
      }
      return ValidationResult.failure('비밀번호 재설정 이메일 전송 오류: ${e.message}');
    } catch (e) {
      print('E/flutter: [PWReset] 일반 오류 발생 (sendPasswordResetEmail): $e');
      return ValidationResult.failure('알 수 없는 오류 발생: $e');
    }
  }

  /// 이메일 변경 함수: ID, 비밀번호, 새 이메일을 매개변수로 받습니다.
  /// 현재 로그인된 사용자의 이메일 주소를 변경합니다.
  /// Firebase는 이메일 변경 시 확인 이메일을 보내므로, 사용자에게 해당 안내가 필요합니다.
  Future<ValidationResult> changeEmailAddress(String id, String pw, String email, String newEmail) async {
    User? user = _auth.currentUser;
    if (user == null) {
      return ValidationResult.failure('로그인된 사용자가 없습니다.');
    }

    if (user.email != email) {
      return ValidationResult.failure('입력하신 현재 E메일 주소가 로그인된 계정의 E메일 주소와 일치하지 않습니다.');
    }

    try {
      // 1. 재인증: 민감한 작업이므로 현재 로그인된 사용자의 E메일(email)과 비밀번호(pw)로 사용자를 재인증합니다.
      AuthCredential credential = EmailAuthProvider.credential(
        email: email, // 현재 로그인된 사용자의 이메일 사용
        password: pw, // 현재 비밀번호 변수명 'pw' 사용
      );
      await user.reauthenticateWithCredential(credential);

      // 2. Firebase Authentication의 verifyBeforeUpdateEmail을 사용하여 이메일 변경 시도
      //    이메일 확인 후 변경이 이루어집니다.
      //    이 호출은 확인 메일을 보내는 역할만 하며, 실제 Firebase Auth의 이메일은 아직 변경되지 않습니다.
      print('I/flutter: [EmailChange] E메일 변경 확인 메일 발송 시도: $newEmail');
      await user.verifyBeforeUpdateEmail(newEmail);
      // 이메일 변경은 사용자에게 확인 이메일을 보낸 후 적용됩니다.
      print('I/flutter: [EmailChange] E메일 변경 확인 메일 발송 요청 성공');
      return ValidationResult.success('새 E메일 주소로 확인 링크를 보냈습니다. 링크를 클릭하여 이메일 변경을 완료해주세요. '
          '변경 완료 후에는 새 E메일 주소로 다시 로그인해주세요.'); // 사용자 안내 메시지 강화
    } on FirebaseAuthException catch (e) {
      // Firebase Authentication 관련 오류 처리
      print('E/flutter: [EmailChange] FirebaseAuthException 발생 (verifyBeforeUpdateEmail): ${e.code} - ${e.message}');
      if (e.code == 'wrong-password') {
        return ValidationResult.failure('입력하신 비밀번호가 계정의 비밀번호와 일치하지 않습니다.');
      } else if (e.code == 'requires-recent-login') {
        return ValidationResult.failure('보안을 위해 다시 로그인해야 합니다. 재로그인 후 다시 시도해주세요.');
      } else if (e.code == 'email-already-in-use') {
        return ValidationResult.failure('입력하신 E메일은 이미 다른 계정으로 등록되어 있습니다.');
      } else if (e.code == 'invalid-email') {
        return ValidationResult.failure('유효하지 않은 이메일 형식입니다.');
      } else if (e.code == 'too-many-requests') {
        return ValidationResult.failure('너무 많은 E메일 변경 요청이 발생했습니다. 잠시 후 다시 시도해주세요.');
      } else if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        return ValidationResult.failure('입력하신 이메일 또는 비밀번호가 올바르지 않습니다.');
      }
      return ValidationResult.failure('이메일 변경 오류: ${e.message}');
    } catch (e) {
      print('E/flutter: [EmailChange] 일반 오류 발생 (verifyBeforeUpdateEmail): $e');
      return ValidationResult.failure('알 수 없는 오류 발생: $e');
    }
  }

  /// 회원 탈퇴 함수: ID와 비밀번호를 매개변수로 받습니다.
  /// 현재 로그인된 사용자의 계정을 삭제합니다. 민감한 작업이므로 재인증이 필요합니다.
    Future<ValidationResult> deleteAccount(String id, String email, String pw) async {
    User? user = _auth.currentUser;
    if (user == null) {
      return ValidationResult.failure('로그인된 사용자가 없습니다.');
    }

    try {
      // 1. 현재 비밀번호로 재인증 (민감한 작업이므로 필수)
      AuthCredential credential = EmailAuthProvider.credential(
        email: user.email!, // 현재 로그인된 사용자의 이메일 사용
        password: pw, // 입력된 현재 비밀번호
      );
      await user.reauthenticateWithCredential(credential);

      // 2. 재인증 성공 시, 백엔드 Functions를 호출하여 계정 삭제 확인 이메일 발송 요청
      // 이메일 발송 요청 Functions는 이미 requestAccountDeletionEmail 메소드에 있습니다.
      ValidationResult emailRequestResult = await requestAccountDeletionEmail(id, email);
      return emailRequestResult; // Functions 호출 결과 (성공/실패) 반환

    } on FirebaseAuthException catch (e) {
      // Firebase Authentication 관련 오류 처리
      if (e.code == 'wrong-password') {
        return ValidationResult.failure('비밀번호가 일치하지 않습니다.');
      } else if (e.code == 'requires-recent-login') {
        return ValidationResult.failure('보안을 위해 다시 로그인해야 합니다. 재로그인 후 다시 시도해주세요.');
      } else if (e.code == 'too-many-requests') {
        return ValidationResult.failure('너무 많은 요청이 발생했습니다. 잠시 후 다시 시도해주세요.');
      }
      return ValidationResult.failure('계정 삭제 요청 오류: ${e.message}');
    } catch (e) {
      return ValidationResult.failure('알 수 없는 오류 발생: $e');
    }
  }

  /// 이메일 발송 요청을 Firebase Functions에 보냅니다.
  /// (이 코드는 이전에 `deleteAccount.dart`가 호출하던 Functions 호출 로직을 여기로 가져온 것입니다.)
  Future<ValidationResult> requestAccountDeletionEmail(String id, String email) async {
    // 이 URL은 main.py (Functions) 배포 후 얻은 실제 URL로 변경해야 합니다.
    // Firebase Console -> Functions -> 'request_account_deletion' 함수 -> '트리거' 탭에서 확인
    const String functionsUrl = "https://asia-northeast3-certificatestudyaiffelcore12th.cloudfunctions.net/request_account_deletion";

    User? user = _auth.currentUser;
    if (user == null) {
      return ValidationResult.failure('로그인된 사용자가 없습니다.');
    }

    try {
      print('Functions URL 호출 시도: $functionsUrl');
      print('요청 바디: ${jsonEncode(<String, String>{'id': id, 'email': email})}');
      final response = await http.post(
        Uri.parse(functionsUrl),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode(<String, String>{
          'id': id,
          'email': email,
        }),
      );

      print('Functions 응답 상태 코드: ${response.statusCode}');
      print('Functions 응답 바디: ${response.body}');

      if (response.statusCode == 200) {
        return ValidationResult.success('회원 탈퇴 확인 이메일을 $email (으)로 보냈습니다. 받은 편지함을 확인해주세요.');
      } else {
        String errorMessage = '회원 탈퇴 요청에 실패했습니다.';
        try {
          final errorData = jsonDecode(response.body);
          errorMessage = errorData['message'] ?? errorMessage;
        } catch (e) {
          // JSON 파싱 실패 시 기본 메시지 사용
        }
        return ValidationResult.failure('Functions 호출 오류: $errorMessage (상태 코드: ${response.statusCode})');
      }
    } catch (e) {
      print('Firebase Functions 호출 중 네트워크 또는 기타 오류: $e');
      return ValidationResult.failure('네트워크 오류 또는 서버 요청 실패: $e');
    }
  }


  /// 이메일로 ID 찾기 (Firestore 쿼리)
  /// 주어진 이메일 주소를 통해 Firestore에 저장된 사용자 지정 ID를 찾습니다.
  Future<String?> findIdByEmail(String email) async {
    try {
      final querySnapshot = await _firestore.collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (querySnapshot.docs.isNotEmpty) {
        return querySnapshot.docs.first.data()['id'];
      }
      return null;
    } catch (e) {
      print('이메일로 ID를 찾는 중 오류 발생: $e');
      return null;
    }
  }
}

// UserDataProviderUtility 클래스는 UI 계층에서 UserDataProvider를 사용하기 위한
// 유효성 검사 및 헬퍼 함수들을 제공합니다.
class UserDataProviderUtility {
  /// 회원가입 유효성 검사 및 처리
  /// 입력된 ID, 비밀번호, 이메일의 유효성을 검사하고 UserDataProvider를 통해 계정을 생성합니다.
  Future<ValidationResult> registerAccount({
    required String newID, // 사용자에게 보여지는 ID
    required String newPW, // 비밀번호
    required String newEmail, // 이메일
    required UserDataProvider userDataProvider, // Firebase 기능이 있는 UserDataProvider 인스턴스
  }) async {
    // 1. 모든 필수 필드 입력 여부 확인
    if (newID.isEmpty || newPW.isEmpty || newEmail.isEmpty) {
      return ValidationResult.failure('모든 필드를 입력해주세요.');
    }

    // 2. 사용자 지정 ID 중복 확인 (Firestore 쿼리 이용)
    bool isIdTaken = await userDataProvider.isIdAlreadyTaken(newID);
    if (isIdTaken) {
      return ValidationResult.failure('이미 해당 ID로 가입된 회원이 있습니다.');
    }

    // 3. 이메일 중복 확인은 Firebase Authentication의 createUserWithEmailAndPassword 메서드에서
    //    'email-already-in-use' 오류를 통해 자동으로 처리됩니다.
    //    따라서 여기서는 별도의 사전 이메일 중복 검사 로직을 넣지 않고,
    //    UserDataProvider의 registerUser 호출 시 반환되는 결과를 기다립니다.

    // 모든 클라이언트 측 유효성 검사를 통과했다면, UserDataProvider를 통해 실제 계정 생성 시도
    ValidationResult registerResult = await userDataProvider.registerUser(newID, newPW, newEmail);

    // UserDataProvider에서 반환된 최종 결과를 그대로 반환합니다.
    return registerResult;
  }

  /// ID와 비밀번호로 로그인 유효성 검사 및 처리
  /// 입력된 ID와 비밀번호를 사용하여 UserDataProvider를 통해 로그인 시도합니다.
  Future<ValidationResult> validateAndLoginById({
    required String id,
    required String pw, // 비밀번호 변수명 'pw' 사용
    required UserDataProvider userDataProvider,
  }) async {
    // 1. 모든 필수 필드 입력 여부 확인
    if (id.isEmpty || pw.isEmpty) {
      return ValidationResult.failure('ID와 비밀번호를 모두 입력해주세요.');
    }

    // 2. UserDataProvider의 loginUser 메서드를 호출하여 실제 로그인 처리
    // 이 메서드 내부에서 ID로 이메일을 조회하고, 이메일/비밀번호로 Firebase Auth 로그인을 시도합니다.
    ValidationResult loginResult = await userDataProvider.loginUser(id, pw);

    return loginResult;
  }

  /// 비밀번호 변경 유효성 검사 및 처리
  /// 해당 ID와 E메일로 등록된 계정의 E메일로 사용자의 비밀번호를 변경하는 메일을 보냅니다.
  /// ChangePW 메소드는 비밀번호 찾기 기능을 겸하기 때문에
  /// 로그인되지 않은 상태에서도 유효성 검사를 할 수 있도록 맞췄습니다.
  Future<ValidationResult> validateAndChangePW({
    required String id, // 변경하려는 계정의 ID (로그인된 사용자와 일치하는지 확인용)
    required String email, // 현재 E메일 (재인증용)
    required UserDataProvider userDataProvider, // Firebase 기능이 있는 UserDataProvider 인스턴스
  }) async {
    // 1. 모든 필수 필드 입력 여부 확인
    if (id.isEmpty || email.isEmpty ) {
      return ValidationResult.failure('모든 필드를 입력해주세요.');
    }

    // 2. UserDataProvider의 changePW 메서드를 호출하여 실제 비밀번호 재설정 이메일 전송 작업 위임
    // 이 함수 내부에서 입력된 ID와 E메일이 로그인된 계정과 일치하는지,
    // 그리고 Firestore에 저장된 ID와 E메일이 일치하는지 확인합니다.
    ValidationResult result = await userDataProvider.changePW(id, email);
    return result;
  }

  /// 이메일 변경 유효성 검사 및 처리
  /// 현재 로그인된 사용자의 이메일 주소를 변경합니다.
  Future<ValidationResult> validateAndChangeEmail({
    required String id, // 변경하려는 계정의 ID (로그인된 사용자와 일치하는지 확인용)
    required String pw, // 현재 비밀번호 (재인증용)
    required String email, // 기존의 E메일 주소 (로그인된 사용자와 일치하는지 확인요)
    required String newEmail, // 변경할 새 E메일 주소
    required UserDataProvider userDataProvider, // Firebase 기능이 있는 UserDataProvider 인스턴스
  }) async {
    // 1. 모든 필수 필드 입력 여부 확인
    if (id.isEmpty || pw.isEmpty || email.isEmpty || newEmail.isEmpty) {
      return ValidationResult.failure('모든 필드를 입력해주세요.');
    }

    // 2. 현재 로그인된 사용자 확인
    if (userDataProvider.currentUser == null) {
      return ValidationResult.failure('로그인된 사용자가 없습니다. 먼저 로그인해주세요.');
    }

    // 3. 입력된 ID가 현재 로그인된 사용자의 ID와 일치하는지 확인 (보안 강화)
    String? loggedInId = (await userDataProvider.loggedInUserId);
    if (loggedInId != id) {
      return ValidationResult.failure('입력하신 ID가 현재 로그인된 계정과 일치하지 않습니다.');
    }

    // 3. 입력된 E메일 주소가 현재 로그인된 사용자의 E메일 주소와 일치하는지 확인 (보안 강화)
    String? loggedInEmail = (await userDataProvider.loggedInUserEmail);
    if (loggedInEmail != email) {
      return ValidationResult.failure('입력하신 ID가 현재 로그인된 계정과 일치하지 않습니다.');
    }

    // 5. 변경할 E메일 주소가 기존 E메일 주소와 동일한지 확인
    if (userDataProvider.loggedInUserEmail == newEmail) {
      return ValidationResult.failure('기존 E메일 주소와 동일합니다. 다른 주소를 입력해주세요.');
    }

    // 모든 유효성 검사를 통과했다면, UserDataProvider를 통해 실제 이메일 변경 작업 위임
    ValidationResult changeResult = await userDataProvider.changeEmailAddress(id, pw, email, newEmail);
    return changeResult;
  }

  /// ID 찾기 (이메일 기반)
  /// 이메일 주소를 통해 Firestore에 저장된 사용자 지정 ID를 찾습니다.
  Future<String?> findIdByEmail({
    required String email,
    required UserDataProvider userDataProvider,
  }) async {
    if (email.isEmpty) {
      return null; // 이메일이 비어있으면 ID를 찾을 수 없음
    }
    // UserDataProvider의 findIdByEmail 메서드를 호출하여 Firestore에서 ID를 조회합니다.
    return await userDataProvider.findIdByEmail(email);
  }

  /// 회원 탈퇴 유효성 검사 및 처리
  /// 사용자에게 비밀번호를 재확인 받은 후 계정을 삭제합니다.
  Future<ValidationResult> validateAndDeleteUser({
    required String id, // 탈퇴하려는 계정의 ID (로그인된 사용자와 일치하는지 확인용)
    required String email, // 탈퇴하려는 계정의 E메일 (로그인된 사용자와 일치하는지 확인용)
    required String pw, // 비밀번호 (재인증용)
    required UserDataProvider userDataProvider,
  }) async {
    // 1. 모든 필수 필드 입력 여부 확인
    if (id.isEmpty || email.isEmpty || pw.isEmpty) {
      return ValidationResult.failure('ID와 E메일, 비밀번호를 모두 입력해주세요.');
    }

    // 2. 현재 로그인된 사용자 확인
    if (userDataProvider.currentUser == null) {
      return ValidationResult.failure('로그인된 사용자가 없습니다.');
    }

    // 3. 입력된 ID가 현재 로그인된 사용자의 ID와 일치하는지 확인 (보안 강화)
    String? loggedInId = (await userDataProvider.loggedInUserId);
    if (loggedInId != id) {
      return ValidationResult.failure('입력하신 ID가 현재 로그인된 계정과 일치하지 않습니다.');
    }

    // 4. 입력된 E메일이 현재 로그인된 사용자의 E메일과 일치하는지 확인 (보안 강화)
    String? loggedInEmail = (await userDataProvider.loggedInUserEmail);
    if (loggedInEmail != email) {
      return ValidationResult.failure('입력하신 E메일이 현재 로그인된 계정과 일치하지 않습니다.');
    }

    // 모든 유효성 검사를 통과했다면, UserDataProvider를 통해 실제 회원 탈퇴 작업 위임
    ValidationResult deleteResult = await userDataProvider.deleteAccount(id, email, pw);
    return deleteResult;
  }
}
