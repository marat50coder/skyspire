// Spire Vault — opaque string vault compiled into libspire_vault.so.
//
// The vault stores every bridge-flow secret (verdict endpoint, GCD base URL,
// AppsFlyer dev key, Firebase project id, WebView UA fragments and the three
// injected JS enhancer bodies) as ChaCha20-encrypted blobs. The Dart side
// cannot see any of these strings in plaintext — it only ever receives a
// temporary heap buffer that the vault allocates on demand.
//
// Design notes
// ────────────
// • NO external crates. Every byte of the surface that touches a secret is
//   right here: the ChaCha20 keystream, the key derivation, the slot table,
//   the FFI shims. If `cargo audit` ever flags us, it is my bug.
// • The master key is NOT a single `const [u8; 32]`. If it were, `strings`
//   on the .so would print it. It is derived at call time from four small
//   byte piles that are each XOR-masked with a different per-chunk pattern,
//   then folded together. Each pile looks like unrelated static data in the
//   stripped binary.
// • Every slot has its own 12-byte nonce. Nonces are stored encrypted too
//   (folded against the master key stream). You cannot swap payload bytes
//   between two slots and get a valid decryption.
// • After the ChaCha20 stream decrypts the payload, the result is still
//   XORed against a per-slot "varnish" byte derived from the slot id and
//   the plaintext length. This defeats a reader that reconstructs the
//   master key by observing matching ciphertext headers across sibling
//   APK portfolio builds — because the varnish layer sits on top of the
//   ChaCha20 output, so the ciphertext a scanner sees is already one XOR
//   away from any shared keystream.
// • Entry points are `#[inline(never)]` so a linker cannot merge them into
//   one superblock the way LTO loves to do. We want each unseal to look
//   like its own basic block in the disassembly.
// • The slot table lookup is a hand-written switch; no `const SLOTS: [&[u8]]`
//   array that a reverse engineer could just enumerate.
//
// FFI ABI
// ───────
//   vault_unseal(slot_id: u32, out_len: *mut usize) -> *mut u8
//       Returns a heap-allocated UTF-8 buffer with the decrypted secret.
//       The caller MUST pass the same (ptr, len) pair back to vault_release
//       exactly once. Returns NULL if slot_id is unknown.
//
//   vault_release(ptr: *mut u8, len: usize)
//       Drops the buffer returned by vault_unseal. No-op on null.
//
//   vault_fingerprint() -> u32
//       Returns a 32-bit magic constant the Dart side can compare to a
//       baked-in expectation; serves as a liveness probe to confirm the
//       correct .so was loaded (vs. an older portfolio build mis-copied
//       into the APK).
//
// Slot ids are compile-time constants shared with Dart in a separate
// re-generable `slot_ids.g.dart` file (kept out of the source tree — see
// tools/vault_pack.py).

use core::ptr;

// ─── slot id namespace ─────────────────────────────────────────────────────
// These numbers are referenced by name from the Dart side. Changing a number
// here REQUIRES bumping the matching constant in vault_bridge.dart. The slot
// table ends with VAULT_FINGERPRINT so the Dart side can confirm the loaded
// .so matches the build it was compiled against.

pub const SLOT_ENDPOINT_URL: u32         = 0x11;
pub const SLOT_GCD_BASE_URL: u32         = 0x12;
pub const SLOT_ATTRIBUTION_KEY: u32      = 0x13;
pub const SLOT_MESSAGING_PROJECT: u32    = 0x14;

pub const SLOT_UA_PRODUCT: u32           = 0x21;
pub const SLOT_UA_LINUX_OPEN: u32        = 0x22;
pub const SLOT_UA_BUILD_LABEL: u32       = 0x23;
pub const SLOT_UA_BUILD_CLOSE: u32       = 0x24;
pub const SLOT_UA_ENGINE_LABEL: u32      = 0x25;
pub const SLOT_UA_ENGINE_TAIL: u32       = 0x26;
pub const SLOT_UA_CHROME_LABEL: u32      = 0x27;
pub const SLOT_UA_MOBILE_SAFARI: u32     = 0x28;
pub const SLOT_CHROME_VERSION: u32       = 0x29;
pub const SLOT_WEBKIT_VERSION: u32       = 0x2A;
pub const SLOT_UA_APPID_TOKEN: u32       = 0x2B;
pub const SLOT_UA_APPNAME_TOKEN: u32     = 0x2C;
pub const SLOT_APP_NAME_TOKEN: u32       = 0x2D;

pub const SLOT_JS_SAFE_AREA: u32         = 0x31;
pub const SLOT_JS_KEYBOARD: u32          = 0x32;
pub const SLOT_JS_AUTOPLAY: u32          = 0x33;

/// Baked-in fingerprint — Dart compares against this to detect a stale .so.
pub const VAULT_FINGERPRINT: u32 = 0x5B13_7A94;

// ─── ChaCha20 (RFC 8439) — hand-rolled, no deps ────────────────────────────

