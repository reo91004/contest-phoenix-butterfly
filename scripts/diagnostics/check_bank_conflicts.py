#!/usr/bin/env python3
"""Check coefficient scheduler bank conflicts.

This mirrors rtl/coefficient_index.v and rtl/bank_decoder.v:
  - FFT-like scheduler emits two butterfly pairs per cycle
  - pointwise scheduler emits one ML-KEM PWM index or two ML-DSA PWM indexes
  - b=4 digit-sum bank decoder must avoid same-side bank conflicts

The script is intentionally dependency-free so it can be run before Vivado.
"""

from __future__ import annotations


CASES = (
    ("mlkem_128_words", 128),
    ("mldsa_256_words", 256),
)

WB_LAT = 9
INIT_OFFSETS = (0, 1024, 2048, 3072)


def valid_offsets(poly_words: int) -> tuple[int, ...]:
    return tuple(offset for offset in INIT_OFFSETS if offset + poly_words <= 4096)


def bank(index: int) -> int:
    """MRW+22 b=4 digit-sum bank decoder."""

    total = 0
    while index:
        total += index & 0x3
        index >>= 2
    return total & 0x3


def pair_a(pair_id: int, layer: int) -> int:
    step = 1 << layer
    group = pair_id >> layer
    within = pair_id & (step - 1)
    return (group << (layer + 1)) + within


def pair_b(pair_id: int, layer: int) -> int:
    return pair_a(pair_id, layer) + (1 << layer)


def pair_delta(layer: int) -> int:
    return 1 if layer == 0 or (layer & 1) else 2


def ntt_ct_addr(index: int, layer: int) -> int:
    group_id = index >> (layer + 1)
    return (1 << (6 - layer)) + group_id


def ntt_gs_addr(index: int, layer: int) -> int:
    group_id = index >> (layer + 1)
    return 128 + (128 - (1 << (7 - layer))) + group_id


def ntt_rom_zeta_index(addr: int) -> int:
    if addr < 128:
        return addr
    return 127 - (addr - 128)


def emitted_cycles(poly_words: int, layer: int) -> list[tuple[int, int]]:
    total_pairs = poly_words // 2
    delta = pair_delta(layer)
    cycles: list[tuple[int, int]] = []
    pair_base = 0

    while True:
        for pair_within in range(delta):
            first = pair_base + pair_within
            second = pair_base + pair_within + delta
            if second < total_pairs:
                cycles.append((first, second))

        if pair_base + (delta << 1) >= total_pairs:
            break
        pair_base += delta << 1

    return cycles


def check_case(name: str, poly_words: int) -> int:
    failures = 0
    expected_cycles_per_layer = poly_words // 4

    for layer in range(poly_words.bit_length() - 1):
        cycles = emitted_cycles(poly_words, layer)
        if len(cycles) != expected_cycles_per_layer:
            print(
                f"[FAIL] {name} layer={layer}: expected "
                f"{expected_cycles_per_layer} cycles, got {len(cycles)}"
            )
            failures += 1
            continue

        seen_pairs: set[int] = set()
        for cycle, (p0, p1) in enumerate(cycles):
            indexes = (
                pair_a(p0, layer),
                pair_b(p0, layer),
                pair_a(p1, layer),
                pair_b(p1, layer),
            )
            banks = tuple(bank(index) for index in indexes)
            if len(set(banks)) != 4:
                print(
                    f"[FAIL] {name} layer={layer} cycle={cycle}: "
                    f"pairs=({p0},{p1}) indexes={indexes} banks={banks}"
                )
                failures += 1
                break
            seen_pairs.update((p0, p1))

        total_pairs = poly_words // 2
        if len(seen_pairs) != total_pairs:
            missing = sorted(set(range(total_pairs)) - seen_pairs)[:8]
            print(
                f"[FAIL] {name} layer={layer}: emitted {len(seen_pairs)} "
                f"of {total_pairs} pairs, first_missing={missing}"
            )
            failures += 1

    if failures == 0:
        layers = poly_words.bit_length() - 1
        print(
            f"[OK] {name}: {layers} layers, "
            f"{expected_cycles_per_layer} cycles/layer, no bank conflicts, "
            "complete selected-side coverage"
        )
    return failures


