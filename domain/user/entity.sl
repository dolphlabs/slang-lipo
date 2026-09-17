// domain/user — User entity + auth / profile value types.
import "../../shared";

pub struct User {
    id: str,
    email: str,
    username: str,
    display_name: str,
    bio: str,
    avatar_path: str,
    website: str,
    location: str,
    pronouns: str,
    is_private: bool,
    show_email: bool,
    allow_dms: bool,
    notify_likes: bool,
    notify_follows: bool,
    notify_mentions: bool,
    email_verified: bool,
    created_at: int,
    updated_at: int,
    deactivated_at: int
}

// Full card for /auth/me and /me/* (includes email).
pub struct UserPublic {
    id: str,
    email: str,
    username: str,
    display_name: str,
    bio: str,
    avatar_path: str,
    website: str,
    location: str,
    pronouns: str,
    is_private: bool,
    show_email: bool,
    allow_dms: bool,
    notify_likes: bool,
    notify_follows: bool,
    notify_mentions: bool,
    email_verified: bool,
    created_at: i64,
    updated_at: i64,
    deactivated_at: i64
}

// Public profile card — no email (always omitted on GET by username).
pub struct UserProfile {
    id: str,
    username: str,
    display_name: str,
    bio: str,
    avatar_path: str,
    website: str,
    location: str,
    pronouns: str,
    is_private: bool,
    created_at: i64
}

pub struct UserSettings {
    is_private: bool,
    show_email: bool,
    allow_dms: bool,
    notify_likes: bool,
    notify_follows: bool,
    notify_mentions: bool
}

pub struct AuthSession {
    token: str,
    user: UserPublic
}

pub struct SignupResult {
    user: UserPublic,
    verification_sent: bool
}

impl User {
    fn has_username(self: User) -> bool {
        return len(self.username) > 0;
    }
}

pub fn to_public(u: User) -> UserPublic {
    return UserPublic {
        id: u.id,
        email: u.email,
        username: u.username,
        display_name: u.display_name,
        bio: u.bio,
        avatar_path: u.avatar_path,
        website: u.website,
        location: u.location,
        pronouns: u.pronouns,
        is_private: u.is_private,
        show_email: u.show_email,
        allow_dms: u.allow_dms,
        notify_likes: u.notify_likes,
        notify_follows: u.notify_follows,
        notify_mentions: u.notify_mentions,
        email_verified: u.email_verified,
        created_at: u.created_at as i64,
        updated_at: u.updated_at as i64,
        deactivated_at: u.deactivated_at as i64
    };
}

pub fn to_profile(u: User) -> UserProfile {
    return UserProfile {
        id: u.id,
        username: u.username,
        display_name: u.display_name,
        bio: u.bio,
        avatar_path: u.avatar_path,
        website: u.website,
        location: u.location,
        pronouns: u.pronouns,
        is_private: u.is_private,
        created_at: u.created_at as i64
    };
}

pub fn to_settings(u: User) -> UserSettings {
    return UserSettings {
        is_private: u.is_private,
        show_email: u.show_email,
        allow_dms: u.allow_dms,
        notify_likes: u.notify_likes,
        notify_follows: u.notify_follows,
        notify_mentions: u.notify_mentions
    };
}

pub fn new_user(id: str, email: str, username: str, display_name: str, created_at: int) -> result[User, str] {
    let idr = shared.user_id(id);
    guard let uid = idr else let e = err_of(idr) {
        return err(e);
    }
    if len(username) == 0 {
        return err(shared.invalid_argument);
    }
    if len(email) == 0 {
        return err(shared.invalid_argument);
    }
    let u = User {
        id: uid,
        email: email,
        username: username,
        display_name: display_name,
        bio: "",
        avatar_path: "",
        website: "",
        location: "",
        pronouns: "",
        is_private: false,
        show_email: false,
        allow_dms: true,
        notify_likes: true,
        notify_follows: true,
        notify_mentions: true,
        email_verified: false,
        created_at: created_at,
        updated_at: 0,
        deactivated_at: 0
    };
    if !u.has_username() {
        return err(shared.invalid_argument);
    }
    return ok(u);
}
