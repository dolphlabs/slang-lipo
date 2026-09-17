import "strings";
import "../../shared";

pub struct Conversation {
    id: str,
    user_a_id: str,
    user_b_id: str,
    created_at: i64,
    updated_at: i64
}

pub struct Message {
    id: str,
    conversation_id: str,
    sender_id: str,
    body: str,
    created_at: i64
}

pub struct MessagePage {
    messages: [Message],
    next_cursor: str
}

pub struct ConversationView {
    id: str,
    peer_id: str,
    peer_username: str,
    peer_display_name: str,
    peer_avatar_path: str,
    created_at: i64,
    updated_at: i64
}

pub fn ordered_pair(user_x: str, user_y: str) -> result[[str], str] {
    let a = shared.user_id(user_x);
    guard let ux = a else let e = err_of(a) { return err(e); }
    let b = shared.user_id(user_y);
    guard let uy = b else let e = err_of(b) { return err(e); }
    if ux == uy {
        return err(shared.invalid_argument);
    }
    if ux < uy {
        let out: [str] = [ux, uy];
        return ok(out);
    }
    let out2: [str] = [uy, ux];
    return ok(out2);
}

pub fn new_message(id: str, conversation_id: str, sender_id: str, body: str, created_at: int) -> result[Message, str] {
    if len(id) == 0 || len(conversation_id) == 0 {
        return err(shared.invalid_argument);
    }
    let s = shared.user_id(sender_id);
    guard let sid = s else let e = err_of(s) { return err(e); }
    if len(body) == 0 {
        return err(shared.empty_message);
    }
    return ok(Message {
        id: id,
        conversation_id: conversation_id,
        sender_id: sid,
        body: body,
        created_at: created_at as i64
    });
}

pub fn encode_cursor(created_at: i64, id: str) -> str {
    return to_str(created_at) + "_" + id;
}

pub fn parse_cursor(cursor: str) -> result[[str], str] {
    if len(cursor) == 0 {
        return err(shared.invalid_cursor);
    }
    let us = strings.find(cursor, "_");
    if us <= 0 {
        return err(shared.invalid_cursor);
    }
    let ts_s = strings.slice(cursor, 0, us);
    let id = strings.slice(cursor, us + 1, len(cursor));
    if len(id) == 0 {
        return err(shared.invalid_cursor);
    }
    let tr = to_int(ts_s);
    guard let _ts = tr else let e = err_of(tr) {
        let _discard_e = e;
        return err(shared.invalid_cursor);
    }
    let out: [str] = [ts_s, id];
    return ok(out);
}
