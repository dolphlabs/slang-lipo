import "encoding";
import "http";
import "json";
import "log";
import "strings";
import "time";
import "../../application/user" as user_app;
import "../../infrastructure/ws" as wslib;
import "../../shared";


// Avoid reserved `type` field — decode loosely via map isn't available;
// parse token from JSON with simple string find for auth messages.
fn extract_auth_token(text: str) -> str {
    // Expect {"type":"auth","token":"..."}
    if !strings.contains(text, "\"auth\"") {
        return "";
    }
    let key = "\"token\"";
    let idx = strings.find(text, key);
    if idx < 0 {
        return "";
    }
    let rest = strings.slice(text, idx + len(key), len(text));
    let colon = strings.find(rest, ":");
    if colon < 0 {
        return "";
    }
    rest = strings.slice(rest, colon + 1, len(rest));
    let q1 = strings.find(rest, "\"");
    if q1 < 0 {
        return "";
    }
    rest = strings.slice(rest, q1 + 1, len(rest));
    let q2 = strings.find(rest, "\"");
    if q2 < 0 {
        return "";
    }
    return strings.slice(rest, 0, q2);
}

fn query_token(path: str) -> str {
    let qo: opt[str] = encoding.query_get(path, "token");
    guard let t = qo else {
        return "";
    }
    return t;
}

fn wire_to_bytes(buf: wire, n: int) -> bytes {
    let out = b"";
    let i = 0;
    while i < n {
        out = out + to_le(buf[i])[0..1];
        i = i + 1;
    }
    return out;
}

fn compact(buf: wire, used: int, filled: int) -> int {
    if used <= 0 {
        return filled;
    }
    let n = filled - used;
    let i = 0;
    while i < n {
        buf[i] = buf[used + i];
        i = i + 1;
    }
    return n;
}

fn send_raw(c: &mut link, raw: bytes) -> bool {
    let wr = c.send_bytes(raw, until_never());
    guard let _n = wr else {
        return false;
    }
    return true;
}

fn send_text(c: &mut link, text: str) -> bool {
    return send_raw(&mut *c, wslib.encode_text(text));
}

fn send_err_and_close(c: &mut link, code: str) -> bool {
    let body = "{\"type\":\"error\",\"payload\":{\"error\":\"" + code + "\",\"message\":\"" + shared.message_of(code) + "\"}}";
    let _s = send_text(&mut *c, body);
    return send_raw(&mut *c, wslib.encode_close(1008, code));
}

