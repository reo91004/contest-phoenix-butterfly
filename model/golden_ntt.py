"""
ML-KEM incomplete NTT reference (n=256, q=3329).

Standard primitive 256-th root of unity zeta = 17 (NIST FIPS 203).
The NTT uses bit-reversed indexing via BitRev7.

This file is for testbench correctness checks only - the PHOENIX RTL
operates on coefficient pairs through the SBU rather than running the
whole transform in hardware.
"""
from golden_arithmetic import Q, modq_add, modq_sub, modq_mul

ZETA = 17
N = 256


def bitrev7(i: int) -> int:
    r = 0
    for k in range(7):
        if i & (1 << k):
            r |= 1 << (6 - k)
    return r


_ZETAS = None


def zetas():
    global _ZETAS
    if _ZETAS is None:
        _ZETAS = [pow(ZETA, bitrev7(i), Q) for i in range(128)]
    return _ZETAS


def ntt(f):
    """Forward incomplete NTT (Cooley-Tukey, in-order output, bit-reversed twiddles)."""
    z = zetas()
    f = list(f)
    k = 1
    length = 128
    while length >= 2:
        for start in range(0, N, 2 * length):
            zeta_k = z[k]
            k += 1
            for j in range(start, start + length):
                t = modq_mul(zeta_k, f[j + length])
                f[j + length] = modq_sub(f[j], t)
                f[j] = modq_add(f[j], t)
        length >>= 1
    return f


def intt(f):
    """Inverse incomplete NTT (Gentleman-Sande)."""
    z = zetas()
    f = list(f)
    k = 127
    length = 2
    while length <= 128:
        for start in range(0, N, 2 * length):
            zeta_k = z[k]
            k -= 1
            for j in range(start, start + length):
                t = f[j]
                f[j] = modq_add(t, f[j + length])
                f[j + length] = modq_mul(zeta_k, modq_sub(f[j + length], t))
        length <<= 1
    inv128 = pow(128, Q - 2, Q)
    return [modq_mul(x, inv128) for x in f]


def base_mul(a0, a1, b0, b1, zeta_pow):
    """
    NTT-domain base multiplication mod (X^2 - zeta_pow):
        h0 = a0*b0 + zeta_pow * a1*b1
        h1 = a0*b1 + a1*b0
    """
    h0 = modq_add(modq_mul(a0, b0), modq_mul(zeta_pow, modq_mul(a1, b1)))
    h1 = modq_add(modq_mul(a0, b1), modq_mul(a1, b0))
    return h0, h1


def pwm(f_hat, g_hat):
    """
    NTT-domain pointwise multiplication. For each of the 128 quadratic
    factors X^2 - zeta^(2*BitRev7(i)+1), compute the base product mod
    that quadratic.
    """
    h = [0] * N
    for i in range(128):
        zp = pow(ZETA, 2 * bitrev7(i) + 1, Q)
        h0, h1 = base_mul(f_hat[2*i], f_hat[2*i+1],
                          g_hat[2*i], g_hat[2*i+1], zp)
        h[2*i] = h0
        h[2*i+1] = h1
    return h


def poly_mul(f, g):
    """Full polynomial multiplication via NTT(f)*NTT(g) -> INTT."""
    return intt(pwm(ntt(f), ntt(g)))