def check_case_offsets(name: str, poly_words: int) -> int:
    failures = 0
    offsets = valid_offsets(poly_words)

    for offset in offsets:
        for layer in range(poly_words.bit_length() - 1):
            for cycle, (p0, p1) in enumerate(emitted_cycles(poly_words, layer)):
                indexes = (
                    offset + pair_a(p0, layer),
                    offset + pair_b(p0, layer),
                    offset + pair_a(p1, layer),
                    offset + pair_b(p1, layer),
                )
                banks = tuple(bank(index) for index in indexes)
                if len(set(banks)) != 4:
                    print(
                        f"[FAIL] {name} offset={offset} layer={layer} cycle={cycle}: "
                        f"pairs=({p0},{p1}) indexes={indexes} banks={banks}"
                    )
                    failures += 1
                    break

    if failures == 0:
        joined = ",".join(str(offset) for offset in offsets)
        print(f"[OK] {name}: valid offsets {{{joined}}} preserve bank conflicts")
    return failures


def check_pointwise(name: str, poly_words: int, single: bool) -> int:
    failures = 0
    step = 1 if single else 2
    cycles = 0
    seen: set[int] = set()

    for base in range(0, poly_words, step):
        indexes = (base,) if single else (base, base + 1)
        banks = tuple(bank(index) for index in indexes)
        if len(set(banks)) != len(banks):
            print(
                f"[FAIL] {name}: pointwise cycle={cycles} "
                f"indexes={indexes} banks={banks}"
            )
            failures += 1
            break
        seen.update(indexes)
        cycles += 1

    if len(seen) != poly_words:
        missing = sorted(set(range(poly_words)) - seen)[:8]
        print(
            f"[FAIL] {name}: pointwise emitted {len(seen)} of "
            f"{poly_words} indexes, first_missing={missing}"
        )
        failures += 1

    if failures == 0:
        mode = "single-SBU cascade" if single else "dual-SBU"
        print(f"[OK] {name}: pointwise {mode}, {cycles} cycles, no bank conflicts")
    return failures


def check_pointwise_offsets(name: str, poly_words: int, single: bool) -> int:
    failures = 0
    step = 1 if single else 2
    offsets = valid_offsets(poly_words)

    for offset in offsets:
        seen: set[int] = set()
        for base in range(0, poly_words, step):
            local_indexes = (base,) if single else (base, base + 1)
            indexes = tuple(offset + index for index in local_indexes)
            banks = tuple(bank(index) for index in indexes)
            if len(set(banks)) != len(banks):
                print(
                    f"[FAIL] {name}: pointwise offset={offset} "
                    f"indexes={indexes} banks={banks}"
                )
                failures += 1
                break
            seen.update(local_indexes)
        if len(seen) != poly_words:
            missing = sorted(set(range(poly_words)) - seen)[:8]
            print(
                f"[FAIL] {name}: pointwise offset={offset} emitted {len(seen)} of "
                f"{poly_words} local indexes, first_missing={missing}"
            )
            failures += 1

    if failures == 0:
        joined = ",".join(str(offset) for offset in offsets)
        print(f"[OK] {name}: pointwise valid offsets {{{joined}}} preserve bank conflicts")
    return failures


def check_inter_layer_hazards(name: str, poly_words: int, descending: bool = False) -> int:
    """Ensure the next layer never reads an index before prior write-back."""

    failures = 0
    layer_count = poly_words.bit_length() - 1
    order = list(range(layer_count - 1, -1, -1)) if descending else list(range(layer_count))

    for pos in range(len(order) - 1):
        layer = order[pos]
        next_layer = order[pos + 1]
        prev_cycles = emitted_cycles(poly_words, layer)
        next_cycles = emitted_cycles(poly_words, next_layer)
        prev_emit: dict[int, int] = {}
        next_emit: dict[int, int] = {}

        for cycle, (p0, p1) in enumerate(prev_cycles):
            for pair in (p0, p1):
                prev_emit[pair_a(pair, layer)] = cycle
                prev_emit[pair_b(pair, layer)] = cycle

        for cycle, (p0, p1) in enumerate(next_cycles):
            for pair in (p0, p1):
                next_emit[pair_a(pair, next_layer)] = cycle
                next_emit[pair_b(pair, next_layer)] = cycle

        layer_start = len(prev_cycles)
        for index, next_cycle in next_emit.items():
            prev_write_cycle = prev_emit[index] + WB_LAT
            next_read_cycle = layer_start + next_cycle
            if next_read_cycle <= prev_write_cycle:
                print(
                    f"[FAIL] {name}: layer {layer}->{next_layer} "
                    f"index={index} prev_write={prev_write_cycle} "
                    f"next_read={next_read_cycle}"
                )
                failures += 1
                break

    if failures == 0:
        direction = "descending" if descending else "ascending"
        print(f"[OK] {name}: {direction} inter-layer read/write hazards clear")
    return failures


