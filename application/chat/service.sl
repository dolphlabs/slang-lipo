import "json";
import "strings";
import "time";
import "../../domain/chat" as chat_domain;
import "../../infrastructure/sqlite" as sqlite;
import "../../infrastructure/ws" as wshub;
import "../../shared";

pub gc struct ChatService {
    repo: sqlite.SqliteChatRepo,
    users: sqlite.SqliteUserRepo,
    hub: wshub.Hub
}

pub fn new_service(repo: sqlite.SqliteChatRepo, users: sqlite.SqliteUserRepo, hub: wshub.Hub) -> ChatService {
    return ChatService { repo: repo, users: users, hub: hub };
}

fn now_secs() -> int {
    return time.wall() / 1000000000;
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

fn is_participant(c: chat_domain.Conversation, user_id: str) -> bool {
    return c.user_a_id == user_id || c.user_b_id == user_id;
}

gc struct ChatMessagePayload {
    id: str,
    conversation_id: str,
    sender_id: str,
    body: str,
    created_at: i64
}

fn push_message(hub: wshub.Hub, user_id: str, msg: chat_domain.Message) {
    let payload = ChatMessagePayload {
        id: msg.id,
        conversation_id: msg.conversation_id,
        sender_id: msg.sender_id,
        body: msg.body,
        created_at: msg.created_at
    };
    let text = "{\"type\":\"chat.message\",\"payload\":" + json.encode(payload) + "}";
    wshub.publish(hub, user_id, text);
}

pub fn create_or_get_dm(svc: ChatService, me_id: str, username_raw: str) -> result[chat_domain.ConversationView, str] {
    let username = strings.trim(username_raw);
    if len(username) == 0 {
        return err(shared.invalid_username);
    }
    let ur = sqlite.find_auth_by_username(svc.users, username);
    guard let peer = ur else let e = err_of(ur) {
        return err(e);
    }
    if peer.deactivated_at != 0 {
        return err(shared.not_found);
    }
    if peer.id == me_id {
        return err(shared.invalid_argument);
    }
    if !peer.allow_dms {
        return err(shared.forbidden);
    }
    let pr = chat_domain.ordered_pair(me_id, peer.id);
    guard let pair = pr else let e = err_of(pr) {
        return err(e);
    }
    let existing = sqlite.find_conversation_by_pair(svc.repo, pair[0], pair[1]);
    guard let conv = existing else let e = err_of(existing) {
        if e != shared.not_found {
            return err(e);
        }
        let idr = shared.new_id();
        guard let cid = idr else let e2 = err_of(idr) {
            return err(e2);
        }
        let now = now_secs();
        let ir = sqlite.insert_conversation(svc.repo, cid, pair[0], pair[1], now);
        guard let created = ir else let e3 = err_of(ir) {
            return err(e3);
        }
        return ok(chat_domain.ConversationView {
            id: created.id,
            peer_id: peer.id,
            peer_username: peer.username,
            peer_display_name: peer.display_name,
            peer_avatar_path: peer.avatar_path,
            created_at: created.created_at,
            updated_at: created.updated_at
        });
    }
    return ok(chat_domain.ConversationView {
        id: conv.id,
        peer_id: peer.id,
        peer_username: peer.username,
        peer_display_name: peer.display_name,
        peer_avatar_path: peer.avatar_path,
        created_at: conv.created_at,
        updated_at: conv.updated_at
    });
}

pub fn list_chats(svc: ChatService, me_id: str) -> result[[chat_domain.ConversationView], str] {
    return sqlite.list_conversations_for_user(svc.repo, me_id);
}

pub fn list_messages(svc: ChatService, me_id: str, conversation_id: str, limit_raw: int, cursor: str) -> result[chat_domain.MessagePage, str] {
    let cr = sqlite.find_conversation_by_id(svc.repo, conversation_id);
    guard let conv = cr else let e = err_of(cr) {
        return err(e);
    }
    if !is_participant(conv, me_id) {
        return err(shared.forbidden);
    }
    let limit = clamp_limit(limit_raw);
    let has_cursor = false;
    let cursor_ts = 0;
    let cursor_id = "";
    if len(cursor) > 0 {
        let pr = chat_domain.parse_cursor(cursor);
        guard let parts = pr else let e = err_of(pr) {
            return err(e);
        }
        let tr = to_int(parts[0]);
        guard let ts = tr else let e = err_of(tr) {
            let _discard_e = e;
            return err(shared.invalid_cursor);
        }
        cursor_ts = ts;
        cursor_id = parts[1];
        has_cursor = true;
    }
    let rr = sqlite.list_messages(svc.repo, conversation_id, limit + 1, cursor_ts, cursor_id, has_cursor);
    guard let rows = rr else let e = err_of(rr) {
        return err(e);
    }
    let messages: [chat_domain.Message] = [];
    let i = 0;
    while i < len(rows) && i < limit {
        push(messages, rows[i]);
        i = i + 1;
    }
    let next_cursor = "";
    if len(rows) > limit {
        let last = messages[len(messages) - 1];
        next_cursor = chat_domain.encode_cursor(last.created_at, last.id);
    }
    return ok(chat_domain.MessagePage { messages: messages, next_cursor: next_cursor });
}

pub fn send_message(svc: ChatService, me_id: str, conversation_id: str, body_raw: str) -> result[chat_domain.Message, str] {
    let body = strings.trim(body_raw);
    if len(body) == 0 {
        return err(shared.empty_message);
    }
    let cr = sqlite.find_conversation_by_id(svc.repo, conversation_id);
    guard let conv = cr else let e = err_of(cr) {
        return err(e);
    }
    if !is_participant(conv, me_id) {
        return err(shared.forbidden);
    }
    let idr = shared.new_id();
    guard let mid = idr else let e = err_of(idr) {
        return err(e);
    }
    let now = now_secs();
    let ir = sqlite.insert_message(svc.repo, mid, conversation_id, me_id, body, now);
    guard let msg = ir else let e = err_of(ir) {
        return err(e);
    }
    push_message(svc.hub, conv.user_a_id, msg);
    if conv.user_b_id != conv.user_a_id {
        push_message(svc.hub, conv.user_b_id, msg);
    }
    return ok(msg);
}

gc struct TypingPayload {
    conversation_id: str,
    user_id: str
}

gc struct ChatReadPayload {
    conversation_id: str,
    message_id: str,
    user_id: str
}

pub fn peer_id(conv: chat_domain.Conversation, me_id: str) -> str {
    if conv.user_a_id == me_id {
        return conv.user_b_id;
    }
    return conv.user_a_id;
}

pub fn emit_typing(svc: ChatService, me_id: str, conversation_id: str, except_conn_id: str) -> result[bool, str] {
    let cr = sqlite.find_conversation_by_id(svc.repo, conversation_id);
    guard let conv = cr else let e = err_of(cr) {
        return err(e);
    }
    if !is_participant(conv, me_id) {
        return err(shared.forbidden);
    }
    let peer = peer_id(conv, me_id);
    let payload = TypingPayload {
        conversation_id: conversation_id,
        user_id: me_id
    };
    let text = "{\"type\":\"typing\",\"payload\":" + json.encode(payload) + "}";
    wshub.publish(svc.hub, peer, text);
    // Other devices of sender (optional): skip same conn
    if len(except_conn_id) > 0 {
        wshub.publish_except(svc.hub, me_id, except_conn_id, text);
    }
    return ok(true);
}

pub fn mark_read(svc: ChatService, me_id: str, conversation_id: str, message_id: str) -> result[bool, str] {
    if len(message_id) == 0 {
        return err(shared.invalid_argument);
    }
    let cr = sqlite.find_conversation_by_id(svc.repo, conversation_id);
    guard let conv = cr else let e = err_of(cr) {
        return err(e);
    }
    if !is_participant(conv, me_id) {
        return err(shared.forbidden);
    }
    let now = now_secs();
    let ur = sqlite.upsert_conversation_read(svc.repo, me_id, conversation_id, message_id, now);
    guard let _u = ur else let e = err_of(ur) {
        return err(e);
    }
    let peer = peer_id(conv, me_id);
    let payload = ChatReadPayload {
        conversation_id: conversation_id,
        message_id: message_id,
        user_id: me_id
    };
    let text = "{\"type\":\"chat.read\",\"payload\":" + json.encode(payload) + "}";
    wshub.publish(svc.hub, peer, text);
    return ok(true);
}
