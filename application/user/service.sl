import "crypto";
import "encoding";
import "log";
import "strings";
import "time";
import "../../domain/user" as user_domain;
import "../../infrastructure/sqlite" as sqlite;
import "../../infrastructure/email" as email;
import "../../infrastructure/storage" as storage;
import "../../shared";

pub gc struct UserService {
    repo: sqlite.SqliteUserRepo,
    mailer: email.Mailer,
    pepper: str,
    upload_dir: str
}

pub fn new_service(repo: sqlite.SqliteUserRepo, mailer: email.Mailer, pepper: str, upload_dir: str) -> UserService {
    return UserService { repo: repo, mailer: mailer, pepper: pepper, upload_dir: upload_dir };
}

fn now_secs() -> int {
    return time.wall() / 1000000000;
}

fn valid_username(s: str) -> bool {
    if len(s) < 3 || len(s) > 32 {
        return false;
    }
    let b = to_bytes(s);
    let i = 0;
    while i < len(b) {
        let c = b[i];
        let okc = (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95;
        if !okc {
            return false;
        }
        i = i + 1;
    }
    return true;
}

fn valid_email(s: str) -> bool {
    if len(s) < 3 {
        return false;
    }
    let at = strings.find(s, "@");
    if at <= 0 {
        return false;
    }
    if at >= len(s) - 1 {
        return false;
    }
    return true;
}

fn six_digit_code() -> result[str, str] {
    let rr = crypto.rand(6);
    guard let b = rr else let e = err_of(rr) {
        return err(e);
    }
    let out = "";
    let i = 0;
    while i < 6 {
        let d = b[i] % 10;
        out = out + to_str(d);
        i = i + 1;
    }
    return ok(out);
}

// Runs in a spawned task so signup/resend/change_email do not wait on Resend.
fn deliver_verification_email(mailer: email.Mailer, to_email: str, code: str) {
    let r = email.send_verification(mailer, to_email, code);
    guard let _ok = r else let e = err_of(r) {
        log.warn("verification email failed for " + to_email + ": " + e);
        return;
    }
}

fn issue_verification(svc: UserService, user_id: str, to_email: str) -> result[bool, str] {
    let cr = six_digit_code();
    guard let code = cr else let e = err_of(cr) {
        return err(e);
    }
    let idr = shared.new_id();
    guard let vid = idr else let e = err_of(idr) {
        return err(e);
    }
    let now = now_secs();
    let code_hash = shared.hmac_str_hex(svc.pepper, code);
    let ir = sqlite.insert_verification(svc.repo, vid, user_id, code_hash, now + 900, now);
    guard let _ok = ir else let e = err_of(ir) {
        return err(e);
    }
    // Expose code immediately for mail_dev / smoke; network send is async.
    svc.mailer.last_code = code;
    spawn deliver_verification_email(svc.mailer, to_email, code);
    return ok(true);
}

fn token_hash_of(svc: UserService, token: str) -> result[str, str] {
    if len(token) == 0 {
        return err(shared.invalid_token);
    }
    let hd = encoding.hex_decode(token);
    guard let raw = hd else {
        return err(shared.invalid_token);
    }
    return ok(shared.hmac_hex(svc.pepper, raw));
}

fn auth_from_token(svc: UserService, token: str) -> result[sqlite.AuthRow, str] {
    let thr = token_hash_of(svc, token);
    guard let token_hash = thr else let e = err_of(thr) {
        return err(e);
    }
    let sr = sqlite.find_session_user(svc.repo, token_hash, now_secs());
    guard let row = sr else let e = err_of(sr) {
        if e == shared.not_found || e == shared.unauthorized {
            return err(shared.invalid_token);
        }
        return err(e);
    }
    if row.deactivated_at != 0 {
        return err(shared.account_deactivated);
    }
    return ok(row);
}

pub fn signup(svc: UserService, email_raw: str, username_raw: str, password: str) -> result[user_domain.SignupResult, str] {
    let email_addr = strings.trim(email_raw);
    let username = strings.trim(username_raw);
    if !valid_email(email_addr) {
        return err(shared.invalid_email);
    }
    if !valid_username(username) {
        return err(shared.invalid_username);
    }
    if len(password) < 8 {
        return err(shared.weak_password);
    }

    let existing_e = sqlite.find_auth_by_email(svc.repo, email_addr);
    guard let _ee = existing_e else let e = err_of(existing_e) {
        if e != shared.not_found {
            return err(e);
        }
        let existing_u = sqlite.find_auth_by_username(svc.repo, username);
        guard let _eu = existing_u else let e2 = err_of(existing_u) {
            if e2 != shared.not_found {
                return err(e2);
            }
            let idr = shared.new_id();
            guard let uid = idr else let e3 = err_of(idr) {
                return err(e3);
            }
            let hr = shared.hash_password(svc.pepper, password);
            guard let parts = hr else let e4 = err_of(hr) {
                return err(e4);
            }
            let now = now_secs();
            let row = sqlite.default_auth_row(uid, email_addr, username, parts[1], parts[0], username, now);
            let ir = sqlite.insert_user(svc.repo, row);
            guard let _ins = ir else let e5 = err_of(ir) {
                return err(e5);
            }
            let vr = issue_verification(svc, uid, email_addr);
            guard let _sent = vr else let e6 = err_of(vr) {
                log.warn("signup verification send failed: " + e6);
                return err(e6);
            }
            let pubu = user_domain.to_public(sqlite.to_user(row));
            return ok(user_domain.SignupResult { user: pubu, verification_sent: true });
        }
        return err(shared.username_taken);
    }
    return err(shared.email_taken);
}

pub fn verify_email(svc: UserService, email_raw: str, code_raw: str) -> result[user_domain.UserPublic, str] {
    let email_addr = strings.trim(email_raw);
    let code = strings.trim(code_raw);
    if len(code) != 6 {
        return err(shared.invalid_code);
    }
    let ar = sqlite.find_auth_by_email(svc.repo, email_addr);
    guard let row = ar else let e = err_of(ar) {
        return err(e);
    }
    if row.email_verified {
        return ok(user_domain.to_public(sqlite.to_user(row)));
    }
    let now = now_secs();
    let code_hash = shared.hmac_str_hex(svc.pepper, code);
    let vr = sqlite.find_open_verification(svc.repo, row.id, code_hash, now);
    guard let vid = vr else let e = err_of(vr) {
        if e == shared.invalid_argument || e == shared.not_found {
            return err(shared.invalid_code);
        }
        return err(e);
    }
    let cr = sqlite.consume_verification(svc.repo, vid, now);
    guard let _c = cr else let e = err_of(cr) {
        return err(e);
    }
    let sr = sqlite.set_email_verified(svc.repo, row.id);
    guard let _s = sr else let e = err_of(sr) {
        return err(e);
    }
    row.email_verified = true;
    return ok(user_domain.to_public(sqlite.to_user(row)));
}

pub fn resend_code(svc: UserService, email_raw: str) -> result[bool, str] {
    let email_addr = strings.trim(email_raw);
    let ar = sqlite.find_auth_by_email(svc.repo, email_addr);
    guard let row = ar else let e = err_of(ar) {
        return err(e);
    }
    if row.email_verified {
        return err(shared.already_verified);
    }
    return issue_verification(svc, row.id, row.email);
}

pub fn signin(svc: UserService, login_raw: str, password: str) -> result[user_domain.AuthSession, str] {
    let _purge = sqlite.purge_expired_sessions(svc.repo, now_secs());
    let login = strings.trim(login_raw);
    if len(login) == 0 || len(password) == 0 {
        return err(shared.invalid_argument);
    }
    let ar: result[sqlite.AuthRow, str] = err(shared.not_found);
    if strings.contains(login, "@") {
        ar = sqlite.find_auth_by_email(svc.repo, login);
    } else {
        ar = sqlite.find_auth_by_username(svc.repo, login);
    }
    guard let row = ar else let e = err_of(ar) {
        if e == shared.not_found {
            return err(shared.invalid_credentials);
        }
        return err(e);
    }
    if row.deactivated_at != 0 {
        return err(shared.account_deactivated);
    }
    if !shared.verify_password(svc.pepper, password, row.password_salt, row.password_hash) {
        return err(shared.invalid_credentials);
    }
    if !row.email_verified {
        return err(shared.email_unverified);
    }
    let tr = shared.new_session_token();
    guard let token = tr else let e = err_of(tr) {
        return err(e);
    }
    let hd = encoding.hex_decode(token);
    guard let raw = hd else let e = err_of(hd) {
        return err(e);
    }
    let token_hash = shared.hmac_hex(svc.pepper, raw);
    let idr = shared.new_id();
    guard let sid = idr else let e = err_of(idr) {
        return err(e);
    }
    let now = now_secs();
    let ir = sqlite.insert_session(svc.repo, sid, row.id, token_hash, now + 2592000, now);
    guard let _s = ir else let e = err_of(ir) {
        return err(e);
    }
    return ok(user_domain.AuthSession {
        token: token,
        user: user_domain.to_public(sqlite.to_user(row))
    });
}

pub fn get_by_id(svc: UserService, id: str) -> result[user_domain.User, str] {
    return sqlite.find_user_by_id(svc.repo, id);
}

pub fn me_from_token(svc: UserService, token: str) -> result[user_domain.UserPublic, str] {
    let ar = auth_from_token(svc, token);
    guard let row = ar else let e = err_of(ar) {
        return err(e);
    }
    return ok(user_domain.to_public(sqlite.to_user(row)));
}

pub fn user_id_from_token(svc: UserService, token: str) -> result[str, str] {
    let ar = auth_from_token(svc, token);
    guard let row = ar else let e = err_of(ar) {
        return err(e);
    }
    return ok(row.id);
}

pub fn get_public_by_username(svc: UserService, username: str) -> result[user_domain.UserProfile, str] {
    let ar = sqlite.find_auth_by_username(svc.repo, strings.trim(username));
    guard let row = ar else let e = err_of(ar) {
        return err(e);
    }
    if row.deactivated_at != 0 {
        return err(shared.not_found);
    }
    // Limited public card always (even if is_private) for now.
    return ok(user_domain.to_profile(sqlite.to_user(row)));
}

pub fn update_profile(svc: UserService, token: str, display_name: opt[str], bio: opt[str], website: opt[str], location: opt[str], pronouns: opt[str], username: opt[str]) -> result[user_domain.UserPublic, str] {
    let ar = auth_from_token(svc, token);
    guard let row = ar else let e = err_of(ar) {
        return err(e);
    }
    let dn2 = display_name ?? row.display_name;
    let b2 = bio ?? row.bio;
    let w2 = website ?? row.website;
    let loc2 = location ?? row.location;
    let prn2 = pronouns ?? row.pronouns;
    let cand = username ?? row.username;
    let cand2 = strings.trim(cand);
    if !valid_username(cand2) {
        return err(shared.invalid_username);
    }
    if cand2 != row.username {
        let existing = sqlite.find_auth_by_username(svc.repo, cand2);
        guard let _ex = existing else let e = err_of(existing) {
            if e != shared.not_found {
                return err(e);
            }
            let now = now_secs();
            let ur = sqlite.update_profile_fields(svc.repo, row.id, dn2, b2, w2, loc2, prn2, cand2, now);
            guard let _u = ur else let e2 = err_of(ur) {
                return err(e2);
            }
            let rr = sqlite.find_auth_by_id(svc.repo, row.id);
            guard let fresh = rr else let e3 = err_of(rr) {
                return err(e3);
            }
            return ok(user_domain.to_public(sqlite.to_user(fresh)));
        }
        return err(shared.username_taken);
    }
    let now2 = now_secs();
    let ur2 = sqlite.update_profile_fields(svc.repo, row.id, dn2, b2, w2, loc2, prn2, cand2, now2);
    guard let _u2 = ur2 else let e4 = err_of(ur2) {
        return err(e4);
    }
    let rr2 = sqlite.find_auth_by_id(svc.repo, row.id);
    guard let fresh2 = rr2 else let e5 = err_of(rr2) {
        return err(e5);
    }
    return ok(user_domain.to_public(sqlite.to_user(fresh2)));
}

pub fn get_settings(svc: UserService, token: str) -> result[user_domain.UserSettings, str] {
    let ar = auth_from_token(svc, token);
    guard let row = ar else let e = err_of(ar) {
        return err(e);
    }
    return ok(user_domain.to_settings(sqlite.to_user(row)));
}

pub fn update_settings(svc: UserService, token: str, is_private: bool, show_email: bool, allow_dms: bool, notify_likes: bool, notify_follows: bool, notify_mentions: bool) -> result[user_domain.UserSettings, str] {
    let ar = auth_from_token(svc, token);
    guard let row = ar else let e = err_of(ar) {
        return err(e);
    }
    let now = now_secs();
    let ur = sqlite.update_settings_fields(svc.repo, row.id, is_private, show_email, allow_dms, notify_likes, notify_follows, notify_mentions, now);
    guard let _u = ur else let e = err_of(ur) {
        return err(e);
    }
    let rr = sqlite.find_auth_by_id(svc.repo, row.id);
    guard let fresh = rr else let e = err_of(rr) {
        return err(e);
    }
    return ok(user_domain.to_settings(sqlite.to_user(fresh)));
}

pub fn change_password(svc: UserService, token: str, current: str, new_password: str) -> result[bool, str] {
    let ar = auth_from_token(svc, token);
    guard let row = ar else let e = err_of(ar) {
        return err(e);
    }
    if len(new_password) < 8 {
        return err(shared.weak_password);
    }
    if !shared.verify_password(svc.pepper, current, row.password_salt, row.password_hash) {
        return err(shared.invalid_credentials);
    }
    let hr = shared.hash_password(svc.pepper, new_password);
    guard let parts = hr else let e = err_of(hr) {
        return err(e);
    }
    return sqlite.update_password(svc.repo, row.id, parts[1], parts[0], now_secs());
}

pub fn change_email(svc: UserService, token: str, new_email: str, password: str) -> result[bool, str] {
    let ar = auth_from_token(svc, token);
    guard let row = ar else let e = err_of(ar) {
        return err(e);
    }
    let email_addr = strings.trim(new_email);
    if !valid_email(email_addr) {
        return err(shared.invalid_email);
    }
    if !shared.verify_password(svc.pepper, password, row.password_salt, row.password_hash) {
        return err(shared.invalid_credentials);
    }
    let existing = sqlite.find_auth_by_email(svc.repo, email_addr);
    guard let _ex = existing else let e = err_of(existing) {
        if e != shared.not_found {
            return err(e);
        }
        let ur = sqlite.update_email(svc.repo, row.id, email_addr, now_secs());
        guard let _u = ur else let e2 = err_of(ur) {
            return err(e2);
        }
        return issue_verification(svc, row.id, email_addr);
    }
    if _ex.id != row.id {
        return err(shared.email_taken);
    }
    return ok(true);
}

fn is_jpeg(b: bytes) -> bool {
    return len(b) >= 2 && b[0] == 255 && b[1] == 216;
}

fn is_png(b: bytes) -> bool {
    return len(b) >= 4 && b[0] == 137 && b[1] == 80 && b[2] == 78 && b[3] == 71;
}

pub fn set_avatar(svc: UserService, token: str, data: bytes, content_type: str) -> result[user_domain.UserPublic, str] {
    let ar = auth_from_token(svc, token);
    guard let row = ar else let e = err_of(ar) {
        return err(e);
    }
    if len(data) == 0 || len(data) > 2097152 {
        return err(shared.invalid_avatar);
    }
    let ct = strings.to_lower(strings.trim(content_type));
    let ext = "";
    if ct == "image/jpeg" || ct == "image/jpg" {
        if !is_jpeg(data) {
            return err(shared.invalid_avatar);
        }
        ext = "jpg";
    } else if ct == "image/png" {
        if !is_png(data) {
            return err(shared.invalid_avatar);
        }
        ext = "png";
    } else {
        return err(shared.invalid_avatar);
    }
    let wr = storage.write_avatar(svc.upload_dir, row.id, ext, data);
    guard let path = wr else let e = err_of(wr) {
        return err(e);
    }
    let ur = sqlite.set_avatar_path(svc.repo, row.id, path, now_secs());
    guard let _u = ur else let e = err_of(ur) {
        return err(e);
    }
    let rr = sqlite.find_auth_by_id(svc.repo, row.id);
    guard let fresh = rr else let e = err_of(rr) {
        return err(e);
    }
    return ok(user_domain.to_public(sqlite.to_user(fresh)));
}

pub fn clear_avatar(svc: UserService, token: str) -> result[user_domain.UserPublic, str] {
    let ar = auth_from_token(svc, token);
    guard let row = ar else let e = err_of(ar) {
        return err(e);
    }
    if len(row.avatar_path) > 0 {
        let dr = storage.delete_file(row.avatar_path);
        guard let _d = dr else let e = err_of(dr) {
            let _discard_del = e;
        }
    }
    let ur = sqlite.set_avatar_path(svc.repo, row.id, "", now_secs());
    guard let _u = ur else let e = err_of(ur) {
        return err(e);
    }
    let rr = sqlite.find_auth_by_id(svc.repo, row.id);
    guard let fresh = rr else let e = err_of(rr) {
        return err(e);
    }
    return ok(user_domain.to_public(sqlite.to_user(fresh)));
}

pub struct AvatarBlob {
    content_type: str,
    data: bytes
}

pub fn get_avatar(svc: UserService, user_id: str) -> result[AvatarBlob, str] {
    let ar = sqlite.find_auth_by_id(svc.repo, user_id);
    guard let row = ar else let e = err_of(ar) {
        return err(e);
    }
    if row.deactivated_at != 0 || len(row.avatar_path) == 0 {
        return err(shared.not_found);
    }
    let rr = storage.read_file(row.avatar_path);
    guard let data = rr else let e = err_of(rr) {
        return err(e);
    }
    return ok(AvatarBlob {
        content_type: storage.content_type_for_path(row.avatar_path),
        data: data
    });
}

pub fn logout(svc: UserService, token: str) -> result[bool, str] {
    let thr = token_hash_of(svc, token);
    guard let token_hash = thr else let e = err_of(thr) {
        return err(e);
    }
    return sqlite.revoke_session(svc.repo, token_hash, now_secs());
}

pub fn deactivate(svc: UserService, token: str, password: str) -> result[bool, str] {
    let ar = auth_from_token(svc, token);
    guard let row = ar else let e = err_of(ar) {
        return err(e);
    }
    if !shared.verify_password(svc.pepper, password, row.password_salt, row.password_hash) {
        return err(shared.invalid_credentials);
    }
    let now = now_secs();
    let dr = sqlite.deactivate_user(svc.repo, row.id, now);
    guard let _d = dr else let e = err_of(dr) {
        return err(e);
    }
    return sqlite.revoke_all_sessions(svc.repo, row.id, now);
}

pub fn last_dev_code(svc: UserService) -> str {
    return svc.mailer.last_code;
}

fn deliver_password_reset_email(mailer: email.Mailer, to_email: str, code: str) {
    let r = email.send_password_reset(mailer, to_email, code);
    guard let _ok = r else let e = err_of(r) {
        log.warn("password reset email failed for " + to_email + ": " + e);
        return;
    }
}

pub fn forgot_password(svc: UserService, email_raw: str) -> result[bool, str] {
    let email_addr = strings.trim(email_raw);
    if !valid_email(email_addr) {
        // Still generic — but invalid_email is useful for malformed input
        return err(shared.invalid_email);
    }
    let ar = sqlite.find_auth_by_email(svc.repo, email_addr);
    guard let row = ar else let e = err_of(ar) {
        if e == shared.not_found {
            return ok(true);
        }
        return err(e);
    }
    if row.deactivated_at != 0 {
        return ok(true);
    }
    let cr = six_digit_code();
    guard let code = cr else let e = err_of(cr) {
        return err(e);
    }
    let idr = shared.new_id();
    guard let rid = idr else let e = err_of(idr) {
        return err(e);
    }
    let now = now_secs();
    let code_hash = shared.hmac_str_hex(svc.pepper, code);
    let ir = sqlite.insert_password_reset(svc.repo, rid, row.id, code_hash, now + 900, now);
    guard let _ok = ir else let e = err_of(ir) {
        return err(e);
    }
    svc.mailer.last_code = code;
    spawn deliver_password_reset_email(svc.mailer, email_addr, code);
    return ok(true);
}

pub fn reset_password(svc: UserService, email_raw: str, code_raw: str, new_password: str) -> result[bool, str] {
    let email_addr = strings.trim(email_raw);
    let code = strings.trim(code_raw);
    if !valid_email(email_addr) {
        return err(shared.invalid_email);
    }
    if len(code) != 6 {
        return err(shared.invalid_code);
    }
    if len(new_password) < 8 {
        return err(shared.weak_password);
    }
    let ar = sqlite.find_auth_by_email(svc.repo, email_addr);
    guard let row = ar else let e = err_of(ar) {
        if e == shared.not_found {
            return err(shared.invalid_code);
        }
        return err(e);
    }
    let now = now_secs();
    let code_hash = shared.hmac_str_hex(svc.pepper, code);
    let rr = sqlite.find_open_password_reset(svc.repo, row.id, code_hash, now);
    guard let rid = rr else let e = err_of(rr) {
        if e == shared.invalid_argument || e == shared.not_found {
            return err(shared.invalid_code);
        }
        return err(e);
    }
    let hr = shared.hash_password(svc.pepper, new_password);
    guard let parts = hr else let e = err_of(hr) {
        return err(e);
    }
    let ur = sqlite.update_password(svc.repo, row.id, parts[1], parts[0], now);
    guard let _u = ur else let e = err_of(ur) {
        return err(e);
    }
    let cr = sqlite.consume_password_reset(svc.repo, rid, now);
    guard let _c = cr else let e = err_of(cr) {
        return err(e);
    }
    let _rev = sqlite.revoke_all_sessions(svc.repo, row.id, now);
    return ok(true);
}

pub fn sweep_expired_sessions(svc: UserService) -> result[int, str] {
    return sqlite.purge_expired_sessions(svc.repo, now_secs());
}
