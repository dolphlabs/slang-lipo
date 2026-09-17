# Lipo

Lipo is a social-media **backend** written in [Slang](https://slang.dolphlabs.com/). It exposes a REST API (SQLite) plus **WebSockets** for realtime (including 1:1 DMs).

This README is the living overview — update it whenever a module lands or an endpoint changes.

| | |
|---|---|
| **Language** | [Slang](https://slang.dolphlabs.com/) (`slangc`) |
| **API** | HTTP/JSON REST · OpenAPI `docs/openapi.json` (**v0.6.0**) |
| **Realtime** | WebSocket `GET /ws` (RFC 6455 over `link`) |
| **Store** | SQLite (`LIPO_DB_PATH`, default `lipo.db`) · schema **v4** |
| **Mail** | [Resend](https://resend.com/) via `httpc` (or mail-dev logging) |
| **Layout** | DDD · plain `struct` for DTOs · `gc struct` for services/repos |
| **Repo** | [dolphlabs/slang-lipo](https://github.com/dolphlabs/slang-lipo) |

---

## Status

### Done

- [x] Scaffold + DDD tree
- [x] Auth (signup / verify / signin / sessions / logout / me)
- [x] Profile, settings, avatar (multipart file upload), password/email change, deactivate
- [x] Posts CRUD
- [x] Social (follow / like)
- [x] Home feed (cursor pagination)
- [x] Standardized `{error, message}` errors
- [x] OpenAPI living spec
- [x] **WebSockets** (`/ws?token=…`)
- [x] **1:1 chats / DMs** (REST + live `chat.message` pushes)

### Next

- [ ] Password reset
- [ ] Richer notifications / more realtime event types (likes, follows, …)
- [ ] Media on posts
- [ ] Hardening (rate limits, production deploy notes)

---

## Architecture

```
lipo/
├── main.sl
├── config/                 # env + .env loader
├── shared/                 # ids, password, errors, sha1 (WS Accept)
├── domain/                 # user, post, social, feed, chat, realtime
├── application/            # use-cases
├── infrastructure/
│   ├── sqlite/             # repos + migrations (v4: conversations/messages)
│   ├── email/              # Resend / mail-dev
│   ├── storage/            # avatars
│   ├── http/               # TCP server
│   ├── httpread/           # Expect:100-continue + O(n) body copy
│   └── ws/                 # handshake, frames, hub
├── interfaces/
│   ├── http/               # REST routes (incl. chats)
│   └── ws/                 # WS session handler
└── docs/openapi.json
```

**`struct` vs `gc struct`:** plain `struct` for entities/DTOs; `gc struct` for services, repos, hub.

---

## Quick start

```bash
cd /path/to/lipo
cp .env.example .env   # only if missing — never clobber a filled .env
make run               # slangc main.sl --run
```

Health: `curl -s http://127.0.0.1:8080/health`

**Never delete or overwrite `.env` when syncing code.**

### Smoke

```bash
slangc smoke_chat/main.sl -o smoke_chat_bin && LIPO_MAIL_DEV=1 ./smoke_chat_bin
```

(`smoke_*` folders are gitignored — keep them locally.)

---

## Configuration

| Variable | Notes |
|----------|--------|
| `LIPO_DB_PATH` | default `lipo.db` |
| `LIPO_HTTP_ADDR` / `LIPO_HTTP_PORT` | default `0.0.0.0:8080` |
| `LIPO_UPLOAD_DIR` | default `data/uploads` |
| `LIPO_AUTH_PEPPER` | password HMAC pepper |
| `LIPO_MAIL_DEV` | `1` = log codes; `0` = Resend when key set |
| `RESEND_API_KEY` / `RESEND_FROM` | mail |

---

## API overview

Full contract: [`docs/openapi.json`](docs/openapi.json). Auth: `Authorization: Bearer <token>`.

Errors: `{ "error": "<code>", "message": "<sentence>" }`.

### Auth / profile / posts / social / feed

See OpenAPI tags **Auth**, **Profile**, **Posts**, **Social**, **Feed**. Avatar: multipart field `avatar` (or raw `image/*` body) — not base64 JSON. Server answers `Expect: 100-continue` (Apidog).

### Chats (REST)

| Method | Path | Notes |
|--------|------|--------|
| `POST` | `/chats/dm` | `{ "username" }` create-or-get 1:1 |
| `GET` | `/chats` | list my conversations |
| `GET` | `/chats/:id/messages` | `?limit=&cursor=` |
| `POST` | `/chats/:id/messages` | `{ "body" }` persist + WS push to both users |

---

## WebSocket

```
ws://localhost:8080/ws?token=<session_token>
```

Fallback: connect then send text frame `{"type":"auth","token":"..."}` → `auth.ok`.

Live push example:

```json
{
  "type": "chat.message",
  "payload": {
    "id": "...",
    "conversation_id": "...",
    "sender_id": "...",
    "body": "hello",
    "created_at": 0
  }
}
```

`POST /chats/:id/messages` publishes that envelope to **both** participants’ connections (hub keyed by `user_id`). Ping/pong and close are handled. Pure RFC 6455 over `link` (no stdlib WS package); Accept uses `shared/sha1.sl` + base64.

---

## Keeping docs honest

When routes change: implement → bump OpenAPI → update this README → prefer a smoke path.

---

## License / attribution

Dolph Labs (`dolphlabs/slang-lipo`). Built with Slang — [slang.dolphlabs.com](https://slang.dolphlabs.com/).
