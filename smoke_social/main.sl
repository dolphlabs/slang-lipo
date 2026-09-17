// smoke_social — follow/unfollow + like/unlike against :memory: (mail_dev)
import "../shared";
import "../application/user" as user_app;
import "../application/post" as post_app;
import "../application/social" as social_app;
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
    let social_repo = sqlite.new_social_repo(db);
    let mailer = email.new_mailer("", "Lipo <dev@localhost>", true);
    let users = user_app.new_service(user_repo, mailer, "smoke-pepper", "/tmp/lipo-smoke-social-uploads");
    let posts = post_app.new_service(post_repo, user_repo);
    let social = social_app.new_service(social_repo, user_repo, post_repo);

    // user A
    let sa = user_app.signup(users, "alice@example.com", "alice_a", "password123");
    guard let _sa = sa else let e = err_of(sa) {
        die("signup A: " + e);
    }
    let code_a = user_app.last_dev_code(users);
    let va = user_app.verify_email(users, "alice@example.com", code_a);
    guard let _va = va else let e = err_of(va) {
        die("verify A: " + e);
    }
    let ia = user_app.signin(users, "alice_a", "password123");
    guard let sess_a = ia else let e = err_of(ia) {
        die("signin A: " + e);
    }
    let uida_r = user_app.user_id_from_token(users, sess_a.token);
    guard let uid_a = uida_r else let e = err_of(uida_r) {
        die("uid A: " + e);
    }

    // user B
    let sb = user_app.signup(users, "bob@example.com", "bob_b", "password123");
    guard let _sb = sb else let e = err_of(sb) {
        die("signup B: " + e);
    }
    let code_b = user_app.last_dev_code(users);
    let vb = user_app.verify_email(users, "bob@example.com", code_b);
    guard let _vb = vb else let e = err_of(vb) {
        die("verify B: " + e);
    }
    let ib = user_app.signin(users, "bob_b", "password123");
    guard let sess_b = ib else let e = err_of(ib) {
        die("signin B: " + e);
    }
    let uidb_r = user_app.user_id_from_token(users, sess_b.token);
    guard let uid_b = uidb_r else let e = err_of(uidb_r) {
        die("uid B: " + e);
    }
    println("auth ok");

    // A creates a post
    let cr = post_app.create(posts, uid_a, "hello from alice");
    guard let post = cr else let e = err_of(cr) {
        die("create post: " + e);
    }
    println("post ok id=" + post.id);

    // B follows A
    let fr = social_app.follow(social, uid_b, "alice_a");
    guard let f1 = fr else let e = err_of(fr) {
        die("follow: " + e);
    }
    if f1.follower_id != uid_b {
        die("follow follower_id");
    }
    println("follow ok");

    let followers = social_app.list_followers(social, "alice_a", 50);
    guard let flist = followers else let e = err_of(followers) {
        die("followers: " + e);
    }
    if len(flist) != 1 {
        die("followers expected 1 got " + to_str(len(flist)));
    }
    if flist[0].username != "bob_b" {
        die("follower username");
    }
    println("followers ok");

    let following = social_app.list_following(social, "bob_b", 50);
    guard let glist = following else let e = err_of(following) {
        die("following: " + e);
    }
    if len(glist) != 1 {
        die("following expected 1");
    }
    if glist[0].username != "alice_a" {
        die("following username");
    }
    println("following ok");

    let st1 = social_app.following_status(social, uid_b, "alice_a");
    guard let yes = st1 else let e = err_of(st1) {
        die("status: " + e);
    }
    if !yes {
        die("expected following=true");
    }

    // unfollow
    let ur = social_app.unfollow(social, uid_b, "alice_a");
    guard let _u = ur else let e = err_of(ur) {
        die("unfollow: " + e);
    }
    let st2 = social_app.following_status(social, uid_b, "alice_a");
    guard let no = st2 else let e = err_of(st2) {
        die("status2: " + e);
    }
    if no {
        die("expected following=false after unfollow");
    }
    println("unfollow ok");

    // follow again (idempotent)
    let fr2 = social_app.follow(social, uid_b, "alice_a");
    guard let _f2 = fr2 else let e = err_of(fr2) {
        die("follow again: " + e);
    }
    let fr3 = social_app.follow(social, uid_b, "alice_a");
    guard let _f3 = fr3 else let e = err_of(fr3) {
        die("follow idempotent: " + e);
    }
    println("follow again ok");

    // B likes post
    let lr = social_app.like(social, uid_b, post.id);
    guard let like1 = lr else let e = err_of(lr) {
        die("like: " + e);
    }
    if like1.user_id != uid_b {
        die("like user_id");
    }
    let gr = post_app.get(posts, post.id);
    guard let got = gr else let e = err_of(gr) {
        die("get after like: " + e);
    }
    if got.like_count != 1 {
        die("like_count expected 1 got " + to_str(got.like_count));
    }
    println("like ok count=1");

    // unlike
    let ul = social_app.unlike(social, uid_b, post.id);
    guard let _ul = ul else let e = err_of(ul) {
        die("unlike: " + e);
    }
    let gr2 = post_app.get(posts, post.id);
    guard let got2 = gr2 else let e = err_of(gr2) {
        die("get after unlike: " + e);
    }
    if got2.like_count != 0 {
        die("like_count expected 0 got " + to_str(got2.like_count));
    }
    println("unlike ok");

    // like again + idempotent
    let lr2 = social_app.like(social, uid_b, post.id);
    guard let _l2 = lr2 else let e = err_of(lr2) {
        die("like again: " + e);
    }
    let lr3 = social_app.like(social, uid_b, post.id);
    guard let _l3 = lr3 else let e = err_of(lr3) {
        die("like idempotent: " + e);
    }
    let gr3 = post_app.get(posts, post.id);
    guard let got3 = gr3 else let e = err_of(gr3) {
        die("get after like again: " + e);
    }
    if got3.like_count != 1 {
        die("like_count after idempotent expected 1 got " + to_str(got3.like_count));
    }
    println("like again ok");

    // self-follow rejected
    let self_f = social_app.follow(social, uid_a, "alice_a");
    guard let _sf = self_f else let e = err_of(self_f) {
        if e != shared.invalid_argument {
            die("self-follow expected invalid_argument got " + e);
        }
        println("self-follow rejected");
        sqlite.close(db);
        println("OK");
        return;
    }
    die("expected self-follow to fail");
}

run();
