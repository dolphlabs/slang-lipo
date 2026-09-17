// smoke_profile — signup→verify→signin→profile→settings→avatar→password
import "../shared";
import "../application/user" as user_app;
import "../infrastructure/sqlite" as sqlite;
import "../infrastructure/email" as email;
import "../infrastructure/storage" as storage;
import "encoding";

fn die(msg: str) {
    println("FAIL: " + msg);
    exit(1);
}

fn do_auth(svc: user_app.UserService) -> str {
    let sr = user_app.signup(svc, "grace@example.com", "grace_hopper", "password123");
    guard let signed = sr else let e = err_of(sr) {
        die("signup: " + e);
    }
    println("signup ok user=" + signed.user.username);
    let code = user_app.last_dev_code(svc);
    let vr = user_app.verify_email(svc, "grace@example.com", code);
    guard let _v = vr else let e = err_of(vr) {
        die("verify: " + e);
    }
    println("verify ok");
    let ar = user_app.signin(svc, "grace_hopper", "password123");
    guard let sess = ar else let e = err_of(ar) {
        die("signin: " + e);
    }
    println("signin ok");
    return sess.token;
}

fn do_profile(svc: user_app.UserService, token: str) {
    let dn: opt[str] = some("Grace Hopper");
    let bio: opt[str] = some("navy + cobol");
    let web: opt[str] = some("https://example.com");
    let loc: opt[str] = some("NYC");
    let prn: opt[str] = some("she/her");
    let un: opt[str] = none;
    let pr = user_app.update_profile(svc, token, dn, bio, web, loc, prn, un);
    guard let prof = pr else let e = err_of(pr) {
        die("update_profile: " + e);
    }
    if prof.display_name != "Grace Hopper" {
        die("profile display_name mismatch");
    }
    if prof.location != "NYC" {
        die("profile location mismatch");
    }
    println("profile ok");
    let pubr = user_app.get_public_by_username(svc, "grace_hopper");
    guard let card = pubr else let e = err_of(pubr) {
        die("public: " + e);
    }
    if card.username != "grace_hopper" {
        die("public username");
    }
    println("public profile ok");
}

fn do_settings(svc: user_app.UserService, token: str) {
    let sr2 = user_app.update_settings(svc, token, true, false, true, false, true, true);
    guard let settings = sr2 else let e = err_of(sr2) {
        die("settings: " + e);
    }
    if !settings.is_private {
        die("settings is_private");
    }
    if settings.notify_likes {
        die("settings notify_likes expected false");
    }
    let gs = user_app.get_settings(svc, token);
    guard let settings2 = gs else let e = err_of(gs) {
        die("get_settings: " + e);
    }
    if !settings2.is_private {
        die("get_settings mismatch");
    }
    println("settings ok");
}

fn do_avatar(svc: user_app.UserService, token: str) {
    let png = encoding.base64_decode("iVBORw0KGgo=");
    guard let png_bytes = png else let e = err_of(png) {
        die("png decode: " + e);
    }
    let av = user_app.set_avatar(svc, token, png_bytes, "image/png");
    guard let with_av = av else let e = err_of(av) {
        die("set_avatar: " + e);
    }
    if len(with_av.avatar_path) == 0 {
        die("avatar_path empty");
    }
    let blob = user_app.get_avatar(svc, with_av.id);
    guard let got = blob else let e = err_of(blob) {
        die("get_avatar: " + e);
    }
    if got.content_type != "image/png" {
        die("avatar content_type");
    }
    if len(got.data) < 4 {
        die("avatar bytes bad");
    }
    println("avatar ok");
}

fn do_password(svc: user_app.UserService, token: str) {
    let cp = user_app.change_password(svc, token, "password123", "password456");
    guard let _cp = cp else let e = err_of(cp) {
        die("change_password: " + e);
    }
    let bad = user_app.signin(svc, "grace_hopper", "password123");
    guard let _b = bad else let e = err_of(bad) {
        if e != shared.unauthorized {
            die("old password should fail: " + e);
        }
        let good = user_app.signin(svc, "grace_hopper", "password456");
        guard let _g = good else let e2 = err_of(good) {
            die("new password signin: " + e2);
        }
        println("password ok");
        return;
    }
    die("old password unexpectedly worked");
}

fn run() {
    let upload = "/tmp/lipo-smoke-profile-uploads";
    let er = storage.ensure_dir(upload);
    guard let _udir = er else let e = err_of(er) {
        die("upload dir: " + e);
    }
    let dr = sqlite.open(":memory:");
    guard let db = dr else let e = err_of(dr) {
        die("open: " + e);
    }
    let mr = sqlite.migrate(db);
    guard let _mig = mr else let e = err_of(mr) {
        die("migrate: " + e);
    }
    let repo = sqlite.new_user_repo(db);
    let mailer = email.new_mailer("", "Lipo <dev@localhost>", true);
    let svc = user_app.new_service(repo, mailer, "smoke-pepper", upload);
    let token = do_auth(svc);
    do_profile(svc, token);
    do_settings(svc, token);
    do_avatar(svc, token);
    do_password(svc, token);
    sqlite.close(db);
    println("OK");
}

run();
