// infrastructure/storage — avatar file read/write under upload_dir.
import "fs";
import "os";
import "strings";
import "../../shared";

pub fn ensure_dir(dir: str) -> result[bool, str] {
    if os.is_dir(dir) {
        return ok(true);
    }
    // create parent if nested like data/uploads
    let slash = strings.rfind(dir, "/");
    if slash > 0 {
        let parent = strings.slice(dir, 0, slash);
        if len(parent) > 0 && !os.is_dir(parent) {
            let pr = fs.mkdir(parent);
            guard let _p = pr else let e = err_of(pr) {
                if !os.is_dir(parent) {
                    return err(e);
                }
            }
        }
    }
    let mr = fs.mkdir(dir);
    guard let _d = mr else let e = err_of(mr) {
        if os.is_dir(dir) {
            return ok(true);
        }
        return err(e);
    }
    return ok(true);
}

pub fn path_for(upload_dir: str, user_id: str, ext: str) -> str {
    return upload_dir + "/" + user_id + "." + ext;
}

pub fn write_avatar(upload_dir: str, user_id: str, ext: str, data: bytes) -> result[str, str] {
    let er = ensure_dir(upload_dir);
    guard let _ok = er else let e = err_of(er) {
        return err(e);
    }
    let path = path_for(upload_dir, user_id, ext);
    // remove sibling ext if switching format
    let other = "png";
    if ext == "png" {
        other = "jpg";
    }
    let other_path = path_for(upload_dir, user_id, other);
    if os.is_file(other_path) {
        let rr = os.remove(other_path);
        guard let _discard_rm = rr else let _e = err_of(rr) {
            let _discard_err = _e;
        }
    }
    let cr = fs.create(path);
    guard let fd = cr else let e = err_of(cr) {
        return err(e);
    }
    let wr = fs.write(fd, data);
    guard let _n = wr else let e = err_of(wr) {
        let _discard_close = fs.close(fd);
        return err(e);
    }
    let clr = fs.close(fd);
    guard let _c = clr else let e = err_of(clr) {
        return err(e);
    }
    return ok(path);
}

pub fn read_file(path: str) -> result[bytes, str] {
    if !os.is_file(path) {
        return err(shared.not_found);
    }
    let sr = os.size(path);
    guard let n = sr else let e = err_of(sr) {
        return err(e);
    }
    let or = fs.open(path);
    guard let fd = or else let e = err_of(or) {
        return err(e);
    }
    let rr = fs.read(fd, n);
    guard let data = rr else let e = err_of(rr) {
        let _discard_close2 = fs.close(fd);
        return err(e);
    }
    let clr = fs.close(fd);
    guard let _c = clr else let e = err_of(clr) {
        return err(e);
    }
    return ok(data);
}

pub fn delete_file(path: str) -> result[bool, str] {
    if !os.is_file(path) {
        return ok(true);
    }
    return os.remove(path);
}

pub fn content_type_for_path(path: str) -> str {
    if strings.has_suffix(path, ".png") {
        return "image/png";
    }
    return "image/jpeg";
}
