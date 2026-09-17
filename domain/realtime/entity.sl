import "../../shared";

pub struct RealtimeSession {
    session_id: str,
    user_id: str,
    connected_at: int
}

pub fn new_session(session_id: str, user_id: str, connected_at: int) -> result[RealtimeSession, str] {
    if len(session_id) == 0 {
        return err(shared.invalid_argument);
    }
    let a = shared.user_id(user_id);
    guard let uid = a else let e = err_of(a) { return err(e); }
    return ok(RealtimeSession {
        session_id: session_id,
        user_id: uid,
        connected_at: connected_at
    });
}