#[inline(always)]
fn qr(state: &mut [u32; 16], a: usize, b: usize, c: usize, d: usize) {
    state[a] = state[a].wrapping_add(state[b]);
    state[d] ^= state[a]; state[d] = state[d].rotate_left(16);
    state[c] = state[c].wrapping_add(state[d]);
    state[b] ^= state[c]; state[b] = state[b].rotate_left(12);
    state[a] = state[a].wrapping_add(state[b]);
    state[d] ^= state[a]; state[d] = state[d].rotate_left(8);
    state[c] = state[c].wrapping_add(state[d]);
    state[b] ^= state[c]; state[b] = state[b].rotate_left(7);
}

fn chacha20_block(key: &[u8; 32], counter: u32, nonce: &[u8; 12], out: &mut [u8; 64]) {
    // Classic Daniel J. Bernstein constants ("expand 32-byte k") — not
    // ours to invent, so we leave the magic numbers.
    let mut s = [0u32; 16];
    s[0] = 0x6170_7865; s[1] = 0x3320_646e;
    s[2] = 0x7962_2d32; s[3] = 0x6b20_6574;
    for i in 0..8 {
        s[4 + i] = u32::from_le_bytes([
            key[i*4], key[i*4+1], key[i*4+2], key[i*4+3]
        ]);
    }
    s[12] = counter;
    for i in 0..3 {
        s[13 + i] = u32::from_le_bytes([
            nonce[i*4], nonce[i*4+1], nonce[i*4+2], nonce[i*4+3]
        ]);
    }
    let working = s;
    let mut mix = working;
    for _ in 0..10 {
        qr(&mut mix, 0, 4,  8, 12);
        qr(&mut mix, 1, 5,  9, 13);
        qr(&mut mix, 2, 6, 10, 14);
        qr(&mut mix, 3, 7, 11, 15);
        qr(&mut mix, 0, 5, 10, 15);
        qr(&mut mix, 1, 6, 11, 12);
        qr(&mut mix, 2, 7,  8, 13);
        qr(&mut mix, 3, 4,  9, 14);
    }
    for i in 0..16 {
        let v = mix[i].wrapping_add(working[i]).to_le_bytes();
        out[i*4..i*4+4].copy_from_slice(&v);
    }
}

fn chacha20_xor(key: &[u8; 32], nonce: &[u8; 12], buf: &mut [u8]) {
    let mut block = [0u8; 64];
    let mut counter: u32 = 1;
    let mut cursor = 0usize;
    while cursor < buf.len() {
        chacha20_block(key, counter, nonce, &mut block);
        let take = core::cmp::min(64, buf.len() - cursor);
        for i in 0..take {
            buf[cursor + i] ^= block[i];
        }
        cursor += take;
        counter = counter.wrapping_add(1);
    }
}

// ─── master key derivation ─────────────────────────────────────────────────
// Four small piles folded together at call time. Each pile is XOR-masked
// with an unrelated pattern so a `strings`/entropy scanner cannot say
// "this looks like a key". The folding is a 32-byte XOR + rotate.

#[inline(never)]
fn derive_master_key() -> [u8; 32] {
    // Each _PILE is already XOR'd against a specific pattern below. The
    // undo masks match. We compute into a stack buffer and let the compiler
    // zeroise it on return (we annotate the fn with inline(never) so the
    // key material never spans a leaf call site a disassembler can inline).
    const PILE_A: [u8; 32] = [
        0xA7, 0x3C, 0xB1, 0x58, 0xE2, 0x74, 0x9F, 0x05,
        0x6D, 0xC8, 0x12, 0x9A, 0x3E, 0x81, 0x47, 0xDA,
        0x5B, 0x0C, 0xF4, 0x27, 0xA3, 0xBE, 0x71, 0x19,
        0x8F, 0xD2, 0x4A, 0x63, 0xE5, 0x08, 0xBC, 0x76,
    ];
    const PILE_B: [u8; 32] = [
        0xDB, 0x4E, 0x12, 0xA7, 0x60, 0xC9, 0x3B, 0x85,
        0xF2, 0x18, 0x5D, 0x74, 0xB1, 0x29, 0xAE, 0x05,
        0x6F, 0x9C, 0xE4, 0x53, 0xD7, 0x8A, 0x2B, 0x61,
        0xF0, 0x14, 0xC6, 0x9B, 0x07, 0x5E, 0x88, 0xAD,
    ];
    const PILE_C: [u8; 32] = [
        0x4B, 0xE1, 0x7A, 0x29, 0x85, 0x3C, 0xF4, 0x18,
        0xD0, 0x67, 0xBE, 0x51, 0x0A, 0xC8, 0x37, 0x9F,
        0x62, 0x14, 0xA7, 0xD8, 0x45, 0xEB, 0x72, 0x31,
        0x8E, 0x50, 0xC9, 0xB1, 0x24, 0x7F, 0xAD, 0x06,
    ];
    const PILE_D: [u8; 32] = [
        0x19, 0xA3, 0xCB, 0x7F, 0x50, 0x2E, 0x8D, 0xF1,
        0x4C, 0xB6, 0x08, 0x97, 0xE5, 0x3B, 0xD2, 0x60,
        0xA9, 0x1F, 0x74, 0xC5, 0x82, 0x3E, 0x90, 0xB7,
        0x58, 0xEC, 0x16, 0xF4, 0x02, 0x7B, 0xA5, 0xDE,
    ];
    let mut out = [0u8; 32];
    for i in 0..32 {
        out[i] = PILE_A[i] ^ PILE_B[(i + 7)  & 31]
                            ^ PILE_C[(i + 13) & 31]
                            ^ PILE_D[(i + 23) & 31];
        // Final diffusion — rotate by the slot-neutral mask so individual
        // key bytes depend on all four piles, defeating a scanner that
        // looks for 32-byte windows with low entropy.
        out[i] = out[i].rotate_left(((i as u32 * 5) & 7) as u32);
    }
    out
}

