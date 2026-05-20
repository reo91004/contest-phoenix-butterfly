# Datapath Blanking Experiment

이 파일은 예전 긴 raw ledger의 redirect 문서다.

- 새 Stage 단위 문서 위치: `docs/experiments/datapath_blanking/README.md`
- inactive dummy matrix 결과: `docs/experiments/inactive_dummy_matrix/README.md`
- COMP3 internal dummy matrix 결과: `docs/experiments/comp3_internal_dummy_matrix/README.md`
- COMP2 internal dummy matrix: `docs/experiments/comp2_internal_dummy_matrix/README.md`
- 원본 full ledger 보존본: `docs/archive/260521_datapath_blanking_experiment_full_ledger.md`

현재 working tree의 active RTL은 Stage 6c candidate다.

- 기준: Stage 4b restored RTL
- 추가 적용: COMP3 internal Stage 2 `DSA Karatsuba-only PRD`
- 추가 적용: COMP2 internal Stage 4 `KEM cone PRD in ML-DSA mode`
- 현재 best-so-far 결과: `docs/experiments/comp2_internal_dummy_matrix/stage6_combined_accepted.md`
- Stage 4b restored RTL로 복구하려면 RTL/testbench 변경을 `git restore`로 제거한다.
