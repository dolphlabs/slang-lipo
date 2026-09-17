// infrastructure/sqlite — DB open + schema spine.
import "sql";
import "strings";

pub fn open(path: str) -> result[rawptr, str] {
    return sql.open(path);
}

pub fn close(db: rawptr) {
    sql.close(db);
}

fn exec_one(db: rawptr, stmt: str) -> result[bool, str] {
    let er = sql.exec(db, stmt);
    guard let _n = er else let e = err_of(er) {
        return err(e);
    }
    return ok(true);
}

pub fn migrate(db: rawptr) -> result[bool, str] {
    let r0 = exec_one(db, "CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY, applied_at INTEGER NOT NULL)");
    guard let _m0 = r0 else let e = err_of(r0) {
        return err(e);
    }

    let pr = sql.prepare(db, "SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    let version = 0;
    let sr = sql.step(st);
    guard let more = sr else let e = err_of(sr) {
        sql.finalize(st);
        return err(e);
    }
    if more {
        version = sql.col_int(st, 0);
    }
    sql.finalize(st);

    if version < 2 {
        let d1 = exec_one(db, "DROP TABLE IF EXISTS users");
        guard let _d1 = d1 else let e = err_of(d1) {
            return err(e);
        }
        let stmts: [str] = [
            "CREATE TABLE users (id TEXT PRIMARY KEY, email TEXT NOT NULL UNIQUE, username TEXT NOT NULL UNIQUE, password_hash TEXT NOT NULL, password_salt TEXT NOT NULL, display_name TEXT NOT NULL DEFAULT '', bio TEXT NOT NULL DEFAULT '', email_verified INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL)",
            "CREATE TABLE IF NOT EXISTS email_verifications (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, code_hash TEXT NOT NULL, expires_at INTEGER NOT NULL, consumed_at INTEGER, created_at INTEGER NOT NULL)",
            "CREATE TABLE IF NOT EXISTS sessions (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, token_hash TEXT NOT NULL UNIQUE, expires_at INTEGER NOT NULL, created_at INTEGER NOT NULL, revoked_at INTEGER)",
            "CREATE TABLE IF NOT EXISTS posts (id TEXT PRIMARY KEY, author_id TEXT NOT NULL, body TEXT NOT NULL, created_at INTEGER NOT NULL, like_count INTEGER NOT NULL DEFAULT 0)",
            "CREATE TABLE IF NOT EXISTS follows (follower_id TEXT NOT NULL, followee_id TEXT NOT NULL, created_at INTEGER NOT NULL, PRIMARY KEY (follower_id, followee_id))",
            "CREATE TABLE IF NOT EXISTS likes (user_id TEXT NOT NULL, post_id TEXT NOT NULL, created_at INTEGER NOT NULL, PRIMARY KEY (user_id, post_id))",
            "INSERT INTO schema_migrations (version, applied_at) VALUES (2, 0)"
        ];
        let i = 0;
        while i < len(stmts) {
            let er = exec_one(db, stmts[i]);
            guard let _ok = er else let e = err_of(er) {
                return err(e);
            }
            i = i + 1;
        }
        version = 2;
    }

    // v3 profile columns. Greenfield: DROP auth tables + recreate full users
    // (keeps posts/follows/likes). Intentional for early schema churn.
    if version < 3 {
        let drops: [str] = [
            "DROP TABLE IF EXISTS email_verifications",
            "DROP TABLE IF EXISTS sessions",
            "DROP TABLE IF EXISTS users"
        ];
        let di = 0;
        while di < len(drops) {
            let dr = exec_one(db, drops[di]);
            guard let _dd = dr else let e = err_of(dr) {
                return err(e);
            }
            di = di + 1;
        }
        let stmts3: [str] = [
            "CREATE TABLE users (id TEXT PRIMARY KEY, email TEXT NOT NULL UNIQUE, username TEXT NOT NULL UNIQUE, password_hash TEXT NOT NULL, password_salt TEXT NOT NULL, display_name TEXT NOT NULL DEFAULT '', bio TEXT NOT NULL DEFAULT '', avatar_path TEXT NOT NULL DEFAULT '', website TEXT NOT NULL DEFAULT '', location TEXT NOT NULL DEFAULT '', pronouns TEXT NOT NULL DEFAULT '', is_private INTEGER NOT NULL DEFAULT 0, show_email INTEGER NOT NULL DEFAULT 0, allow_dms INTEGER NOT NULL DEFAULT 1, notify_likes INTEGER NOT NULL DEFAULT 1, notify_follows INTEGER NOT NULL DEFAULT 1, notify_mentions INTEGER NOT NULL DEFAULT 1, email_verified INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL DEFAULT 0, deactivated_at INTEGER NOT NULL DEFAULT 0)",
            "CREATE TABLE email_verifications (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, code_hash TEXT NOT NULL, expires_at INTEGER NOT NULL, consumed_at INTEGER, created_at INTEGER NOT NULL)",
            "CREATE TABLE sessions (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, token_hash TEXT NOT NULL UNIQUE, expires_at INTEGER NOT NULL, created_at INTEGER NOT NULL, revoked_at INTEGER)",
            "CREATE TABLE IF NOT EXISTS posts (id TEXT PRIMARY KEY, author_id TEXT NOT NULL, body TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL DEFAULT 0, like_count INTEGER NOT NULL DEFAULT 0)",
            "CREATE TABLE IF NOT EXISTS follows (follower_id TEXT NOT NULL, followee_id TEXT NOT NULL, created_at INTEGER NOT NULL, PRIMARY KEY (follower_id, followee_id))",
            "CREATE TABLE IF NOT EXISTS likes (user_id TEXT NOT NULL, post_id TEXT NOT NULL, created_at INTEGER NOT NULL, PRIMARY KEY (user_id, post_id))",
            "INSERT INTO schema_migrations (version, applied_at) VALUES (3, 0)"
        ];
        let j = 0;
        while j < len(stmts3) {
            let er = exec_one(db, stmts3[j]);
            guard let _ok3 = er else let e = err_of(er) {
                return err(e);
            }
            j = j + 1;
        }
        // v2 posts lacked updated_at; ADD COLUMN if CREATE IF NOT EXISTS kept old table.
        let ar = exec_one(db, "ALTER TABLE posts ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0");
        guard let _alt = ar else let e = err_of(ar) {
            if !strings.contains(e, "duplicate column") {
                return err(e);
            }
        }
        version = 3;
    }

    // v4: 1:1 DM conversations + messages
    if version < 4 {
        let stmts4: [str] = [
            "CREATE TABLE IF NOT EXISTS conversations (id TEXT PRIMARY KEY, user_a_id TEXT NOT NULL, user_b_id TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, UNIQUE(user_a_id, user_b_id), CHECK(user_a_id < user_b_id))",
            "CREATE TABLE IF NOT EXISTS messages (id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL, sender_id TEXT NOT NULL, body TEXT NOT NULL, created_at INTEGER NOT NULL)",
            "CREATE INDEX IF NOT EXISTS idx_messages_conv_created ON messages (conversation_id, created_at DESC, id DESC)",
            "CREATE INDEX IF NOT EXISTS idx_conversations_updated ON conversations (updated_at DESC)",
            "INSERT INTO schema_migrations (version, applied_at) VALUES (4, 0)"
        ];
        let k = 0;
        while k < len(stmts4) {
            let er4 = exec_one(db, stmts4[k]);
            guard let _ok4 = er4 else let e = err_of(er4) {
                return err(e);
            }
            k = k + 1;
        }
    }

    // v5: conversation read receipts
    if version < 5 {
        let stmts5: [str] = [
            "CREATE TABLE IF NOT EXISTS conversation_reads (user_id TEXT NOT NULL, conversation_id TEXT NOT NULL, last_read_message_id TEXT NOT NULL DEFAULT '', updated_at INTEGER NOT NULL, PRIMARY KEY (user_id, conversation_id))",
            "INSERT INTO schema_migrations (version, applied_at) VALUES (5, 0)"
        ];
        let m = 0;
        while m < len(stmts5) {
            let er5 = exec_one(db, stmts5[m]);
            guard let _ok5 = er5 else let e = err_of(er5) {
                return err(e);
            }
            m = m + 1;
        }
        version = 5;
    }


    // v6: password reset codes
    if version < 6 {
        let stmts6: [str] = [
            "CREATE TABLE IF NOT EXISTS password_resets (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, code_hash TEXT NOT NULL, expires_at INTEGER NOT NULL, consumed_at INTEGER, created_at INTEGER NOT NULL)",
            "INSERT INTO schema_migrations (version, applied_at) VALUES (6, 0)"
        ];
        let n6 = 0;
        while n6 < len(stmts6) {
            let er6 = exec_one(db, stmts6[n6]);
            guard let _ok6 = er6 else let e = err_of(er6) {
                return err(e);
            }
            n6 = n6 + 1;
        }
        version = 6;
    }


    // v7: post media path
    if version < 7 {
        let ar7 = exec_one(db, "ALTER TABLE posts ADD COLUMN media_path TEXT NOT NULL DEFAULT ''");
        guard let _alt7 = ar7 else let e = err_of(ar7) {
            if !strings.contains(e, "duplicate column") {
                return err(e);
            }
        }
        let ir7 = exec_one(db, "INSERT INTO schema_migrations (version, applied_at) VALUES (7, 0)");
        guard let _ok7 = ir7 else let e = err_of(ir7) {
            return err(e);
        }
        version = 7;
    }

    return ok(true);
}
