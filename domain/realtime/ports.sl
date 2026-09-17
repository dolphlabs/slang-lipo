pub gc struct RealtimeGateway {
    _pad: int
}

pub fn new_realtime_gateway() -> RealtimeGateway {
    return RealtimeGateway { _pad: 0 };
}