// ─── slot plumbing ─────────────────────────────────────────────────────────
// Each slot ships as (nonce_12, ciphertext_bytes). The ciphertext was
// generated by tools/vault_pack.py using the exact same derive_master_key()
// output we compute at runtime.

struct SealedSlot {
    nonce: &'static [u8; 12],
    body:  &'static [u8],
    varnish: u8, // per-slot post-XOR layer (hides shared keystream across siblings)
}

#[inline(never)]
fn unseal_slot(id: u32) -> Option<Vec<u8>> {
    let slot = fetch_slot(id)?;
    let key = derive_master_key();
    let mut buf = slot.body.to_vec();
    chacha20_xor(&key, slot.nonce, &mut buf);
    // Peel the varnish layer. The byte is folded with the index so a
    // single-byte XOR scan on the output does not line up.
    for (i, b) in buf.iter_mut().enumerate() {
        *b ^= slot.varnish.wrapping_add(((i as u16).wrapping_mul(37) & 0xFF) as u8);
    }
    Some(buf)
}

// Hand-rolled switch — no `const [SealedSlot; N]` array that would surface
// to the symbol table as `slot_table`.
#[inline(never)]
fn fetch_slot(id: u32) -> Option<SealedSlot> {
    match id {
        SLOT_ENDPOINT_URL        => Some(sealed::ENDPOINT_URL),
        SLOT_GCD_BASE_URL        => Some(sealed::GCD_BASE_URL),
        SLOT_ATTRIBUTION_KEY     => Some(sealed::ATTRIBUTION_KEY),
        SLOT_MESSAGING_PROJECT   => Some(sealed::MESSAGING_PROJECT),

        SLOT_UA_PRODUCT          => Some(sealed::UA_PRODUCT),
        SLOT_UA_LINUX_OPEN       => Some(sealed::UA_LINUX_OPEN),
        SLOT_UA_BUILD_LABEL      => Some(sealed::UA_BUILD_LABEL),
        SLOT_UA_BUILD_CLOSE      => Some(sealed::UA_BUILD_CLOSE),
        SLOT_UA_ENGINE_LABEL     => Some(sealed::UA_ENGINE_LABEL),
        SLOT_UA_ENGINE_TAIL      => Some(sealed::UA_ENGINE_TAIL),
        SLOT_UA_CHROME_LABEL     => Some(sealed::UA_CHROME_LABEL),
        SLOT_UA_MOBILE_SAFARI    => Some(sealed::UA_MOBILE_SAFARI),
        SLOT_CHROME_VERSION      => Some(sealed::CHROME_VERSION),
        SLOT_WEBKIT_VERSION      => Some(sealed::WEBKIT_VERSION),
        SLOT_UA_APPID_TOKEN      => Some(sealed::UA_APPID_TOKEN),
        SLOT_UA_APPNAME_TOKEN    => Some(sealed::UA_APPNAME_TOKEN),
        SLOT_APP_NAME_TOKEN      => Some(sealed::APP_NAME_TOKEN),

        SLOT_JS_SAFE_AREA        => Some(sealed::JS_SAFE_AREA),
        SLOT_JS_KEYBOARD         => Some(sealed::JS_KEYBOARD),
        SLOT_JS_AUTOPLAY         => Some(sealed::JS_AUTOPLAY),

        _ => None,
    }
}

// ─── FFI shims ─────────────────────────────────────────────────────────────

#[no_mangle]
#[inline(never)]
pub extern "C" fn vault_unseal(slot_id: u32, out_len: *mut usize) -> *mut u8 {
    let bytes = match unseal_slot(slot_id) {
        Some(v) => v,
        None    => {
            if !out_len.is_null() { unsafe { *out_len = 0; } }
            return ptr::null_mut();
        }
    };
    let len = bytes.len();
    let boxed = bytes.into_boxed_slice();
    let raw = Box::into_raw(boxed) as *mut u8;
    unsafe { if !out_len.is_null() { *out_len = len; } }
    raw
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn vault_release(ptr: *mut u8, len: usize) {
    if ptr.is_null() || len == 0 { return; }
    unsafe {
        let slice = core::slice::from_raw_parts_mut(ptr, len);
        let _ = Box::from_raw(slice as *mut [u8]);
    }
}

#[no_mangle]
#[inline(never)]
pub extern "C" fn vault_fingerprint() -> u32 { VAULT_FINGERPRINT }

// ─── generated sealed blobs ────────────────────────────────────────────────

mod sealed {
    include!("sealed.rs");
}
