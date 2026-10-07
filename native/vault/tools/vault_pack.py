#!/usr/bin/env python3
"""
vault_pack.py — generates native/vault/src/sealed.rs with the ChaCha20-sealed
payloads for every slot defined in lib.rs.

The output file mirrors the plaintext that lib.rs expects to decrypt back.
Keep this script in sync with lib.rs: if you change derive_master_key(),
chacha20_xor() or the varnish layer, re-run this script and commit the
regenerated sealed.rs alongside the lib.rs change.

Usage:
    python3 native/vault/tools/vault_pack.py > native/vault/src/sealed.rs

The script has NO external dependencies. ChaCha20 is implemented in-place
so we can run it in CI containers that don't carry PyCryptodome.
"""

import os
import struct
import sys

# ── master key piles (same bytes as src/lib.rs) ────────────────────────────
PILE_A = [
    0xA7, 0x3C, 0xB1, 0x58, 0xE2, 0x74, 0x9F, 0x05,
    0x6D, 0xC8, 0x12, 0x9A, 0x3E, 0x81, 0x47, 0xDA,
    0x5B, 0x0C, 0xF4, 0x27, 0xA3, 0xBE, 0x71, 0x19,
    0x8F, 0xD2, 0x4A, 0x63, 0xE5, 0x08, 0xBC, 0x76,
]
PILE_B = [
    0xDB, 0x4E, 0x12, 0xA7, 0x60, 0xC9, 0x3B, 0x85,
    0xF2, 0x18, 0x5D, 0x74, 0xB1, 0x29, 0xAE, 0x05,
    0x6F, 0x9C, 0xE4, 0x53, 0xD7, 0x8A, 0x2B, 0x61,
    0xF0, 0x14, 0xC6, 0x9B, 0x07, 0x5E, 0x88, 0xAD,
]
PILE_C = [
    0x4B, 0xE1, 0x7A, 0x29, 0x85, 0x3C, 0xF4, 0x18,
    0xD0, 0x67, 0xBE, 0x51, 0x0A, 0xC8, 0x37, 0x9F,
    0x62, 0x14, 0xA7, 0xD8, 0x45, 0xEB, 0x72, 0x31,
    0x8E, 0x50, 0xC9, 0xB1, 0x24, 0x7F, 0xAD, 0x06,
]
PILE_D = [
    0x19, 0xA3, 0xCB, 0x7F, 0x50, 0x2E, 0x8D, 0xF1,
    0x4C, 0xB6, 0x08, 0x97, 0xE5, 0x3B, 0xD2, 0x60,
    0xA9, 0x1F, 0x74, 0xC5, 0x82, 0x3E, 0x90, 0xB7,
    0x58, 0xEC, 0x16, 0xF4, 0x02, 0x7B, 0xA5, 0xDE,
]


def rotl8(b: int, bits: int) -> int:
    bits &= 7
    return ((b << bits) | (b >> (8 - bits))) & 0xFF if bits else b & 0xFF


def derive_master_key() -> bytes:
    out = bytearray(32)
    for i in range(32):
        v = PILE_A[i] ^ PILE_B[(i + 7) & 31] ^ PILE_C[(i + 13) & 31] ^ PILE_D[(i + 23) & 31]
        out[i] = rotl8(v, (i * 5) & 7)
    return bytes(out)


# ── ChaCha20 (RFC 8439) ────────────────────────────────────────────────────
MASK32 = 0xFFFFFFFF


def rotl32(x: int, n: int) -> int:
    n &= 31
    return ((x << n) | (x >> (32 - n))) & MASK32


def qr(s, a, b, c, d):
    s[a] = (s[a] + s[b]) & MASK32; s[d] ^= s[a]; s[d] = rotl32(s[d], 16)
    s[c] = (s[c] + s[d]) & MASK32; s[b] ^= s[c]; s[b] = rotl32(s[b], 12)
    s[a] = (s[a] + s[b]) & MASK32; s[d] ^= s[a]; s[d] = rotl32(s[d], 8)
    s[c] = (s[c] + s[d]) & MASK32; s[b] ^= s[c]; s[b] = rotl32(s[b], 7)


def chacha20_block(key: bytes, counter: int, nonce: bytes) -> bytes:
    assert len(key) == 32 and len(nonce) == 12
    s = [0] * 16
    s[0], s[1], s[2], s[3] = 0x61707865, 0x3320646e, 0x79622d32, 0x6b206574
    for i in range(8):
        s[4 + i] = struct.unpack('<I', key[i*4:i*4+4])[0]
    s[12] = counter & MASK32
    for i in range(3):
        s[13 + i] = struct.unpack('<I', nonce[i*4:i*4+4])[0]
    working = list(s)
    mix = list(s)
    for _ in range(10):
        qr(mix, 0, 4,  8, 12); qr(mix, 1, 5,  9, 13)
        qr(mix, 2, 6, 10, 14); qr(mix, 3, 7, 11, 15)
        qr(mix, 0, 5, 10, 15); qr(mix, 1, 6, 11, 12)
        qr(mix, 2, 7,  8, 13); qr(mix, 3, 4,  9, 14)
    out = bytearray()
    for i in range(16):
        out += struct.pack('<I', (mix[i] + working[i]) & MASK32)
    return bytes(out)


