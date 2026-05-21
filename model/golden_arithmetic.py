"""Golden arithmetic helpers for the ML-KEM / ML-DSA refactor."""

KEM_Q = 3329
KEM_Q_HALF = (KEM_Q + 1) // 2
Q = KEM_Q

MLDSA_Q = 8380417
MLDSA_QINV = 58728449
MLDSA_R = 1 << 32
MLDSA_R_MOD_Q = MLDSA_R % MLDSA_Q
MLDSA_Q_HALF = (MLDSA_Q + 1) // 2


def modq_add(a: int, b: int) -> int:
    return (a + b) % KEM_Q


def modq_sub(a: int, b: int) -> int:
    return (a - b) % KEM_Q


def modq_div2(a: int) -> int:
    return ((a >> 1) + (KEM_Q_HALF if (a & 1) else 0)) % KEM_Q


def modq_mul(a: int, b: int) -> int:
    return (a * b) % KEM_Q


def mldsa_add(a: int, b: int) -> int:
    return (a + b) % MLDSA_Q


def mldsa_sub(a: int, b: int) -> int:
    return (a - b) % MLDSA_Q


def mldsa_div2(a: int) -> int:
    return ((a >> 1) + (MLDSA_Q_HALF if (a & 1) else 0)) % MLDSA_Q


def mldsa_montgomery_reduce(t: int) -> int:
    """Return t * R^-1 mod MLDSA_Q for 0 <= t < q*2^32."""

    m = ((t & 0xFFFFFFFF) * MLDSA_QINV) & 0xFFFFFFFF
    u = (t - m * MLDSA_Q) >> 32
    if u >= MLDSA_Q:
        u -= MLDSA_Q
    if u < 0:
        u += MLDSA_Q
    return u


def mldsa_to_mont(a: int) -> int:
    return (a % MLDSA_Q) * MLDSA_R_MOD_Q % MLDSA_Q


def mldsa_mul_mont(a_mont: int, b_mont: int) -> int:
    return mldsa_montgomery_reduce(a_mont * b_mont)
