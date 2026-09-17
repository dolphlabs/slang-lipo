import "sql";
import "../../domain/post" as post_domain;
import "../../shared";

pub gc struct SqlitePostRepo {
    db: rawptr
}

pub fn new_post_repo(db: rawptr) -> SqlitePostRepo {
    return SqlitePostRepo { db: db };
}

pub fn as_post_port(repo: SqlitePostRepo) -> post_domain.PostRepository {
    let _discard_repo = repo;
    return post_domain.new_post_repository();
}

fn post_row_from_stmt(st: rawptr) -> post_domain.Post {
    return post_domain.Post {
        id: sql.col_text(st, 0),
        author_id: sql.col_text(st, 1),
        body: sql.col_text(st, 2),
        created_at: sql.col_int(st, 3),
        updated_at: sql.col_int(st, 4),
        like_count: sql.col_int(st, 5),
        media_path: sql.col_text(st, 6)
    };
}

pub fn insert_post(repo: SqlitePostRepo, p: post_domain.Post) -> result[bool, str] {
    let pr = sql.prepare(repo.db, "INSERT INTO posts (id, author_id, body, created_at, updated_at, like_count, media_path) VALUES (?, ?, ?, ?, ?, ?, ?)");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_text(st, 1, p.id);
    sql.bind_text(st, 2, p.author_id);
    sql.bind_text(st, 3, p.body);
    sql.bind_int(st, 4, p.created_at);
    sql.bind_int(st, 5, p.updated_at);
    sql.bind_int(st, 6, p.like_count);
    sql.bind_text(st, 7, p.media_path);
    let sr = sql.step(st);
    sql.finalize(st);
    guard let _done = sr else let e = err_of(sr) {
        return err(e);
    }
    return ok(true);
}

pub fn find_post_by_id(repo: SqlitePostRepo, id: str) -> result[post_domain.Post, str] {
    let pr = sql.prepare(repo.db, "SELECT id, author_id, body, created_at, updated_at, like_count, media_path FROM posts WHERE id = ?");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_text(st, 1, id);
    let sr = sql.step(st);
    guard let more = sr else let e = err_of(sr) {
        sql.finalize(st);
        return err(e);
    }
    if !more {
        sql.finalize(st);
        return err(shared.not_found);
    }
    let row = post_row_from_stmt(st);
    sql.finalize(st);
    return ok(row);
}

pub fn list_by_author_id(repo: SqlitePostRepo, author_id: str, limit: int) -> result[[post_domain.Post], str] {
    let pr = sql.prepare(repo.db, "SELECT id, author_id, body, created_at, updated_at, like_count, media_path FROM posts WHERE author_id = ? ORDER BY created_at DESC LIMIT ?");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_text(st, 1, author_id);
    sql.bind_int(st, 2, limit);
    let out: [post_domain.Post] = [];
    while true {
        let sr = sql.step(st);
        guard let more = sr else let e = err_of(sr) {
            sql.finalize(st);
            return err(e);
        }
        if !more {
            break;
        }
        push(out, post_row_from_stmt(st));
    }
    sql.finalize(st);
    return ok(out);
}

pub fn update_post_body(repo: SqlitePostRepo, id: str, body: str, updated_at: int) -> result[bool, str] {
    let pr = sql.prepare(repo.db, "UPDATE posts SET body = ?, updated_at = ? WHERE id = ?");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_text(st, 1, body);
    sql.bind_int(st, 2, updated_at);
    sql.bind_text(st, 3, id);
    let sr = sql.step(st);
    sql.finalize(st);
    guard let _done = sr else let e = err_of(sr) {
        return err(e);
    }
    return ok(true);
}

pub fn set_post_media_path(repo: SqlitePostRepo, id: str, media_path: str, updated_at: int) -> result[bool, str] {
    let pr = sql.prepare(repo.db, "UPDATE posts SET media_path = ?, updated_at = ? WHERE id = ?");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_text(st, 1, media_path);
    sql.bind_int(st, 2, updated_at);
    sql.bind_text(st, 3, id);
    let sr = sql.step(st);
    sql.finalize(st);
    guard let _done = sr else let e = err_of(sr) {
        return err(e);
    }
    return ok(true);
}

pub fn delete_post(repo: SqlitePostRepo, id: str) -> result[bool, str] {
    let pr = sql.prepare(repo.db, "DELETE FROM posts WHERE id = ?");
    guard let st = pr else let e = err_of(pr) {
        return err(e);
    }
    sql.bind_text(st, 1, id);
    let sr = sql.step(st);
    sql.finalize(st);
    guard let _done = sr else let e = err_of(sr) {
        return err(e);
    }
    return ok(true);
}
