# IMPROVEMENTS — perf (`perf_main.sh`)

공통 사항은 [IMPROVEMENTS_COMMON_KR.md](IMPROVEMENTS_COMMON_KR.md)에 있습니다.

## 1. 측정 내용

| 항목 | legacy (`2_perf_sp`) | 현재 (`suites/perf`) |
|---|---|---|
| 템플릿 | 7개 (`changeRefLib` 포함) | 같은 7개 (`changeLibRef`로 이름 통일). 명령 줄은 legacy와 같음 |
| 측정 구간·결과 문구 | `t1`~`t2`, `Test<N>_<lib>. Performance ... time <초>` | 같음 |
| 라이브러리·셀 | `lib_cell_view.txt`, `main.pl -lib/-cell` | `PERF_LIBS` / `PERF_CELLS` (BM01·BM02·BM03) |
| 차이 | — | changeLibRef가 쓰는 함수(`changeRefLib`, `changeRefLib_revertICM`)를 별도 SKILL 파일 2개에서 로드. `HierCopy`가 빈 skip 목록과 없는 라이브러리를 안전하게 처리 |

## 2. 워크스페이스

| 항목 | legacy | 현재 |
|---|---|---|
| 생성 | 워크스페이스 하나를 `ICM_createProj.sh`로 수동 생성 | 템플릿×라이브러리 조합마다 `perf_init.sh`가 자동 생성(`-no-run`, `-auto-init`) |
| UNMANAGED | `README_CREATENEWMANWS` 절차로 수동 복사 | 자동: `oa/` 이동, 쓰기 권한, `DMTYPE none`, `cds.lib` 경로 치환 |
| 라이브러리 | 하나의 워크스페이스에 전부 | 템플릿에 필요한 것만(`<LIB>`, `_ORIGIN`, `_TARGET`, `_MIX`, `_CHIP`, `_COPY`) + 모든 워크스페이스에 DRAMLIB, `-common`으로 추가 |
| 조회 | 고정 상대 경로 | `gdp find`로 위치 조회, `WORKSPACES_MANAGED/` 디렉터리로 목록 관리 |

## 3. 측정 전 초기화

| 모드 | legacy | 현재 |
|---|---|---|
| MANAGED | 열린 파일 revert, `sync`, 덮어쓰기 거부 파일만 `sync -f` | 같음. `sync`가 다른 이유로 실패하면 측정하지 않고 그 조합을 실패로 |
| UNMANAGED | 없음(이전 실행이 바꾼 데이터에서 측정) | init 때 저장한 `.oa_pristine`에서 `rsync -a --delete`로 복원 |

초기화는 측정 시간에 들어가지 않습니다. MANAGED는 depot에 없는 파일(예: copyHier*가 만든 셀)을 지우지 못하는 한계가 legacy와 같습니다.

## 4. 실행과 결과

| 항목 | legacy | 현재 |
|---|---|---|
| replay 생성 | `rm replay*.au` 후 템플릿마다 | 조합마다, 그 조합의 이전 출력만 지움(동시 실행 보호, 오래된 replay 재사용 방지) |
| 모드 전달 | `code/managed.txt` | replay에 직접 치환 |
| 실행 | 생성된 `main.sh`가 순차 | 병렬(`-j`), 조합·모드별 |
| 결과 | `result/<날짜_버전>/`, `summary.sh` | `result/<id>/` + legacy 형식 `summary.txt`, 시간 표(`CDS_log/<id>/perf_summary.txt`), 추세 데이터(`perf_metrics/`의 json/csv/`history.jsonl`) |
| 버전 | `main.pl -version` | `VSE_VERSION`(site) 또는 `-version` |
| 종료 코드 | — | 측정·summary·teardown 중 하나라도 실패면 1. 시간 값은 판정하지 않음 |

## 5. 정리

| 항목 | legacy | 현재 |
|---|---|---|
| 워크스페이스 정리 | `teardown.sh`, `ICM_deleteProj.sh` | `perf_main.sh -no-run -t [-lib] [-test]`, 실행과 함께 `-t` |
| 고아 프로젝트 | — | `perf_teardown_all.sh`: GDP의 `perf_*` 프로젝트 중 워크스페이스가 없거나 디렉터리가 사라진 것만 정리. 진행 중인 init 보호(`-min-age`, 기본 120분), 확인 후 삭제, 조회 실패 시 아무것도 지우지 않음 |
| 남은 로컬 디렉터리 | — | GDP 기록이 없다는 확인이 있을 때만 휴지통으로 옮김 |
