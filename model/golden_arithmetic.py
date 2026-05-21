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


def pack_mlkem_word(lo: int, hi: int) -> int:
    return ((hi % KEM_Q) << 16) | (lo % KEM_Q)


def unpack_mlkem_word(word: int) -> tuple[int, int]:
    return int(word) & 0xFFFF, (int(word) >> 16) & 0xFFFF


def mlkem_split_word(word: int, mask_word: int) -> tuple[int, int]:
    lo, hi = unpack_mlkem_word(word)
    mlo, mhi = unpack_mlkem_word(mask_word)
    share0 = pack_mlkem_word((lo - mlo) % KEM_Q, (hi - mhi) % KEM_Q)
    share1 = pack_mlkem_word(mlo, mhi)
    return share0, share1


def mlkem_recombine_word(share0: int, share1: int) -> int:
    lo0, hi0 = unpack_mlkem_word(share0)
    lo1, hi1 = unpack_mlkem_word(share1)
    return pack_mlkem_word((lo0 + lo1) % KEM_Q, (hi0 + hi1) % KEM_Q)


def mldsa_split_word(word: int, mask_word: int) -> tuple[int, int]:
    share1 = mask_word % MLDSA_Q
    share0 = (word - share1) % MLDSA_Q
    return share0, share1


def mldsa_recombine_word(share0: int, share1: int) -> int:
    return (share0 + share1) % MLDSA_Q


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
