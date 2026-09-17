import "encoding";
import "http";
import "json";
import "../../application/user" as user_app;
import "../../shared";

gc struct ProfileDto {
    id: str,
    username: str,
    display_name: str,
    bio: str,
    avatar_path: str,
    website: str,
    location: str,
    pronouns: str,
    is_private: bool,
    created_at: i64
}

gc struct SettingsDto {
    is_private: bool,
    show_email: bool,
    allow_dms: bool,
    notify_likes: bool,
    notify_follows: bool,
    notify_mentions: bool
}

gc struct ProfilePatch {
    display_name: opt[str],
    bio: opt[str],
    website: opt[str],
    location: opt[str],
    pronouns: opt[str],
    username: opt[str]
}

gc struct SettingsPatch {
    is_private: bool,
    show_email: bool,
    allow_dms: bool,
    notify_likes: bool,
    notify_follows: bool,
    notify_mentions: bool
}

gc struct PasswordReq {
    current_password: str,
    new_password: str
}

gc struct EmailReq {
    email: str,
    password: str
}

gc struct DeactivateReq {
    password: str
}

gc struct AvatarReq {
    content_type: str,
    data_base64: str
}

pub fn users_collection_path() -> str {
    return "/users";
}

pub fn handle_get_user(svc: user_app.UserService, username: str) -> http.Response {
    let rr = user_app.get_public_by_username(svc, username);
    guard let p = rr else let e = err_of(rr) {
        return map_err(e);
    }
    let dto = ProfileDto {
        id: p.id,
        username: p.username,
        display_name: p.display_name,
        bio: p.bio,
        avatar_path: p.avatar_path,
        website: p.website,
        location: p.location,
        pronouns: p.pronouns,
        is_private: p.is_private,
        created_at: p.created_at
    };
    return http.ok_json(json.encode(dto));
}

pub fn handle_patch_profile(svc: user_app.UserService, req: http.Request) -> http.Response {
    let token = bearer_token(req);
    let dr: result[ProfilePatch, str] = json.decode(req.body);
    guard let body = dr else let e = err_of(dr) {
        return bad_request_json(shared.invalid_json);
    }
    let rr = user_app.update_profile(svc, token, body.display_name, body.bio, body.website, body.location, body.pronouns, body.username);
    guard let u = rr else let e = err_of(rr) {
        return map_err(e);
    }
    return http.ok_json(me_dto_json(u.id, u.email, u.username, u.display_name, u.bio, u.avatar_path, u.website, u.location, u.pronouns, u.is_private, u.show_email, u.allow_dms, u.notify_likes, u.notify_follows, u.notify_mentions, u.email_verified, u.created_at, u.updated_at, u.deactivated_at));
}

pub fn handle_get_settings(svc: user_app.UserService, req: http.Request) -> http.Response {
    let token = bearer_token(req);
    let rr = user_app.get_settings(svc, token);
    guard let s = rr else let e = err_of(rr) {
        return map_err(e);
    }
    let dto = SettingsDto {
        is_private: s.is_private,
        show_email: s.show_email,
        allow_dms: s.allow_dms,
        notify_likes: s.notify_likes,
        notify_follows: s.notify_follows,
        notify_mentions: s.notify_mentions
    };
    return http.ok_json(json.encode(dto));
}

pub fn handle_patch_settings(svc: user_app.UserService, req: http.Request) -> http.Response {
    let token = bearer_token(req);
    let dr: result[SettingsPatch, str] = json.decode(req.body);
    guard let body = dr else let e = err_of(dr) {
        return bad_request_json(shared.invalid_json);
    }
    let rr = user_app.update_settings(svc, token, body.is_private, body.show_email, body.allow_dms, body.notify_likes, body.notify_follows, body.notify_mentions);
    guard let s = rr else let e = err_of(rr) {
        return map_err(e);
    }
    let dto = SettingsDto {
        is_private: s.is_private,
        show_email: s.show_email,
        allow_dms: s.allow_dms,
        notify_likes: s.notify_likes,
        notify_follows: s.notify_follows,
        notify_mentions: s.notify_mentions
    };
    return http.ok_json(json.encode(dto));
}

