// smoke_auth — signup → verify → signin against :memory: (mail_dev).
import "../config";
import "../shared";
import "../application/user" as user_app;
import "../infrastructure/sqlite" as sqlite;
import "../infrastructure/email" as email;
import "log";

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

    let repo = sqlite.new_user_repo(db);
    let mailer = email.new_mailer("", "Lipo <dev@localhost>", true);
    let svc = user_app.new_service(repo, mailer, "smoke-pepper", "/tmp/lipo-smoke-uploads");

    let sr = user_app.signup(svc, "ada@example.com", "ada_lovelace", "password123");
    guard let signed = sr else let e = err_of(sr) {
        die("signup: " + e);
    }
    println("signup ok user=" + signed.user.username);

    let code = user_app.last_dev_code(svc);
    if len(code) != 6 {
        die("expected 6-digit code, got '" + code + "'");
    }
    println("dev code=" + code);

    let vr = user_app.verify_email(svc, "ada@example.com", code);
    guard let user = vr else let e = err_of(vr) {
        die("verify: " + e);
    }
    if !user.email_verified {
        die("user not verified");
    }
    println("verify ok");

    let ar = user_app.signin(svc, "ada@example.com", "password123");
    guard let sess = ar else let e = err_of(ar) {
        die("signin email: " + e);
    }
    if len(sess.token) < 32 {
        die("token too short");
    }
    println("signin email ok token_len=" + to_str(len(sess.token)));

    let ar2 = user_app.signin(svc, "ada_lovelace", "password123");
    guard let sess2 = ar2 else let e = err_of(ar2) {
        die("signin username: " + e);
    }
    let _discard_tok = sess2.token;

    let me = user_app.me_from_token(svc, sess.token);
    guard let me_user = me else let e = err_of(me) {
        die("me: " + e);
    }
    if me_user.email != "ada@example.com" {
        die("me email mismatch");
    }
    println("me ok");

    let bad = user_app.signin(svc, "ada@example.com", "wrongpass!");
    guard let _b = bad else let e = err_of(bad) {
        if e != shared.unauthorized {
            die("expected unauthorized, got " + e);
        }
        println("bad password rejected");
        // conflict signup
        let c = user_app.signup(svc, "ada@example.com", "other_user", "password123");
        guard let _c = c else let e2 = err_of(c) {
            if e2 != shared.conflict {
                die("expected conflict, got " + e2);
            }
            println("conflict ok");
            sqlite.close(db);
            println("OK");
            return;
        }
        die("expected conflict signup to fail");
    }
    die("expected bad password to fail");
}

run();
