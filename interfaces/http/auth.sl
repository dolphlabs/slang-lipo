import "http";
import "json";
import "strings";
import "../../application/user" as user_app;
import "../../shared";

gc struct SignupReq {
    email: str,
    username: str,
    password: str
}

gc struct VerifyReq {
    email: str,
    code: str
}

gc struct SigninReq {
    login: str,
    password: str
}

gc struct ErrorBody {
    error: str
}

gc struct SignupResp {
    user: UserDto,
    verification_sent: bool
}

gc struct UserDto {
    id: str,
    email: str,
    username: str,
    display_name: str,
    bio: str,
    avatar_path: str,
    website: str,
    location: str,
    pronouns: str,
    is_private: bool,
    show_email: bool,
    allow_dms: bool,
    notify_likes: bool,
    notify_follows: bool,
    notify_mentions: bool,
    email_verified: bool,
    created_at: i64,
    updated_at: i64,
    deactivated_at: i64
}

gc struct SigninResp {
    token: str,
    user: UserDto
}

gc struct OkBody {
    ok: bool
}

fn dto_from_fields(id: str, email: str, username: str, display_name: str, bio: str, avatar_path: str, website: str, location: str, pronouns: str, is_private: bool, show_email: bool, allow_dms: bool, notify_likes: bool, notify_follows: bool, notify_mentions: bool, email_verified: bool, created_at: i64, updated_at: i64, deactivated_at: i64) -> UserDto {
    return UserDto {
        id: id,
        email: email,
        username: username,
        display_name: display_name,
        bio: bio,
        avatar_path: avatar_path,
        website: website,
        location: location,
        pronouns: pronouns,
        is_private: is_private,
        show_email: show_email,
        allow_dms: allow_dms,
        notify_likes: notify_likes,
        notify_follows: notify_follows,
        notify_mentions: notify_mentions,
        email_verified: email_verified,
        created_at: created_at,
        updated_at: updated_at,
        deactivated_at: deactivated_at
    };
}

fn err_json(status: i32, status_text: str, msg: str) -> http.Response {
    let body: str = json.encode(ErrorBody { error: msg });
    return http.text_response(status, status_text, "application/json; charset=utf-8", body);
}

pub fn unauthorized_json(msg: str) -> http.Response {
    return err_json(401, "Unauthorized", msg);
}

fn conflict_json(msg: str) -> http.Response {
    return err_json(409, "Conflict", msg);
}

fn forbidden_json(msg: str) -> http.Response {
    return err_json(403, "Forbidden", msg);
}

pub fn map_err(e: str) -> http.Response {
    if e == shared.invalid_argument {
        return http.bad_request(e);
    }
    if e == shared.conflict {
        return conflict_json(e);
    }
    if e == shared.unauthorized {
        return unauthorized_json(e);
    }
    if e == shared.email_unverified {
        return forbidden_json(e);
    }
    if e == shared.forbidden {
        return forbidden_json(e);
    }
    if e == shared.not_found {
        return http.not_found();
    }
    return err_json(500, "Internal Server Error", shared.internal);
}

pub fn handle_signup(svc: user_app.UserService, req: http.Request) -> http.Response {
    let dr: result[SignupReq, str] = json.decode(req.body);
    guard let body = dr else let e = err_of(dr) {
        return http.bad_request("invalid JSON: " + e);
    }
    let rr = user_app.signup(svc, body.email, body.username, body.password);
    guard let res = rr else let e = err_of(rr) {
        return map_err(e);
    }
    let u = res.user;
    let resp = SignupResp {
        user: dto_from_fields(u.id, u.email, u.username, u.display_name, u.bio, u.avatar_path, u.website, u.location, u.pronouns, u.is_private, u.show_email, u.allow_dms, u.notify_likes, u.notify_follows, u.notify_mentions, u.email_verified, u.created_at, u.updated_at, u.deactivated_at),
        verification_sent: res.verification_sent
    };
    return http.created_json(json.encode(resp));
}

pub fn handle_verify(svc: user_app.UserService, req: http.Request) -> http.Response {
    let dr: result[VerifyReq, str] = json.decode(req.body);
    guard let body = dr else let e = err_of(dr) {
        return http.bad_request("invalid JSON: " + e);
    }
    let rr = user_app.verify_email(svc, body.email, body.code);
    guard let u = rr else let e = err_of(rr) {
        return map_err(e);
    }
    let dto = dto_from_fields(u.id, u.email, u.username, u.display_name, u.bio, u.avatar_path, u.website, u.location, u.pronouns, u.is_private, u.show_email, u.allow_dms, u.notify_likes, u.notify_follows, u.notify_mentions, u.email_verified, u.created_at, u.updated_at, u.deactivated_at);
    return http.ok_json(json.encode(dto));
}

pub fn handle_signin(svc: user_app.UserService, req: http.Request) -> http.Response {
    let dr: result[SigninReq, str] = json.decode(req.body);
    guard let body = dr else let e = err_of(dr) {
        return http.bad_request("invalid JSON: " + e);
    }
    let rr = user_app.signin(svc, body.login, body.password);
    guard let sess = rr else let e = err_of(rr) {
        return map_err(e);
    }
    let u = sess.user;
    let resp = SigninResp {
        token: sess.token,
        user: dto_from_fields(u.id, u.email, u.username, u.display_name, u.bio, u.avatar_path, u.website, u.location, u.pronouns, u.is_private, u.show_email, u.allow_dms, u.notify_likes, u.notify_follows, u.notify_mentions, u.email_verified, u.created_at, u.updated_at, u.deactivated_at)
    };
    return http.ok_json(json.encode(resp));
}

pub fn bearer_token(req: http.Request) -> str {
    let h = http.header(req, "authorization");
    guard let v = h else {
        return "";
    }
    let low = strings.to_lower(v);
    if !strings.has_prefix(low, "bearer ") {
        return "";
    }
    return strings.trim(strings.slice(v, 7, len(v)));
}

pub fn handle_me(svc: user_app.UserService, req: http.Request) -> http.Response {
    let token = bearer_token(req);
    let rr = user_app.me_from_token(svc, token);
    guard let u = rr else let e = err_of(rr) {
        return map_err(e);
    }
    let dto = dto_from_fields(u.id, u.email, u.username, u.display_name, u.bio, u.avatar_path, u.website, u.location, u.pronouns, u.is_private, u.show_email, u.allow_dms, u.notify_likes, u.notify_follows, u.notify_mentions, u.email_verified, u.created_at, u.updated_at, u.deactivated_at);
    return http.ok_json(json.encode(dto));
}

pub fn handle_logout(svc: user_app.UserService, req: http.Request) -> http.Response {
    let token = bearer_token(req);
    let rr = user_app.logout(svc, token);
    guard let _ok = rr else let e = err_of(rr) {
        return map_err(e);
    }
    return http.ok_json(json.encode(OkBody { ok: true }));
}

pub fn me_dto_json(u_id: str, email: str, username: str, display_name: str, bio: str, avatar_path: str, website: str, location: str, pronouns: str, is_private: bool, show_email: bool, allow_dms: bool, notify_likes: bool, notify_follows: bool, notify_mentions: bool, email_verified: bool, created_at: i64, updated_at: i64, deactivated_at: i64) -> str {
    return json.encode(dto_from_fields(u_id, email, username, display_name, bio, avatar_path, website, location, pronouns, is_private, show_email, allow_dms, notify_likes, notify_follows, notify_mentions, email_verified, created_at, updated_at, deactivated_at));
}
