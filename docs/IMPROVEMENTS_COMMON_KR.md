# IMPROVEMENTS — 공통 (legacy 대비)

이 저장소의 현재 코드가 legacy(`1_cico_sp`, `2_perf_sp`, `3_func_sp`)와 비교해 무엇이 같고 무엇이 나아졌는지 정리합니다.
suite별 내용은 [IMPROVEMENTS_CICO_KR.md](IMPROVEMENTS_CICO_KR.md) · [IMPROVEMENTS_FUNC_KR.md](IMPROVEMENTS_FUNC_KR.md) ·
[IMPROVEMENTS_PERF_KR.md](IMPROVEMENTS_PERF_KR.md)에 있습니다. legacy 변경을 옮기는 방법은 [MIGRATION_COMMON_KR.md](MIGRATION_COMMON_KR.md)를 봅니다.

---

## 1. 원칙: 테스트 내용은 legacy와 같다

| suite | legacy와 같은 것 | 확인 방법 |
|---|---|---|
| cico | replay 1~144번이 legacy 생성기 출력과 **바이트 단위로 같음** | legacy `generate_templates.py`와 저장소 생성기를 같은 인자로 실행해 `cmp` |
| func | 모든 list(30종, 8221개)의 시나리오 본문이 같음 | `;;; Test Scenario::Begin`~`End` 사이 비교 |
| perf | 7개 템플릿 × 3개 라이브러리 × 2개 모드(42개)의 명령 줄이 같음. 남는 차이는 changeLibRef의 SKILL `load` 2줄 | 틀(결과 경로, 모드 전달) 정규화 후 비교 |

테스트 픽스처(GDP 프로젝트, 라이브러리, 워크스페이스)도 legacy와 같은 순서·같은 옵션으로 만들고 지웁니다.
바뀐 것은 **실행 틀**(병렬, 경로, 정리, 오류 처리, 미리보기)입니다.

---

## 2. 구조

| 항목 | legacy | 현재 |
|---|---|---|
| 배치 단위 | suite마다 독립 디렉터리, 공용 파일을 복사해 둠 | `shared/`(2개 이상 suite가 쓰는 파일) + `suites/<suite>/`(prod 배치와 같은 구조), 링크로 공유 |
| 사이트 값 | 스크립트·SKILL에 박힌 경로와 버전 | `site/dev.env`, `site/prod.env` 6개 키(`MAX_CASES`, `FROM_LIB`, `GDP_BASE`, `VSE_VERSION`, `ICM_ENV`, `CDS_LIB_MGR`) |
| 배포 | 디렉터리 복사 | `deploy.sh <suite> <site>`: git이 추적하는 파일만, 링크를 풀어, 임시 디렉터리에서 조립해 한 번에 이동. 사이트 파일 키 검증, 커밋 안 된 변경 경고, `.deploy_info` 기록 |
| prod 대조 | — | `tools/compare_deploy.sh`: 실행 결과물을 빼고 내용 + 스크립트 실행 권한 비교 |
| 미사용 파일 | 백업이 섞여 있음 | `archive/`로 분리, 배치하지 않음 |

---

## 3. 실행 틀

### 3.1 경로와 설정
- 진입 스크립트가 `script_dir`을 한 번 정해 export하고, 모든 자식이 그 값만 씁니다. 다른 디렉터리에서 실행해도 동작합니다.
- 설정은 `code/env.sh` 하나에 모았습니다. 실행 중에 바꾸는 값은 `CAT_*` 이름(`CAT_VSE_VERSION`, `CAT_WS_PREFIX` 등)으로만 받아서,
  셸에 우연히 있는 같은 이름의 변수가 끼어들지 않습니다.
- Virtuoso 버전은 세 suite가 같은 `VSE_VERSION`을 씁니다(현재 `IC251SM_ISR8_003-260902`).

### 3.2 미리보기와 로컬 실행 (DRY_RUN)
| 단계 | 동작 |
|---|---|
| 0 | 모두 실행 |
| 1 | `gdp`/`xlp4`/`rm`/`vse_*`를 건너뛰고, 워크스페이스는 mock 디렉터리로 만듦(`--location` 반영) |
| 2 | 출력만, 아무것도 만들지 않음. 워크스페이스가 없어도 전체 흐름을 보여 줌 |

legacy에는 미리보기가 없었습니다. 추가로 `tools/mock/gdp`는 만든 GDP object를 등록부 파일에 기록하고 실제 gdp처럼 응답하므로
(`gdp list <경로>`는 있으면 그 경로, `<경로>/`는 하위까지), 단계 0 전체 흐름(생성 → 실행 → teardown → 재시도 → 정리 sweep)을
로컬에서 확인할 수 있습니다. `MOCK_GDP_DOWN=1`로 gdp 장애도 흉내 냅니다.

### 3.3 병렬 실행
legacy는 테스트를 순차로 돌렸습니다. 현재는 `xargs -P`(`-j`, 기본 4)로 병렬 실행합니다. 이를 위해:
- 테스트마다 고유한 id(`<번호>_<시각>_<pid>` 등)로 프로젝트·워크스페이스를 만듭니다.
- legacy가 `temp/`나 `code/managed.txt` 같은 공유 파일로 replay에 넘기던 값(번호, 날짜, 모드)을 replay 생성 시 직접 치환합니다.
- 실행마다 regression 디렉터리를 원자적 `mkdir`로 확보해, 동시에 시작한 실행이 디렉터리를 공유하지 않습니다.

