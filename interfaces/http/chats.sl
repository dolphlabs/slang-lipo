import "encoding";
import "http";
import "json";
import "../../application/user" as user_app;
import "../../application/chat" as chat_app;
import "../../domain/chat" as chat_domain;
import "../../shared";

gc struct DmReq {
    username: str
}

gc struct SendMsgReq {
    body: str
}

gc struct MessageDto {
    id: str,
    conversation_id: str,
    sender_id: str,
    body: str,
    created_at: i64
}

gc struct MessagePageDto {
    messages: [MessageDto],
    next_cursor: str
}

gc struct ConversationDto {
    id: str,
    peer_id: str,
    peer_username: str,
    peer_display_name: str,
    peer_avatar_path: str,
    created_at: i64,
    updated_at: i64
}

gc struct ConversationsDto {
    conversations: [ConversationDto]
}

fn msg_dto(m: chat_domain.Message) -> MessageDto {
    return MessageDto {
        id: m.id,
        conversation_id: m.conversation_id,
        sender_id: m.sender_id,
        body: m.body,
        created_at: m.created_at
    };
}

fn conv_dto(c: chat_domain.ConversationView) -> ConversationDto {
    return ConversationDto {
        id: c.id,
        peer_id: c.peer_id,
        peer_username: c.peer_username,
        peer_display_name: c.peer_display_name,
        peer_avatar_path: c.peer_avatar_path,
        created_at: c.created_at,
        updated_at: c.updated_at
    };
}

fn parse_chat_limit(path: str) -> int {
    let qo: opt[str] = encoding.query_get(path, "limit");
    guard let s = qo else {
        return 50;
    }
    let tr = to_int(s);
    guard let n = tr else let e = err_of(tr) {
        let _discard_e = e;
        return 50;
    }
    return n;
}

fn parse_chat_cursor_q(path: str) -> str {
    let qo: opt[str] = encoding.query_get(path, "cursor");
    guard let s = qo else {
        return "";
    }
    return s;
}

pub fn handle_create_dm(users: user_app.UserService, chat: chat_app.ChatService, req: http.Request) -> http.Response {
    let token = bearer_token(req);
    let uidr = user_app.user_id_from_token(users, token);
    guard let uid = uidr else let e = err_of(uidr) {
        return map_err(e);
    }
    let dr: result[DmReq, str] = json.decode(req.body);
    guard let body = dr else let e = err_of(dr) {
        return bad_request_json(shared.invalid_json);
    }
    let rr = chat_app.create_or_get_dm(chat, uid, body.username);
    guard let conv = rr else let e = err_of(rr) {
        return map_err(e);
    }
    return http.ok_json(json.encode(conv_dto(conv)));
}


pub fn handle_list_chats(users: user_app.UserService, chat: chat_app.ChatService, req: http.Request) -> http.Response {
    let token = bearer_token(req);
    let uidr = user_app.user_id_from_token(users, token);
    guard let uid = uidr else let e = err_of(uidr) {
        return map_err(e);
    }
    let rr = chat_app.list_chats(chat, uid);
    guard let rows = rr else let e = err_of(rr) {
        return map_err(e);
    }
    let out: [ConversationDto] = [];
    let i = 0;
    while i < len(rows) {
        push(out, conv_dto(rows[i]));
        i = i + 1;
    }
    return http.ok_json(json.encode(ConversationsDto { conversations: out }));
}

pub fn handle_list_messages(users: user_app.UserService, chat: chat_app.ChatService, req: http.Request, conversation_id: str) -> http.Response {
    let token = bearer_token(req);
    let uidr = user_app.user_id_from_token(users, token);
    guard let uid = uidr else let e = err_of(uidr) {
        return map_err(e);
    }
    let limit = parse_chat_limit(req.path);
    let cursor = parse_chat_cursor_q(req.path);
    let rr = chat_app.list_messages(chat, uid, conversation_id, limit, cursor);
    guard let page = rr else let e = err_of(rr) {
        return map_err(e);
    }
    let out: [MessageDto] = [];
    let i = 0;
    while i < len(page.messages) {
        push(out, msg_dto(page.messages[i]));
        i = i + 1;
    }
    return http.ok_json(json.encode(MessagePageDto { messages: out, next_cursor: page.next_cursor }));
}

pub fn handle_send_message(users: user_app.UserService, chat: chat_app.ChatService, req: http.Request, conversation_id: str) -> http.Response {
    let token = bearer_token(req);
    let uidr = user_app.user_id_from_token(users, token);
    guard let uid = uidr else let e = err_of(uidr) {
        return map_err(e);
    }
    let dr: result[SendMsgReq, str] = json.decode(req.body);
    guard let body = dr else let e = err_of(dr) {
        return bad_request_json(shared.invalid_json);
    }
    let rr = chat_app.send_message(chat, uid, conversation_id, body.body);
    guard let msg = rr else let e = err_of(rr) {
        return map_err(e);
    }
    return http.created_json(json.encode(msg_dto(msg)));
}
