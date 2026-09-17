import "sql";
import "strings";
import "../../domain/user" as user_domain;
import "../../shared";

pub gc struct SqliteUserRepo {
    db: rawptr
}

// Internal row including secrets — never JSON-encoded to clients.
pub struct AuthRow {
    id: str,
    email: str,
    username: str,
    password_hash: str,
    password_salt: str,
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
    created_at: int,
    updated_at: int,
    deactivated_at: int
}

fn select_user_cols() -> str {
    return "id, email, username, password_hash, password_salt, display_name, bio, avatar_path, website, location, pronouns, is_private, show_email, allow_dms, notify_likes, notify_follows, notify_mentions, email_verified, created_at, updated_at, deactivated_at";
}

pub fn new_user_repo(db: rawptr) -> SqliteUserRepo {
    return SqliteUserRepo { db: db };
}

pub fn as_user_port(repo: SqliteUserRepo) -> user_domain.UserRepository {
    let _discard_repo = repo;
    return user_domain.new_user_repository();
}

fn flag(st: rawptr, col: int) -> bool {
    return sql.col_int(st, col) != 0;
}

fn row_from_stmt(st: rawptr) -> AuthRow {
    return AuthRow {
        id: sql.col_text(st, 0),
        email: sql.col_text(st, 1),
        username: sql.col_text(st, 2),
        password_hash: sql.col_text(st, 3),
        password_salt: sql.col_text(st, 4),
        display_name: sql.col_text(st, 5),
        bio: sql.col_text(st, 6),
        avatar_path: sql.col_text(st, 7),
        website: sql.col_text(st, 8),
        location: sql.col_text(st, 9),
        pronouns: sql.col_text(st, 10),
        is_private: flag(st, 11),
        show_email: flag(st, 12),
        allow_dms: flag(st, 13),
        notify_likes: flag(st, 14),
        notify_follows: flag(st, 15),
        notify_mentions: flag(st, 16),
        email_verified: flag(st, 17),
        created_at: sql.col_int(st, 18),
        updated_at: sql.col_int(st, 19),
        deactivated_at: sql.col_int(st, 20)
    };
}

pub fn to_user(row: AuthRow) -> user_domain.User {
    return user_domain.User {
        id: row.id,
        email: row.email,
        username: row.username,
        display_name: row.display_name,
        bio: row.bio,
        avatar_path: row.avatar_path,
        website: row.website,
        location: row.location,
        pronouns: row.pronouns,
        is_private: row.is_private,
        show_email: row.show_email,
        allow_dms: row.allow_dms,
        notify_likes: row.notify_likes,
        notify_follows: row.notify_follows,
        notify_mentions: row.notify_mentions,
        email_verified: row.email_verified,
        created_at: row.created_at,
        updated_at: row.updated_at,
        deactivated_at: row.deactivated_at
    };
}

fn is_unique_err(e: str) -> bool {
    return strings.contains(e, "UNIQUE");
}

fn bool_i(v: bool) -> int {
    if v {
        return 1;
    }
    return 0;
}

pub fn default_auth_row(id: str, email: str, username: str, password_hash: str, password_salt: str, display_name: str, created_at: int) -> AuthRow {
    return AuthRow {
        id: id,
        email: email,
        username: username,
        password_hash: password_hash,
        password_salt: password_salt,
        display_name: display_name,
        bio: "",
        avatar_path: "",
        website: "",
        location: "",
        pronouns: "",
        is_private: false,
        show_email: false,
        allow_dms: true,
        notify_likes: true,
        notify_follows: true,
        notify_mentions: true,
        email_verified: false,
        created_at: created_at,
        updated_at: 0,
        deactivated_at: 0
    };
}

