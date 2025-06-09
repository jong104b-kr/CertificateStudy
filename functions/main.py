# main.py - 최종 2세대(v2) 코드

import firebase_admin
from firebase_admin import firestore
from firebase_functions import auth_fn, options

options.set_global_options(region="asia-northeast3")
firebase_admin.initialize_app()

@auth_fn.on_user_updated
def sync_email_on_auth_update(change: auth_fn.Change[auth_fn.UserRecord]) -> None:
    db = firestore.client()
    before_data = change.before
    after_data = change.after

    if before_data.email == after_data.email:
        print(f"User {after_data.uid}: 이메일이 변경되지 않았습니다.")
        return

    print(f"User {after_data.uid}: 이메일 변경 감지. '{before_data.email}' -> '{after_data.email}'")

    uid = after_data.uid
    new_email = after_data.email
    user_doc_ref = db.collection("users").document(uid)

    try:
        user_doc_ref.update({"email": new_email})
        print(f"✅ Firestore 동기화 성공: User {uid}의 이메일을 업데이트했습니다.")
    except Exception as e:
        print(f"❗️ Firestore 동기화 실패: User {uid}, 오류: {e}")
    return