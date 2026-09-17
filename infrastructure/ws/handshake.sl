// infrastructure/ws/handshake — HTTP Upgrade → 101 Switching Protocols.
import "encoding";
import "http";
import "strings";
import "../../shared";

pub let WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

fn lower(s: str) -> str {
    return strings.to_lower(s);
}

fn header_has_token(value: str, token: str) -> bool {
    let parts = strings.split(lower(value), ",");
    let i = 0;
    let want = lower(token);
    while i < len(parts) {
        if strings.trim(parts[i]) == want {
            return true;
        }
        i = i + 1;
    }
    return false;
}

pub fn is_upgrade_request(req: http.Request) -> bool {
    let up = http.header(req, "upgrade");
    guard let uv = up else {
        return false;
    }
    if lower(strings.trim(uv)) != "websocket" {
        return false;
    }
    let conn = http.header(req, "connection");
    guard let cv = conn else {
        return false;
    }
    if !header_has_token(cv, "upgrade") {
        return false;
    }
    let ver = http.header(req, "sec-websocket-version");
    guard let vv = ver else {
        return false;
    }
    if strings.trim(vv) != "13" {
        return false;
    }
    let key = http.header(req, "sec-websocket-key");
    guard let kv = key else {
        return false;
    }
    if len(strings.trim(kv)) == 0 {
        return false;
    }
    return true;
}

pub fn accept_key(sec_key: str) -> str {
    let dig = shared.sha1_str(strings.trim(sec_key) + WS_GUID);
    return encoding.base64_encode(dig);
}

pub fn switching_response(sec_key: str) -> http.Response {
    let headers: map[str]str = {};
    headers["upgrade"] = "websocket";
    headers["connection"] = "Upgrade";
    headers["sec-websocket-accept"] = accept_key(sec_key);
    return http.Response {
        status: 101,
        status_text: "Switching Protocols",
        headers: headers,
        body: b""
    };
}

pub fn bad_upgrade_response() -> http.Response {
    return http.text_response(400, "Bad Request", "application/json; charset=utf-8",
        "{\"error\":\"invalid_argument\",\"message\":\"Invalid WebSocket upgrade.\"}");
}