pub fn handle_websocket(users: user_app.UserService, hub: wslib.Hub, c: &mut link, req: http.Request, buf: wire, filled_in: int) {
    if !wslib.is_upgrade_request(req) {
        let sa = arena_new(4096);
        let _wr = http.write(&mut *c, wslib.bad_upgrade_response(), &mut sa, until_never());
        return;
    }
    let key_h = http.header(req, "sec-websocket-key");
    guard let key = key_h else {
        let sa = arena_new(4096);
        let _wr = http.write(&mut *c, wslib.bad_upgrade_response(), &mut sa, until_never());
        return;
    }
    let sa = arena_new(4096);
    let wr = http.write(&mut *c, wslib.switching_response(key), &mut sa, until_never());
    guard let _n = wr else {
        return;
    }

    let user_id = "";
    let authed = false;
    let tok = query_token(req.path);
    if len(tok) > 0 {
        let uidr = user_app.user_id_from_token(users, tok);
        guard let uid = uidr else let e = err_of(uidr) {
            let _x = send_err_and_close(&mut *c, e);
            return;
        }
        user_id = uid;
        authed = true;
    }

    let out: chan[str] = make_chan(64);
    let conn_id = "";
    if authed {
        let idr = shared.new_id();
        guard let cid = idr else {
            return;
        }
        conn_id = cid;
        wslib.register(hub, conn_id, user_id, out);
        let _ok = send_text(&mut *c, "{\"type\":\"auth.ok\",\"payload\":{\"user_id\":\"" + user_id + "\"}}");
    }

    let filled = filled_in;
    while true {
        // Drain outbound publishes (non-blocking via short select)
        let drained = true;
        while drained {
            select {
                case let msg = chan_recv(out) {
                    guard let text = msg else {
                        // channel closed
                        if len(conn_id) > 0 {
                            wslib.unregister(hub, conn_id);
                        }
                        return;
                    }
                    if !send_text(&mut *c, text) {
                        if len(conn_id) > 0 {
                            wslib.unregister(hub, conn_id);
                            chan_close(out);
                        }
                        return;
                    }
                }
                default {
                    drained = false;
                }
            }
        }

        // Read with short deadline so we can keep draining hub publishes
        if filled >= len(buf) {
            log.warn("ws buffer full");
            if len(conn_id) > 0 {
                wslib.unregister(hub, conn_id);
                chan_close(out);
            }
            return;
        }
        let deadline = until_of(time.mono() + 50000000);
        let tail = buf[filled..];
        let rr = c.recv(tail, deadline);
        guard let n = rr else let e = err_of(rr) {
            // timeout → loop again to drain outbound
            if to_str(e) == "timeout" || strings.contains(to_str(e), "timeout") {
                continue;
            }
            if len(conn_id) > 0 {
                wslib.unregister(hub, conn_id);
                chan_close(out);
            }
            return;
        }
        if n == 0 {
            if len(conn_id) > 0 {
                wslib.unregister(hub, conn_id);
                chan_close(out);
            }
            return;
        }
        filled = filled + n;

        // Decode frames
        while true {
            let raw = wire_to_bytes(buf, filled);
            let dr = wslib.try_decode_ex(raw, filled);
            guard let dec = dr else let e = err_of(dr) {
                if e == "incomplete" {
                    break;
                }
                log.warn("ws decode: " + e);
                if len(conn_id) > 0 {
                    wslib.unregister(hub, conn_id);
                    chan_close(out);
                }
                return;
            }
            filled = compact(buf, dec.consumed, filled);
            let fr = dec.frame;
            if fr.opcode == wslib.OP_CLOSE {
                let _c = send_raw(&mut *c, wslib.encode_close(1000, ""));
                if len(conn_id) > 0 {
                    wslib.unregister(hub, conn_id);
                    chan_close(out);
                }
                return;
            }
            if fr.opcode == wslib.OP_PING {
                if !send_raw(&mut *c, wslib.encode_pong(fr.payload)) {
                    if len(conn_id) > 0 {
                        wslib.unregister(hub, conn_id);
                        chan_close(out);
                    }
                    return;
                }
                continue;
            }
            if fr.opcode == wslib.OP_PONG || fr.opcode == wslib.OP_CONTINUATION || fr.opcode == wslib.OP_BINARY {
                continue;
            }
            if fr.opcode == wslib.OP_TEXT {
                let text = to_str(fr.payload);
                if !authed {
                    let at = extract_auth_token(text);
                    if len(at) == 0 {
                        let _x = send_err_and_close(&mut *c, shared.unauthorized);
                        return;
                    }
                    let uidr = user_app.user_id_from_token(users, at);
                    guard let uid = uidr else let e = err_of(uidr) {
                        let _x = send_err_and_close(&mut *c, e);
                        return;
                    }
                    user_id = uid;
                    authed = true;
                    let idr = shared.new_id();
                    guard let cid = idr else {
                        return;
                    }
                    conn_id = cid;
                    wslib.register(hub, conn_id, user_id, out);
                    let _ok = send_text(&mut *c, "{\"type\":\"auth.ok\",\"payload\":{\"user_id\":\"" + user_id + "\"}}");
                    continue;
                }
                // Authenticated: ignore client application messages for now (server pushes only)
                continue;
            }
        }
    }
}
