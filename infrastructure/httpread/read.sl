// infrastructure/httpread — request reader with Expect:100-continue + O(n) wire copy.
// Wraps the same link/wire loop as stdlib http.read, but answers 100-continue
// once headers are complete so clients can send the body.
import "http";
import "strings";

pub gc struct Incoming {
    req: http.Request,
    filled: int
}

fn lower_byte(b: int) -> int {
    if b >= 65 && b <= 90 {
        return b + 32;
    }
    return b;
}

fn lower_ascii(s: str) -> str {
    let b = to_bytes(s);
    let i = 0;
    while i < len(b) {
        b[i] = lower_byte(b[i]);
        i = i + 1;
    }
    return to_str(b);
}

fn find_crlf(b: bytes, from: int) -> int {
    let i = from;
    while i + 1 < len(b) {
        if b[i] == 13 && b[i + 1] == 10 {
            return i;
        }
        i = i + 1;
    }
    return -1;
}

fn find_blank_line(b: bytes) -> int {
    let i = 0;
    let n = len(b);
    while i + 3 < n {
        if b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10 {
            return i;
        }
        i = i + 1;
    }
    return -1;
}

// O(n) wire → bytes (single allocation via doubling concat of chunks).
fn make_bytes(n: int) -> bytes {
    if n <= 0 {
        return b"";
    }
    let s = b"\x00";
    while len(s) < n {
        s = s + s;
    }
    return s[0..n];
}

fn copy_wire_on(w: wire, n: int) -> bytes {
    // O(n): doubling buffer + index fill (byte-at-a-time concat is O(n^2)).
    let out = make_bytes(n);
    let i = 0;
    while i < n {
        out[i] = w[i];
        i = i + 1;
    }
    return out;
}

fn compact_wire(buf: wire, used: int, filled: int) -> int {
    if used <= 0 {
        return filled;
    }
    let n = filled - used;
    let i = 0;
    while i < n {
        buf[i] = buf[used + i];
        i = i + 1;
    }
    return n;
}

fn parse_digits(s: str) -> result[int, str] {
    let b = to_bytes(s);
    if len(b) == 0 {
        return err("empty number");
    }
    let n = 0;
    let i = 0;
    while i < len(b) {
        let d = b[i];
        if d < 48 || d > 57 {
            return err("bad number");
        }
        n = n * 10 + (d - 48);
        i = i + 1;
    }
    return ok(n);
}

fn expects_100(headers: map[str]str) -> bool {
    if !has(headers, "expect") {
        return false;
    }
    return strings.contains(lower_ascii(headers["expect"]), "100-continue");
}

fn body_need(headers: map[str]str, sep: int) -> result[int, str] {
    if !has(headers, "content-length") {
        return ok(sep + 4);
    }
    let clr = parse_digits(headers["content-length"]);
    guard let cl = clr else {
        return err("bad Content-Length");
    }
    if cl < 0 {
        return err("bad Content-Length");
    }
    return ok(sep + 4 + cl);
}

fn rejects_transfer(headers: map[str]str) -> bool {
    if !has(headers, "transfer-encoding") {
        return false;
    }
    return lower_ascii(headers["transfer-encoding"]) != "identity";
}

fn parse_headers_only(raw: bytes, start: int, sep: int) -> result[map[str]str, str] {
    let headers: map[str]str = {};
    let i = start;
    while i < sep {
        let eol = find_crlf(raw, i);
        if eol < 0 || eol > sep {
            return err("malformed header");
        }
        if eol == i {
            break;
        }
        let colon = i;
        while colon < eol && raw[colon] != 58 {
            colon = colon + 1;
        }
        if colon >= eol || colon == i {
            return err("malformed header");
        }
        let name = lower_ascii(to_str(raw[i..colon]));
        let lo = colon + 1;
        let hi = eol;
        while lo < hi && (raw[lo] == 32 || raw[lo] == 9) {
            lo = lo + 1;
        }
        while hi > lo && (raw[hi - 1] == 32 || raw[hi - 1] == 9) {
            hi = hi - 1;
        }
        headers[name] = to_str(raw[lo..hi]);
        i = eol + 2;
    }
    return ok(headers);
}

pub fn read_request(c: &mut link, buf: wire, filled_in: int, deadline: until) -> result[Incoming, str] {
    let filled = filled_in;
    let sent_100 = false;
    while true {
        if filled > 0 {
            let raw = copy_wire_on(buf, filled);
            let sep = find_blank_line(raw);
            if sep >= 0 {
                let line_end = find_crlf(raw, 0);
                if line_end < 0 {
                    return err("malformed request line");
                }
                let hr = parse_headers_only(raw, line_end + 2, sep);
                guard let headers = hr else let e = err_of(hr) {
                    return err("header: " + e);
                }
                if rejects_transfer(headers) {
                    return err("chunked encoding is not supported");
                }
                let nr = body_need(headers, sep);
                guard let need = nr else let e = err_of(nr) {
                    return err("body: " + e);
                }
                if need > len(buf) {
                    return err("request too large for buffer");
                }
                if !sent_100 && expects_100(headers) && filled < need {
                    let wr = c.send_bytes(b"HTTP/1.1 100 Continue\r\n\r\n", deadline);
                    guard let _n = wr else let e = err_of(wr) {
                        return err("100-continue: " + to_str(e));
                    }
                    sent_100 = true;
                }
                if filled >= need {
                    let parsed = http.parse(raw);
                    guard let req = parsed else let e = err_of(parsed) {
                        return err(e);
                    }
                    let rest = compact_wire(buf, need, filled);
                    return ok(Incoming { req: req, filled: rest });
                }
            }
        }
        if filled >= len(buf) {
            return err("request too large for buffer");
        }
        let tail = buf[filled..];
        let rr = c.recv(tail, deadline);
        guard let n = rr else let e = err_of(rr) {
            return err("recv: " + to_str(e));
        }
        if n == 0 {
            if filled == 0 {
                return err("connection closed");
            }
            return err("truncated request");
        }
        filled = filled + n;
    }
}
