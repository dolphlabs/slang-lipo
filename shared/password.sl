// shared/password — salt + HMAC-SHA256(pepper, salt||password).
import "crypto";
import "encoding";

pub fn hash_password(pepper: str, password: str) -> result[[str], str] {
    let sr = crypto.rand(16);
    guard let salt = sr else let e = err_of(sr) {
        return err(e);
    }
    let digest = crypto.hmac_sha256(to_bytes(pepper), salt + to_bytes(password));
    let out: [str] = [encoding.hex_encode(salt), encoding.hex_encode(digest)];
    return ok(out);
}

pub fn verify_password(pepper: str, password: str, salt_hex: str, hash_hex: str) -> bool {
    let sd = encoding.hex_decode(salt_hex);
    guard let salt = sd else {
        return false;
    }
    let digest = crypto.hmac_sha256(to_bytes(pepper), salt + to_bytes(password));
    let got = encoding.hex_encode(digest);
    return got == hash_hex;
}

pub fn hmac_hex(pepper: str, msg: bytes) -> str {
    return encoding.hex_encode(crypto.hmac_sha256(to_bytes(pepper), msg));
}

pub fn hmac_str_hex(pepper: str, msg: str) -> str {
    return hmac_hex(pepper, to_bytes(msg));
}
