// smoke_posts — auth → create → get → list → patch → delete
import "../shared";
import "../application/user" as user_app;
import "../application/post" as post_app;
import "../infrastructure/sqlite" as sqlite;
import "../infrastructure/email" as email;

fn die(msg: str) {
    println("FAIL: " + msg);
    exit(1);
}

fn run() {
    let dr = sqlite.open(":memory:");
    guard let db = dr else let e = err_of(dr) {
        die("open: " + e);
    }
    let mr = sqlite.migrate(db);
    guard let _mig = mr else let e = err_of(mr) {
        die("migrate: " + e);
    }

    let user_repo = sqlite.new_user_repo(db);
    let post_repo = sqlite.new_post_repo(db);
    let mailer = email.new_mailer("", "Lipo <dev@localhost>", true);
    let users = user_app.new_service(user_repo, mailer, "smoke-pepper", "/tmp/lipo-smoke-posts-uploads");
    let posts = post_app.new_service(post_repo, user_repo);

    let sr = user_app.signup(users, "alan@example.com", "alan_turing", "password123");
    guard let _s = sr else let e = err_of(sr) {
        die("signup: " + e);
    }
    let code = user_app.last_dev_code(users);
    let vr = user_app.verify_email(users, "alan@example.com", code);
    guard let _v = vr else let e = err_of(vr) {
        die("verify: " + e);
    }
    let ar = user_app.signin(users, "alan_turing", "password123");
    guard let sess = ar else let e = err_of(ar) {
        die("signin: " + e);
    }
    let uidr = user_app.user_id_from_token(users, sess.token);
    guard let uid = uidr else let e = err_of(uidr) {
        die("uid: " + e);
    }
    println("auth ok");

    let cr = post_app.create(posts, uid, "hello lipo posts");
    guard let p = cr else let e = err_of(cr) {
        die("create: " + e);
    }
    if p.body != "hello lipo posts" {
        die("create body");
    }
    println("create ok id=" + p.id);

    let gr = post_app.get(posts, p.id);
    guard let got = gr else let e = err_of(gr) {
        die("get: " + e);
    }
    if got.id != p.id {
        die("get id mismatch");
    }
    println("get ok");

    let lr = post_app.list_by_username(posts, "alan_turing", 10);
    guard let list = lr else let e = err_of(lr) {
        die("list: " + e);
    }
    if len(list) < 1 {
        die("list empty");
    }
    println("list ok n=" + to_str(len(list)));

    let ur = post_app.update(posts, uid, p.id, "updated body");
    guard let up = ur else let e = err_of(ur) {
        die("update: " + e);
    }
    if up.body != "updated body" {
        die("update body");
    }
    println("patch ok");

    let del = post_app.delete(posts, uid, p.id);
    guard let _d = del else let e = err_of(del) {
        die("delete: " + e);
    }
    let gone = post_app.get(posts, p.id);
    guard let _g = gone else let e = err_of(gone) {
        if e != shared.not_found {
            die("expected not_found after delete, got " + e);
        }
        println("delete ok");
        sqlite.close(db);
        println("OK");
        return;
    }
    die("post still present after delete");
}

run();
