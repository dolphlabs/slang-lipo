// Minimal multipart/form-data parser for avatar uploads.
import "strings";
import "../../shared";

pub gc struct MultipartFile {
    field_name: str,
    filename: str,
    content_type: str,
    data: bytes
}

fn find_bytes(hay: bytes, needle: bytes, from: int) -> int {
    if len(needle) == 0 || from >= len(hay) {
        return -1;
    }
    let i = from;
    while i + len(needle) <= len(hay) {
        let j = 0;
        let okm = true;
        while j < len(needle) {
            if hay[i + j] != needle[j] {
                okm = false;
                break;
            }
            j = j + 1;
        }
        if okm {
            return i;
        }
        i = i + 1;
    }
    return -1;
}

fn header_map(raw: bytes) -> map[str]str {
    let out: map[str]str = {};
    let text = to_str(raw);
    let lines = strings.split(strings.replace(text, "\r\n", "\n"), "\n");
    let i = 0;
    while i < len(lines) {
        let line = strings.trim(lines[i]);
        if len(line) > 0 {
            let colon = strings.find(line, ":");
            if colon > 0 {
                let name = strings.to_lower(strings.trim(strings.slice(line, 0, colon)));
                let val = strings.trim(strings.slice(line, colon + 1, len(line)));
                out[name] = val;
            }
        }
        i = i + 1;
    }
    return out;
}

fn disp_param(disp: str, key: str) -> str {
    let needle = key + "=\"";
    let idx = strings.find(disp, needle);
    if idx >= 0 {
        let start = idx + len(needle);
        let rest = strings.slice(disp, start, len(disp));
        let end = strings.find(rest, "\"");
        if end < 0 {
            return "";
        }
        return strings.slice(rest, 0, end);
    }
    let needle2 = key + "=";
    let idx2 = strings.find(disp, needle2);
    if idx2 < 0 {
        return "";
    }
    let start2 = idx2 + len(needle2);
    let rest2 = strings.slice(disp, start2, len(disp));
    let semi = strings.find(rest2, ";");
    if semi < 0 {
        return strings.trim(rest2);
    }
    return strings.trim(strings.slice(rest2, 0, semi));
}

pub fn boundary_of(content_type: str) -> result[str, str] {
    let v = strings.trim(content_type);
    if len(v) == 0 {
        return err(shared.invalid_argument);
    }
    let low = strings.to_lower(v);
    if !strings.has_prefix(low, "multipart/form-data") {
        return err(shared.invalid_argument);
    }
    let key = "boundary=";
    let idx = strings.find(low, key);
    if idx < 0 {
        return err(shared.invalid_argument);
    }
    let start = idx + len(key);
    let rest = strings.trim(strings.slice(v, start, len(v)));
    if strings.has_prefix(rest, "\"") {
        let inner = strings.slice(rest, 1, len(rest));
        let end = strings.find(inner, "\"");
        if end < 0 {
            return err(shared.invalid_argument);
        }
        return ok(strings.slice(inner, 0, end));
    }
    let semi = strings.find(rest, ";");
    if semi < 0 {
        return ok(strings.trim(rest));
    }
    return ok(strings.trim(strings.slice(rest, 0, semi)));
}

pub fn parse_file(content_type: str, body: bytes, preferred_name: str) -> result[MultipartFile, str] {
    let br = boundary_of(content_type);
    guard let boundary = br else let e = err_of(br) {
        return err(e);
    }
    let delim = to_bytes("--" + boundary);
    let pos = 0;
    let found_preferred = false;
    let preferred = MultipartFile { field_name: "", filename: "", content_type: "", data: b"" };
    let found_named = false;
    let named = MultipartFile { field_name: "", filename: "", content_type: "", data: b"" };
    let found_any = false;
    let anyf = MultipartFile { field_name: "", filename: "", content_type: "", data: b"" };

    while true {
        let start = find_bytes(body, delim, pos);
        if start < 0 {
            break;
        }
        let after = start + len(delim);
        if after + 1 < len(body) && body[after] == 45 && body[after + 1] == 45 {
            break;
        }
        if after + 1 < len(body) && body[after] == 13 && body[after + 1] == 10 {
            after = after + 2;
        }
        let next = find_bytes(body, delim, after);
        let part_end = len(body);
        if next >= 0 {
            part_end = next;
        }
        let part = body[after..part_end];
        if len(part) >= 2 && part[len(part) - 2] == 13 && part[len(part) - 1] == 10 {
            part = part[..len(part) - 2];
        }
        let sep = find_bytes(part, b"\r\n\r\n", 0);
        if sep < 0 {
            pos = after;
            continue;
        }
        let headers = header_map(part[..sep]);
        let data = part[sep + 4..];
        let disp = "";
        if has(headers, "content-disposition") {
            disp = headers["content-disposition"];
        }
        let name = disp_param(disp, "name");
        let filename = disp_param(disp, "filename");
        let pct = "application/octet-stream";
        if has(headers, "content-type") {
            pct = headers["content-type"];
        }
        let file = MultipartFile {
            field_name: name,
            filename: filename,
            content_type: pct,
            data: data
        };
        if preferred_name != "" && name == preferred_name && len(data) > 0 {
            preferred = file;
            found_preferred = true;
        }
        if len(filename) > 0 && len(data) > 0 && !found_named {
            named = file;
            found_named = true;
        }
        if len(data) > 0 && !found_any {
            anyf = file;
            found_any = true;
        }
        pos = after;
    }

    if found_preferred {
        return ok(preferred);
    }
    if found_named {
        return ok(named);
    }
    if found_any {
        return ok(anyf);
    }
    return err(shared.invalid_avatar);
}
