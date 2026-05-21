# Datapath Blanking Experiment

이 파일은 예전 긴 raw ledger의 redirect 문서다.

- 새 Stage 단위 문서 위치: `docs/experiments/datapath_blanking/README.md`
- inactive dummy matrix 결과: `docs/experiments/inactive_dummy_matrix/README.md`
- COMP3 internal dummy matrix 결과: `docs/experiments/comp3_internal_dummy_matrix/README.md`
- COMP2 internal dummy matrix: `docs/experiments/comp2_internal_dummy_matrix/README.md`
- 원본 full ledger 보존본: `docs/archive/260521_datapath_blanking_experiment_full_ledger.md`

현재 working tree의 active RTL은 COMP3 internal Stage 2 `DSA Karatsuba-only PRD in
ML-KEM mode` 논문 후보다.

- 적용 내용: COMP1/2/4 unused input zero blanking 유지.
- 추가 적용: ML-KEM mode에서 COMP3 내부 inactive DSA Karatsuba 입력에 public PRD.
- 추가 적용: 같은 ML-KEM mode에서 inactive DSA Montgomery reducer 입력은 `0`.
- 적용하지 않음: COMP2 internal Stage 4 `KEM cone PRD in ML-DSA mode`.
- 현재 RTL 상세: `docs/experiments/stage2_dsa_mul_only_prd.md`
