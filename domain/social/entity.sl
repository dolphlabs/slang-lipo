import "../../shared";

pub struct Follow {
    follower_id: str,
    followee_id: str,
    created_at: int
}

pub struct Like {
    user_id: str,
    post_id: str,
    created_at: int
}

pub fn new_follow(follower_id: str, followee_id: str, created_at: int) -> result[Follow, str] {
    let a = shared.user_id(follower_id);
    guard let fid = a else let e = err_of(a) { return err(e); }
    let b = shared.user_id(followee_id);
    guard let eid = b else let e = err_of(b) { return err(e); }
    if fid == eid {
        return err(shared.invalid_argument);
    }
    return ok(Follow { follower_id: fid, followee_id: eid, created_at: created_at });
}

pub fn new_like(user_id: str, post_id: str, created_at: int) -> result[Like, str] {
    let a = shared.user_id(user_id);
    guard let uid = a else let e = err_of(a) { return err(e); }
    let b = shared.post_id(post_id);
    guard let pid = b else let e = err_of(b) { return err(e); }
    return ok(Like { user_id: uid, post_id: pid, created_at: created_at });
}
