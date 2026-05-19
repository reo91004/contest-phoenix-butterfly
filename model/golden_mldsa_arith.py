"""ML-DSA arithmetic aliases for diagnostics."""

from golden_arithmetic import (
    MLDSA_Q,
    MLDSA_QINV,
    MLDSA_R_MOD_Q,
    mldsa_add,
    mldsa_sub,
    mldsa_div2,
    mldsa_montgomery_reduce,
    mldsa_to_mont,
    mldsa_mul_mont,
)

__all__ = [
    "MLDSA_Q",
    "MLDSA_QINV",
    "MLDSA_R_MOD_Q",
    "mldsa_add",
    "mldsa_sub",
    "mldsa_div2",
    "mldsa_montgomery_reduce",
    "mldsa_to_mont",
    "mldsa_mul_mont",
]
