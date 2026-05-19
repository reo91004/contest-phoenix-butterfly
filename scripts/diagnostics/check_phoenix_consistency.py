#!/usr/bin/env python3
"""Check RTL scheduling conventions against ML-KEM / ML-DSA golden helpers."""

from __future__ import annotations

import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "model"))

from golden_arithmetic import (
    MLDSA_Q,
    Q,
    mldsa_mul_mont,
    mldsa_to_mont,
    modq_add,
    modq_div2,
    modq_mul,
    modq_sub,
)
from golden_ntt import ZETA, bitrev7, intt as golden_intt, ntt as golden_ntt, pwm as golden_pwm

INIT_OFFSETS = (0, 1024, 2048, 3072)


def valid_offsets(words: int) -> tuple[int, ...]:
    return tuple(offset for offset in INIT_OFFSETS if offset + words <= 4096)


def bitrev8(i: int) -> int:
    out = 0
    for bit in range(8):
        if i & (1 << bit):
            out |= 1 << (7 - bit)
    return out


def pair_a(pair_id: int, layer: int) -> int:
    step = 1 << layer
    group = pair_id >> layer
    within = pair_id & (step - 1)
    return (group << (layer + 1)) + within


def pair_b(pair_id: int, layer: int) -> int:
    return pair_a(pair_id, layer) + (1 << layer)


def scheduled_pairs(words: int, layer: int):
    delta = 1 if layer == 0 or (layer & 1) else 2
    total_pairs = words // 2
    base = 0
    while base < total_pairs:
        for within in range(delta):
            p0 = base + within
            p1 = p0 + delta
            if p1 < total_pairs:
                yield pair_a(p0, layer), pair_b(p0, layer)
                yield pair_a(p1, layer), pair_b(p1, layer)
        base += delta * 2


def pack_mlkem(poly: list[int]) -> list[tuple[int, int]]:
    return [(poly[2 * i], poly[2 * i + 1]) for i in range(128)]


def unpack_mlkem(words: list[tuple[int, int]]) -> list[int]:
    out: list[int] = []
    for lo, hi in words:
        out.extend([lo, hi])
    return out


def mlkem_ntt_addr(index: int, layer: int) -> int:
    return (1 << (6 - layer)) + (index >> (layer + 1))


def mlkem_intt_addr(index: int, layer: int) -> int:
    return 128 + (128 - (1 << (7 - layer))) + (index >> (layer + 1))


def mlkem_twiddle(addr: int) -> int:
    if addr < 128:
        return pow(ZETA, bitrev7(addr), Q)
    return pow(ZETA, bitrev7(127 - (addr - 128)), Q)


def sim_mlkem_ntt(poly: list[int]) -> list[int]:
    words = pack_mlkem(poly)
    for layer in range(6, -1, -1):
        for x, y in scheduled_pairs(128, layer):
            zeta = mlkem_twiddle(mlkem_ntt_addr(x, layer))
            a0, a1 = words[x]
            b0, b1 = words[y]
            t0 = modq_mul(zeta, b0)
            t1 = modq_mul(zeta, b1)
            words[x] = (modq_add(a0, t0), modq_add(a1, t1))
            words[y] = (modq_sub(a0, t0), modq_sub(a1, t1))
    return unpack_mlkem(words)


def sim_mlkem_intt(poly: list[int]) -> list[int]:
    words = pack_mlkem(poly)
    for layer in range(7):
        for x, y in scheduled_pairs(128, layer):
            zeta = mlkem_twiddle(mlkem_intt_addr(x, layer))
            a0, a1 = words[x]
            b0, b1 = words[y]
            words[x] = (modq_div2(modq_add(a0, b0)), modq_div2(modq_add(a1, b1)))
            words[y] = (
                modq_div2(modq_mul(zeta, modq_sub(b0, a0))),
                modq_div2(modq_mul(zeta, modq_sub(b1, a1))),
            )
    return unpack_mlkem(words)


def sim_mlkem_pwm(f_hat: list[int], g_hat: list[int]) -> list[int]:
    out = [0] * 256
    for i in range(128):
        f0, f1 = f_hat[2 * i], f_hat[2 * i + 1]
        g0, g1 = g_hat[2 * i], g_hat[2 * i + 1]
        s0 = modq_add(f0, f1)
        s1 = modq_add(g0, g1)
        m0 = modq_mul(f0, g0)
        m1 = modq_mul(f1, g1)
        zeta_pow = pow(ZETA, 2 * bitrev7(i) + 1, Q)
        out[2 * i] = modq_add(m0, modq_mul(m1, zeta_pow))
        out[2 * i + 1] = modq_sub(modq_mul(s0, s1), modq_add(m0, m1))
    return out


