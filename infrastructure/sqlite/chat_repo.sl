import "sql";
import "../../domain/chat" as chat_domain;
import "../../shared";

pub gc struct SqliteChatRepo {
    db: rawptr
}

pub fn new_chat_repo(db: rawptr) -> SqliteChatRepo {
    return SqliteChatRepo { db: db };
}

fn conv_from_stmt(st: rawptr) -> chat_domain.Conversation {
    return chat_domain.Conversation {
        id: sql.col_text(st, 0),
        user_a_id: sql.col_text(st, 1),
        user_b_id: sql.col_text(st, 2),
        created_at: sql.col_int(st, 3) as i64,
        updated_at: sql.col_int(st, 4) as i64
    };
}

fn msg_from_stmt(st: rawptr) -> chat_domain.Message {
    return chat_domain.Message {
        id: sql.col_text(st, 0),
        conversation_id: sql.col_text(st, 1),
        sender_id: sql.col_text(st, 2),
        body: sql.col_text(st, 3),
        created_at: sql.col_int(st, 4) as i64
    };
}

pub fn find_conversation_by_pair(repo: SqliteChatRepo, user_a: str, user_b: str) -> result[chat_domain.Conversation, str] {
    let pr = sql.prepare(repo.db, "SELECT id, user_a_id, user_b_id, created_at, updated_at FROM conversations WHERE user_a_id = ? AND user_b_id = ? LIMIT 1");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_text(st, 1, user_a);
    sql.bind_text(st, 2, user_b);
    let sr = sql.step(st);
    guard let more = sr else let e = err_of(sr) {
        sql.finalize(st);
        return err(e);
    }
    if !more {
        sql.finalize(st);
        return err(shared.not_found);
    }
    let c = conv_from_stmt(st);
    sql.finalize(st);
    return ok(c);
}

pub fn find_conversation_by_id(repo: SqliteChatRepo, id: str) -> result[chat_domain.Conversation, str] {
    let pr = sql.prepare(repo.db, "SELECT id, user_a_id, user_b_id, created_at, updated_at FROM conversations WHERE id = ? LIMIT 1");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_text(st, 1, id);
    let sr = sql.step(st);
    guard let more = sr else let e = err_of(sr) {
        sql.finalize(st);
        return err(e);
    }
    if !more {
        sql.finalize(st);
        return err(shared.not_found);
    }
    let c = conv_from_stmt(st);
    sql.finalize(st);
    return ok(c);
}

pub fn insert_conversation(repo: SqliteChatRepo, id: str, user_a: str, user_b: str, now: int) -> result[chat_domain.Conversation, str] {
    let pr = sql.prepare(repo.db, "INSERT INTO conversations (id, user_a_id, user_b_id, created_at, updated_at) VALUES (?, ?, ?, ?, ?)");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_text(st, 1, id);
    sql.bind_text(st, 2, user_a);
    sql.bind_text(st, 3, user_b);
    sql.bind_int(st, 4, now);
    sql.bind_int(st, 5, now);
    let sr = sql.step(st);
    guard let _done = sr else let e = err_of(sr) {
        sql.finalize(st);
        return err(e);
    }
    sql.finalize(st);
    return ok(chat_domain.Conversation {
        id: id,
        user_a_id: user_a,
        user_b_id: user_b,
        created_at: now as i64,
        updated_at: now as i64
    });
}

pub fn touch_conversation(repo: SqliteChatRepo, id: str, updated_at: int) -> result[bool, str] {
    let pr = sql.prepare(repo.db, "UPDATE conversations SET updated_at = ? WHERE id = ?");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_int(st, 1, updated_at);
    sql.bind_text(st, 2, id);
    let sr = sql.step(st);
    guard let _done = sr else let e = err_of(sr) {
        sql.finalize(st);
        return err(e);
    }
    sql.finalize(st);
    return ok(true);
}

pub fn insert_message(repo: SqliteChatRepo, id: str, conversation_id: str, sender_id: str, body: str, created_at: int) -> result[chat_domain.Message, str] {
    let pr = sql.prepare(repo.db, "INSERT INTO messages (id, conversation_id, sender_id, body, created_at) VALUES (?, ?, ?, ?, ?)");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_text(st, 1, id);
    sql.bind_text(st, 2, conversation_id);
    sql.bind_text(st, 3, sender_id);
    sql.bind_text(st, 4, body);
    sql.bind_int(st, 5, created_at);
    let sr = sql.step(st);
    guard let _done = sr else let e = err_of(sr) {
        sql.finalize(st);
        return err(e);
    }
    sql.finalize(st);
    let tr = touch_conversation(repo, conversation_id, created_at);
    guard let _t = tr else let e = err_of(tr) {
        return err(e);
    }
    return ok(chat_domain.Message {
        id: id,
        conversation_id: conversation_id,
        sender_id: sender_id,
        body: body,
        created_at: created_at as i64
    });
}

