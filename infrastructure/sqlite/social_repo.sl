import "sql";
import "strings";
import "../../domain/social" as social_domain;
import "../../domain/user" as user_domain;
import "../../shared";

pub gc struct SqliteSocialRepo {
    db: rawptr
}

pub fn new_social_repo(db: rawptr) -> SqliteSocialRepo {
    return SqliteSocialRepo { db: db };
}

pub fn as_social_port(repo: SqliteSocialRepo) -> social_domain.SocialRepository {
    let _discard_repo = repo;
    return social_domain.new_social_repository();
}

fn social_is_unique_err(e: str) -> bool {
    return strings.contains(e, "UNIQUE");
}

fn profile_from_stmt(st: rawptr) -> user_domain.UserProfile {
    let priv_i = sql.col_int(st, 8);
    let is_priv = false;
    if priv_i != 0 {
        is_priv = true;
    }
    return user_domain.UserProfile {
        id: sql.col_text(st, 0),
        username: sql.col_text(st, 1),
        display_name: sql.col_text(st, 2),
        bio: sql.col_text(st, 3),
        avatar_path: sql.col_text(st, 4),
        website: sql.col_text(st, 5),
        location: sql.col_text(st, 6),
        pronouns: sql.col_text(st, 7),
        is_private: is_priv,
        created_at: sql.col_int(st, 9) as i64
    };
}

pub fn find_follow(repo: SqliteSocialRepo, follower_id: str, followee_id: str) -> result[social_domain.Follow, str] {
    let pr = sql.prepare(repo.db, "SELECT follower_id, followee_id, created_at FROM follows WHERE follower_id = ? AND followee_id = ?");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_text(st, 1, follower_id);
    sql.bind_text(st, 2, followee_id);
    let sr = sql.step(st);
    guard let more = sr else let e = err_of(sr) {
        sql.finalize(st);
        return err(e);
    }
    if !more {
        sql.finalize(st);
        return err(shared.not_found);
    }
    let f = social_domain.Follow {
        follower_id: sql.col_text(st, 0),
        followee_id: sql.col_text(st, 1),
        created_at: sql.col_int(st, 2)
    };
    sql.finalize(st);
    return ok(f);
}

pub fn insert_follow(repo: SqliteSocialRepo, follower_id: str, followee_id: str, created_at: int) -> result[social_domain.Follow, str] {
    let existing = find_follow(repo, follower_id, followee_id);
    guard let _ex = existing else let e = err_of(existing) {
        if e != shared.not_found {
            return err(e);
        }
        let pr = sql.prepare(repo.db, "INSERT INTO follows (follower_id, followee_id, created_at) VALUES (?, ?, ?)");
        guard let st = pr else let e2 = err_of(pr) {
            return err(e2);
        }
        sql.bind_text(st, 1, follower_id);
        sql.bind_text(st, 2, followee_id);
        sql.bind_int(st, 3, created_at);
        let sr = sql.step(st);
        sql.finalize(st);
        guard let _done = sr else let e3 = err_of(sr) {
            if social_is_unique_err(e3) {
                return find_follow(repo, follower_id, followee_id);
            }
            return err(e3);
        }
        return ok(social_domain.Follow {
            follower_id: follower_id,
            followee_id: followee_id,
            created_at: created_at
        });
    }
    return ok(_ex);
}

pub fn delete_follow(repo: SqliteSocialRepo, follower_id: str, followee_id: str) -> result[bool, str] {
    let pr = sql.prepare(repo.db, "DELETE FROM follows WHERE follower_id = ? AND followee_id = ?");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_text(st, 1, follower_id);
    sql.bind_text(st, 2, followee_id);
    let sr = sql.step(st);
    sql.finalize(st);
    guard let _done = sr else let e = err_of(sr) {
        return err(e);
    }
    return ok(true);
}

pub fn is_following(repo: SqliteSocialRepo, follower_id: str, followee_id: str) -> result[bool, str] {
    let fr = find_follow(repo, follower_id, followee_id);
    guard let _f = fr else let e = err_of(fr) {
        if e == shared.not_found {
            return ok(false);
        }
        return err(e);
    }
    return ok(true);
}


pub fn list_follower_ids(repo: SqliteSocialRepo, followee_id: str, limit: int) -> result[[str], str] {
    let lim = limit;
    if lim <= 0 {
        lim = 500;
    }
    if lim > 2000 {
        lim = 2000;
    }
    let pr = sql.prepare(repo.db, "SELECT follower_id FROM follows WHERE followee_id = ? ORDER BY created_at DESC LIMIT ?");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_text(st, 1, followee_id);
    sql.bind_int(st, 2, lim);
    let out: [str] = [];
    while true {
        let sr = sql.step(st);
        guard let more = sr else let e = err_of(sr) {
            sql.finalize(st);
            return err(e);
        }
        if !more {
            break;
        }
        push(out, sql.col_text(st, 0));
    }
    sql.finalize(st);
    return ok(out);
}

pub fn list_followers(repo: SqliteSocialRepo, followee_id: str, limit: int) -> result[[user_domain.UserProfile], str] {
    let pr = sql.prepare(repo.db, "SELECT u.id, u.username, u.display_name, u.bio, u.avatar_path, u.website, u.location, u.pronouns, u.is_private, u.created_at FROM follows f JOIN users u ON u.id = f.follower_id WHERE f.followee_id = ? AND u.deactivated_at = 0 ORDER BY f.created_at DESC LIMIT ?");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_text(st, 1, followee_id);
    sql.bind_int(st, 2, limit);
    let out: [user_domain.UserProfile] = [];
    while true {
        let sr = sql.step(st);
        guard let more = sr else let e = err_of(sr) {
            sql.finalize(st);
            return err(e);
        }
        if !more {
            break;
        }
        push(out, profile_from_stmt(st));
    }
    sql.finalize(st);
    return ok(out);
}

