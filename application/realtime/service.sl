import "time";
import "../../domain/realtime" as rt_domain;
import "../../infrastructure/ws" as wshub;
import "../../shared";

pub gc struct RealtimeService {
    gateway: rt_domain.RealtimeGateway,
    hub: wshub.Hub
}

pub fn new_service(gateway: rt_domain.RealtimeGateway, hub: wshub.Hub) -> RealtimeService {
    return RealtimeService { gateway: gateway, hub: hub };
}

pub fn connect(svc: RealtimeService, user_id: str) -> result[rt_domain.RealtimeSession, str] {
    let idr = shared.new_id();
    guard let sid = idr else let e = err_of(idr) {
        return err(e);
    }
    let now = time.wall() / 1000000000;
    return rt_domain.new_session(sid, user_id, now);
}

pub fn publish(svc: RealtimeService, user_id: str, json_text: str) {
    wshub.publish(svc.hub, user_id, json_text);
}
