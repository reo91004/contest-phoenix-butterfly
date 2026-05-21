#!/usr/bin/env python3
"""CW305 register helper for the ML-KEM / ML-DSA PHOENIX wrapper."""

from __future__ import annotations

import time
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

import chipwhisperer as cw


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BITFILE = REPO_ROOT / "boards" / "cw305" / "output" / "phoenix_cw305.bit"
DEFAULT_DEFINES = REPO_ROOT / "boards" / "cw305" / "cw305_aes_defines.v"

TARGET_SN = "50203220535035313230303139313033"
SCOPE_SN = "50203220573555303230353232313036"

MAGIC = 0x50485831  # "PHX1"

OP_FWD = 0b0100
OP_INV = 0b0001
OP_PWM = 0b0010


def make_instr(*, scheme: int, op: int, mem_down: int = 0, offset: int = 0) -> int:
    """Build the current 9-bit PHOENIX instruction word."""

    if not 0 <= scheme <= 1:
        raise ValueError(f"scheme out of range: {scheme}")
    if not 0 <= op < 16:
        raise ValueError(f"opcode out of range: {op}")
    if not 0 <= mem_down <= 1:
        raise ValueError(f"mem_down out of range: {mem_down}")
    if not 0 <= offset < 4:
        raise ValueError(f"offset out of range: {offset}")
    return (scheme << 7) | (mem_down << 6) | (op << 2) | offset


INSTR = {
    "mlkem_ntt": make_instr(scheme=0, op=OP_FWD),
    "mlkem_intt": make_instr(scheme=0, op=OP_INV),
    "mlkem_pwm": make_instr(scheme=0, op=OP_PWM),
    "mldsa_ntt": make_instr(scheme=1, op=OP_FWD),
    "mldsa_intt": make_instr(scheme=1, op=OP_INV),
    "mldsa_pwm": make_instr(scheme=1, op=OP_PWM),
    # Backward-compatible aliases for the old ML-KEM-only labels.
    "ntt": make_instr(scheme=0, op=OP_FWD),
    "intt": make_instr(scheme=0, op=OP_INV),
    "pwm": make_instr(scheme=0, op=OP_PWM),
}


@dataclass(frozen=True)
class Status:
    magic: int
    field1: int
    field2: int
    field3: int
    raw: bytes

    @property
    def ok(self) -> bool:
        return self.magic == MAGIC and (self.field1 & 0xFFFF0000) != 0xFFFF0000


def make_key(
    *,
    start: bool = False,
    instr: int = 0,
    slot: int = 0,
    addr: int = 0,
    bulk: bool = False,
    read: bool = False,
) -> bytearray:
    """Build the 128-bit little-endian REG_CRYPT_KEY command word."""

    if not 0 <= instr < 512:
        raise ValueError(f"instr out of range: {instr}")
    if not 0 <= slot < 16:
        raise ValueError(f"slot out of range: {slot}")
    if not 0 <= addr < 1024:
        raise ValueError(f"addr out of range: {addr}")

    value = addr & 0x3FF
    if start:
        value |= 1 << 127
        value |= (instr & 0x1FF) << 118
    else:
        value |= (slot & 0xF) << 123
        if bulk:
            value |= 1 << 122
        if read:
            value |= 1 << 121
    return bytearray(value.to_bytes(16, "little"))


def words_to_payload(words: Sequence[int]) -> bytearray:
    payload = bytearray(16)
    for i, word in enumerate(words[:4]):
        payload[i * 4 : i * 4 + 4] = (int(word) & 0xFFFFFFFF).to_bytes(4, "little")
    return payload


def parse_status(raw: Iterable[int]) -> Status:
    data = bytes(raw)
    if len(data) != 16:
        raise ValueError(f"status length must be 16, got {len(data)}")
    value = int.from_bytes(data, "little")
    return Status(
        magic=(value >> 96) & 0xFFFFFFFF,
        field1=(value >> 64) & 0xFFFFFFFF,
        field2=(value >> 32) & 0xFFFFFFFF,
        field3=value & 0xFFFFFFFF,
        raw=data,
    )


