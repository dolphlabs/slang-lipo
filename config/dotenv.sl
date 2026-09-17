// Load KEY=VALUE pairs from a .env file into the process environment.
// Does not override variables already set in the real environment.
import "fs";
import "log";
import "os";
import "proc";
import "strings";

fn strip_quotes(v: str) -> str {
    let n = len(v);
    if n >= 2 {
        let b = to_bytes(v);
        if (b[0] == 34 && b[n - 1] == 34) || (b[0] == 39 && b[n - 1] == 39) {
            return strings.slice(v, 1, n - 1);
        }
    }
    return v;
}

fn apply_line(raw: str) -> result[bool, str] {
    let line = strings.trim(raw);
    if len(line) == 0 {
        return ok(true);
    }
    if strings.has_prefix(line, "#") {
        return ok(true);
    }
    if strings.has_prefix(line, "export ") {
        line = strings.trim(strings.slice(line, 7, len(line)));
    }
    let eq = strings.find(line, "=");
    if eq <= 0 {
        return ok(true);
    }
    let key = strings.trim(strings.slice(line, 0, eq));
    let val = strip_quotes(strings.trim(strings.slice(line, eq + 1, len(line))));
    if len(key) == 0 {
        return ok(true);
    }
    // Process env wins over .env
    let existing = proc.getenv(key);
    guard let _e = existing else {
        let sr = os.setenv(key, val);
        guard let _ok = sr else let e = err_of(sr) {
            return err(e);
        }
        return ok(true);
    }
    return ok(true);
}

fn read_all(path: str) -> result[str, str] {
    let or = fs.open(path);
    guard let fd = or else let e = err_of(or) {
        return err(e);
    }
    let out = "";
    while true {
        let rr = fs.read(fd, 4096);
        guard let chunk = rr else let e = err_of(rr) {
            fs.close(fd);
            return err(e);
        }
        if len(chunk) == 0 {
            break;
        }
        out = out + to_str(chunk);
        if len(chunk) < 4096 {
            break;
        }
    }
    fs.close(fd);
    return ok(out);
}

pub fn load_file(path: str) -> result[bool, str] {
    if !os.is_file(path) {
        return ok(false);
    }
    let rr = read_all(path);
    guard let body = rr else let e = err_of(rr) {
        return err(e);
    }
    // Normalize CRLF
    let normalized = strings.replace(body, "\r\n", "\n");
    let lines = strings.split(normalized, "\n");
    let i = 0;
    while i < len(lines) {
        let ar = apply_line(lines[i]);
        guard let _ok = ar else let e = err_of(ar) {
            return err(e);
        }
        i = i + 1;
    }
    log.info("loaded env file: " + path);
    return ok(true);
}

pub fn load_default() -> result[bool, str] {
    return load_file(".env");
}
