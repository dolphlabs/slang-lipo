import "../../shared";

pub fn handle_connect(session_id: str) -> result[bool, str] {
    let _discard_session_id = session_id;
    return err(shared.not_implemented);
}
