// interfaces/http — route dispatch for auth + profile + posts + social + feed + health.
import "http";
import "strings";
import "../../application/user" as user_app;
import "../../application/post" as post_app;
import "../../application/social" as social_app;
import "../../application/feed" as feed_app;
import "../../application/chat" as chat_app;

pub fn strip_query(path: str) -> str {
    let q = strings.find(path, "?");
    if q < 0 {
        return path;
    }
    return strings.slice(path, 0, q);
}

pub fn register() -> [str] {
    let routes: [str] = [
        "GET /health",
        "POST /auth/signup",
        "POST /auth/verify",
        "POST /auth/signin",
        "POST /auth/password/forgot",
        "POST /auth/password/reset",
        "GET /auth/me",
        "POST /auth/logout",
        "GET /users/:username",
        "GET /users/:username/posts",
        "POST /users/:username/follow",
        "DELETE /users/:username/follow",
        "GET /users/:username/follow",
        "GET /users/:username/followers",
        "GET /users/:username/following",
        "PATCH /me",
        "PATCH /me/profile",
        "GET /me/settings",
        "PATCH /me/settings",
        "PUT /me/avatar",
        "DELETE /me/avatar",
        "GET /avatars/:id",
        "POST /me/password",
        "POST /me/email",
        "POST /me/deactivate",
        "POST /posts",
        "GET /posts/:id",
        "PATCH /posts/:id",
        "DELETE /posts/:id",
        "POST /posts/:id/like",
        "DELETE /posts/:id/like",
        "PUT /posts/:id/media",
        "POST /posts/:id/media",
        "GET /media/:id",
        "GET /feed",
        "POST /chats/dm",
        "GET /chats",
        "GET /chats/:id/messages",
        "POST /chats/:id/messages",
        "GET /ws"
    ];
    return routes;
}

pub fn print_routes() {
    let routes = register();
    let i = 0;
    while i < len(routes) {
        println("  route " + routes[i]);
        i = i + 1;
    }
}

pub fn dispatch(svc: user_app.UserService, post_svc: post_app.PostService, social_svc: social_app.SocialService, feed_svc: feed_app.FeedService, chat_svc: chat_app.ChatService, req: http.Request) -> http.Response {
    let path = strip_query(req.path);
    if path == health_path() && req.method == "GET" {
        return http.ok_json("{\"status\":\"" + health_ok() + "\"}");
    }
    if path == "/auth/signup" && req.method == "POST" {
        return handle_signup(svc, req);
    }
    if path == "/auth/verify" && req.method == "POST" {
        return handle_verify(svc, req);
    }
    if path == "/auth/signin" && req.method == "POST" {
        return handle_signin(svc, req);
    }
    if path == "/auth/password/forgot" && req.method == "POST" {
        return handle_forgot_password(svc, req);
    }
    if path == "/auth/password/reset" && req.method == "POST" {
        return handle_reset_password(svc, req);
    }
    if path == "/auth/me" && req.method == "GET" {
        return handle_me(svc, req);
    }
    if path == "/auth/logout" && req.method == "POST" {
        return handle_logout(svc, req);
    }
    if (path == "/me" || path == "/me/profile") && req.method == "PATCH" {
        return handle_patch_profile(svc, req);
    }
    if path == "/me/settings" && req.method == "GET" {
        return handle_get_settings(svc, req);
    }
    if path == "/me/settings" && req.method == "PATCH" {
        return handle_patch_settings(svc, req);
    }
    if path == "/me/avatar" && req.method == "PUT" {
        return handle_put_avatar(svc, req);
    }
    if path == "/me/avatar" && req.method == "DELETE" {
        return handle_delete_avatar(svc, req);
    }
    if path == "/me/password" && req.method == "POST" {
        return handle_change_password(svc, req);
    }
    if path == "/me/email" && req.method == "POST" {
        return handle_change_email(svc, req);
    }
    if path == "/me/deactivate" && req.method == "POST" {
        return handle_deactivate(svc, req);
    }
    if path == "/posts" && req.method == "POST" {
        return handle_create_post(svc, post_svc, req);
    }
    if path == feed_path() && req.method == "GET" {
        return handle_get_feed(svc, feed_svc, req);
    }
    if path == "/chats/dm" && req.method == "POST" {
        return handle_create_dm(svc, chat_svc, req);
    }
    if path == "/chats" && req.method == "GET" {
        return handle_list_chats(svc, chat_svc, req);
    }

    let parts = strings.split(path, "/");
    // ["", "users", ":username"] or ["", "users", ":username", "posts"|"follow"|"followers"|"following"]
    // ["", "posts", ":id"] ["", "posts", ":id", "like"] ["", "avatars", ":id"]
    if len(parts) == 4 && parts[1] == "users" {
        let username = parts[2];
        let tail = parts[3];
        if tail == "posts" && req.method == "GET" {
            return handle_list_user_posts(post_svc, username);
        }
        if tail == "followers" && req.method == "GET" {
            return handle_list_followers(social_svc, username);
        }
        if tail == "following" && req.method == "GET" {
            return handle_list_following(social_svc, username);
        }
        if tail == "follow" {
            if req.method == "POST" {
                return handle_follow(svc, social_svc, req, username);
            }
            if req.method == "DELETE" {
                return handle_unfollow(svc, social_svc, req, username);
            }
            if req.method == "GET" {
                return handle_follow_status(svc, social_svc, req, username);
            }
            return http.method_not_allowed();
        }
        return not_found_json();
    }
    if len(parts) == 3 && parts[1] == "users" && req.method == "GET" {
        return handle_get_user(svc, parts[2]);
    }
    if len(parts) == 4 && parts[1] == "chats" && parts[3] == "messages" {
        let id = parts[2];
        if req.method == "GET" {
            return handle_list_messages(svc, chat_svc, req, id);
        }
        if req.method == "POST" {
            return handle_send_message(svc, chat_svc, req, id);
        }
        return http.method_not_allowed();
    }
    if len(parts) == 3 && parts[1] == "avatars" && req.method == "GET" {
        return handle_get_avatar(svc, parts[2]);
    }
    if len(parts) == 4 && parts[1] == "posts" && parts[3] == "like" {
        let id = parts[2];
        if req.method == "POST" {
            return handle_like(svc, social_svc, req, id);
        }
        if req.method == "DELETE" {
            return handle_unlike(svc, social_svc, req, id);
        }
        return http.method_not_allowed();
    }
    if len(parts) == 4 && parts[1] == "posts" && parts[3] == "media" {
        let id = parts[2];
        if req.method == "PUT" || req.method == "POST" {
            return handle_post_media(svc, post_svc, req, id);
        }
        return http.method_not_allowed();
    }
    if len(parts) == 3 && parts[1] == "media" && req.method == "GET" {
        return handle_get_media(post_svc, parts[2]);
    }
    if len(parts) == 3 && parts[1] == "posts" {
        let id = parts[2];
        if req.method == "GET" {
            return handle_get_post(post_svc, id);
        }
        if req.method == "PATCH" {
            return handle_patch_post(svc, post_svc, req, id);
        }
        if req.method == "DELETE" {
            return handle_delete_post(svc, post_svc, req, id);
        }
        return http.method_not_allowed();
    }

    if strings.has_prefix(path, "/auth/") || strings.has_prefix(path, "/me") || path == "/posts" || path == "/chats" || path == "/chats/dm" || path == feed_path() || path == health_path() {
        return http.method_not_allowed();
    }
    return not_found_json();
}
