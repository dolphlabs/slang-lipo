import "json";
import "strings";
import "time";
import "../../domain/post" as post_domain;
import "../../infrastructure/sqlite" as sqlite;
import "../../infrastructure/storage" as storage;
import "../../infrastructure/ws" as wshub;
import "../../shared";

pub gc struct PostService {
    repo: sqlite.SqlitePostRepo,
    users: sqlite.SqliteUserRepo,
    social: sqlite.SqliteSocialRepo,
    hub: wshub.Hub,
    upload_dir: str
}

pub fn new_service(repo: sqlite.SqlitePostRepo, users: sqlite.SqliteUserRepo, social: sqlite.SqliteSocialRepo, hub: wshub.Hub, upload_dir: str) -> PostService {
    return PostService { repo: repo, users: users, social: social, hub: hub, upload_dir: upload_dir };
}

fn now_secs() -> int {
    return time.wall() / 1000000000;
}

fn valid_body(body: str) -> bool {
    let n = len(body);
    return n >= 1 && n <= 4000;
}

gc struct PostCreatedPayload {
    id: str,
    author_id: str,
    body: str,
    created_at: i64,
    updated_at: i64,
    like_count: i64
}

fn push_post_created(svc: PostService, p: post_domain.Post) {
    let payload = PostCreatedPayload {
        id: p.id,
        author_id: p.author_id,
        body: p.body,
        created_at: p.created_at as i64,
        updated_at: p.updated_at as i64,
        like_count: p.like_count as i64
    };
    let text = "{\"type\":\"post.created\",\"payload\":" + json.encode(payload) + "}";
    wshub.publish(svc.hub, p.author_id, text);
    let fr = sqlite.list_follower_ids(svc.social, p.author_id, 2000);
    guard let ids = fr else let e = err_of(fr) {
        let _discard = e;
        return;
    }
    let i = 0;
    while i < len(ids) {
        if ids[i] != p.author_id {
            wshub.publish(svc.hub, ids[i], text);
        }
        i = i + 1;
    }
}

pub fn create(svc: PostService, author_id: str, body_raw: str) -> result[post_domain.Post, str] {
    let body = body_raw;
    if len(body) == 0 {
        return err(shared.empty_post_body);
    }
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
    push_post_created(svc, p);
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
    if len(body_raw) == 0 {
        return err(shared.empty_post_body);
    }
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

fn is_jpeg(b: bytes) -> bool {
    return len(b) >= 2 && b[0] == 255 && b[1] == 216;
}

fn is_png(b: bytes) -> bool {
    return len(b) >= 4 && b[0] == 137 && b[1] == 80 && b[2] == 78 && b[3] == 71;
}

pub struct MediaBlob {
    content_type: str,
    data: bytes
}

pub fn set_media(svc: PostService, token_user_id: str, post_id: str, data: bytes, content_type: str) -> result[post_domain.Post, str] {
    let gr = sqlite.find_post_by_id(svc.repo, post_id);
    guard let p = gr else let e = err_of(gr) {
        return err(e);
    }
    if p.author_id != token_user_id {
        return err(shared.forbidden);
    }
    if len(data) == 0 || len(data) > 2097152 {
        return err(shared.invalid_media);
    }
    let ct = strings.to_lower(strings.trim(content_type));
    let ext = "";
    if ct == "image/jpeg" || ct == "image/jpg" {
        if !is_jpeg(data) {
            return err(shared.invalid_media);
        }
        ext = "jpg";
    } else if ct == "image/png" {
        if !is_png(data) {
            return err(shared.invalid_media);
        }
        ext = "png";
    } else {
        // sniff magic bytes when multipart omits type
        if is_jpeg(data) {
            ext = "jpg";
            ct = "image/jpeg";
        } else if is_png(data) {
            ext = "png";
            ct = "image/png";
        } else {
            return err(shared.invalid_media);
        }
    }
    let wr = storage.write_post_media(svc.upload_dir, post_id, ext, data);
    guard let path = wr else let e = err_of(wr) {
        return err(e);
    }
    let now = now_secs();
    let ur = sqlite.set_post_media_path(svc.repo, post_id, path, now);
    guard let _u = ur else let e = err_of(ur) {
        return err(e);
    }
    return sqlite.find_post_by_id(svc.repo, post_id);
}

pub fn get_media(svc: PostService, post_id: str) -> result[MediaBlob, str] {
    let gr = sqlite.find_post_by_id(svc.repo, post_id);
    guard let p = gr else let e = err_of(gr) {
        return err(e);
    }
    if len(p.media_path) == 0 {
        return err(shared.not_found);
    }
    let rr = storage.read_file(p.media_path);
    guard let data = rr else let e = err_of(rr) {
        return err(e);
    }
    return ok(MediaBlob {
        content_type: storage.content_type_for_path(p.media_path),
        data: data
    });
}
