// infrastructure/ratelimit — simple in-memory token bucket keyed by string.
// Auth + message-send throttles. Process-local only (not distributed).
import "time";

pub gc struct Limiter {
    lock: mutex,
    last: map[str]int,
    tokens: map[str]int,
    capacity: int,
    refill_per_sec: int
}

pub fn new_limiter(capacity: int, refill_per_sec: int) -> Limiter {
    let last: map[str]int = {};
    let tokens: map[str]int = {};
    return Limiter {
        lock: make_mutex(),
        last: last,
        tokens: tokens,
        capacity: capacity,
        refill_per_sec: refill_per_sec
    };
}

pub fn allow(lim: Limiter, key: str) -> bool {
    if len(key) == 0 {
        key = "_";
    }
    let now = time.wall();
    mutex_lock(lim.lock);
    let tokens = lim.capacity;
    if has(lim.tokens, key) {
        tokens = lim.tokens[key];
        let last = lim.last[key];
        let elapsed = now - last;
        if elapsed < 0 {
            elapsed = 0;
        }
        let add = (elapsed * lim.refill_per_sec) / 1000000000;
        tokens = tokens + add;
        if tokens > lim.capacity {
            tokens = lim.capacity;
        }
    }
    let ok = false;
    if tokens >= 1 {
        tokens = tokens - 1;
        ok = true;
    }
    lim.tokens[key] = tokens;
    lim.last[key] = now;
    mutex_unlock(lim.lock);
    return ok;
}
