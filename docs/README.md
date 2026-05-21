# PHOENIX SCA 문서 안내

작성일: 2026-05-21 KST

현재 working tree의 active RTL은 commit `5c0a201`의 논문 후보
**COMP3 internal Stage 2: DSA Karatsuba-only PRD in ML-KEM mode** 위에
**ML-KEM + ML-DSA first-order arithmetic masking**을 올린 실험 상태다.

즉 이전 논문 후보의 COMP1/2/4 zero blanking과 COMP3 inactive DSA Karatsuba PRD는
유지하고, 그 위에 ML-KEM/ML-DSA share memory, random tape memory, share-wise SBU
arithmetic, PWM masked multiplication을 추가했다. 이전 논문 후보 단독 RTL의 설명은
`docs/experiments/stage2_dsa_mul_only_prd.md`에 보존한다.

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
   - COMP3 Stage 2가 올라간 이전 datapath blanking 기준점이 어떤 zero/PRD를 포함하는지.
6. `docs/experiments/datapath_blanking/07_next_experiments.md`
   - Stage 6b 결과 이후 Solinas-style reduction과 COMP1/2/3/4 public dummy 후속 계획.
7. `docs/experiments/inactive_dummy_matrix/README.md`
   - Stage 4b 복구 후 실행한 inactive calculation dummy matrix 실험 원장.
8. `docs/experiments/stage2_dsa_mul_only_prd.md`
   - 이전 논문 후보 RTL에 해당하는 COMP3 internal Stage 2 최종 보고서.
9. `docs/experiments/comp3_internal_dummy_matrix/README.md`
   - COMP3 내부 multiplier/reducer sub-cone dummy matrix 실험 원장.
10. `docs/experiments/comp2_internal_dummy_matrix/README.md`
   - COMP2 내부 KEM/DSA cone dummy matrix와 Stage 6c 조합 후보. 현재 RTL에는 적용하지 않는다.
11. `docs/experiments/arithmetic_masking/README.md`
   - 현재 active RTL인 ML-KEM/ML-DSA arithmetic masking 실험 기록. 1000/1000
     fixed-vs-random TVLA에서 여섯 operation이 모두 threshold 아래로 내려갔다.

## 폴더 구조

| 경로 | 내용 |
|---|---|
| `docs/handover/` | 인수인계, 재구조화, 실행 계획 문서 |
| `docs/experiments/datapath_blanking/` | TVLA datapath blanking 실험 분석 |
| `docs/experiments/stage2_dsa_mul_only_prd.md` | 현재 논문 후보 RTL 최종 보고서 |
| `docs/experiments/arithmetic_masking/` | 현재 active RTL인 ML-KEM/ML-DSA arithmetic masking 실험 |
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
- COMP2 internal dummy matrix의 Stage 6c는 worst를 더 낮췄지만 `mlkem_intt` 악화가 남아 final RTL로 쓰지 않는다.
- 이전 논문 후보 RTL은 COMP3 internal Stage 2다. Original baseline 대비 six-op max `|t|`가 모두 낮아졌고, 2026-05-21 11:15:47 KST에 CW305 30ns bitstream을 재생성했다.
- 현재 working tree는 그 후보 위에 ML-KEM/ML-DSA arithmetic masking을 추가한 실험
  RTL이다. 기능/Verilator/CW305 30ns timing은 통과했고, bitstream은 2026-05-21
  13:28:47 KST에 재생성했다. 1000/1000 TVLA에서 `mlkem_ntt=2.904`,
  `mlkem_intt=3.451`, `mlkem_pwm=3.147`, `mldsa_ntt=3.435`, `mldsa_intt=4.053`,
  `mldsa_pwm=2.969`로 여섯 operation이 모두 threshold 4.5 아래다. 사용자 요청에
  따라 이 AM4 결과의 seed repeat는 아직 수행하지 않았으므로, 현재 표현은
  "single shuffled 1000/1000 full six-op pass 후보"가 가장 정직하다.

## 문서 업데이트 규칙

- 새 RTL 실험은 먼저 `docs/experiments/datapath_blanking/` 아래 Stage 문서에 기록한다.
- raw detail이 매우 길어지면 `docs/archive/`에 full ledger를 보존하고 Stage 문서에는 복구 가능한 요약을 남긴다.
- rejected 실험도 지우지 않는다. 부채널 실험에서는 악화 원인이 다음 실험의 단서가 된다.