def check_ntt_twiddles() -> int:
    failures = 0
    for layer in range(7):
        cycles = emitted_cycles(128, layer)
        ct_addr_seen: set[int] = set()
        gs_addr_seen: set[int] = set()
        ct_zeta_seen: set[int] = set()
        gs_zeta_seen: set[int] = set()
        for p0, p1 in cycles:
            for pair in (p0, p1):
                index = pair_a(pair, layer)
                ct_addr = ntt_ct_addr(index, layer)
                gs_addr = ntt_gs_addr(index, layer)
                ct_addr_seen.add(ct_addr)
                gs_addr_seen.add(gs_addr)
                ct_zeta_seen.add(ntt_rom_zeta_index(ct_addr))
                gs_zeta_seen.add(ntt_rom_zeta_index(gs_addr))
        expected_zeta = set(range(1 << (6 - layer), 1 << (7 - layer)))
        expected_gs_addr = set(
            range(
                128 + (128 - (1 << (7 - layer))),
                128 + (128 - (1 << (7 - layer))) + (1 << (6 - layer)),
            )
        )
        if ct_zeta_seen != expected_zeta or gs_zeta_seen != expected_zeta or gs_addr_seen != expected_gs_addr:
            print(
                f"[FAIL] mlkem twiddle layer={layer}: "
                f"ct_zeta={sorted(ct_zeta_seen)[:4]}.. "
                f"gs_zeta={sorted(gs_zeta_seen)[:4]}.. "
                f"gs_addr={sorted(gs_addr_seen)[:4]}.."
            )
            failures += 1
    if failures == 0:
        print("[OK] mlkem twiddle ROM addresses select CT and GS halves and cover zeta ranges 1..127")
    return failures


def mldsa_ntt_addr(index: int, layer: int) -> int:
    group_id = index >> (layer + 1)
    return (1 << (7 - layer)) + group_id


def mldsa_intt_addr(index: int, layer: int) -> int:
    group_id = index >> (layer + 1)
    return (1 << (8 - layer)) - 1 - group_id


def check_mldsa_twiddles() -> int:
    failures = 0
    for layer in range(8):
        cycles = emitted_cycles(256, layer)
        fwd_seen: set[int] = set()
        inv_seen: set[int] = set()
        for p0, p1 in cycles:
            for pair in (p0, p1):
                index = pair_a(pair, layer)
                fwd_seen.add(mldsa_ntt_addr(index, layer))
                inv_seen.add(mldsa_intt_addr(index, layer))
        expected_fwd = set(range(1 << (7 - layer), 1 << (8 - layer)))
        expected_inv = set(range(1 << (7 - layer), 1 << (8 - layer)))
        if fwd_seen != expected_fwd or inv_seen != expected_inv:
            print(
                f"[FAIL] mldsa twiddle layer={layer}: "
                f"fwd={sorted(fwd_seen)[:4]}.. inv={sorted(inv_seen)[:4]}.."
            )
            failures += 1
    if failures == 0:
        print("[OK] mldsa twiddle ROM addresses cover ranges 1..255")
    return failures


def main() -> int:
    failures = 0
    for name, poly_words in CASES:
        failures += check_case(name, poly_words)
        failures += check_case_offsets(name, poly_words)
        failures += check_inter_layer_hazards(name, poly_words, descending=False)
        failures += check_inter_layer_hazards(name, poly_words, descending=True)
    failures += check_ntt_twiddles()
    failures += check_mldsa_twiddles()
    failures += check_pointwise("mlkem_pwm_128_words", 128, single=True)
    failures += check_pointwise_offsets("mlkem_pwm_128_words", 128, single=True)
    failures += check_pointwise("mldsa_pwm_256_words", 256, single=False)
    failures += check_pointwise_offsets("mldsa_pwm_256_words", 256, single=False)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