def chacha20_xor(key: bytes, nonce: bytes, data: bytes) -> bytes:
    out = bytearray(len(data))
    counter = 1
    cursor = 0
    while cursor < len(data):
        block = chacha20_block(key, counter, nonce)
        take = min(64, len(data) - cursor)
        for i in range(take):
            out[cursor + i] = data[cursor + i] ^ block[i]
        cursor += take
        counter += 1
    return bytes(out)


# ── slot definitions ────────────────────────────────────────────────────────
# These must mirror the SLOT_* ids in lib.rs. Each slot has (id, name,
# plaintext). Nonce bytes are derived from the slot id so the generator and
# runtime stay deterministic without needing a shared salt file.

SLOTS = [
    (0x11, 'ENDPOINT_URL',       'https://skyspirre.com/config.php'),
    (0x12, 'GCD_BASE_URL',       'https://gcdsdk.appsflyer.com/install_data/v4.0/'),
    (0x13, 'ATTRIBUTION_KEY',    '6Pv5qxxKu42sMTDQiHgbVh'),
    (0x14, 'MESSAGING_PROJECT',  'skyspire-69a94'),

    (0x21, 'UA_PRODUCT',         'Mozilla/5.0'),
    (0x22, 'UA_LINUX_OPEN',      '(Linux; Android'),
    (0x23, 'UA_BUILD_LABEL',     ' Build/'),
    (0x24, 'UA_BUILD_CLOSE',     ')'),
    (0x25, 'UA_ENGINE_LABEL',    ' AppleWebKit/'),
    (0x26, 'UA_ENGINE_TAIL',     ' (KHTML, like Gecko)'),
    (0x27, 'UA_CHROME_LABEL',    ' Chrome/'),
    (0x28, 'UA_MOBILE_SAFARI',   ' Mobile Safari/'),
    (0x29, 'CHROME_VERSION',     '149.0.7623.148'),
    (0x2A, 'WEBKIT_VERSION',     '537.36'),
    (0x2B, 'UA_APPID_TOKEN',     'appid/'),
    (0x2C, 'UA_APPNAME_TOKEN',   'appname/'),
    (0x2D, 'APP_NAME_TOKEN',     'Skyspire'),

    (0x31, 'JS_SAFE_AREA',       """(function(){if(window.__spireSafeArea===true)return;window.__spireSafeArea=true;var V=document.documentElement.style;['top','right','bottom','left'].forEach(function(k){V.setProperty('--safe-area-inset-'+k,'0px','important');});V.setProperty('--sat','0px','important');V.setProperty('--sab','0px','important');var sel='.gameview-mobile-header,.app-header,.js-safe-top',n=document.querySelectorAll(sel);for(var i=0;i<n.length;i++){n[i].style.setProperty('padding-top','0','important');n[i].style.setProperty('margin-top','0','important');}})();"""),
    (0x32, 'JS_KEYBOARD',        """(function(){if(window.__spireKbDock===true)return;window.__spireKbDock=true;function editable(el){if(!el)return false;if(el.isContentEditable)return true;var tag=(el.tagName||'').toUpperCase();return tag==='INPUT'||tag==='TEXTAREA'||tag==='SELECT';}function lift(){var el=document.activeElement;if(!editable(el))return;var vv=window.visualViewport;if(vv){var box=el.getBoundingClientRect();var floor=vv.offsetTop+vv.height;if(box.bottom>floor-24||box.top<vv.offsetTop){el.scrollIntoView({block:'nearest',inline:'nearest'});}}else{el.scrollIntoView({block:'nearest',inline:'nearest'});}}document.addEventListener('focusin',function(ev){if(editable(ev.target))setTimeout(lift,320);});if(window.visualViewport){var seen=window.visualViewport.height;window.visualViewport.addEventListener('resize',function(){var now=window.visualViewport.height;if(now<seen)setTimeout(lift,110);seen=now;});}})();"""),
    (0x33, 'JS_AUTOPLAY',        """(function(){if(window.__spireAutoplay===true)return;window.__spireAutoplay=true;function spin(v){try{v.muted=true;v.setAttribute('playsinline','');var p=v.play();if(p&&p.catch)p.catch(function(){});}catch(_){}}var vs=document.querySelectorAll('video');for(var i=0;i<vs.length;i++)spin(vs[i]);new MutationObserver(function(muts){for(var m=0;m<muts.length;m++){var ad=muts[m].addedNodes;for(var k=0;k<ad.length;k++){var el=ad[k];if(!el)continue;if(el.tagName==='VIDEO')spin(el);else if(el.querySelectorAll){var vv=el.querySelectorAll('video');for(var j=0;j<vv.length;j++)spin(vv[j]);}}}}).observe(document.documentElement,{childList:true,subtree:true});})();"""),
]


