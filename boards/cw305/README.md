# CW305 메모

이 디렉터리는 ML-KEM / ML-DSA 가속기를 위한 CW305 wrapper, register bridge,
constraint, Vivado project flow를 보관한다.

## Wrapper 프로토콜

`cw305_phoenix_top`은 표준 CW305 USB/register/clock shell을 유지하고,
`phoenix_cw305_wrapper`를 인스턴스화한다. 이 wrapper는 AES-style key/text
register protocol을 `phoenix_top`의 command 및 memory port로 변환한다.

시작 command:

```text
key_i[127]     = 1
key_i[126:118] = instr[8:0]
```

메모리 command:

```text
key_i[127]     = 0
key_i[126:123] = slot
key_i[122]     = bulk write, little-endian 32비트 word 네 개
key_i[121]     = read
key_i[9:0]     = word address
data_i         = payload
```

Slot mapping:

```text
slot 0..3 : memory-up bank 0..3
slot 4..7 : memory-down bank 0..3
```

ML-KEM은 32비트 워드마다 16비트 lane 두 개를 packing한다. ML-DSA는
32비트 워드마다 정규화된 계수 하나를 사용하므로, 256계수 polynomial 하나가
256 word를 차지한다.

## Vivado project

Project file은 다음 위치에 보존되어 있다.

```text
boards/cw305/vivado_project/phoenix_cw305.xpr
```

`.runs`, `.cache`, `.sim`, 생성 log, DCP, bitstream 같은 재생성 가능한
project 하위 산출물은 보관 대상이 아니다. Project를 다시 만들어야 하면:

```bash
cd boards/cw305
vivado -mode batch -source create_phoenix_project.tcl
vivado vivado_project/phoenix_cw305.xpr
```

### Vivado 2024.2로 맞출 때

`.xpr`는 Vivado product version, simulator version, project path를 포함한다.
2025.2에서 저장된 `.xpr`를 2024.2용으로 낮출 때는 XML을 직접 편집하지 말고
2024.2 Vivado에서 다시 생성한다.

```bash
cd boards/cw305
source <Vivado-2024.2>/Vivado/settings64.sh
vivado -mode batch -source create_phoenix_project.tcl
vivado vivado_project/phoenix_cw305.xpr
```

재생성 후에는 `.runs`, `.cache`, `.sim`, DCP, bitstream, report를 같은
Vivado 버전에서 새로 만든다. 현재 project flow는 IP/BD/XCI 없이 RTL만 읽기
때문에 2024.2로 옮길 때 별도 IP downgrade 단계는 필요하지 않다.

## Build script

```bash
cd boards/cw305
vivado -mode batch -source build_phoenix_bitstream.tcl
```

Bitstream closure는 이 리팩터의 1차 성공 기준이 아니다. 현재 구현 단계는 RTL
lint와 simulation으로 판단한다.