pub fn handle_put_avatar(svc: user_app.UserService, req: http.Request) -> http.Response {
    let token = bearer_token(req);
    let dr: result[AvatarReq, str] = json.decode(req.body);
    guard let body = dr else let e = err_of(dr) {
        return bad_request_json(shared.invalid_json);
    }
    let br = encoding.base64_decode(body.data_base64);
    guard let data = br else let e = err_of(br) {
        return bad_request_json(shared.invalid_base64);
    }
    let rr = user_app.set_avatar(svc, token, data, body.content_type);
    guard let u = rr else let e = err_of(rr) {
        return map_err(e);
    }
    return http.ok_json(me_dto_json(u.id, u.email, u.username, u.display_name, u.bio, u.avatar_path, u.website, u.location, u.pronouns, u.is_private, u.show_email, u.allow_dms, u.notify_likes, u.notify_follows, u.notify_mentions, u.email_verified, u.created_at, u.updated_at, u.deactivated_at));
}

pub fn handle_delete_avatar(svc: user_app.UserService, req: http.Request) -> http.Response {
    let token = bearer_token(req);
    let rr = user_app.clear_avatar(svc, token);
    guard let u = rr else let e = err_of(rr) {
        return map_err(e);
    }
    return http.ok_json(me_dto_json(u.id, u.email, u.username, u.display_name, u.bio, u.avatar_path, u.website, u.location, u.pronouns, u.is_private, u.show_email, u.allow_dms, u.notify_likes, u.notify_follows, u.notify_mentions, u.email_verified, u.created_at, u.updated_at, u.deactivated_at));
}

pub fn handle_get_avatar(svc: user_app.UserService, user_id: str) -> http.Response {
    let rr = user_app.get_avatar(svc, user_id);
    guard let blob = rr else let e = err_of(rr) {
        return map_err(e);
    }
    let headers: map[str]str = {};
    headers["content-type"] = blob.content_type;
    return http.Response {
        status: 200,
        status_text: "OK",
        headers: headers,
        body: blob.data
    };
}

pub fn handle_change_password(svc: user_app.UserService, req: http.Request) -> http.Response {
    let token = bearer_token(req);
    let dr: result[PasswordReq, str] = json.decode(req.body);
    guard let body = dr else let e = err_of(dr) {
        return bad_request_json(shared.invalid_json);
    }
    let rr = user_app.change_password(svc, token, body.current_password, body.new_password);
    guard let _ok = rr else let e = err_of(rr) {
        return map_err(e);
    }
    return http.ok_json(json.encode(OkBody { ok: true }));
}

pub fn handle_change_email(svc: user_app.UserService, req: http.Request) -> http.Response {
    let token = bearer_token(req);
    let dr: result[EmailReq, str] = json.decode(req.body);
    guard let body = dr else let e = err_of(dr) {
        return bad_request_json(shared.invalid_json);
    }
    let rr = user_app.change_email(svc, token, body.email, body.password);
    guard let _ok = rr else let e = err_of(rr) {
        return map_err(e);
    }
    return http.ok_json(json.encode(OkBody { ok: true }));
}

pub fn handle_deactivate(svc: user_app.UserService, req: http.Request) -> http.Response {
    let token = bearer_token(req);
    let dr: result[DeactivateReq, str] = json.decode(req.body);
    guard let body = dr else let e = err_of(dr) {
        return bad_request_json(shared.invalid_json);
    }
    let rr = user_app.deactivate(svc, token, body.password);
    guard let _ok = rr else let e = err_of(rr) {
        return map_err(e);
    }
    return http.ok_json(json.encode(OkBody { ok: true }));
}
