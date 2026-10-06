# IMPROVEMENTS — cico (`main.sh`)

공통 사항은 [IMPROVEMENTS_COMMON_KR.md](IMPROVEMENTS_COMMON_KR.md)에 있습니다.

## 1. 테스트 내용

| 항목 | legacy (`1_cico_sp`) | 현재 (`suites/cico`) |
|---|---|---|
| control | 화살표 형식 한 줄 | 같은 내용을 블록 형식으로. 단계 이름 체계는 legacy 그대로 |
| list | 144줄 (`list`), 전체 256줄은 `list_Original_AllTestcases_256` | 256줄: 1~144번 = legacy `list` 순서, 145~256번 = Fast 계열 112줄 |
| template, validate, Flat/Hierarchical 목록 | — | legacy와 같은 파일 |
| replay | — | 1~144번이 legacy 생성기 출력과 바이트 단위로 같음 |

이전 prod는 control의 단계 이름 체계가 list와 달라 256개 중 235개 replay에 매핑 누락이 있었습니다. 이를 legacy control로 되돌렸고,
생성기의 매핑 누락 검사(exit 3)가 재발을 막습니다. 테스트 번호와 결과의 `Row_<번호>` 이름도 1~144번은 legacy와 같습니다.
dev 사이트의 기본 실행(`MAX_CASES=144`)은 정확히 legacy 케이스이고, prod(256)와 `-c 145-256`은 Fast 계열까지 돕니다.

## 2. 실행

| 항목 | legacy | 현재 |
|---|---|---|
| 실행 방식 | 순차, 실행 하나에 프로젝트 이름 하나를 테스트마다 재생성 | 병렬(`-j`), 테스트마다 고유 프로젝트·워크스페이스 |
| Virtuoso | `virtuoso -replay` | `run_vse` (`vse_run -v VSE_VERSION -nograph`, 또는 `VSE_MODE=sub`) |
| 도우미 파일 | `cdsLibMgr.il`, `.cdsenv`를 복사 | 사이트 `CDS_LIB_MGR`과 func `.cdsenv`를 링크 |
| 실패 처리 | `|| true`로 계속, 결과는 항상 성공 | init/링크 실패 시 그 테스트를 멈추고 실패로 집계. summary와 teardown은 계속 |
| CDS 로그 누락 | — | Virtuoso 로그가 없는 테스트를 경고 |
| 옵션 | `-m -c -ws -proj -lib -cell -debug` | 같음 + `-j`, `-d`, `-k`(teardown 생략), `-t`(호환용). 값·범위 검사 |

## 3. 정리

| 항목 | legacy | 현재 |
|---|---|---|
| teardown | 테스트마다 끝나고 바로(순차, 실패 무시) | 백그라운드 worker가 끝나는 대로 정리, 실패는 `.failed`에 기록하고 종료 코드에 반영 |
| 산출물 삭제 | 항상(`-debug`면 유지) | teardown이 모두 성공했을 때만(`-debug`면 유지). 실패하면 `teardown_all.sh <dir>`로 재시도할 수 있게 남김 |
| 수동 정리 | `ICM_deleteProj.sh -prefix` | `teardown_all.sh <dir>` (실행 단위), `teardown_all.sh -p <prefix> [-y]` (이름 단위, 후보 확인 후 삭제) |
| 중단 안내 | init이 정리 명령 출력 | 같음(`CAT_*` 접두어와 dry-run 단계까지 포함한 명령) |

## 4. 결과

`summary.sh`는 legacy 판정(결과 파일에 `FAIL`이 있으면 FAIL)과 `summary.txt` 형식을 유지합니다. 결과는 `result/<id>/`에 남고
`clean.sh`가 지우지 않습니다.