pub fn insert_user(repo: SqliteUserRepo, row: AuthRow) -> result[bool, str] {
    let pr = sql.prepare(repo.db, "INSERT INTO users (id, email, username, password_hash, password_salt, display_name, bio, avatar_path, website, location, pronouns, is_private, show_email, allow_dms, notify_likes, notify_follows, notify_mentions, email_verified, created_at, updated_at, deactivated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_text(st, 1, row.id);
    sql.bind_text(st, 2, row.email);
    sql.bind_text(st, 3, row.username);
    sql.bind_text(st, 4, row.password_hash);
    sql.bind_text(st, 5, row.password_salt);
    sql.bind_text(st, 6, row.display_name);
    sql.bind_text(st, 7, row.bio);
    sql.bind_text(st, 8, row.avatar_path);
    sql.bind_text(st, 9, row.website);
    sql.bind_text(st, 10, row.location);
    sql.bind_text(st, 11, row.pronouns);
    sql.bind_int(st, 12, bool_i(row.is_private));
    sql.bind_int(st, 13, bool_i(row.show_email));
    sql.bind_int(st, 14, bool_i(row.allow_dms));
    sql.bind_int(st, 15, bool_i(row.notify_likes));
    sql.bind_int(st, 16, bool_i(row.notify_follows));
    sql.bind_int(st, 17, bool_i(row.notify_mentions));
    sql.bind_int(st, 18, bool_i(row.email_verified));
    sql.bind_int(st, 19, row.created_at);
    sql.bind_int(st, 20, row.updated_at);
    sql.bind_int(st, 21, row.deactivated_at);
    let sr = sql.step(st);
    sql.finalize(st);
    guard let _done = sr else let e = err_of(sr) {
        if is_unique_err(e) {
            return err(shared.conflict);
        }
        return err(e);
    }
    return ok(true);
}

fn find_by_query(repo: SqliteUserRepo, q: str, arg: str) -> result[AuthRow, str] {
    let pr = sql.prepare(repo.db, q);
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_text(st, 1, arg);
    let sr = sql.step(st);
    guard let more = sr else let e = err_of(sr) {
        sql.finalize(st);
        return err(e);
    }
    if !more {
        sql.finalize(st);
        return err(shared.not_found);
    }
    let row = row_from_stmt(st);
    sql.finalize(st);
    return ok(row);
}

pub fn find_auth_by_id(repo: SqliteUserRepo, id: str) -> result[AuthRow, str] {
    return find_by_query(repo, "SELECT " + select_user_cols() + " FROM users WHERE id = ?", id);
}

pub fn find_auth_by_email(repo: SqliteUserRepo, email: str) -> result[AuthRow, str] {
    return find_by_query(repo, "SELECT " + select_user_cols() + " FROM users WHERE email = ?", email);
}

pub fn find_auth_by_username(repo: SqliteUserRepo, username: str) -> result[AuthRow, str] {
    return find_by_query(repo, "SELECT " + select_user_cols() + " FROM users WHERE username = ?", username);
}

pub fn find_user_by_id(repo: SqliteUserRepo, id: str) -> result[user_domain.User, str] {
    let rr = find_auth_by_id(repo, id);
    guard let row = rr else let e = err_of(rr) {
        return err(e);
    }
    return ok(to_user(row));
}

pub fn set_email_verified(repo: SqliteUserRepo, user_id: str) -> result[bool, str] {
    let pr = sql.prepare(repo.db, "UPDATE users SET email_verified = 1 WHERE id = ?");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_text(st, 1, user_id);
    let sr = sql.step(st);
    sql.finalize(st);
    guard let _done = sr else let e = err_of(sr) {
        return err(e);
    }
    return ok(true);
}

pub fn update_profile_fields(repo: SqliteUserRepo, user_id: str, display_name: str, bio: str, website: str, location: str, pronouns: str, username: str, updated_at: int) -> result[bool, str] {
    let pr = sql.prepare(repo.db, "UPDATE users SET display_name = ?, bio = ?, website = ?, location = ?, pronouns = ?, username = ?, updated_at = ? WHERE id = ?");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_text(st, 1, display_name);
    sql.bind_text(st, 2, bio);
    sql.bind_text(st, 3, website);
    sql.bind_text(st, 4, location);
    sql.bind_text(st, 5, pronouns);
    sql.bind_text(st, 6, username);
    sql.bind_int(st, 7, updated_at);
    sql.bind_text(st, 8, user_id);
    let sr = sql.step(st);
    sql.finalize(st);
    guard let _done = sr else let e = err_of(sr) {
        if is_unique_err(e) {
            return err(shared.conflict);
        }
        return err(e);
    }
    return ok(true);
}

pub fn update_settings_fields(repo: SqliteUserRepo, user_id: str, is_private: bool, show_email: bool, allow_dms: bool, notify_likes: bool, notify_follows: bool, notify_mentions: bool, updated_at: int) -> result[bool, str] {
    let pr = sql.prepare(repo.db, "UPDATE users SET is_private = ?, show_email = ?, allow_dms = ?, notify_likes = ?, notify_follows = ?, notify_mentions = ?, updated_at = ? WHERE id = ?");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_int(st, 1, bool_i(is_private));
    sql.bind_int(st, 2, bool_i(show_email));
    sql.bind_int(st, 3, bool_i(allow_dms));
    sql.bind_int(st, 4, bool_i(notify_likes));
    sql.bind_int(st, 5, bool_i(notify_follows));
    sql.bind_int(st, 6, bool_i(notify_mentions));
    sql.bind_int(st, 7, updated_at);
    sql.bind_text(st, 8, user_id);
    let sr = sql.step(st);
    sql.finalize(st);
    guard let _done = sr else let e = err_of(sr) {
        return err(e);
    }
    return ok(true);
}

pub fn update_password(repo: SqliteUserRepo, user_id: str, password_hash: str, password_salt: str, updated_at: int) -> result[bool, str] {
    let pr = sql.prepare(repo.db, "UPDATE users SET password_hash = ?, password_salt = ?, updated_at = ? WHERE id = ?");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_text(st, 1, password_hash);
    sql.bind_text(st, 2, password_salt);
    sql.bind_int(st, 3, updated_at);
    sql.bind_text(st, 4, user_id);
    let sr = sql.step(st);
    sql.finalize(st);
    guard let _done = sr else let e = err_of(sr) {
        return err(e);
    }
    return ok(true);
}

pub fn update_email(repo: SqliteUserRepo, user_id: str, email: str, updated_at: int) -> result[bool, str] {
    let pr = sql.prepare(repo.db, "UPDATE users SET email = ?, email_verified = 0, updated_at = ? WHERE id = ?");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_text(st, 1, email);
    sql.bind_int(st, 2, updated_at);
    sql.bind_text(st, 3, user_id);
    let sr = sql.step(st);
    sql.finalize(st);
    guard let _done = sr else let e = err_of(sr) {
        if is_unique_err(e) {
            return err(shared.conflict);
        }
        return err(e);
    }
    return ok(true);
}

pub fn set_avatar_path(repo: SqliteUserRepo, user_id: str, avatar_path: str, updated_at: int) -> result[bool, str] {
    let pr = sql.prepare(repo.db, "UPDATE users SET avatar_path = ?, updated_at = ? WHERE id = ?");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_text(st, 1, avatar_path);
    sql.bind_int(st, 2, updated_at);
    sql.bind_text(st, 3, user_id);
    let sr = sql.step(st);
    sql.finalize(st);
    guard let _done = sr else let e = err_of(sr) {
        return err(e);
    }
    return ok(true);
}

pub fn deactivate_user(repo: SqliteUserRepo, user_id: str, deactivated_at: int) -> result[bool, str] {
    let pr = sql.prepare(repo.db, "UPDATE users SET deactivated_at = ?, updated_at = ? WHERE id = ?");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_int(st, 1, deactivated_at);
    sql.bind_int(st, 2, deactivated_at);
    sql.bind_text(st, 3, user_id);
    let sr = sql.step(st);
    sql.finalize(st);
    guard let _done = sr else let e = err_of(sr) {
        return err(e);
    }
    return ok(true);
}

pub fn insert_verification(repo: SqliteUserRepo, id: str, user_id: str, code_hash: str, expires_at: int, created_at: int) -> result[bool, str] {
    let pr = sql.prepare(repo.db, "INSERT INTO email_verifications (id, user_id, code_hash, expires_at, consumed_at, created_at) VALUES (?, ?, ?, ?, NULL, ?)");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_text(st, 1, id);
    sql.bind_text(st, 2, user_id);
    sql.bind_text(st, 3, code_hash);
    sql.bind_int(st, 4, expires_at);
    sql.bind_int(st, 5, created_at);
    let sr = sql.step(st);
    sql.finalize(st);
    guard let _done = sr else let e = err_of(sr) {
        return err(e);
    }
    return ok(true);
}

pub fn find_open_verification(repo: SqliteUserRepo, user_id: str, code_hash: str, now: int) -> result[str, str] {
    let pr = sql.prepare(repo.db, "SELECT id FROM email_verifications WHERE user_id = ? AND code_hash = ? AND consumed_at IS NULL AND expires_at >= ? ORDER BY created_at DESC LIMIT 1");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_text(st, 1, user_id);
    sql.bind_text(st, 2, code_hash);
    sql.bind_int(st, 3, now);
    let sr = sql.step(st);
    guard let more = sr else let e = err_of(sr) {
        sql.finalize(st);
        return err(e);
    }
    if !more {
        sql.finalize(st);
        return err(shared.invalid_argument);
    }
    let vid = sql.col_text(st, 0);
    sql.finalize(st);
    return ok(vid);
}

pub fn consume_verification(repo: SqliteUserRepo, id: str, now: int) -> result[bool, str] {
    let pr = sql.prepare(repo.db, "UPDATE email_verifications SET consumed_at = ? WHERE id = ?");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_int(st, 1, now);
    sql.bind_text(st, 2, id);
    let sr = sql.step(st);
    sql.finalize(st);
    guard let _done = sr else let e = err_of(sr) {
        return err(e);
    }
    return ok(true);
}

pub fn insert_session(repo: SqliteUserRepo, id: str, user_id: str, token_hash: str, expires_at: int, created_at: int) -> result[bool, str] {
    let pr = sql.prepare(repo.db, "INSERT INTO sessions (id, user_id, token_hash, expires_at, created_at, revoked_at) VALUES (?, ?, ?, ?, ?, NULL)");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_text(st, 1, id);
    sql.bind_text(st, 2, user_id);
    sql.bind_text(st, 3, token_hash);
    sql.bind_int(st, 4, expires_at);
    sql.bind_int(st, 5, created_at);
    let sr = sql.step(st);
    sql.finalize(st);
    guard let _done = sr else let e = err_of(sr) {
        return err(e);
    }
    return ok(true);
}

pub fn find_session_user(repo: SqliteUserRepo, token_hash: str, now: int) -> result[AuthRow, str] {
    let pr = sql.prepare(repo.db, "SELECT u.id, u.email, u.username, u.password_hash, u.password_salt, u.display_name, u.bio, u.avatar_path, u.website, u.location, u.pronouns, u.is_private, u.show_email, u.allow_dms, u.notify_likes, u.notify_follows, u.notify_mentions, u.email_verified, u.created_at, u.updated_at, u.deactivated_at FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token_hash = ? AND s.revoked_at IS NULL AND s.expires_at >= ? LIMIT 1");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_text(st, 1, token_hash);
    sql.bind_int(st, 2, now);
    let sr = sql.step(st);
    guard let more = sr else let e = err_of(sr) {
        sql.finalize(st);
        return err(e);
    }
    if !more {
        sql.finalize(st);
        return err(shared.unauthorized);
    }
    let row = row_from_stmt(st);
    sql.finalize(st);
    return ok(row);
}

pub fn revoke_session(repo: SqliteUserRepo, token_hash: str, now: int) -> result[bool, str] {
    let pr = sql.prepare(repo.db, "UPDATE sessions SET revoked_at = ? WHERE token_hash = ? AND revoked_at IS NULL");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_int(st, 1, now);
    sql.bind_text(st, 2, token_hash);
    let sr = sql.step(st);
    sql.finalize(st);
    guard let _done = sr else let e = err_of(sr) {
        return err(e);
    }
    return ok(true);
}

pub fn revoke_all_sessions(repo: SqliteUserRepo, user_id: str, now: int) -> result[bool, str] {
    let pr = sql.prepare(repo.db, "UPDATE sessions SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_int(st, 1, now);
    sql.bind_text(st, 2, user_id);
    let sr = sql.step(st);
    sql.finalize(st);
    guard let _done = sr else let e = err_of(sr) {
        return err(e);
    }
    return ok(true);
}
