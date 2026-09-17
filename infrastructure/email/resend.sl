// infrastructure/email — Resend verification mailer (+ mail_dev hook).
import "httpc";
import "json";
import "log";
import "time";

pub gc struct Mailer {
    api_key: str,
    from_addr: str,
    mail_dev: bool,
    last_code: str
}

gc struct ResendBody {
    from: str,
    to: [str],
    subject: str,
    text: str
}

pub fn new_mailer(api_key: str, from_addr: str, mail_dev: bool) -> Mailer {
    return Mailer {
        api_key: api_key,
        from_addr: from_addr,
        mail_dev: mail_dev,
        last_code: ""
    };
}

pub fn send_verification(mailer: Mailer, to_email: str, code: str) -> result[bool, str] {
    mailer.last_code = code;
    if mailer.mail_dev || mailer.api_key == "" {
        log.info("mail_dev verification code for " + to_email + ": " + code);
        return ok(true);
    }
    let body = ResendBody {
        from: mailer.from_addr,
        to: [to_email],
        subject: "Your Lipo verification code",
        text: "Your Lipo verification code is: " + code + "\n\nIt expires in 15 minutes."
    };
    let payload: str = json.encode(body);
    let req = httpc.new_request("POST", "https://api.resend.com/emails");
    req.headers["Authorization"] = "Bearer " + mailer.api_key;
    req.headers["Content-Type"] = "application/json";
    req.body = to_bytes(payload);
    let dl = until_of(time.mono() + 10000000000);
    let rr = httpc.send(req, dl);
    guard let resp = rr else let e = err_of(rr) {
        return err(e);
    }
    if resp.status < 200 || resp.status >= 300 {
        return err("resend status " + to_str(resp.status) + ": " + to_str(resp.body));
    }
    return ok(true);
}

pub fn send_password_reset(mailer: Mailer, to_email: str, code: str) -> result[bool, str] {
    mailer.last_code = code;
    if mailer.mail_dev || mailer.api_key == "" {
        log.info("mail_dev password reset code for " + to_email + ": " + code);
        return ok(true);
    }
    let body = ResendBody {
        from: mailer.from_addr,
        to: [to_email],
        subject: "Your Lipo password reset code",
        text: "Your Lipo password reset code is: " + code + "\n\nIt expires in 15 minutes. If you did not request this, ignore this email."
    };
    let payload: str = json.encode(body);
    let req = httpc.new_request("POST", "https://api.resend.com/emails");
    req.headers["Authorization"] = "Bearer " + mailer.api_key;
    req.headers["Content-Type"] = "application/json";
    req.body = to_bytes(payload);
    let dl = until_of(time.mono() + 10000000000);
    let rr = httpc.send(req, dl);
    guard let resp = rr else let e = err_of(rr) {
        return err(e);
    }
    if resp.status < 200 || resp.status >= 300 {
        return err("resend status " + to_str(resp.status) + ": " + to_str(resp.body));
    }
    return ok(true);
}
