# PHOENIX SCA 문서 안내

작성일: 2026-05-21 KST

현재 working tree의 active RTL은 **Stage 6c candidate**다. 즉 Stage 4b restored RTL 위에
COMP3 internal Stage 2와 COMP2 internal Stage 4 PRD dummy를 조합한 상태다.
Stage 4b restored RTL로 되돌리려면 RTL/testbench 변경을 `git restore`로 제거하면 된다.

## 읽는 순서

1. `docs/implementation/260519_migration_log.md`
   - 원 PHOENIX 복사본을 ML-KEM / ML-DSA RTL로 바꾼 구현 로그.
2. `docs/reference/260519_phoenix_paper_analysis.md`
   - 원 PHOENIX 구조 중 무엇을 유지했고 무엇을 버렸는지에 대한 배경.
3. `docs/handover/260520_181617_sca.md`
   - Stage 5 실행 전 handover 계획.
4. `docs/experiments/datapath_blanking/README.md`
   - datapath blanking TVLA 실험의 현재 결론과 Stage별 링크.
5. `docs/experiments/datapath_blanking/04_stage4.md`
   - Stage 6c의 기준점인 Stage 4b가 정확히 어떤 blanking을 포함하는지.
6. `docs/experiments/datapath_blanking/07_next_experiments.md`
   - Stage 6b 결과 이후 Solinas-style reduction과 COMP1/2/3/4 public dummy 후속 계획.
7. `docs/experiments/inactive_dummy_matrix/README.md`
   - Stage 4b 복구 후 실행한 inactive calculation dummy matrix 실험 원장.
8. `docs/experiments/comp3_internal_dummy_matrix/README.md`
   - COMP3 내부 multiplier/reducer sub-cone dummy matrix 실험 원장.
9. `docs/experiments/comp2_internal_dummy_matrix/README.md`
   - COMP2 내부 KEM/DSA cone dummy matrix와 현재 best-so-far Stage 6c 조합.

## 폴더 구조

| 경로 | 내용 |
|---|---|
| `docs/handover/` | 인수인계, 재구조화, 실행 계획 문서 |
| `docs/experiments/datapath_blanking/` | TVLA datapath blanking 실험 분석 |
| `docs/experiments/inactive_dummy_matrix/` | Stage 4b 기반 inactive COMP1/2/3/4 dummy matrix 실험 |
| `docs/experiments/comp3_internal_dummy_matrix/` | Stage 4b 기반 COMP3 내부 sub-cone dummy matrix 실험 |
| `docs/experiments/comp2_internal_dummy_matrix/` | Stage 4b 기반 COMP2 내부 KEM/DSA cone dummy matrix 실험 |
| `docs/implementation/` | RTL migration 및 구현 배경 |
| `docs/reference/` | 논문 분석과 원 PHOENIX PDF |
| `docs/archive/` | 흡수된 초안과 full raw ledger |

## 최종 결론

- Original baseline은 모든 operation에서 threshold `4.5`를 크게 넘었다.
- Stage 1-4b는 큰 구조를 바꾸지 않고 invalid/unused datapath leakage를 줄인 실험이다.
- Stage 1-6의 deterministic blanking 흐름에서 최종 선택 RTL은 Stage 4b였다.
- Stage 4b는 TVLA pass가 아니지만, baseline worst `144.055`를 `112.877`로 낮춘 가장 균형 잡힌 후보였다.
- Stage 6b는 ML-KEM을 크게 개선했지만 ML-DSA INTT/PWM을 악화시켜 informative but rejected로 보존한다.
- Stage 7 Solinas는 기능/timing은 통과했지만 TVLA worst를 악화시켜 rejected/informative로 보존한다.
- Stage 4b 기반 inactive calculation dummy matrix는 accepted 후보 없이 rejected/informative로 정리했다.
- COMP3 internal dummy matrix에서는 Stage 2 `DSA Karatsuba-only PRD`가 균형 잡힌 accepted 후보였고, Stage 9 zero counterpart는 `mldsa_intt`를 더 낮추지만 `mlkem_intt`/`mldsa_ntt`를 악화하는 trade-off로 보존한다.
- COMP2 internal dummy matrix의 현재 best-so-far는 Stage 6c다. Stage 4b control 대비 worst를 `122.083 -> 99.696`, repeat에서 `102.864`까지 낮췄지만 `mlkem_intt` 악화가 남아 final accepted보다는 candidate로 둔다.

## 문서 업데이트 규칙

- 새 RTL 실험은 먼저 `docs/experiments/datapath_blanking/` 아래 Stage 문서에 기록한다.
- raw detail이 매우 길어지면 `docs/archive/`에 full ledger를 보존하고 Stage 문서에는 복구 가능한 요약을 남긴다.
- rejected 실험도 지우지 않는다. 부채널 실험에서는 악화 원인이 다음 실험의 단서가 된다.