### 3.4 오류 처리와 종료 코드
- 모든 스크립트가 `set -euo pipefail`입니다. 서브셸 `( ... ) || rc=$?`처럼 `set -e`가 꺼지는 곳에는 단계마다 `|| exit 1`을 붙였습니다.
  legacy와 이전 prod는 init이 실패해도 Virtuoso를 돌리고 성공으로 보고했습니다.
- 테스트가 실패해도 summary와 teardown은 실행됩니다. 종료 코드는 테스트 실행 → summary → teardown 순서로 처음 실패한 값입니다.
  PASS/FAIL **판정**은 legacy처럼 종료 코드에 넣지 않고 `summary.txt`에 남깁니다.
- 값이 필요한 옵션에 값이 없으면, 범위 밖 번호(`-c 0`, list 줄 수 초과), `-j 0`이면 시작 전에 이유를 말하고 멈춥니다. `-c 08` 같은 번호는 10진수로 읽습니다.
- `-h`는 로그 파일을 만들지 않습니다.
- 로그는 suite 디렉터리의 `log/`에 실행마다 하나씩 남습니다.

### 3.5 replay 생성기 (`shared/code/generate_templates.py`, cico·func 공용)
- legacy 두 생성기(cico 화살표 형식, func 블록 형식)를 하나로 합쳤고 블록 형식을 읽습니다. 출력은 legacy와 같습니다(§1).
- control에 없는 단계가 list에 있으면 replay는 만들되 **exit 3**으로 실행을 막습니다. prod에서 이 검사가 없어 cico 256개 중
  235개가 단계를 조용히 건너뛰고 있었습니다.
- `=== End`가 없는 블록, 같은 이름이 두 번 나오는 블록은 legacy처럼 받아들이고 경고합니다.
- 결과 파일의 테스트 번호를 replay 파일 이름과 같은 자릿수로 씁니다(func는 legacy처럼 list 줄 수의 자릿수).

---

## 4. GDP 픽스처와 정리

### 4.1 생성
- `gdp create library`에 `--location=oa/{{library}}`를 붙여(legacy와 같음) 라이브러리가 워크스페이스의 `oa/<lib>`에 놓입니다. prod에서 이 옵션이 빠져 있었습니다.
- 프로젝트 생성은 `create_gdp_project`가 확인과 재시도를 합니다(`GDP_PROJ_MAX_ATTEMPTS`, 기본 5회, 10초 간격).
- GDP 기본 폴더가 없으면 만들고, 만들기에 실패하면 멈춥니다.

### 4.2 teardown
legacy 순서(revert → p4 client 삭제 → GDP 워크스페이스 삭제 → 로컬 삭제 → 프로젝트 삭제 → depot obliterate)는 그대로이고 다음을 더했습니다.
- 미결 changelist 삭제.
- 한 단계가 실패해도 다음 단계를 계속하고, 실패를 세어 rc 1로 끝냅니다.
- **멱등**: 이미 지워진 프로젝트는 성공으로 봅니다. 그래서 실패한 teardown을 그대로 다시 실행할 수 있습니다.
- **조회 실패를 "없음"으로 보지 않음**: `gdp_path_state`(exists/gone/unknown)와 `gdp_ws_state`(registered/gone/unknown)로 판단합니다.
  GDP가 기록 삭제를 확인해 줄 때만 로컬 워크스페이스를 `.trash`로 옮기고, gdp가 응답하지 않으면 남기고 실패로 셉니다.
- cico·func는 백그라운드 worker가 테스트가 끝나는 대로 정리합니다. 대기열은 덧붙이기만 하므로 동시에 덧붙여도 유실되지 않고,
  실패한 id는 `<queue>.failed`에 남습니다. 메인 프로세스가 강제 종료돼도 worker는 남은 대기열을 처리하고 끝납니다.
- `-k`로 teardown을 건너뛴 실행이나 실패한 teardown은 `teardown_all.sh` / `func_teardown_all.sh`로 나중에 정리합니다.
  실행 때의 접두어는 `run_prefixes` 파일에서 읽습니다.
- 이름 접두어로 남은 프로젝트를 찾는 정리(legacy `ICM_deleteProj.sh -prefix`)는 `teardown_all.sh -p`, `perf_teardown_all.sh`입니다.
  워크스페이스가 등록된 프로젝트는 건너뛰고, 조회가 실패하면 아무것도 지우지 않으며, `-y` 없이는 후보만 보여 줍니다.

### 4.3 로컬 정리 (`clean.sh`)
suite 디렉터리의 실행 결과물을 지웁니다(`-n`은 목록만). GDP 워크스페이스가 남은 디렉터리와 teardown이 밀린 실행(`-k`, 실패)은
지우지 않고 정리 명령을 안내합니다. `result/`와 `perf_metrics/`는 남깁니다.
