pub gc struct Hub {
    session_count: int
}

pub fn new_hub() -> Hub {
    return Hub { session_count: 0 };
}

pub fn size(hub: Hub) -> int {
    return hub.session_count;
}
