// Request reader that answers Expect: 100-continue (Apidog and similar clients).
// Same shape as stdlib http.read, but sends "100 Continue" once headers are in
// and the body is still outstanding — otherwise the client waits forever.
import "byteutil";
import "http";
import "strings";

fn find_crlf(raw: bytes, from: int) -> int {
    let i = from;
    while i + 1 < len(raw) {
        if raw[i] == 13 && raw[i + 1] == 10 {
            return i;
        }
        i = i + 1;
    }
    return -1;
}

fn find_blank_line(raw: bytes) -> int {
    let i = 0;
    while i + 3 < len(raw) {
        if raw[i] == 13 && raw[i + 1] == 10 && raw[i + 2] == 13 && raw[i + 3] == 10 {
            return i;
        }
        i = i + 1;
    }
    return -1;
}

fn is_ows(b: int) -> bool {
    return b == 32 || b == 9;
}

fn trim_ows(b: bytes) -> bytes {
    let lo = 0;
    let hi = len(b);
    while lo < hi && is_ows(b[lo]) {
        lo = lo + 1;
    }
    while hi > lo && is_ows(b[hi - 1]) {
        hi = hi - 1;
    }
    return b[lo..hi];
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

fn parse_headers_map(raw: bytes, start: int, sep: int) -> result[map[str]str, str] {
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
        let colon = byteutil.find(raw, i, 58);
        if colon < 0 || colon >= eol {
            return err("malformed header");
        }
        let name = strings.to_lower(to_str(raw[i..colon]));
        let value = to_str(trim_ows(raw[colon + 1..eol]));
        headers[name] = value;
        i = eol + 2;
    }
    return ok(headers);
}

fn copy_wire(w: wire, n: int) -> bytes {
    let out = b"";
    let i = 0;
    while i < n {
        out = out + to_le(w[i])[0..1];
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

fn wants_100(headers: map[str]str) -> bool {
    if !has(headers, "expect") {
        return false;
    }
    return strings.contains(strings.to_lower(headers["expect"]), "100-continue");
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
    return strings.to_lower(headers["transfer-encoding"]) != "identity";
}

pub fn read_request(c: &mut link, buf: wire, filled: int, deadline: until) -> result[http.Incoming, str] {
    let sent_100 = false;
    while true {
        if filled > 0 {
            let raw = copy_wire(buf, filled);
            let sep = find_blank_line(raw);
            if sep >= 0 {
                let line_end = find_crlf(raw, 0);
                if line_end < 0 {
                    return err("malformed request line");
                }
                let hr = parse_headers_map(raw, line_end + 2, sep);
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
                if filled < need && wants_100(headers) && !sent_100 {
                    let wr = c.send_bytes(b"HTTP/1.1 100 Continue\r\n\r\n", deadline);
                    guard let _n = wr else {
                        return err("100-continue send failed");
                    }
                    sent_100 = true;
                }
                if filled >= need {
                    let parsed = http.parse(raw);
                    guard let req = parsed else let e = err_of(parsed) {
                        return err(e);
                    }
                    let rest = compact_wire(buf, need, filled);
                    return ok(http.Incoming { req: req, filled: rest });
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