def derive_nonce(slot_id: int) -> bytes:
    # 12-byte nonce derived from the slot id. Each slot ends up with its own
    # keystream, so swapping ciphertexts between slots produces garbage.
    seed = (slot_id * 0x9E3779B9) & 0xFFFFFFFFFFFFFFFF
    out = bytearray(12)
    s = seed
    for i in range(12):
        s = (s ^ ((s >> 7) & 0xFFFFFFFFFFFFFFFF)) & 0xFFFFFFFFFFFFFFFF
        s = (s * 0xBF58476D1CE4E5B9) & 0xFFFFFFFFFFFFFFFF
        out[i] = (s >> ((i & 7) * 4)) & 0xFF
    return bytes(out)


def derive_varnish(slot_id: int, plain_len: int) -> int:
    v = ((slot_id * 0x45) ^ (plain_len * 0x1F)) & 0xFF
    return v


def pack_slot(slot_id: int, plain: str) -> dict:
    key = derive_master_key()
    nonce = derive_nonce(slot_id)
    data = plain.encode('utf-8')
    # Apply the varnish FIRST — runtime peels it after ChaCha20, so to seal
    # we apply the inverse order: varnish → ChaCha20.
    varnish = derive_varnish(slot_id, len(data))
    varnished = bytearray(data)
    for i in range(len(varnished)):
        varnished[i] ^= (varnish + ((i * 37) & 0xFF)) & 0xFF
    sealed = chacha20_xor(key, nonce, bytes(varnished))
    return dict(nonce=nonce, body=sealed, varnish=varnish)


def render_byte_array(name: str, data: bytes, indent: str = '    ') -> str:
    PER = 12
    chunks = []
    for i in range(0, len(data), PER):
        hx = ', '.join(f'0x{x:02X}' for x in data[i:i+PER])
        chunks.append(f'{indent}{hx},')
    body = '\n'.join(chunks)
    return f'{indent[:-4]}pub static {name}: {kind_for(data)} = [\n{body}\n{indent[:-4]}];\n'


def kind_for(data: bytes) -> str:
    return f'[u8; {len(data)}]'


def render_slot(name: str, slot_id: int, payload: dict) -> str:
    nonce_var = f'{name}_NONCE'
    body_var  = f'{name}_BODY'
    lines = []
    lines.append(f'// slot 0x{slot_id:02X} — {name}')
    lines.append(render_byte_array(nonce_var, payload["nonce"]))
    lines.append(render_byte_array(body_var,  payload["body"]))
    lines.append(
        f'pub const {name}: super::SealedSlot = super::SealedSlot {{\n'
        f'    nonce: &{nonce_var},\n'
        f'    body:  &{body_var},\n'
        f'    varnish: 0x{payload["varnish"]:02X},\n'
        f'}};\n'
    )
    return '\n'.join(lines)


def main() -> int:
    out = sys.stdout
    out.write('// AUTOGENERATED by native/vault/tools/vault_pack.py — do not edit by hand.\n')
    out.write('// Regenerate: `python3 native/vault/tools/vault_pack.py > native/vault/src/sealed.rs`\n')
    out.write('//\n')
    out.write('// Every slot is ChaCha20-encrypted with a key derived at runtime from four\n')
    out.write('// XOR-masked piles (see derive_master_key in lib.rs). The plaintext is also\n')
    out.write('// XOR-varnished before encryption so swapping ciphertexts between slots or\n')
    out.write('// across sibling portfolio APKs produces garbage.\n\n')
    out.write('')
    for slot_id, name, plain in SLOTS:
        payload = pack_slot(slot_id, plain)
        # Round-trip assert so a bad commit never ships.
        key = derive_master_key()
        decrypted = bytearray(chacha20_xor(key, payload["nonce"], payload["body"]))
        for i in range(len(decrypted)):
            decrypted[i] ^= (payload["varnish"] + ((i * 37) & 0xFF)) & 0xFF
        assert bytes(decrypted).decode('utf-8') == plain, f'round-trip failed for {name}'
        out.write(render_slot(name, slot_id, payload))
        out.write('\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())
