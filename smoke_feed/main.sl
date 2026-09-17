// smoke_feed — home timeline: follow graph + own posts + cursor pagination
import "../application/user" as user_app;
import "../application/post" as post_app;
import "../application/social" as social_app;
import "../application/feed" as feed_app;
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
    let feed_repo = sqlite.new_feed_repo(db);
    let mailer = email.new_mailer("", "Lipo <dev@localhost>", true);
    let users = user_app.new_service(user_repo, mailer, "smoke-pepper", "/tmp/lipo-smoke-feed-uploads");
    let posts = post_app.new_service(post_repo, user_repo);
    let social = social_app.new_service(social_repo, user_repo, post_repo);
    let feed = feed_app.new_service(feed_repo);

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

    // B follows A
    let fr = social_app.follow(social, uid_b, "alice_a");
    guard let _f = fr else let e = err_of(fr) {
        die("follow: " + e);
    }
    println("follow ok");

    // A posts 2, B posts 1 (with tiny spacing via distinct bodies; created_at may tie)
    let pa1 = post_app.create(posts, uid_a, "alice post one");
    guard let a1 = pa1 else let e = err_of(pa1) {
        die("A post1: " + e);
    }
    let pa2 = post_app.create(posts, uid_a, "alice post two");
    guard let a2 = pa2 else let e = err_of(pa2) {
        die("A post2: " + e);
    }
    let pb1 = post_app.create(posts, uid_b, "bob own post");
    guard let b1 = pb1 else let e = err_of(pb1) {
        die("B post1: " + e);
    }
    println("posts ok a1=" + a1.id + " a2=" + a2.id + " b1=" + b1.id);

    // B likes A's first post
    let lr = social_app.like(social, uid_b, a1.id);
    guard let _l = lr else let e = err_of(lr) {
        die("like: " + e);
    }

    // B GET feed — should see A's posts + B's own (3)
    let page1r = feed_app.home(feed, uid_b, 20, "");
    guard let page1 = page1r else let e = err_of(page1r) {
        die("feed: " + e);
    }
    if len(page1.posts) != 3 {
        die("feed expected 3 got " + to_str(len(page1.posts)));
    }
    let saw_a1 = false;
    let saw_a2 = false;
    let saw_b1 = false;
    let liked_ok = false;
    let i = 0;
    while i < len(page1.posts) {
        let it = page1.posts[i];
        if it.id == a1.id {
            saw_a1 = true;
            if it.author_username != "alice_a" {
                die("author_username for a1");
            }
            if !it.liked_by_me {
                die("liked_by_me expected true for a1");
            }
            liked_ok = true;
        }
        if it.id == a2.id {
            saw_a2 = true;
            if it.liked_by_me {
                die("liked_by_me expected false for a2");
            }
        }
        if it.id == b1.id {
            saw_b1 = true;
            if it.author_id != uid_b {
                die("own post author_id");
            }
        }
        i = i + 1;
    }
    if !saw_a1 || !saw_a2 || !saw_b1 {
        die("feed missing expected posts");
    }
    if !liked_ok {
        die("liked_by_me not observed");
    }
    if len(page1.next_cursor) != 0 {
        die("expected empty next_cursor on full page");
    }
    println("feed full ok");

    // Pagination limit=1
    let p1r = feed_app.home(feed, uid_b, 1, "");
    guard let p1 = p1r else let e = err_of(p1r) {
        die("page1: " + e);
    }
    if len(p1.posts) != 1 {
        die("limit=1 expected 1 got " + to_str(len(p1.posts)));
    }
    if len(p1.next_cursor) == 0 {
        die("expected next_cursor after limit=1");
    }
    let first_id = p1.posts[0].id;
    println("page1 ok id=" + first_id + " cursor=" + p1.next_cursor);

    let p2r = feed_app.home(feed, uid_b, 1, p1.next_cursor);
    guard let p2 = p2r else let e = err_of(p2r) {
        die("page2: " + e);
    }
    if len(p2.posts) != 1 {
        die("page2 expected 1");
    }
    if p2.posts[0].id == first_id {
        die("page2 should differ from page1");
    }
    if len(p2.next_cursor) == 0 {
        die("expected next_cursor on page2 (3 items)");
    }
    println("page2 ok id=" + p2.posts[0].id);

    let p3r = feed_app.home(feed, uid_b, 1, p2.next_cursor);
    guard let p3 = p3r else let e = err_of(p3r) {
        die("page3: " + e);
    }
    if len(p3.posts) != 1 {
        die("page3 expected 1");
    }
    if len(p3.next_cursor) != 0 {
        die("expected empty next_cursor on last page");
    }
    println("pagination ok");

    // Unfollow → A's posts leave; B's remain
    let ur = social_app.unfollow(social, uid_b, "alice_a");
    guard let _u = ur else let e = err_of(ur) {
        die("unfollow: " + e);
    }
    let afterr = feed_app.home(feed, uid_b, 20, "");
    guard let after = afterr else let e = err_of(afterr) {
        die("feed after unfollow: " + e);
    }
    if len(after.posts) != 1 {
        die("after unfollow expected 1 got " + to_str(len(after.posts)));
    }
    if after.posts[0].id != b1.id {
        die("after unfollow expected own post");
    }
    println("unfollow feed ok");

    // Empty follow graph still returns own (already covered); empty if none:
    let empty_feed_r = feed_app.home(feed, uid_a, 20, "");
    guard let empty_a = empty_feed_r else let e = err_of(empty_feed_r) {
        die("A feed: " + e);
    }
    if len(empty_a.posts) != 2 {
        die("A with no follows should still see own 2 posts got " + to_str(len(empty_a.posts)));
    }
    println("own-only feed ok");

    sqlite.close(db);
    println("OK");
}

run();