def connect_target(
    *,
    bitfile: Path = DEFAULT_BITFILE,
    defines: Path = DEFAULT_DEFINES,
    sn: str = TARGET_SN,
    force: bool = True,
    pll_freq_hz: float = 33.333e6,
):
    target = cw.target(
        None,
        cw.targets.CW305,
        bsfile=str(bitfile),
        defines_files=[str(defines)],
        force=force,
        sn=sn,
    )
    target.clkusbautooff = False
    target.toggle_user_led = False
    target.vccint_set(1.0)
    target.pll.pll_enable_set(True)
    target.pll.pll_outenable_set(False, 0)
    target.pll.pll_outenable_set(True, 1)
    target.pll.pll_outenable_set(False, 2)
    target.pll.pll_outfreq_set(pll_freq_hz, 1)
    # 0x09 selects PLL1 as crypto clock and drives tio_clkout for the scope.
    target.fpga_write(target.REG_CLKSETTINGS, [0x09])
    return target


class PhoenixCW305:
    def __init__(self, target):
        self.target = target

    def _write_command(self, key: bytearray, payload: bytearray) -> None:
        self.target.fpga_write(self.target.REG_CRYPT_KEY, key)
        self.target.fpga_write(self.target.REG_CRYPT_TEXTIN, payload)

    def pulse_go(self) -> None:
        self.target.fpga_write(self.target.REG_CRYPT_GO, [1])

    def wait_done(self, timeout_s: float = 2.0) -> None:
        deadline = time.monotonic() + timeout_s
        time.sleep(0.001)
        while not self.target.is_done():
            if time.monotonic() > deadline:
                raise TimeoutError("PHOENIX command did not complete")
            time.sleep(0.001)

    def read_status(self) -> Status:
        return parse_status(self.target.fpga_read(self.target.REG_CRYPT_CIPHEROUT, 16))

    def issue(self, key: bytearray, payload: bytearray, timeout_s: float = 2.0) -> Status:
        self._write_command(key, payload)
        self.pulse_go()
        self.wait_done(timeout_s)
        return self.read_status()

    def issue_no_status(self, key: bytearray, payload: bytearray) -> None:
        self._write_command(key, payload)
        self.pulse_go()

    def write_word(self, slot: int, addr: int, word: int) -> Status:
        return self.issue(make_key(slot=slot, addr=addr), words_to_payload([word]))

    def read_word(self, slot: int, addr: int) -> int:
        status = self.issue(make_key(slot=slot, addr=addr, read=True), bytearray(16))
        if status.magic != MAGIC:
            raise RuntimeError(f"bad status magic: 0x{status.magic:08x}")
        return status.field3

    def bulk_write_words(self, slot: int, base_addr: int, words: Sequence[int]) -> Status:
        if len(words) > 4:
            raise ValueError("bulk write accepts at most four words")
        return self.issue(make_key(slot=slot, addr=base_addr, bulk=True), words_to_payload(words))

    def load_slot_words(self, slot: int, words: Sequence[int]) -> None:
        for base in range(0, len(words), 4):
            self.issue_no_status(
                make_key(slot=slot, addr=base, bulk=True),
                words_to_payload(words[base : base + 4]),
            )
        self.wait_done(timeout_s=0.1)
        status = self.read_status()
        if not status.ok:
            raise RuntimeError(f"bulk slot load failed: {status}")

    def prepare_start(self, instr: int) -> None:
        self._write_command(make_key(start=True, instr=instr), bytearray(16))

    def start_and_wait(self, instr: int, timeout_s: float = 5.0) -> Status:
        self.prepare_start(instr)
        self.pulse_go()
        self.wait_done(timeout_s)
        return self.read_status()
