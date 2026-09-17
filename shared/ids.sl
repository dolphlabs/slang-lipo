// shared/ids — id / token helpers.
import "crypto";
import "encoding";

pub fn require_nonempty(id: str, label: str) -> result[str, str] {
    if len(id) == 0 {
        return err(label + " must be non-empty");
    }
    return ok(id);
}

pub fn user_id(raw: str) -> result[str, str] {
    return require_nonempty(raw, "user id");
}

pub fn post_id(raw: str) -> result[str, str] {
    return require_nonempty(raw, "post id");
}

pub fn new_hex_id(nbytes: int) -> result[str, str] {
    let rr = crypto.rand(nbytes);
    guard let b = rr else let e = err_of(rr) {
        return err(e);
    }
    return ok(encoding.hex_encode(b));
}

pub fn new_id() -> result[str, str] {
    return new_hex_id(16);
}

pub fn new_session_token() -> result[str, str] {
    return new_hex_id(32);
}
