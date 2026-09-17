import "time";
import "strings";
import "../../domain/social" as social_domain;
import "../../domain/user" as user_domain;
import "../../infrastructure/sqlite" as sqlite;
import "../../shared";

pub gc struct SocialService {
    repo: sqlite.SqliteSocialRepo,
    users: sqlite.SqliteUserRepo,
    posts: sqlite.SqlitePostRepo
}

pub fn new_service(repo: sqlite.SqliteSocialRepo, users: sqlite.SqliteUserRepo, posts: sqlite.SqlitePostRepo) -> SocialService {
    return SocialService { repo: repo, users: users, posts: posts };
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

pub fn follow(svc: SocialService, follower_id: str, username: str) -> result[social_domain.Follow, str] {
    let tr = resolve_active_user(svc, username);
    guard let target = tr else let e = err_of(tr) {
        return err(e);
    }
    if follower_id == target.id {
        return err(shared.cannot_follow_self);
    }
    let now = now_secs();
    let fr = social_domain.new_follow(follower_id, target.id, now);
    guard let _v = fr else let e = err_of(fr) {
        return err(e);
    }
    return sqlite.insert_follow(svc.repo, follower_id, target.id, now);
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
    guard let _p = pr else let e = err_of(pr) {
        return err(e);
    }
    let now = now_secs();
    let lr = social_domain.new_like(user_id, post_id, now);
    guard let _v = lr else let e = err_of(lr) {
        return err(e);
    }
    return sqlite.insert_like(svc.repo, user_id, post_id, now);
}

pub fn unlike(svc: SocialService, user_id: str, post_id: str) -> result[bool, str] {
    let pr = sqlite.find_post_by_id(svc.posts, post_id);
    guard let _p = pr else let e = err_of(pr) {
        return err(e);
    }
    return sqlite.delete_like(svc.repo, user_id, post_id);
}
