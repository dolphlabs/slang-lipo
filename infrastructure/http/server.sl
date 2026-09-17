import "http";
import "log";
import "proc";
import "strings";
import "time";
import "../../application/user" as user_app;
import "../../application/post" as post_app;
import "../../application/social" as social_app;
import "../../application/feed" as feed_app;
import "../../application/chat" as chat_app;
import "../../infrastructure/ws" as wshub;
import "../../infrastructure/httpread" as httpread;
import "../../infrastructure/ratelimit" as ratelimit;
import "../../interfaces/http" as rest;
import "../../interfaces/ws" as wsiface;
import "../../shared";

pub struct Server {
    addr: str,
    port: int
}

pub gc struct App {
    svc: user_app.UserService,
    post_svc: post_app.PostService,
    social_svc: social_app.SocialService,
    feed_svc: feed_app.FeedService,
    chat_svc: chat_app.ChatService,
    hub: wshub.Hub,
    auth_limiter: ratelimit.Limiter,
    msg_limiter: ratelimit.Limiter,
    port: int,
    addr: str
}

pub fn new_server(addr: str, port: int) -> Server {
    return Server { addr: addr, port: port };
}

pub fn banner(srv: Server) -> str {
    return "lipo http " + srv.addr + ":" + to_str(srv.port);
}

fn path_without_query(path: str) -> str {
    let q = strings.find(path, "?");
    if q < 0 {
        return path;
    }
    return strings.slice(path, 0, q);
}

fn msg_rate_key(req: http.Request) -> str {
    let ah = http.header(req, "authorization");
    guard let tok = ah else {
        return "msg:anon";
    }
    if len(tok) > 48 {
        return "msg:" + strings.slice(tok, 0, 48);
    }
    return "msg:" + tok;
}

fn serve_conn(app: App, c: link) {
    let ra = arena_new(65536);
    let sa = arena_new(65536);
    let buf = ra.wire(65536);
    let filled = 0;
    while true {
        let rr = httpread.read_request(&mut c, buf, filled, until_never());
        guard let got = rr else {
            return;
        }
        let path = path_without_query(got.req.path);
        if path == "/ws" {
            wsiface.handle_websocket(app.svc, app.chat_svc, app.hub, &mut c, got.req, buf, got.filled);
            return;
        }
        // Auth: ~10 tokens capacity, refill 10/min equivalent via refill_per_sec~0.2 — use 10 cap / 1 per 6s ≈ 10/min
        if (path == "/auth/signin" || path == "/auth/signup" || path == "/auth/password/forgot" || path == "/auth/password/reset") && got.req.method == "POST" {
            let body_s = to_str(got.req.body);
            let key = path + ":" + body_s;
            if len(key) > 200 {
                key = strings.slice(key, 0, 200);
            }
            if !ratelimit.allow(app.auth_limiter, key) {
                let resp_rl = rest.map_err(shared.rate_limited);
                let wr = http.write(&mut c, resp_rl, &mut sa, until_never());
                guard let _n = wr else {
                    return;
                }
                sa.reset();
                if http.wants_close(got.req) {
                    return;
                }
                filled = got.filled;
                continue;
            }
        }
        // Message send: ~30/min per bearer token
        if got.req.method == "POST" && strings.contains(path, "/messages") {
            if !ratelimit.allow(app.msg_limiter, msg_rate_key(got.req)) {
                let resp_rl2 = rest.map_err(shared.rate_limited);
                let wr2 = http.write(&mut c, resp_rl2, &mut sa, until_never());
                guard let _n2 = wr2 else {
                    return;
                }
                sa.reset();
                if http.wants_close(got.req) {
                    return;
                }
                filled = got.filled;
                continue;
            }
        }
        let resp = rest.dispatch(app.svc, app.post_svc, app.social_svc, app.feed_svc, app.chat_svc, got.req);
        let wr = http.write(&mut c, resp, &mut sa, until_never());
        guard let _n = wr else {
            return;
        }
        sa.reset();
        if http.wants_close(got.req) {
            return;
        }
        filled = got.filled;
    }
}

fn accept_one(app: App, ln: &mut link) {
    let ar = ln.accept(until_never());
    guard let c = ar else {
        return;
    }
    spawn serve_conn(app, c);
}

pub fn listen_and_serve(app: App) -> result[bool, str] {
    let lr = link_listen(app.port);
    guard let ln = lr else {
        return err("could not listen on " + to_str(app.port));
    }
    log.info("listening on http://" + app.addr + ":" + to_str(app.port));
    while !proc.shutdown_requested() {
        accept_one(app, &mut ln);
    }
    log.info("shutting down: waiting for in-flight connections");
    while proc.active_tasks() > 0 {
        time.sleep(20000000);
    }
    return ok(true);
}

pub fn start(srv: Server) -> result[bool, str] {
    let _discard_srv = srv;
    return err("use listen_and_serve with App");
}
