import "encoding";
import "http";
import "json";
import "../../application/user" as user_app;
import "../../application/feed" as feed_app;
import "../../domain/feed" as feed_domain;

gc struct FeedItemDto {
    id: str,
    author_id: str,
    author_username: str,
    author_display_name: str,
    author_avatar_path: str,
    body: str,
    created_at: i64,
    updated_at: i64,
    like_count: i64,
    liked_by_me: bool
}

gc struct FeedPageDto {
    posts: [FeedItemDto],
    next_cursor: str
}

pub fn feed_path() -> str {
    return "/feed";
}

fn item_dto(it: feed_domain.FeedItem) -> FeedItemDto {
    return FeedItemDto {
        id: it.id,
        author_id: it.author_id,
        author_username: it.author_username,
        author_display_name: it.author_display_name,
        author_avatar_path: it.author_avatar_path,
        body: it.body,
        created_at: it.created_at,
        updated_at: it.updated_at,
        like_count: it.like_count,
        liked_by_me: it.liked_by_me
    };
}

fn parse_limit(path: str) -> int {
    let qo: opt[str] = encoding.query_get(path, "limit");
    guard let s = qo else {
        return 20;
    }
    let tr = to_int(s);
    guard let n = tr else let e = err_of(tr) {
        let _discard_e = e;
        return 20;
    }
    return n;
}

fn parse_cursor_q(path: str) -> str {
    let qo: opt[str] = encoding.query_get(path, "cursor");
    guard let s = qo else {
        return "";
    }
    return s;
}

pub fn handle_get_feed(users: user_app.UserService, feed: feed_app.FeedService, req: http.Request) -> http.Response {
    let token = bearer_token(req);
    let uidr = user_app.user_id_from_token(users, token);
    guard let uid = uidr else let e = err_of(uidr) {
        return map_err(e);
    }
    let limit = parse_limit(req.path);
    let cursor = parse_cursor_q(req.path);
    let rr = feed_app.home(feed, uid, limit, cursor);
    guard let page = rr else let e = err_of(rr) {
        return map_err(e);
    }
    let out: [FeedItemDto] = [];
    let i = 0;
    while i < len(page.posts) {
        push(out, item_dto(page.posts[i]));
        i = i + 1;
    }
    return http.ok_json(json.encode(FeedPageDto { posts: out, next_cursor: page.next_cursor }));
}
