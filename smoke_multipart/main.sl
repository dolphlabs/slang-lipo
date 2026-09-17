import "../interfaces/http" as api;

fn die(m: str) {
    println("FAIL: " + m);
    exit(1);
}

fn main() {
    println("start");
    let boundary = "----LipoBoundary7MA4YWxkTrZu0gW";
    let png = b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR";
    let head = "--" + boundary + "\r\n" +
        "Content-Disposition: form-data; name=\"avatar\"; filename=\"a.png\"\r\n" +
        "Content-Type: image/png\r\n\r\n";
    let tail = "\r\n--" + boundary + "--\r\n";
    let body = to_bytes(head) + png + to_bytes(tail);
    let ct = "multipart/form-data; boundary=" + boundary;
    let pr = api.parse_file(ct, body, "avatar");
    guard let part = pr else let e = err_of(pr) {
        die("parse: " + e);
    }
    if part.field_name != "avatar" {
        die("field name=" + part.field_name);
    }
    if part.content_type != "image/png" {
        die("ct: " + part.content_type);
    }
    if len(part.data) != len(png) {
        die("len got=" + to_str(len(part.data)));
    }
    if part.data[0] != 137 {
        die("magic");
    }
    println("multipart parse ok");
}
