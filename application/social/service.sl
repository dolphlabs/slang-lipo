import "json";
import "time";
import "strings";
import "../../domain/social" as social_domain;
import "../../domain/user" as user_domain;
import "../../infrastructure/sqlite" as sqlite;
import "../../infrastructure/ws" as wshub;
import "../../shared";

pub gc struct SocialService {
    repo: sqlite.SqliteSocialRepo,
    users: sqlite.SqliteUserRepo,
    posts: sqlite.SqlitePostRepo,
    hub: wshub.Hub
}

pub fn new_service(repo: sqlite.SqliteSocialRepo, users: sqlite.SqliteUserRepo, posts: sqlite.SqlitePostRepo, hub: wshub.Hub) -> SocialService {
    return SocialService { repo: repo, users: users, posts: posts, hub: hub };
}

fn now_secs() -> int {
    return time.wall() / 1000000000;
}

fn resolve_active_user(svc: SocialService, username: str) -> result[sqlite.AuthRow, str] {
    let ur = sqlite.find_auth_by_username(svc.users, strings.trim(username));
    guard let row = ur else let e = err_of(ur) {
        return err(e);
    }
    if row.deactivated_at != 0 {
        return err(shared.not_found);
    }
    return ok(row);
}

fn clamp_limit(limit_raw: int) -> int {
    let limit = limit_raw;
    if limit <= 0 {
        limit = 50;
    }
    if limit > 100 {
        limit = 100;
    }
    return limit;
}

gc struct FollowedPayload {
    follower_id: str,
    follower_username: str,
    followee_id: str
}

gc struct LikedPayload {
    post_id: str,
    liker_id: str,
    like_count: i64
}

pub fn follow(svc: SocialService, follower_id: str, username: str) -> result[social_domain.Follow, str] {
    let tr = resolve_active_user(svc, username);
    guard let target = tr else let e = err_of(tr) {
        return err(e);
    }
    if follower_id == target.id {
        return err(shared.cannot_follow_self);
    }
    let already = sqlite.is_following(svc.repo, follower_id, target.id);
    let was_new = true;
    guard let following = already else let e = err_of(already) {
        return err(e);
    }
    if following {
        was_new = false;
    }
    let now = now_secs();
    let fr = social_domain.new_follow(follower_id, target.id, now);
    guard let _v = fr else let e = err_of(fr) {
        return err(e);
    }
    let ir = sqlite.insert_follow(svc.repo, follower_id, target.id, now);
    guard let f = ir else let e = err_of(ir) {
        return err(e);
    }
    if !was_new {
        return ok(f);
    }
    let ar = sqlite.find_auth_by_id(svc.users, follower_id);
    let follower_username = "";
    guard let row = ar else let e = err_of(ar) {
        let _discard = e;
        follower_username = "";
        let payload = FollowedPayload {
            follower_id: follower_id,
            follower_username: follower_username,
            followee_id: target.id
        };
        let text = "{\"type\":\"user.followed\",\"payload\":" + json.encode(payload) + "}";
        wshub.publish(svc.hub, target.id, text);
        return ok(f);
    }
    let payload2 = FollowedPayload {
        follower_id: follower_id,
        follower_username: row.username,
        followee_id: target.id
    };
    let text2 = "{\"type\":\"user.followed\",\"payload\":" + json.encode(payload2) + "}";
    wshub.publish(svc.hub, target.id, text2);
    return ok(f);
}

pub fn unfollow(svc: SocialService, follower_id: str, username: str) -> result[bool, str] {
    let tr = resolve_active_user(svc, username);
    guard let target = tr else let e = err_of(tr) {
        return err(e);
    }
    return sqlite.delete_follow(svc.repo, follower_id, target.id);
}

pub fn following_status(svc: SocialService, requester_id: str, username: str) -> result[bool, str] {
    let tr = resolve_active_user(svc, username);
    guard let target = tr else let e = err_of(tr) {
        return err(e);
    }
    if len(requester_id) == 0 {
        return ok(false);
    }
    return sqlite.is_following(svc.repo, requester_id, target.id);
}

pub fn list_followers(svc: SocialService, username: str, limit_raw: int) -> result[[user_domain.UserProfile], str] {
    let tr = resolve_active_user(svc, username);
    guard let target = tr else let e = err_of(tr) {
        return err(e);
    }
    return sqlite.list_followers(svc.repo, target.id, clamp_limit(limit_raw));
}

pub fn list_following(svc: SocialService, username: str, limit_raw: int) -> result[[user_domain.UserProfile], str] {
    let tr = resolve_active_user(svc, username);
    guard let target = tr else let e = err_of(tr) {
        return err(e);
    }
    return sqlite.list_following(svc.repo, target.id, clamp_limit(limit_raw));
}

pub fn like(svc: SocialService, user_id: str, post_id: str) -> result[social_domain.Like, str] {
    let pr = sqlite.find_post_by_id(svc.posts, post_id);
    guard let post = pr else let e = err_of(pr) {
        return err(e);
    }
    let now = now_secs();
    let lr = social_domain.new_like(user_id, post_id, now);
    guard let _v = lr else let e = err_of(lr) {
        return err(e);
    }
    let ir = sqlite.insert_like(svc.repo, user_id, post_id, now);
    guard let like_row = ir else let e = err_of(ir) {
        return err(e);
    }
    let fr = sqlite.find_post_by_id(svc.posts, post_id);
    let like_count: i64 = (post.like_count + 1) as i64;
    guard let fresh = fr else let e = err_of(fr) {
        let _discard = e;
        let payload = LikedPayload {
            post_id: post_id,
            liker_id: user_id,
            like_count: like_count
        };
        let text = "{\"type\":\"post.liked\",\"payload\":" + json.encode(payload) + "}";
        wshub.publish(svc.hub, post.author_id, text);
        if user_id != post.author_id {
            wshub.publish(svc.hub, user_id, text);
        }
        return ok(like_row);
    }
    let payload2 = LikedPayload {
        post_id: post_id,
        liker_id: user_id,
        like_count: fresh.like_count as i64
    };
    let text2 = "{\"type\":\"post.liked\",\"payload\":" + json.encode(payload2) + "}";
    wshub.publish(svc.hub, post.author_id, text2);
    if user_id != post.author_id {
        wshub.publish(svc.hub, user_id, text2);
    }
    return ok(like_row);
}

pub fn unlike(svc: SocialService, user_id: str, post_id: str) -> result[bool, str] {
    let pr = sqlite.find_post_by_id(svc.posts, post_id);
    guard let _p = pr else let e = err_of(pr) {
        return err(e);
    }
    return sqlite.delete_like(svc.repo, user_id, post_id);
}