pub fn list_following(repo: SqliteSocialRepo, follower_id: str, limit: int) -> result[[user_domain.UserProfile], str] {
    let pr = sql.prepare(repo.db, "SELECT u.id, u.username, u.display_name, u.bio, u.avatar_path, u.website, u.location, u.pronouns, u.is_private, u.created_at FROM follows f JOIN users u ON u.id = f.followee_id WHERE f.follower_id = ? AND u.deactivated_at = 0 ORDER BY f.created_at DESC LIMIT ?");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_text(st, 1, follower_id);
    sql.bind_int(st, 2, limit);
    let out: [user_domain.UserProfile] = [];
    while true {
        let sr = sql.step(st);
        guard let more = sr else let e = err_of(sr) {
            sql.finalize(st);
            return err(e);
        }
        if !more {
            break;
        }
        push(out, profile_from_stmt(st));
    }
    sql.finalize(st);
    return ok(out);
}

pub fn find_like(repo: SqliteSocialRepo, user_id: str, post_id: str) -> result[social_domain.Like, str] {
    let pr = sql.prepare(repo.db, "SELECT user_id, post_id, created_at FROM likes WHERE user_id = ? AND post_id = ?");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_text(st, 1, user_id);
    sql.bind_text(st, 2, post_id);
    let sr = sql.step(st);
    guard let more = sr else let e = err_of(sr) {
        sql.finalize(st);
        return err(e);
    }
    if !more {
        sql.finalize(st);
        return err(shared.not_found);
    }
    let like = social_domain.Like {
        user_id: sql.col_text(st, 0),
        post_id: sql.col_text(st, 1),
        created_at: sql.col_int(st, 2)
    };
    sql.finalize(st);
    return ok(like);
}

fn bump_like_count(repo: SqliteSocialRepo, post_id: str, delta: int) -> result[bool, str] {
    let pr = sql.prepare(repo.db, "UPDATE posts SET like_count = CASE WHEN like_count + ? < 0 THEN 0 ELSE like_count + ? END WHERE id = ?");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_int(st, 1, delta);
    sql.bind_int(st, 2, delta);
    sql.bind_text(st, 3, post_id);
    let sr = sql.step(st);
    sql.finalize(st);
    guard let _done = sr else let e = err_of(sr) {
        return err(e);
    }
    return ok(true);
}

pub fn insert_like(repo: SqliteSocialRepo, user_id: str, post_id: str, created_at: int) -> result[social_domain.Like, str] {
    let existing = find_like(repo, user_id, post_id);
    guard let _ex = existing else let e = err_of(existing) {
        if e != shared.not_found {
            return err(e);
        }
        let br = sql.exec(repo.db, "BEGIN IMMEDIATE");
        guard let _b = br else let e0 = err_of(br) {
            return err(e0);
        }
        let pr = sql.prepare(repo.db, "INSERT INTO likes (user_id, post_id, created_at) VALUES (?, ?, ?)");
        guard let st = pr else let e2 = err_of(pr) {
            let _rb = sql.exec(repo.db, "ROLLBACK");
            return err(e2);
        }
        sql.bind_text(st, 1, user_id);
        sql.bind_text(st, 2, post_id);
        sql.bind_int(st, 3, created_at);
        let sr = sql.step(st);
        sql.finalize(st);
        guard let _done = sr else let e3 = err_of(sr) {
            let _rb2 = sql.exec(repo.db, "ROLLBACK");
            if social_is_unique_err(e3) {
                return find_like(repo, user_id, post_id);
            }
            return err(e3);
        }
        let ur = bump_like_count(repo, post_id, 1);
        guard let _u = ur else let e4 = err_of(ur) {
            let _rb3 = sql.exec(repo.db, "ROLLBACK");
            return err(e4);
        }
        let cr2 = sql.exec(repo.db, "COMMIT");
        guard let _c = cr2 else let e5 = err_of(cr2) {
            return err(e5);
        }
        return ok(social_domain.Like {
            user_id: user_id,
            post_id: post_id,
            created_at: created_at
        });
    }
    return ok(_ex);
}

pub fn delete_like(repo: SqliteSocialRepo, user_id: str, post_id: str) -> result[bool, str] {
    let existing = find_like(repo, user_id, post_id);
    guard let _ex = existing else let e = err_of(existing) {
        if e == shared.not_found {
            return ok(true);
        }
        return err(e);
    }
    let br = sql.exec(repo.db, "BEGIN IMMEDIATE");
    guard let _b = br else let e0 = err_of(br) {
        return err(e0);
    }
    let pr = sql.prepare(repo.db, "DELETE FROM likes WHERE user_id = ? AND post_id = ?");
    guard let st = pr else let e2 = err_of(pr) {
        let _rb = sql.exec(repo.db, "ROLLBACK");
        return err(e2);
    }
    sql.bind_text(st, 1, user_id);
    sql.bind_text(st, 2, post_id);
    let sr = sql.step(st);
    sql.finalize(st);
    guard let _done = sr else let e3 = err_of(sr) {
        let _rb2 = sql.exec(repo.db, "ROLLBACK");
        return err(e3);
    }
    let ur = bump_like_count(repo, post_id, -1);
    guard let _u = ur else let e4 = err_of(ur) {
        let _rb3 = sql.exec(repo.db, "ROLLBACK");
        return err(e4);
    }
    let cr = sql.exec(repo.db, "COMMIT");
    guard let _c = cr else let e5 = err_of(cr) {
        return err(e5);
    }
    return ok(true);
}
