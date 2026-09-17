import "http";
import "json";
import "../../application/user" as user_app;
import "../../application/post" as post_app;
import "../../domain/post" as post_domain;

gc struct PostDto {
    id: str,
    author_id: str,
    body: str,
    created_at: i64,
    updated_at: i64,
    like_count: i64
}

gc struct PostBodyReq {
    body: str
}

gc struct PostsListDto {
    posts: [PostDto]
}

pub fn posts_collection_path() -> str {
    return "/posts";
}

fn post_dto(p: post_domain.PostPublic) -> PostDto {
    return PostDto {
        id: p.id,
        author_id: p.author_id,
        body: p.body,
        created_at: p.created_at,
        updated_at: p.updated_at,
        like_count: p.like_count
    };
}

fn dto_from_post(p: post_domain.Post) -> PostDto {
    let pubp = post_domain.to_public(p);
    return post_dto(pubp);
}

pub fn handle_create_post(users: user_app.UserService, posts: post_app.PostService, req: http.Request) -> http.Response {
    let token = bearer_token(req);
    let uidr = user_app.user_id_from_token(users, token);
    guard let uid = uidr else let e = err_of(uidr) {
        return map_err(e);
    }
    let dr: result[PostBodyReq, str] = json.decode(req.body);
    guard let body = dr else let e = err_of(dr) {
        return http.bad_request("invalid JSON: " + e);
    }
    let rr = post_app.create(posts, uid, body.body);
    guard let p = rr else let e = err_of(rr) {
        return map_err(e);
    }
    return http.created_json(json.encode(dto_from_post(p)));
}

pub fn handle_get_post(posts: post_app.PostService, id: str) -> http.Response {
    let rr = post_app.get(posts, id);
    guard let p = rr else let e = err_of(rr) {
        return map_err(e);
    }
    return http.ok_json(json.encode(dto_from_post(p)));
}

pub fn handle_list_user_posts(posts: post_app.PostService, username: str) -> http.Response {
    let rr = post_app.list_by_username(posts, username, 50);
    guard let list = rr else let e = err_of(rr) {
        return map_err(e);
    }
    let out: [PostDto] = [];
    let i = 0;
    while i < len(list) {
        push(out, dto_from_post(list[i]));
        i = i + 1;
    }
    return http.ok_json(json.encode(PostsListDto { posts: out }));
}

pub fn handle_patch_post(users: user_app.UserService, posts: post_app.PostService, req: http.Request, id: str) -> http.Response {
    let token = bearer_token(req);
    let uidr = user_app.user_id_from_token(users, token);
    guard let uid = uidr else let e = err_of(uidr) {
        return map_err(e);
    }
    let dr: result[PostBodyReq, str] = json.decode(req.body);
    guard let body = dr else let e = err_of(dr) {
        return http.bad_request("invalid JSON: " + e);
    }
    let rr = post_app.update(posts, uid, id, body.body);
    guard let p = rr else let e = err_of(rr) {
        return map_err(e);
    }
    return http.ok_json(json.encode(dto_from_post(p)));
}

pub fn handle_delete_post(users: user_app.UserService, posts: post_app.PostService, req: http.Request, id: str) -> http.Response {
    let token = bearer_token(req);
    let uidr = user_app.user_id_from_token(users, token);
    guard let uid = uidr else let e = err_of(uidr) {
        return map_err(e);
    }
    let rr = post_app.delete(posts, uid, id);
    guard let _ok = rr else let e = err_of(rr) {
        return map_err(e);
    }
    return http.ok_json(json.encode(OkBody { ok: true }));
}
