// shared/errors — machine-readable codes + human messages for the social API.

pub let invalid_argument = "invalid_argument";
pub let invalid_json = "invalid_json";
pub let invalid_base64 = "invalid_base64";

pub let invalid_email = "invalid_email";
pub let invalid_username = "invalid_username";
pub let weak_password = "weak_password";
pub let invalid_code = "invalid_code";
pub let invalid_cursor = "invalid_cursor";
pub let invalid_avatar = "invalid_avatar";
pub let invalid_media = "invalid_media";
pub let rate_limited = "rate_limited";
pub let empty_post_body = "empty_post_body";
pub let empty_message = "empty_message";

pub let unauthorized = "unauthorized";
pub let invalid_credentials = "invalid_credentials";
pub let invalid_token = "invalid_token";
pub let account_deactivated = "account_deactivated";

pub let email_unverified = "email_unverified";
pub let already_verified = "already_verified";
pub let forbidden = "forbidden";

pub let not_found = "not_found";
pub let conflict = "conflict";
pub let email_taken = "email_taken";
pub let username_taken = "username_taken";

pub let cannot_follow_self = "cannot_follow_self";
pub let not_implemented = "not_implemented";
pub let internal = "internal";

pub fn message_of(code: str) -> str {
    if code == invalid_argument {
        return "Invalid request.";
    }
    if code == invalid_json {
        return "Request body is not valid JSON.";
    }
    if code == invalid_base64 {
        return "Request data is not valid base64.";
    }
    if code == invalid_email {
        return "Please provide a valid email address.";
    }
    if code == invalid_username {
        return "Username must be 3–32 characters and use only letters, numbers, or underscores.";
    }
    if code == weak_password {
        return "Password must be at least 8 characters.";
    }
    if code == invalid_code {
        return "Invalid or expired verification code.";
    }
    if code == invalid_cursor {
        return "Pagination cursor is invalid.";
    }
    if code == invalid_avatar {
        return "Avatar must be a JPEG or PNG image under 2MB.";
    }
    if code == invalid_media {
        return "Media must be a JPEG or PNG image under 2MB.";
    }
    if code == rate_limited {
        return "Too many requests. Please slow down.";
    }
    if code == empty_post_body {
        return "Post body cannot be empty.";
    }
    if code == empty_message {
        return "Message body cannot be empty.";
    }
    if code == unauthorized {
        return "Authentication required.";
    }
    if code == invalid_credentials {
        return "Invalid email or password.";
    }
    if code == invalid_token {
        return "Missing or invalid access token.";
    }
    if code == account_deactivated {
        return "This account has been deactivated.";
    }
    if code == email_unverified {
        return "Please verify your email before signing in.";
    }
    if code == already_verified {
        return "This email is already verified.";
    }
    if code == forbidden {
        return "You do not have permission to perform this action.";
    }
    if code == not_found {
        return "Resource not found.";
    }
    if code == conflict {
        return "Conflict with existing resource.";
    }
    if code == email_taken {
        return "That email is already registered.";
    }
    if code == username_taken {
        return "That username is already taken.";
    }
    if code == cannot_follow_self {
        return "You cannot follow yourself.";
    }
    if code == not_implemented {
        return "This endpoint is not implemented yet.";
    }
    return "Internal server error.";
}

pub fn status_of(code: str) -> i32 {
    if code == invalid_argument || code == invalid_json || code == invalid_base64 {
        return 400;
    }
    if code == invalid_email || code == invalid_username || code == weak_password {
        return 400;
    }
    if code == invalid_code || code == invalid_cursor || code == invalid_avatar || code == invalid_media {
        return 400;
    }
    if code == rate_limited {
        return 429;
    }
    if code == empty_post_body || code == empty_message || code == cannot_follow_self {
        return 400;
    }
    if code == unauthorized || code == invalid_credentials || code == invalid_token || code == account_deactivated {
        return 401;
    }
    if code == forbidden || code == email_unverified || code == already_verified {
        return 403;
    }
    if code == not_found {
        return 404;
    }
    if code == conflict || code == email_taken || code == username_taken {
        return 409;
    }
    return 500;
}

pub fn not_implemented_err() -> result[bool, str] {
    return err(not_implemented);
}
