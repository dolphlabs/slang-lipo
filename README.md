# Lipo

Slang social-media backend (SQLite): auth, profiles, posts (+ media), social graph, home feed, 1:1 DMs, WebSockets, password reset.

## Status

| Area | Status |
|------|--------|
| Auth (signup / verify / signin / session) | Done |
| Password forgot / reset | Done |
| Profile + avatar + settings | Done |
| Posts + likes + media | Done |
| Follow graph | Done |
| Home feed (cursor pagination) | Done |
| WebSocket `/ws` (RFC 6455) | Done |
| Realtime: `post.created` / `post.liked` / `user.followed` | Done |
| 1:1 chats / DMs + typing / read | Done |
| Rate limits (auth + message send) | Done |
| Session expiry sweep | Done |

Schema migrations currently at **v7** (`conversation_reads`, `password_resets`, `posts.media_path`).

## Run

```bash
cp .env.example .env   # set LIPO_AUTH_PEPPER
slangc main.sl --run
# or: make run
```

Default: `http://0.0.0.0:8080` (`LIPO_HTTP_PORT`).

## HTTP API (Bearer)

| Method | Path | Notes |
|--------|------|-------|
| GET | `/health` | Liveness |
| POST | `/auth/signup` | `{email,username,password}` |
| POST | `/auth/verify` | `{email,code}` |
| POST | `/auth/signin` | `{login,password}` → `{token,user}` |
| POST | `/auth/password/forgot` | `{email}` — always generic success |
| POST | `/auth/password/reset` | `{email,code,new_password}` |
| GET | `/auth/me` | Current user |
| POST | `/auth/logout` | Revoke session |
| GET/PATCH | `/me`, `/me/profile`, `/me/settings`, … | Profile |
| POST/GET/PATCH/DELETE | `/posts`, `/posts/:id` | Posts |
| PUT/POST | `/posts/:id/media` | Multipart field `media` or JSON `{data_base64,content_type}` (jpeg/png ≤2MB) |
| GET | `/media/:id` | Serve post image |
| POST/DELETE/GET | `/users/:username/follow` | Follow |
| POST/DELETE | `/posts/:id/like` | Likes |
| GET | `/feed` | Home timeline |
| POST | `/chats/dm` | `{username}` create-or-get DM |
| GET | `/chats` | List conversations |
| GET | `/chats/:id/messages` | `?limit=&cursor=` |
| POST | `/chats/:id/messages` | `{body}` persist + WS push |

Errors: JSON `{ "error": "<code>", "message": "<human>" }` (see `shared/errors.sl`).

OpenAPI: `docs/openapi.json` (v0.7.0).

### Rate limiting

In-memory token buckets (per process):

- **Auth** (`/auth/signin`, `/signup`, `/password/forgot`, `/password/reset`): capacity 10, refill ~1/s, keyed by path+body prefix → HTTP **429** `rate_limited`.
- **Message send** (`POST …/messages`): capacity 30, refill ~1/s, keyed by `Authorization` header prefix.

### Sessions

Expired sessions are revoked on boot and opportunistically on sign-in.

## WebSocket

Connect after sign-in:

```
ws://localhost:8080/ws?token=<session_token>
```

Preferred auth is the `token` query param (same hex session token as `Authorization: Bearer`).

Fallback: connect without token, then send a text frame:

```json
{"type":"auth","token":"<session_token>"}
```

Server replies with `{"type":"auth.ok","payload":{"user_id":"..."}}` on success, or closes with an error envelope.

### Server → client events

Envelope shape: `{"type":"...","payload":{...}}`

| type | When |
|------|------|
| `chat.message` | New DM (REST send) |
| `post.created` | New post → author + followers |
| `post.liked` | Like → post author (+ liker) |
| `user.followed` | Follow → followee |
| `typing` | Peer is typing |
| `chat.read` | Peer marked read |

### Client → server (after auth)

```json
{"type":"typing","payload":{"conversation_id":"..."}}
{"type":"chat.read","payload":{"conversation_id":"...","message_id":"..."}}
```

`typing` is relayed to the other participant (and other devices of the sender; not echoed on the same connection). `chat.read` persists `conversation_reads` and pushes `chat.read` to the peer.

Ping/pong and close frames are handled. Implementation is pure RFC 6455 over `link` (no stdlib WebSocket package); Accept uses `shared/sha1.sl` + base64.

## Layout

DDD-ish packages: `domain/`, `application/`, `infrastructure/`, `interfaces/`, `shared/`, `config/`.