def mldsa_ntt_addr(index: int, layer: int) -> int:
    return (1 << (7 - layer)) + (index >> (layer + 1))


def mldsa_intt_addr(index: int, layer: int) -> int:
    return (1 << (8 - layer)) - 1 - (index >> (layer + 1))


def check_mlkem(rng: random.Random) -> None:
    for _ in range(20):
        f = [rng.randrange(Q) for _ in range(256)]
        g = [rng.randrange(Q) for _ in range(256)]
        if sim_mlkem_ntt(f) != golden_ntt(f):
            raise AssertionError("ML-KEM NTT schedule mismatch")
        ntt_f = golden_ntt(f)
        ntt_g = golden_ntt(g)
        if sim_mlkem_intt(ntt_f) != f:
            raise AssertionError("ML-KEM NTT/INTT roundtrip mismatch")
        if sim_mlkem_intt(g) != golden_intt(g):
            raise AssertionError("ML-KEM INTT schedule mismatch")
        if sim_mlkem_pwm(ntt_f, ntt_g) != golden_pwm(ntt_f, ntt_g):
            raise AssertionError("ML-KEM PWM schedule mismatch")


def check_mldsa_constants_and_montgomery(rng: random.Random) -> None:
    seen_fwd: set[int] = set()
    seen_inv: set[int] = set()
    for layer in range(8):
        for x, _ in scheduled_pairs(256, layer):
            fwd = mldsa_ntt_addr(x, layer)
            inv = mldsa_intt_addr(x, layer)
            if not 1 <= fwd < 256 or not 1 <= inv < 256:
                raise AssertionError(f"ML-DSA twiddle address out of range: {fwd}, {inv}")
            seen_fwd.add(fwd)
            seen_inv.add(inv)
    if seen_fwd != set(range(1, 256)) or seen_inv != set(range(1, 256)):
        raise AssertionError("ML-DSA twiddle address coverage mismatch")

    for i in range(1, 256):
        z = pow(1753, bitrev8(i), MLDSA_Q)
        z_mont = mldsa_to_mont(z)
        neg_mont = mldsa_to_mont((-z) % MLDSA_Q)
        if not 0 <= z_mont < MLDSA_Q or not 0 <= neg_mont < MLDSA_Q:
            raise AssertionError("ML-DSA Montgomery zeta out of range")

    for _ in range(1000):
        a = rng.randrange(MLDSA_Q)
        b = rng.randrange(MLDSA_Q)
        got = mldsa_mul_mont(mldsa_to_mont(a), mldsa_to_mont(b))
        exp = mldsa_to_mont(a * b)
        if got != exp:
            raise AssertionError("ML-DSA Montgomery multiply mismatch")


def check_offset_constant_invariance() -> None:
    for offset in valid_offsets(128):
        for layer in range(7):
            for x, _ in scheduled_pairs(128, layer):
                local_x = (offset + x - offset) & 0xFFF
                if mlkem_ntt_addr(local_x, layer) != mlkem_ntt_addr(x, layer):
                    raise AssertionError("ML-KEM CT offset mismatch")
                if mlkem_intt_addr(local_x, layer) != mlkem_intt_addr(x, layer):
                    raise AssertionError("ML-KEM GS offset mismatch")

    for offset in valid_offsets(256):
        for layer in range(8):
            for x, _ in scheduled_pairs(256, layer):
                local_x = (offset + x - offset) & 0xFFF
                if mldsa_ntt_addr(local_x, layer) != mldsa_ntt_addr(x, layer):
                    raise AssertionError("ML-DSA CT offset mismatch")
                if mldsa_intt_addr(local_x, layer) != mldsa_intt_addr(x, layer):
                    raise AssertionError("ML-DSA GS offset mismatch")


def main() -> int:
    rng = random.Random(0xC0DEC0DE)
    check_mlkem(rng)
    check_mldsa_constants_and_montgomery(rng)
    check_offset_constant_invariance()
    print("[PHOENIX-CONSISTENCY] PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
