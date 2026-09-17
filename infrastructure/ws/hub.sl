// infrastructure/ws/hub — user_id → outbound message channels.
import "log";

pub gc struct Hub {
    lock: mutex,
    // conn_id → outbound text channel
    outs: map[str]chan[str],
    // conn_id → user_id
    owners: map[str]str
}

pub fn new_hub() -> Hub {
    let outs: map[str]chan[str] = {};
    let owners: map[str]str = {};
    return Hub {
        lock: make_mutex(),
        outs: outs,
        owners: owners
    };
}

pub fn size(hub: Hub) -> int {
    mutex_lock(hub.lock);
    let n = len(hub.outs);
    mutex_unlock(hub.lock);
    return n;
}

pub fn register(hub: Hub, conn_id: str, user_id: str, out: chan[str]) {
    mutex_lock(hub.lock);
    hub.outs[conn_id] = out;
    hub.owners[conn_id] = user_id;
    mutex_unlock(hub.lock);
}

pub fn unregister(hub: Hub, conn_id: str) {
    mutex_lock(hub.lock);
    if has(hub.outs, conn_id) {
        // drop entries; caller closes the channel
        let outs2: map[str]chan[str] = {};
        let owners2: map[str]str = {};
        for k, v in hub.outs {
            if k != conn_id {
                outs2[k] = v;
            }
        }
        for k2, v2 in hub.owners {
            if k2 != conn_id {
                owners2[k2] = v2;
            }
        }
        hub.outs = outs2;
        hub.owners = owners2;
    }
    mutex_unlock(hub.lock);
}

pub fn publish(hub: Hub, user_id: str, json_text: str) {
    let targets: [chan[str]] = [];
    mutex_lock(hub.lock);
    for cid, uid in hub.owners {
        if uid == user_id {
            if has(hub.outs, cid) {
                push(targets, hub.outs[cid]);
            }
        }
    }
    mutex_unlock(hub.lock);
    let i = 0;
    while i < len(targets) {
        // Best-effort: a full/slow buffer parks this task briefly.
        chan_send(targets[i], json_text);
        i = i + 1;
    }
    if len(targets) == 0 {
        // no live sockets for this user — fine
    }
}
