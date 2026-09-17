import "../../domain/realtime" as rt_domain;
import "../../shared";

pub gc struct RealtimeService {
    gateway: rt_domain.RealtimeGateway
}

pub fn new_service(gateway: rt_domain.RealtimeGateway) -> RealtimeService {
    return RealtimeService { gateway: gateway };
}

pub fn connect(svc: RealtimeService, user_id: str) -> result[rt_domain.RealtimeSession, str] {
    let _discard_svc = svc;
    let _discard_user_id = user_id;
    return err(shared.not_implemented);
}
