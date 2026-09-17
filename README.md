# Lipo

Lipo is a social-media **backend** written in [Slang](https://slang.dolphlabs.com/). It exposes a REST API (SQLite persistence today) and is headed toward realtime over WebSockets.

This README is the living overview of the project. Update it whenever a module lands, an endpoint changes, or the ops story shifts.

| | |
|---|---|
| **Language** | [Slang](https://slang.dolphlabs.com/) (`slangc`) |
| **API** | HTTP/JSON REST · OpenAPI `docs/openapi.json` (**v0.5.1**) |
| **Store** | SQLite (`LIPO_DB_PATH`, default `lipo.db`) |
| **Mail** | [Resend](https://resend.com/) via `httpc` (or local code logging in mail-dev mode) |
| **Layout** | Domain-driven design (DDD) with `struct` / `impl`-style services |
| **Repo** | [dolphlabs/slang-lipo](https://github.com/dolphlabs/slang-lipo) |

---

## What it is

Lipo is the server half of a social product: accounts, profiles, posts, follows/likes, and a home feed. Clients talk JSON over HTTP with Bearer session tokens. Avatars are real image files on disk (not base64 in the API). Realtime (live post/like/follow updates) is the next major slice — scaffolding already exists under `domain/realtime`, `application/realtime`, `infrastructure/ws`, and `interfaces/ws`.

Design goals:

- **Clear modules** — auth → profile → posts → social → feed → realtime, one vertical at a time
- **DDD folders** — domain rules stay free of HTTP/SQLite details
- **Predictable API** — every error is `{ "error": "<code>", "message": "<sentence>" }`
- **Local-friendly** — `.env` loading, mail-dev mode, smoke tests you can run offline

---

## Status

### Done

- [x] Project scaffold (`slangc new .`) + DDD tree
- [x] Auth — signup, email verification, signin, sessions, logout, `GET /auth/me`
- [x] Profile — public profile, edit, settings, password/email change, deactivate
- [x] Avatars — multipart (or raw image body) upload; binary storage; `GET /avatars/:id`
- [x] Posts — create / read / update / delete / list by user
- [x] Social — follow / unfollow, follower lists, like / unlike
- [x] Feed — home timeline (follows ∪ own posts), cursor pagination
- [x] OpenAPI spec kept in sync (`docs/openapi.json`)
- [x] Standardized API errors (`shared/errors.sl` + HTTP mappers)

### Next

- [ ] **WebSockets** — authenticated realtime channel; push events for posts, likes, follows (and later notifications)
- [ ] Password reset
- [ ] Richer notifications
- [ ] Media on posts
- [ ] Hardening (rate limits, stronger session hygiene, production deploy notes)

---

## Architecture

```
lipo/
├── main.sl                 # boot: config, migrate, wire services, listen
├── config/                 # env + .env loader
├── shared/                 # ids, password hashing, error codes
├── domain/                 # entities + ports (no I/O)
│   ├── user/
│   ├── post/
│   ├── social/
│   ├── feed/
│   └── realtime/           # stub — next
├── application/            # use-cases / services (gc structs)
│   ├── user/
│   ├── post/
│   ├── social/
│   ├── feed/
│   └── realtime/           # stub — next
├── infrastructure/         # adapters
│   ├── sqlite/             # repos + migrations
│   ├── email/              # Resend / mail-dev
│   ├── storage/            # avatar files
│   ├── http/               # TCP server + connection loop
│   └── ws/                 # hub stub — next
├── interfaces/
│   ├── http/               # routes, DTOs, multipart parser
│   └── ws/                 # connect handler stub — next
├── docs/openapi.json       # machine-readable API contract
├── .env.example
└── Makefile
```

**Layering**

| Layer | Responsibility |
|--------|----------------|
| `domain/` | Entities, validation, ports (interfaces) |
| `application/` | Orchestration: auth rules, feed assembly, side effects (`spawn` for mail) |
| `infrastructure/` | SQLite, Resend, filesystem, HTTP listener, WS hub |
| `interfaces/` | HTTP/WS adapters: parse requests, map errors, shape JSON |

**`struct` vs `gc struct` (Slang)**

- Prefer **plain `struct`** for entities and DTOs (copy-by-value).
- Prefer **`gc struct`** for services, repos, and long-lived app state (shared heap identity).

Nested packages resolve imports relative to *their* directory (e.g. `import "../../shared"` from `application/user`). The root package (`main.sl`) uses root-style imports (`import "domain/user"`).

---

## Quick start

### Prerequisites

- [Slang](https://slang.dolphlabs.com/) installed (`slangc` on your `PATH`)
- macOS / Linux (project is developed on macOS)

### Setup

```bash
cd /path/to/lipo
cp .env.example .env
# edit .env — at least set LIPO_AUTH_PEPPER
```

**Never delete or overwrite `.env` when syncing code.** Merge file changes in place so local secrets and `LIPO_MAIL_DEV` / Resend keys survive.

### Run

```bash
make run
# equivalent: slangc main.sl --run
```

Default listen address: `http://0.0.0.0:8080` (see `.env`).

Health check:

```bash
curl -s http://127.0.0.1:8080/health
```

### Smoke tests

Local service-level checks live in `smoke_*` folders (gitignored — keep them on disk for yourself):

| Folder | Covers |
|--------|--------|
| `smoke_auth/` | signup → verify → signin |
| `smoke_profile/` | profile, settings, avatar, password |
| `smoke_posts/` | posts CRUD |
| `smoke_social/` | follow / like |
| `smoke_feed/` | home feed |
| `smoke_multipart/` | multipart parser |

```bash
make smoke
# or, for another suite:
slangc smoke_profile/main.sl -o smoke_profile_bin && LIPO_MAIL_DEV=1 ./smoke_profile_bin
```

Use `-o <name>` so you do not overwrite the app `main` binary.

---

## Configuration

Loaded via `config.load()` → `dotenv` reads `.env` from the working directory, then **process env wins** over file values.

| Variable | Default / notes |
|----------|-----------------|
| `LIPO_DB_PATH` | `lipo.db` |
| `LIPO_HTTP_ADDR` | `0.0.0.0` |
| `LIPO_HTTP_PORT` | `8080` |
| `LIPO_UPLOAD_DIR` | `data/uploads` |
| `LIPO_AUTH_PEPPER` | **required for real deploys** — password HMAC pepper |
| `LIPO_MAIL_DEV` | `1` = log verification codes locally, skip Resend; `0` = send via Resend when key is set |
| `RESEND_API_KEY` | Resend API key (`re_…`) |
| `RESEND_FROM` | e.g. `Lipo <onboarding@resend.dev>` |

Startup logs a short config summary (mail mode, paths). If `LIPO_MAIL_DEV=1` while a Resend key is present, expect a warning — codes will still only be logged.

Verification emails are **`spawn`ed** after signup so the HTTP response returns as soon as the user + verification row are saved. Failures are logged; they do not fail the signup request.

---

## API overview

Full contract: **[`docs/openapi.json`](docs/openapi.json)** (OpenAPI 3). Import it into Swagger UI, Insomnia, or Postman.

Auth: `Authorization: Bearer <token>` from `POST /auth/signin`.

### Errors

Every error response:

```json
{ "error": "invalid_credentials", "message": "Email/username or password is incorrect." }
```

Codes and HTTP status mapping live in `shared/errors.sl`. Login failures use `invalid_credentials` without revealing whether the account exists.

### Auth

| Method | Path | Notes |
|--------|------|--------|
| `POST` | `/auth/signup` | email + unique username + password; verification email async |
| `POST` | `/auth/verify` | email + code |
| `POST` | `/auth/signin` | email **or** username + password → token |
| `GET` | `/auth/me` | current user |
| `POST` | `/auth/logout` | revoke session |

### Profile & settings

| Method | Path | Notes |
|--------|------|--------|
| `GET` | `/users/{username}` | public profile |
| `PATCH` | `/me` or `/me/profile` | edit display fields |
| `GET` / `PATCH` | `/me/settings` | privacy + notification toggles |
| `PUT` | `/me/avatar` | **file upload** (see below) |
| `DELETE` | `/me/avatar` | clear avatar |
| `GET` | `/avatars/{id}` | binary image |
| `POST` | `/me/password` | change password |
| `POST` | `/me/email` | change email (re-verify) |
| `POST` | `/me/deactivate` | deactivate account |

**Avatar upload** — do **not** send base64 JSON. Prefer multipart:

```bash
curl -X PUT http://127.0.0.1:8080/me/avatar \
  -H "authorization: Bearer $TOKEN" \
  -F "avatar=@./photo.png;type=image/png"
```

Also accepted: raw body with `Content-Type: image/jpeg` or `image/png`. JPEG/PNG only (magic-byte checked), max **2MB**. Files are stored under `LIPO_UPLOAD_DIR` as `{user_id}.jpg|.png`. The HTTP read buffer is sized (~3MiB) to fit that payload.

### Posts

| Method | Path |
|--------|------|
| `POST` | `/posts` |
| `GET` | `/posts/{id}` |
| `PATCH` | `/posts/{id}` |
| `DELETE` | `/posts/{id}` |
| `GET` | `/users/{username}/posts` |

### Social

| Method | Path |
|--------|------|
| `POST` / `DELETE` | `/users/{username}/follow` |
| `GET` | `/users/{username}/follow` (status) |
| `GET` | `/users/{username}/followers` |
| `GET` | `/users/{username}/following` |
| `POST` / `DELETE` | `/posts/{id}/like` |

### Feed

| Method | Path | Notes |
|--------|------|--------|
| `GET` | `/feed?limit=&cursor=` | posts from people you follow **plus** your own; cursor pagination; includes `liked_by_me` |

---

## Keeping docs honest

When you add or change an HTTP route:

1. Implement domain → application → infrastructure → `interfaces/http`
2. Update **`docs/openapi.json`** (bump `info.version` when the contract changes)
3. Update **this README** (status checklist + API tables)
4. Prefer a smoke test for the happy path

There is a reusable skill for OpenAPI sync: keep `docs/openapi.json` aligned with live routes whenever endpoints move.

---

## WebSockets (next)

Scaffolding is already wired at boot (`RealtimeGateway`, `RealtimeService`, WS `Hub`) but handlers still return `not_implemented`.

Planned direction (subject to change while we implement):

1. Authenticated upgrade (Bearer / ticket) to a WS endpoint
2. Hub: subscribe connections per user
3. Publish events from post / like / follow (and later feed-relevant) use-cases
4. Client protocol: small JSON envelopes (`type`, `payload`, optional `id`)
5. OpenAPI or a short `docs/realtime.md` for the event schema
6. Update this README when the first event ships

---

## Development notes

- **Compile / run:** `slangc main.sl` or `make run`
- **DB:** SQLite file on disk; migrations run on boot (`infrastructure/sqlite`)
- **Uploads:** ensure `LIPO_UPLOAD_DIR` exists (boot creates it)
- **Git:** `.env`, `lipo.db`, `data/`, and `smoke_*/` are ignored or untracked on purpose
- **Password hashing:** HMAC-SHA256 with `LIPO_AUTH_PEPPER` (`shared/password.sl`)

---

## License / attribution

Internal / Dolph Labs project (`dolphlabs/slang-lipo`). Built with Slang — see [slang.dolphlabs.com](https://slang.dolphlabs.com/) for language docs.
