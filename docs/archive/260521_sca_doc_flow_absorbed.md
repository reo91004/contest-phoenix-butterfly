# SCA 문서 읽는 순서

작성일: 2026-05-21 KST

이 파일은 현재 SCA/TVLA 관련 문서를 어떤 순서로 읽으면 되는지 정리한 목차다.

## 지금 읽을 문서

1. `docs/migration_log.md`
   - 원 PHOENIX 복사본을 ML-KEM / ML-DSA RTL로 바꾼 과정의 factual log.

2. `docs/phoenix_paper_analysis.md`
   - 원 PHOENIX 구조 중 무엇을 유지했고 무엇을 버렸는지에 대한 배경.

3. `docs/Handover/260520_181617_sca.md`
   - Stage 5 실행 전 기준 계획. Stage 4b 이후 어떤 후보를 볼지 정한 handover.

4. `docs/datapath_blanking_experiment.md`
   - 모든 raw experiment ledger. 숫자, timing, branch별 accept/reject 근거는
     이 파일이 원본이다.

5. `docs/260521_stage4b_blanking_tvla_report.md`
   - baseline부터 Stage 4b, Stage 5, Stage 6 R2까지 이해 중심으로 정리한
     최종 설명 보고서.

6. `docs/260521_mldsa_solinas_random_dummy_followup.md`
   - R2 결과를 바탕으로 Solinas-style ML-DSA reducer와 COMP1/2/3/4 public
     dummy 실험을 어떻게 볼지 정리한 후속 계획.

## Archive로 보낸 문서

아래 문서들은 삭제하지 않고 `docs/archive/`에 보존했다.

| Archived path | 이유 |
|---|---|
| `docs/archive/260521_stage4b_blanking_tvla_report_draft.md` | 새 Stage 4b 보고서로 재작성된 초안 |
| `docs/archive/260519_mldsa_comp3_idea.md` | 후속 Solinas/random dummy 문서에 핵심 내용 흡수 |
| `docs/archive/260519_mlkem_mldsa_refactor_plan.md` | 초기 계획 문서. factual 내용은 migration log와 paper analysis에서 계속 추적 |

## 현재 RTL 기준

현재 active RTL 기준은 Stage 4b다.

- Stage 6 R2는 최종 RTL에 들어가 있지 않다.
- COMP3 inactive-cone PRD dummy도 현재 source에는 없다.
- R2는 ML-KEM 방향의 매우 중요한 후속 실험 힌트로만 보존한다.

## 문서 업데이트 규칙

- 새 RTL 실험을 하면 먼저 `docs/datapath_blanking_experiment.md`에 raw result를
  기록한다.
- 해석이 안정되면 별도 timestamp 문서로 요약한다.
- rejected 실험도 지우지 않는다. SCA 실험에서는 "나빠진 이유"가 다음 실험의
  가장 좋은 단서가 되는 경우가 많다.
