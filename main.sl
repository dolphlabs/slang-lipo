// lipo — social-media REST API (auth + profile + posts + social + feed)
//
// Quirk: nested packages resolve imports relative to THEIR directory,
// so domain/application/infra use paths like `import "../../shared"`.
// Main (project root package) uses root-style `import "domain/user"`.

import "config";
import "shared";
import "log";
import "domain/realtime" as rt_domain;
import "application/user" as user_app;
import "application/post" as post_app;
import "application/social" as social_app;
import "application/feed" as feed_app;
import "application/realtime" as rt_app;
import "infrastructure/sqlite" as sqlite;
import "infrastructure/http" as httpserver;
import "infrastructure/ws" as wshub;
import "infrastructure/email" as email;
import "infrastructure/storage" as storage;
import "interfaces/http" as rest;

fn boot() {
    log.info("lipo starting...");

    let cfg = config.load();
    log.info("config: " + config.summary(cfg));

    let ur = storage.ensure_dir(cfg.upload_dir);
    guard let _up = ur else let e = err_of(ur) {
        log.error("upload dir failed: " + e);
        exit(1);
    }

    let dr = sqlite.open(cfg.db_path);
    guard let db = dr else let e = err_of(dr) {
        log.error("sqlite open failed: " + e);
        exit(1);
    }

    let mr = sqlite.migrate(db);
    guard let _mig = mr else let e = err_of(mr) {
        log.error("sqlite migrate failed: " + e);
        sqlite.close(db);
        exit(1);
    }
    log.info("sqlite: open+migrate ok (" + cfg.db_path + ")");

    let user_repo = sqlite.new_user_repo(db);
    let mailer = email.new_mailer(cfg.resend_api_key, cfg.resend_from, cfg.mail_dev);
    let user_svc = user_app.new_service(user_repo, mailer, cfg.auth_pepper, cfg.upload_dir);

    let post_repo = sqlite.new_post_repo(db);
    let post_svc = post_app.new_service(post_repo, user_repo);

    let social_repo = sqlite.new_social_repo(db);
    let social_svc = social_app.new_service(social_repo, user_repo, post_repo);

    let feed_repo = sqlite.new_feed_repo(db);
    let feed_svc = feed_app.new_service(feed_repo);

    let rt_gw = rt_domain.new_realtime_gateway();
    let _rt_svc = rt_app.new_service(rt_gw);

    let hub = wshub.new_hub();
    let _hub_size = wshub.size(hub);

    log.info("routes:");
    rest.print_routes();

    let app = httpserver.App {
        svc: user_svc,
        post_svc: post_svc,
        social_svc: social_svc,
        feed_svc: feed_svc,
        port: cfg.http_port,
        addr: cfg.http_addr
    };
    let sr = httpserver.listen_and_serve(app);
    guard let _ok = sr else let e = err_of(sr) {
        log.error("http serve failed: " + e);
        sqlite.close(db);
        exit(1);
    }

    sqlite.close(db);
    log.info("lipo stopped");
}

boot();
