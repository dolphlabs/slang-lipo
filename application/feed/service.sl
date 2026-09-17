import "../../domain/feed" as feed_domain;
import "../../infrastructure/sqlite" as sqlite;
import "../../shared";

pub gc struct FeedService {
    repo: sqlite.SqliteFeedRepo
}

pub fn new_service(repo: sqlite.SqliteFeedRepo) -> FeedService {
    return FeedService { repo: repo };
}

fn clamp_limit(limit_raw: int) -> int {
    let limit = limit_raw;
    if limit <= 0 {
        limit = 20;
    }
    if limit > 50 {
        limit = 50;
    }
    return limit;
}

pub fn home(svc: FeedService, user_id: str, limit_raw: int, cursor: str) -> result[feed_domain.FeedPage, str] {
    let limit = clamp_limit(limit_raw);
    let has_cursor = false;
    let cursor_ts = 0;
    let cursor_id = "";
    if len(cursor) > 0 {
        let pr = feed_domain.parse_cursor(cursor);
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
    let fetch_n = limit + 1;
    let rr = sqlite.list_home_feed(svc.repo, user_id, fetch_n, cursor_ts, cursor_id, has_cursor);
    guard let rows = rr else let e = err_of(rr) {
        return err(e);
    }
    let next_cursor = "";
    let posts: [feed_domain.FeedItem] = [];
    let i = 0;
    while i < len(rows) && i < limit {
        push(posts, rows[i]);
        i = i + 1;
    }
    if len(rows) > limit {
        let last = posts[len(posts) - 1];
        next_cursor = feed_domain.encode_cursor(last.created_at, last.id);
    }
    return ok(feed_domain.FeedPage { posts: posts, next_cursor: next_cursor });
}

pub fn timeline(svc: FeedService, user_id: str) -> result[feed_domain.FeedPage, str] {
    return home(svc, user_id, 20, "");
}
