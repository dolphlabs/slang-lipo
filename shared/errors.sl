// shared/errors — common error strings for the social API.

pub let not_found = "not_found";
pub let unauthorized = "unauthorized";
pub let forbidden = "forbidden";
pub let conflict = "conflict";
pub let invalid_argument = "invalid_argument";
pub let not_implemented = "not_implemented";
pub let internal = "internal";
pub let email_unverified = "email_unverified";

pub fn not_implemented_err() -> result[bool, str] {
    return err(not_implemented);
}
