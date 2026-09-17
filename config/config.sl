// config — process configuration from environment with defaults.
// Loads `.env` from the working directory first (does not override real env).
import "proc";
import "log";

pub struct Config {
    db_path: str,
    http_addr: str,
    http_port: int,
    resend_api_key: str,
    resend_from: str,
    auth_pepper: str,
    mail_dev: bool,
    upload_dir: str
}

fn mail_dev_mode(api_key: str) -> bool {
    let env = proc.getenv("LIPO_MAIL_DEV") ?? "";
    if env == "1" {
        if api_key != "" {
            log.warn("LIPO_MAIL_DEV=1: skipping Resend and logging codes locally (set LIPO_MAIL_DEV=0 to send mail)");
        }
        return true;
    }
    return api_key == "";
}

fn build(db: str, addr: str, port: int, key: str, from_addr: str, pepper: str, upload_dir: str) -> Config {
    return Config {
        db_path: db,
        http_addr: addr,
        http_port: port,
        resend_api_key: key,
        resend_from: from_addr,
        auth_pepper: pepper,
        mail_dev: mail_dev_mode(key),
        upload_dir: upload_dir
    };
}

pub fn load() -> Config {
    let dr = load_default();
    guard let _loaded = dr else let e = err_of(dr) {
        log.warn("dotenv load failed: " + e);
    }

    let db = proc.getenv("LIPO_DB_PATH") ?? "lipo.db";
    let addr = proc.getenv("LIPO_HTTP_ADDR") ?? "0.0.0.0";
    let port_s = proc.getenv("LIPO_HTTP_PORT") ?? "8080";
    let pr = to_int(port_s);
    let port = pr ?? 8080;
    let key = proc.getenv("RESEND_API_KEY") ?? "";
    let from_addr = proc.getenv("RESEND_FROM") ?? "Lipo <onboarding@resend.dev>";
    let upload_dir = proc.getenv("LIPO_UPLOAD_DIR") ?? "data/uploads";
    let pepper_opt = proc.getenv("LIPO_AUTH_PEPPER");

    guard let pepper = pepper_opt else {
        log.warn("LIPO_AUTH_PEPPER unset; using insecure default (dev only)");
        return build(db, addr, port, key, from_addr, "INSECURE_DEV_PEPPER_CHANGE_ME", upload_dir);
    }
    return build(db, addr, port, key, from_addr, pepper, upload_dir);
}

pub fn summary(cfg: Config) -> str {
    let mail = "resend";
    if cfg.mail_dev {
        mail = "dev";
    }
    return "db=" + cfg.db_path + " http=" + cfg.http_addr + ":" + to_str(cfg.http_port) + " mail=" + mail + " uploads=" + cfg.upload_dir;
}
