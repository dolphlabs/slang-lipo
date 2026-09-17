import "http";
import "json";
import "../../application/user" as user_app;
import "../../application/social" as social_app;
import "../../domain/social" as social_domain;
import "../../domain/user" as user_domain;

gc struct FollowDto {
    follower_id: str,
    followee_id: str,
    created_at: i64
}

gc struct LikeDto {
    user_id: str,
    post_id: str,
    created_at: i64
}

gc struct FollowingStatus {
    following: bool
}

gc struct ProfileList {
    users: [ProfileDto]
}

fn follow_dto(f: social_domain.Follow) -> FollowDto {
    return FollowDto {
        follower_id: f.follower_id,
        followee_id: f.followee_id,
        created_at: f.created_at as i64
    };
}

fn like_dto(l: social_domain.Like) -> LikeDto {
    return LikeDto {
        user_id: l.user_id,
        post_id: l.post_id,
        created_at: l.created_at as i64
    };
}

fn profile_dto_from(p: user_domain.UserProfile) -> ProfileDto {
    return ProfileDto {
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
}

fn profiles_json(list: [user_domain.UserProfile]) -> str {
    let out: [ProfileDto] = [];
    let i = 0;
    while i < len(list) {
        push(out, profile_dto_from(list[i]));
        i = i + 1;
    }
    return json.encode(ProfileList { users: out });
}

pub fn handle_follow(users: user_app.UserService, social: social_app.SocialService, req: http.Request, username: str) -> http.Response {
    let token = bearer_token(req);
    let uidr = user_app.user_id_from_token(users, token);
    guard let uid = uidr else let e = err_of(uidr) {
        return map_err(e);
    }
    let rr = social_app.follow(social, uid, username);
    guard let f = rr else let e = err_of(rr) {
        return map_err(e);
    }
    return http.ok_json(json.encode(follow_dto(f)));
}

pub fn handle_unfollow(users: user_app.UserService, social: social_app.SocialService, req: http.Request, username: str) -> http.Response {
    let token = bearer_token(req);
    let uidr = user_app.user_id_from_token(users, token);
    guard let uid = uidr else let e = err_of(uidr) {
        return map_err(e);
    }
    let rr = social_app.unfollow(social, uid, username);
    guard let _ok = rr else let e = err_of(rr) {
        return map_err(e);
    }
    return http.ok_json(json.encode(OkBody { ok: true }));
}

pub fn handle_follow_status(users: user_app.UserService, social: social_app.SocialService, req: http.Request, username: str) -> http.Response {
    let token = bearer_token(req);
    let requester = "";
    if len(token) > 0 {
        let uidr = user_app.user_id_from_token(users, token);
        guard let uid = uidr else let e = err_of(uidr) {
            return map_err(e);
        }
        requester = uid;
    }
    let rr = social_app.following_status(social, requester, username);
    guard let following = rr else let e = err_of(rr) {
        return map_err(e);
    }
    return http.ok_json(json.encode(FollowingStatus { following: following }));
}

pub fn handle_list_followers(social: social_app.SocialService, username: str) -> http.Response {
    let rr = social_app.list_followers(social, username, 50);
    guard let list = rr else let e = err_of(rr) {
        return map_err(e);
    }
    return http.ok_json(profiles_json(list));
}

pub fn handle_list_following(social: social_app.SocialService, username: str) -> http.Response {
    let rr = social_app.list_following(social, username, 50);
    guard let list = rr else let e = err_of(rr) {
        return map_err(e);
    }
    return http.ok_json(profiles_json(list));
}

pub fn handle_like(users: user_app.UserService, social: social_app.SocialService, req: http.Request, post_id: str) -> http.Response {
    let token = bearer_token(req);
    let uidr = user_app.user_id_from_token(users, token);
    guard let uid = uidr else let e = err_of(uidr) {
        return map_err(e);
    }
    let rr = social_app.like(social, uid, post_id);
    guard let l = rr else let e = err_of(rr) {
        return map_err(e);
    }
    return http.ok_json(json.encode(like_dto(l)));
}

pub fn handle_unlike(users: user_app.UserService, social: social_app.SocialService, req: http.Request, post_id: str) -> http.Response {
    let token = bearer_token(req);
    let uidr = user_app.user_id_from_token(users, token);
    guard let uid = uidr else let e = err_of(uidr) {
        return map_err(e);
    }
    let rr = social_app.unlike(social, uid, post_id);
    guard let _ok = rr else let e = err_of(rr) {
        return map_err(e);
    }
    return http.ok_json(json.encode(OkBody { ok: true }));
}
