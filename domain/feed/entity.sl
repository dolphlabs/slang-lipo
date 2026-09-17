import "strings";
import "../../shared";

pub struct FeedItem {
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

pub struct FeedPage {
    posts: [FeedItem],
    next_cursor: str
}

pub fn new_feed_item(id: str, author_id: str, author_username: str, author_display_name: str, author_avatar_path: str, body: str, created_at: int, updated_at: int, like_count: int, liked_by_me: bool) -> result[FeedItem, str] {
    let a = shared.post_id(id);
    guard let pid = a else let e = err_of(a) { return err(e); }
    let b = shared.user_id(author_id);
    guard let aid = b else let e = err_of(b) { return err(e); }
    return ok(FeedItem {
        id: pid,
        author_id: aid,
        author_username: author_username,
        author_display_name: author_display_name,
        author_avatar_path: author_avatar_path,
        body: body,
        created_at: created_at as i64,
        updated_at: updated_at as i64,
        like_count: like_count as i64,
        liked_by_me: liked_by_me
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
