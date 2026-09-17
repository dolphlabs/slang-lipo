// infrastructure/ws/frame — RFC 6455 framing (client masked in, server unmasked out).

pub let OP_CONTINUATION = 0;
pub let OP_TEXT = 1;
pub let OP_BINARY = 2;
pub let OP_CLOSE = 8;
pub let OP_PING = 9;
pub let OP_PONG = 10;

pub struct Frame {
    fin: bool,
    opcode: int,
    payload: bytes
}

pub struct Decoded {
    frame: Frame,
    consumed: int
}

fn u16_be(b0: int, b1: int) -> int {
    return ((b0 & 0xff) << 8) | (b1 & 0xff);
}

fn put_u16_be(out: bytes, off: int, v: int) {
    out[off] = (v >> 8) & 0xff;
    out[off + 1] = v & 0xff;
}

fn byte1(n: int) -> bytes {
    return to_le(n & 0xff)[0..1];
}

pub fn try_decode_ex(buf: bytes, filled: int) -> result[Decoded, str] {
    if filled < 2 {
        return err("incomplete");
    }
    let b0 = buf[0];
    let b1 = buf[1];
    let fin = (b0 & 0x80) != 0;
    let opcode = b0 & 0x0f;
    let masked = (b1 & 0x80) != 0;
    let mut_len = b1 & 0x7f;
    let hdr = 2;
    let payload_len = 0;

    if mut_len == 126 {
        if filled < 4 {
            return err("incomplete");
        }
        payload_len = u16_be(buf[2], buf[3]);
        hdr = 4;
    } else if mut_len == 127 {
        if filled < 10 {
            return err("incomplete");
        }
        if buf[2] != 0 || buf[3] != 0 || buf[4] != 0 || buf[5] != 0 {
            return err("frame too large");
        }
        payload_len = (buf[6] << 24) | (buf[7] << 16) | (buf[8] << 8) | buf[9];
        if payload_len < 0 || payload_len > 1048576 {
            return err("frame too large");
        }
        hdr = 10;
    } else {
        payload_len = mut_len;
    }

    let mask_off = hdr;
    let data_off = hdr;
    if masked {
        data_off = hdr + 4;
    }
    let need = data_off + payload_len;
    if filled < need {
        return err("incomplete");
    }

    let payload = b"";
    let i = 0;
    while i < payload_len {
        let b = buf[data_off + i];
        if masked {
            b = b ^ buf[mask_off + (i % 4)];
        }
        payload = payload + byte1(b);
        i = i + 1;
    }

    return ok(Decoded {
        frame: Frame { fin: fin, opcode: opcode, payload: payload },
        consumed: need
    });
}

pub fn encode_server(opcode: int, payload: bytes) -> bytes {
    let plen = len(payload);
    let head = byte1(0x80 | (opcode & 0x0f));
    if plen < 126 {
        head = head + byte1(plen);
    } else if plen < 65536 {
        head = head + byte1(126);
        let lenb = b"\x00\x00";
        put_u16_be(lenb, 0, plen);
        head = head + lenb;
    } else {
        head = head + byte1(127);
        let l8 = b"\x00\x00\x00\x00\x00\x00\x00\x00";
        l8[4] = (plen >> 24) & 0xff;
        l8[5] = (plen >> 16) & 0xff;
        l8[6] = (plen >> 8) & 0xff;
        l8[7] = plen & 0xff;
        head = head + l8;
    }
    return head + payload;
}

pub fn encode_text(text: str) -> bytes {
    return encode_server(OP_TEXT, to_bytes(text));
}

pub fn encode_pong(payload: bytes) -> bytes {
    return encode_server(OP_PONG, payload);
}

pub fn encode_close(code: int, reason: str) -> bytes {
    let body = b"\x00\x00";
    put_u16_be(body, 0, code);
    if len(reason) > 0 {
        body = body + to_bytes(reason);
    }
    return encode_server(OP_CLOSE, body);
}
