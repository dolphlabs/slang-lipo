import "../../shared";

pub struct Post {
    id: str,
    author_id: str,
    body: str,
    created_at: int,
    updated_at: int,
    like_count: int,
    media_path: str
}

pub struct PostPublic {
    id: str,
    author_id: str,
    body: str,
    created_at: i64,
    updated_at: i64,
    like_count: i64,
    media_url: str
}

impl Post {
    fn has_body(self: Post) -> bool {
        return len(self.body) > 0;
    }
}

pub fn media_url_of(p: Post) -> str {
    if len(p.media_path) == 0 {
        return "";
    }
    return "/media/" + p.id;
}

pub fn to_public(p: Post) -> PostPublic {
    return PostPublic {
        id: p.id,
        author_id: p.author_id,
        body: p.body,
        created_at: p.created_at as i64,
        updated_at: p.updated_at as i64,
        like_count: p.like_count as i64,
        media_url: media_url_of(p)
    };
}

pub fn new_post(id: str, author_id: str, body: str, created_at: int) -> result[Post, str] {
    let idr = shared.post_id(id);
    guard let pid = idr else let e = err_of(idr) {
        return err(e);
    }
    let aidr = shared.user_id(author_id);
    guard let aid = aidr else let e = err_of(aidr) {
        return err(e);
    }
    if len(body) == 0 {
        return err(shared.invalid_argument);
    }
    let p = Post {
        id: pid,
        author_id: aid,
        body: body,
        created_at: created_at,
        updated_at: created_at,
        like_count: 0,
        media_path: ""
    };
    if !p.has_body() {
        return err(shared.invalid_argument);
    }
    return ok(p);
}