pub fn list_conversations_for_user(repo: SqliteChatRepo, user_id: str) -> result[[chat_domain.ConversationView], str] {
    let pr = sql.prepare(repo.db, "SELECT c.id, c.user_a_id, c.user_b_id, c.created_at, c.updated_at, u.id, u.username, u.display_name, u.avatar_path FROM conversations c JOIN users u ON u.id = CASE WHEN c.user_a_id = ? THEN c.user_b_id ELSE c.user_a_id END WHERE (c.user_a_id = ? OR c.user_b_id = ?) AND u.deactivated_at = 0 ORDER BY c.updated_at DESC, c.id DESC");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_text(st, 1, user_id);
    sql.bind_text(st, 2, user_id);
    sql.bind_text(st, 3, user_id);
    let out: [chat_domain.ConversationView] = [];
    while true {
        let sr = sql.step(st);
        guard let more = sr else let e = err_of(sr) {
            sql.finalize(st);
            return err(e);
        }
        if !more {
            break;
        }
        push(out, chat_domain.ConversationView {
            id: sql.col_text(st, 0),
            peer_id: sql.col_text(st, 5),
            peer_username: sql.col_text(st, 6),
            peer_display_name: sql.col_text(st, 7),
            peer_avatar_path: sql.col_text(st, 8),
            created_at: sql.col_int(st, 3) as i64,
            updated_at: sql.col_int(st, 4) as i64
        });
    }
    sql.finalize(st);
    return ok(out);
}

pub fn list_messages(repo: SqliteChatRepo, conversation_id: str, limit: int, cursor_ts: int, cursor_id: str, has_cursor: bool) -> result[[chat_domain.Message], str] {
    if has_cursor {
        let pr = sql.prepare(repo.db, "SELECT id, conversation_id, sender_id, body, created_at FROM messages WHERE conversation_id = ? AND (created_at < ? OR (created_at = ? AND id < ?)) ORDER BY created_at DESC, id DESC LIMIT ?");
        guard let st = pr else let e = err_of(pr) {
            return err(e);
        }
        sql.bind_text(st, 1, conversation_id);
        sql.bind_int(st, 2, cursor_ts);
        sql.bind_int(st, 3, cursor_ts);
        sql.bind_text(st, 4, cursor_id);
        sql.bind_int(st, 5, limit);
        let out: [chat_domain.Message] = [];
        while true {
            let sr = sql.step(st);
            guard let more = sr else let e = err_of(sr) {
                sql.finalize(st);
                return err(e);
            }
            if !more {
                break;
            }
            push(out, msg_from_stmt(st));
        }
        sql.finalize(st);
        return ok(out);
    }
    let pr2 = sql.prepare(repo.db, "SELECT id, conversation_id, sender_id, body, created_at FROM messages WHERE conversation_id = ? ORDER BY created_at DESC, id DESC LIMIT ?");
    guard let st2 = pr2 else let e = err_of(pr2) {
        return err(e);
    }
    sql.bind_text(st2, 1, conversation_id);
    sql.bind_int(st2, 2, limit);
    let out2: [chat_domain.Message] = [];
    while true {
        let sr = sql.step(st2);
        guard let more = sr else let e = err_of(sr) {
            sql.finalize(st2);
            return err(e);
        }
        if !more {
            break;
        }
        push(out2, msg_from_stmt(st2));
    }
    sql.finalize(st2);
    return ok(out2);
}

pub fn upsert_conversation_read(repo: SqliteChatRepo, user_id: str, conversation_id: str, message_id: str, updated_at: int) -> result[bool, str] {
    let pr = sql.prepare(repo.db, "INSERT INTO conversation_reads (user_id, conversation_id, last_read_message_id, updated_at) VALUES (?, ?, ?, ?) ON CONFLICT(user_id, conversation_id) DO UPDATE SET last_read_message_id = excluded.last_read_message_id, updated_at = excluded.updated_at");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_text(st, 1, user_id);
    sql.bind_text(st, 2, conversation_id);
    sql.bind_text(st, 3, message_id);
    sql.bind_int(st, 4, updated_at);
    let sr = sql.step(st);
    sql.finalize(st);
    guard let _done = sr else let e = err_of(sr) {
        return err(e);
    }
    return ok(true);
}

pub fn get_conversation_read(repo: SqliteChatRepo, user_id: str, conversation_id: str) -> result[str, str] {
    let pr = sql.prepare(repo.db, "SELECT last_read_message_id FROM conversation_reads WHERE user_id = ? AND conversation_id = ? LIMIT 1");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_text(st, 1, user_id);
    sql.bind_text(st, 2, conversation_id);
    let sr = sql.step(st);
    guard let more = sr else let e = err_of(sr) {
        sql.finalize(st);
        return err(e);
    }
    if !more {
        sql.finalize(st);
        return err(shared.not_found);
    }
    let mid = sql.col_text(st, 0);
    sql.finalize(st);
    return ok(mid);
}
