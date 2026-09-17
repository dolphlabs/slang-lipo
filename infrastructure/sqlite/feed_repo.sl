import "sql";
import "../../domain/feed" as feed_domain;

pub gc struct SqliteFeedRepo {
    db: rawptr
}

pub fn new_feed_repo(db: rawptr) -> SqliteFeedRepo {
    return SqliteFeedRepo { db: db };
}

fn feed_item_from_stmt(st: rawptr) -> feed_domain.FeedItem {
    let liked_i = sql.col_int(st, 9);
    let liked = false;
    if liked_i != 0 {
        liked = true;
    }
    return feed_domain.FeedItem {
        id: sql.col_text(st, 0),
        author_id: sql.col_text(st, 1),
        author_username: sql.col_text(st, 6),
        author_display_name: sql.col_text(st, 7),
        author_avatar_path: sql.col_text(st, 8),
        body: sql.col_text(st, 2),
        created_at: sql.col_int(st, 3) as i64,
        updated_at: sql.col_int(st, 4) as i64,
        like_count: sql.col_int(st, 5) as i64,
        liked_by_me: liked
    };
}

fn collect_feed_rows(st: rawptr) -> result[[feed_domain.FeedItem], str] {
    let out: [feed_domain.FeedItem] = [];
    while true {
        let sr = sql.step(st);
        guard let more = sr else let e = err_of(sr) {
            return err(e);
        }
        if !more {
            break;
        }
        push(out, feed_item_from_stmt(st));
    }
    return ok(out);
}

pub fn list_home_feed(repo: SqliteFeedRepo, viewer_id: str, limit: int, cursor_ts: int, cursor_id: str, has_cursor: bool) -> result[[feed_domain.FeedItem], str] {
    if has_cursor {
        let pr = sql.prepare(repo.db, "SELECT p.id, p.author_id, p.body, p.created_at, p.updated_at, p.like_count, u.username, u.display_name, u.avatar_path, EXISTS(SELECT 1 FROM likes WHERE user_id = ? AND post_id = p.id) AS liked_by_me FROM posts p JOIN users u ON u.id = p.author_id WHERE (p.author_id IN (SELECT followee_id FROM follows WHERE follower_id = ?) OR p.author_id = ?) AND u.deactivated_at = 0 AND (p.created_at < ? OR (p.created_at = ? AND p.id < ?)) ORDER BY p.created_at DESC, p.id DESC LIMIT ?");
        guard let st = pr else let e = err_of(pr) {
            return err(e);
        }
        sql.bind_text(st, 1, viewer_id);
        sql.bind_text(st, 2, viewer_id);
        sql.bind_text(st, 3, viewer_id);
        sql.bind_int(st, 4, cursor_ts);
        sql.bind_int(st, 5, cursor_ts);
        sql.bind_text(st, 6, cursor_id);
        sql.bind_int(st, 7, limit);
        let rr = collect_feed_rows(st);
        sql.finalize(st);
        return rr;
    }
    let pr2 = sql.prepare(repo.db, "SELECT p.id, p.author_id, p.body, p.created_at, p.updated_at, p.like_count, u.username, u.display_name, u.avatar_path, EXISTS(SELECT 1 FROM likes WHERE user_id = ? AND post_id = p.id) AS liked_by_me FROM posts p JOIN users u ON u.id = p.author_id WHERE (p.author_id IN (SELECT followee_id FROM follows WHERE follower_id = ?) OR p.author_id = ?) AND u.deactivated_at = 0 ORDER BY p.created_at DESC, p.id DESC LIMIT ?");
    guard let st2 = pr2 else let e = err_of(pr2) {
        return err(e);
    }
    sql.bind_text(st2, 1, viewer_id);
    sql.bind_text(st2, 2, viewer_id);
    sql.bind_text(st2, 3, viewer_id);
    sql.bind_int(st2, 4, limit);
    let rr2 = collect_feed_rows(st2);
    sql.finalize(st2);
    return rr2;
}
