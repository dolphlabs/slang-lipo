// shared/sha1 — pure SHA-1 (RFC 3174 / FIPS 180-1). Crypto stdlib has no sha1;
// WebSocket Accept (RFC 6455) requires it.
// Returns a 20-byte digest.

fn mask32(n: int) -> int {
    return n & 0xffffffff;
}

fn rotl(n: int, b: int) -> int {
    let x = mask32(n);
    return mask32((x << b) | (x >> (32 - b)));
}

fn get_be32(msg: bytes, off: int) -> int {
    return mask32((msg[off] << 24) | (msg[off + 1] << 16) | (msg[off + 2] << 8) | msg[off + 3]);
}

fn put_be32(out: bytes, off: int, v: int) {
    let x = mask32(v);
    out[off] = (x >> 24) & 0xff;
    out[off + 1] = (x >> 16) & 0xff;
    out[off + 2] = (x >> 8) & 0xff;
    out[off + 3] = x & 0xff;
}

fn process_block(h0: int, h1: int, h2: int, h3: int, h4: int, block: bytes, boff: int) -> [int] {
    let w: [int] = [];
    let i = 0;
    while i < 16 {
        push(w, get_be32(block, boff + i * 4));
        i = i + 1;
    }
    while i < 80 {
        let v = rotl(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
        push(w, v);
        i = i + 1;
    }

    let a = h0;
    let b = h1;
    let c = h2;
    let d = h3;
    let e = h4;
    i = 0;
    while i < 80 {
        let f = 0;
        let k = 0;
        if i < 20 {
            f = (b & c) | ((mask32(~b)) & d);
            k = 0x5a827999;
        } else if i < 40 {
            f = b ^ c ^ d;
            k = 0x6ed9eba1;
        } else if i < 60 {
            f = (b & c) | (b & d) | (c & d);
            k = 0x8f1bbcdc;
        } else {
            f = b ^ c ^ d;
            k = 0xca62c1d6;
        }
        let temp = mask32(rotl(a, 5) + mask32(f) + e + k + w[i]);
        e = d;
        d = c;
        c = rotl(b, 30);
        b = a;
        a = temp;
        i = i + 1;
    }

    let out: [int] = [
        mask32(h0 + a),
        mask32(h1 + b),
        mask32(h2 + c),
        mask32(h3 + d),
        mask32(h4 + e)
    ];
    return out;
}

pub fn sha1(msg: bytes) -> bytes {
    let ml = len(msg);
    // padded length: ml + 1 + pad zeros + 8, multiple of 64
    let bit_len = ml * 8;
    let with_one = ml + 1;
    let mod = with_one % 64;
    let zeros = 0;
    if mod <= 56 {
        zeros = 56 - mod;
    } else {
        zeros = 64 + 56 - mod;
    }
    let total = with_one + zeros + 8;
    let padded = b"";
    let i = 0;
    while i < ml {
        padded = padded + to_le(msg[i])[0..1];
        i = i + 1;
    }
    padded = padded + b"\x80";
    i = 0;
    while i < zeros {
        padded = padded + b"\x00";
        i = i + 1;
    }
    // 64-bit big-endian bit length (high 32 always 0 for our sizes)
    padded = padded + b"\x00\x00\x00\x00";
    let len_buf = b"\x00\x00\x00\x00";
    put_be32(len_buf, 0, bit_len);
    padded = padded + len_buf;

    let h0 = 0x67452301;
    let h1 = 0xefcdab89;
    let h2 = 0x98badcfe;
    let h3 = 0x10325476;
    let h4 = 0xc3d2e1f0;

    let off = 0;
    while off < total {
        let hs = process_block(h0, h1, h2, h3, h4, padded, off);
        h0 = hs[0];
        h1 = hs[1];
        h2 = hs[2];
        h3 = hs[3];
        h4 = hs[4];
        off = off + 64;
    }

    let dig = b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00";
    put_be32(dig, 0, h0);
    put_be32(dig, 4, h1);
    put_be32(dig, 8, h2);
    put_be32(dig, 12, h3);
    put_be32(dig, 16, h4);
    return dig;
}

pub fn sha1_str(s: str) -> bytes {
    return sha1(to_bytes(s));
}
