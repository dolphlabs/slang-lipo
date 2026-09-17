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
import "../../interfaces/http" as rest;
import "../../interfaces/ws" as wsiface;

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
            wsiface.handle_websocket(app.svc, app.hub, &mut c, got.req, buf, got.filled);
            return;
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
