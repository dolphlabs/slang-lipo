import "time";
import "../../domain/post" as post_domain;
import "../../infrastructure/sqlite" as sqlite;
import "../../shared";

pub gc struct PostService {
    repo: sqlite.SqlitePostRepo,
    users: sqlite.SqliteUserRepo
}

pub fn new_service(repo: sqlite.SqlitePostRepo, users: sqlite.SqliteUserRepo) -> PostService {
    return PostService { repo: repo, users: users };
}

fn now_secs() -> int {
    return time.wall() / 1000000000;
}

fn valid_body(body: str) -> bool {
    let n = len(body);
    return n >= 1 && n <= 4000;
}

pub fn create(svc: PostService, author_id: str, body_raw: str) -> result[post_domain.Post, str] {
    let body = body_raw;
    if !valid_body(body) {
        return err(shared.invalid_argument);
    }
    let idr = shared.new_id();
    guard let pid = idr else let e = err_of(idr) {
        return err(e);
    }
    let now = now_secs();
    let pr = post_domain.new_post(pid, author_id, body, now);
    guard let p = pr else let e = err_of(pr) {
        return err(e);
    }
    let ir = sqlite.insert_post(svc.repo, p);
    guard let _i = ir else let e = err_of(ir) {
        return err(e);
    }
    return ok(p);
}

pub fn get(svc: PostService, id: str) -> result[post_domain.Post, str] {
    return sqlite.find_post_by_id(svc.repo, id);
}

pub fn list_by_username(svc: PostService, username: str, limit_raw: int) -> result[[post_domain.Post], str] {
    let limit = limit_raw;
    if limit <= 0 {
        limit = 20;
    }
    if limit > 50 {
        limit = 50;
    }
    let ur = sqlite.find_auth_by_username(svc.users, username);
    guard let row = ur else let e = err_of(ur) {
        return err(e);
    }
    if row.deactivated_at != 0 {
        return err(shared.not_found);
    }
    return sqlite.list_by_author_id(svc.repo, row.id, limit);
}

pub fn update(svc: PostService, token_user_id: str, id: str, body_raw: str) -> result[post_domain.Post, str] {
    if !valid_body(body_raw) {
        return err(shared.invalid_argument);
    }
    let gr = sqlite.find_post_by_id(svc.repo, id);
    guard let p = gr else let e = err_of(gr) {
        return err(e);
    }
    if p.author_id != token_user_id {
        return err(shared.forbidden);
    }
    let now = now_secs();
    let ur = sqlite.update_post_body(svc.repo, id, body_raw, now);
    guard let _u = ur else let e = err_of(ur) {
        return err(e);
    }
    return sqlite.find_post_by_id(svc.repo, id);
}

pub fn delete(svc: PostService, token_user_id: str, id: str) -> result[bool, str] {
    let gr = sqlite.find_post_by_id(svc.repo, id);
    guard let p = gr else let e = err_of(gr) {
        return err(e);
    }
    if p.author_id != token_user_id {
        return err(shared.forbidden);
    }
    return sqlite.delete_post(svc.repo, id);
}
