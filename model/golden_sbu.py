"""Per-mode SuperButterfly reference for the ML-KEM / ML-DSA refactor."""

from golden_arithmetic import (
    modq_add,
    modq_sub,
    modq_mul,
    modq_div2,
    mldsa_add,
    mldsa_sub,
    mldsa_div2,
    mldsa_mul_mont,
)


SBU_MODES = {
    0b010010011: "MLKEM_NTT_CT",
    0b011000100: "MLKEM_INTT_GS",
    0b000010100: "MLKEM_PWM0",
    0b000110000: "MLKEM_PWM1",
    0b000000000: "MLKEM_MOD_ADD",
    0b110010011: "MLDSA_NTT_CT",
    0b111000100: "MLDSA_INTT_GS",
    0b100010100: "MLDSA_PWM",
}

MODE_TO_SEL = {v: k for k, v in SBU_MODES.items()}


def mlkem_ntt_ct(a: int, b: int, omega: int) -> tuple[int, int]:
    t = modq_mul(omega, b)
    return modq_add(a, t), modq_sub(a, t)


def mlkem_intt_gs(a: int, b: int, omega: int) -> tuple[int, int]:
    s = modq_add(a, b)
    d = modq_sub(b, a)
    return modq_div2(s), modq_div2(modq_mul(omega, d))


def mlkem_pwm0(f0: int, f1: int, g0: int, g1: int) -> tuple[int, int, int, int]:
    return (
        modq_add(f0, f1),
        modq_add(g0, g1),
        modq_mul(f0, g0),
        modq_mul(f1, g1),
    )


def mlkem_pwm1(s0: int, s1: int, m0: int, m1: int, zeta_pow: int) -> tuple[int, int]:
    s2 = modq_add(m0, m1)
    m2 = modq_mul(s0, s1)
    m3 = modq_mul(m1, zeta_pow)
    return modq_add(m0, m3), modq_sub(m2, s2)


def mldsa_ntt_ct(a: int, b: int, zeta_mont: int) -> tuple[int, int]:
    t = mldsa_mul_mont(zeta_mont, b)
    return mldsa_add(a, t), mldsa_sub(a, t)


def mldsa_intt_gs(a: int, b: int, zeta_mont: int) -> tuple[int, int]:
    s = mldsa_add(a, b)
    d = mldsa_sub(b, a)
    return mldsa_div2(s), mldsa_div2(mldsa_mul_mont(zeta_mont, d))


def mldsa_pwm(a_mont: int, b_mont: int) -> int:
    return mldsa_mul_mont(a_mont, b_mont)
