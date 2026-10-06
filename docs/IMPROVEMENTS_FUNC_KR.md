# IMPROVEMENTS — func (`func_main.sh`)

공통 사항은 [IMPROVEMENTS_COMMON_KR.md](IMPROVEMENTS_COMMON_KR.md)에 있습니다.

## 1. 테스트 내용

| 항목 | legacy (`3_func_sp`) | 현재 (`suites/func`) |
|---|---|---|
| control | `code/control` | `code/func_control` — legacy와 바이트 단위로 같음 |
| list | `list_<mode>[_<prefix>]` 30종 | 같은 파일 (`list_changeRefLib*` 3개는 mode 목록에 없어 `archive/`) |
| 시나리오 | — | 30종 8221개의 시나리오 본문이 legacy 생성기 출력과 같음 |
| validate, sm_env, functions, .cdsenv | — | legacy와 같은 내용 |

이전 prod에서 `func_control`의 ICM Checkin 뒤 auto checkout/checkin 설정을 되돌리는 `cond(...)` 줄이 주석 처리돼 있었습니다.
legacy대로 되살렸습니다.

## 2. 판정

| 항목 | legacy | 이전 prod | 현재 |
|---|---|---|---|
| 판정 대상 | replay가 쓴 결과 파일 | Virtuoso 세션 로그 + 모드별 기대 행 수 상수(12/6/11/4/12) | replay가 쓴 결과 파일 (`result/<id>/test_<N>_<ver>.log`) |
| 규칙 | `End Time` 없음 → 섹션에 `Row_` 없음 → `FAIL` 토큰 | 행 수 비교(셀마다 행 수가 달라 오판) | legacy와 같은 순서·같은 문구 |
| 결과 파일이 아예 없는 테스트 | 빠짐 | — | FAIL로 집계 ("No result log") |

## 3. 실행

| 항목 | legacy | 현재 |
|---|---|---|
| 번호·날짜 전달 | `temp/CDS_PV_REG_NO_*`, `temp/func_date_*` 파일 | replay 생성 시 치환(`CDS_PV_REGGRESION_NO`, `CDS_PV_REG_RES_NO`). 병렬에서도 섞이지 않음 |
| 번호 자릿수 | list 줄 수의 자릿수 | 같음. 디렉터리·replay·CDS 로그·결과 파일이 모두 같은 자릿수 |
| 실행 | 순차, `virtuoso -replay` | 병렬(`-j`), `run_vse` |
| regression 디렉터리 | `regression_test/<mode>`를 다음 실행이 지움 | `regression_test_<mode>_NNN`, 원자적 확보, `clean.sh`/`func_teardown_all.sh`로 정리 |
| 실행 조건 기록 | — | `result/<id>/run_args.txt` (mode, 대상, 버전, 원본 경로 등) |
| 옵션 | `-mode -prefix -lib -cell -fromLib -toLib -fromCell -min -max -cases` | 같음 + `-j -d -k -ws -proj`. mode별 필수 인자, 값·범위 검사 |

## 4. 정리

| 항목 | legacy | 현재 |
|---|---|---|
| teardown | 테스트마다 바로(순차) | 백그라운드 worker, 실패 집계, `-k`로 생략 가능 |
| 재시도 | — | `func_teardown_all.sh <dir>`: 대기열·`.failed`·남은 워크스페이스에서 id를 모아 정리, 실패하면 디렉터리를 남기고 rc 1 |
| 접두어 | — | `-ws`/`-proj`가 자식과 재시도까지 전달(`CAT_FUNC_*`, `run_prefixes`) |
