"""golden_kyber_arith.py — ML-KEM (q=3329) 산술 golden (핸드오버 §13.1).

RTL rtl/arith/kyber_* 및 reduce/comp/sbu 검증의 단일 정답 출처.
값 계약: 0 <= a,b < Q.
"""

Q = 3329
Q_HALF = 1665  # (Q+1)//2


def addq(a, b):
    return (a + b) % Q


def subq(a, b):
    return (a - b) % Q


def div2q(x):
    # modular division-by-2: 홀수면 (Q+1)/2 를 더한다 (단순 shift 아님)
    return ((x >> 1) + (Q_HALF if (x & 1) else 0)) % Q


def mulq(a, b):
    return (a * b) % Q
