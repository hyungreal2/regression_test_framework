# CAT — 성능 테스트 코드 분석
## `perf_main.sh` 실행 흐름 · `-gen-replay` · 리플레이 7종

> 관련 문서: [MANUAL_PERF_KR.md](MANUAL_PERF_KR.md) · [IMPROVEMENTS_PERF_KR.md](IMPROVEMENTS_PERF_KR.md)

> **분석 기준**
> - 쉘 스크립트: 커밋 `0622fae` 시점의 `perf_main.sh`, `code/*.sh`
> - 리플레이 템플릿: 로컬 `GenerateReplayScript/` 사본. 이 디렉터리는 `.gitignore` 대상이며 **구버전 참고용**입니다. `perf_generate_replay.sh`는 `-manage`/`-result` 옵션을 지원하는 **신버전** `createReplay.pl`을 전제로 작성되어 있습니다. 템플릿 관련 지적은 서버의 신버전에도 해당하는지 확인이 필요합니다.
> - SKILL 함수 정의: `code/function.il`, `legacy/3_func_new/code/init.sh`
> - **(추정)** 표시가 붙은 내용은 코드로 확인하지 못한 추론입니다.

---

## 목차

1. [perf_main.sh 실행 흐름](#1-perf_mainsh-실행-흐름)
2. [-gen-replay 상세](#2--gen-replay-상세)
3. [리플레이 7종 개요](#3-리플레이-7종-개요)
4. [리플레이별 분석](#4-리플레이별-분석)
5. [공통 문제](#5-공통-문제)
6. [라이브러리 구성 최적화](#6-라이브러리-구성-최적화)
7. [권장 조치 우선순위](#7-권장-조치-우선순위)

---

## 1. perf_main.sh 실행 흐름

### 1.1 초기화 단계

| 단계 | 위치 | 내용 |
|---|---|---|
| 셸 옵션 | L3 | `set -euo pipefail`: 실패하면 즉시 종료, 미정의 변수는 에러, 파이프 중간 실패도 감지 |
| 경로 확정 | L5–6 | `script_dir`를 절대 경로로 구해서 export. 자식 스크립트가 이 값을 이어받음 |
| 설정 로드 | L8–9 | `env.sh`(PERF_LIBS/CELLS/TESTS, GDP 경로, DRY_RUN, MAX_JOBS), `common.sh`(log, error_exit, run_cmd 등) |
| 로그 | L14–17 | `exec > >(tee logfile) 2>&1`: 이후의 모든 출력(자식 프로세스 포함)을 화면과 로그 파일에 함께 기록 |
| 기본값 | L22–34 | jobs=4, do_run=true, selected_modes=(managed unmanaged) 등 |
| 트랩 | L39–46 | EXIT/INT/TERM 시 `_cleanup`: `.trash` 삭제, `.gdp_ws_lock` 삭제 |
| 인자 파싱 | L134–194 | `-lib`/`-test`/`-common`은 `IFS=',' read -ra`로 배열로 변환. `-d`만 주면 DRY_RUN=2. `-j`는 MAX_JOBS로 상한 적용 |
| export | L196–197 | `DRY_RUN`, `PERF_COMMON_LIBS`(배열을 공백으로 이은 문자열) |
| 시작 조건 | L202–204 | DRY_RUN<2이면 `ICM_SkillRoot`가 설정되어 있어야 함 |

`env.sh`의 `PERF_LIBS[i]`와 `PERF_CELLS[i]`는 같은 인덱스끼리 1:1로 짝을 이룹니다.

| lib | cell |
|---|---|
| BM01 | VP_FULLCHIP |
| BM02 | FULLCHIP |
| BM03 | XE_FULLCHIP_BASE |

### 1.2 `run_cmd` 동작 (`common.sh`)

| DRY_RUN | 동작 |
|---|---|
| 0 | `[RUN]`을 출력한 뒤 `eval`로 실행 |
| 1 | `gdp`/`xlp4`/`rm`/`vse_sub`/`vse_run`은 건너뜀. `gdp build workspace`는 가짜 디렉터리를 만들고, `vse_run`은 replay 파일의 `mkdir`만 흉내 냄. 나머지 명령은 실제로 실행 |
| 2 | 출력만 하고 실행하지 않음 |

### 1.3 Main 공통 단계

1. `validate_inputs`: `-lib`/`-test` 값이 `PERF_LIBS`/`PERF_TESTS`에 있는지 확인합니다.
2. `build_combos`: 선택이 없으면 전체를 대상으로 합니다. test × lib 조합을 `"testtype lib cell"` 문자열로 만들어 `combos_init`(전역)에 넣습니다. cell은 `get_cell`이 인덱스 매핑으로 찾습니다.

### 1.4 모드 분기 (위에서부터 순서대로 검사)

| 경로 | 조건 | 실행 내용 |
|---|---|---|
| ① | `-gen-replay` | `generate_replays`만 실행 |
| ② | `-no-run` (그리고 `-t` 없음) | `run_init_phases` |
| ③ | 기본 (do_run=true) | `ensure_workspaces` → 새 uniqueid → `generate_replays` → `copy_replays_to_workspaces` → `run_tests` → `perf_summary.sh` → (`-t`가 있으면) teardown |
| ④ | `-no-run -t` | `teardown_workspaces` |

### 1.5 주요 함수

| 함수 | 동작 |
|---|---|
| `run_init_phases` | uniqueid 생성, `WORKSPACES_{MANAGED,UNMANAGED}` 생성, `code/date_virtuosoVer.txt`에 uniqueid 기록, `ensure_gdp_folders`, `generate_replays`, `init_workspaces` |
| `ensure_gdp_folders` | `gdp list`의 출력이 비어 있으면 `gdp create folder` (GDP_BASE, PERF_GDP_BASE) |
| `generate_replays` | 조합마다 managed와 unmanaged 두 번씩 `perf_generate_replay.sh`를 **순차 실행** |
| `init_workspaces` | `compgen -G`로 같은 조합의 워크스페이스가 이미 있으면 건너뜀. 나머지는 `xargs -n3 -P$jobs`로 `perf_init.sh`를 병렬 실행 |
| `scan_workspaces` | `WORKSPACES_MANAGED/perf_<test>_<lib>_*` 디렉터리 이름으로 testtype과 lib를 식별하고 `-lib`/`-test` 필터를 적용해 `active_ws`에 넣음. 세션 파일 없이 **디렉터리 이름만으로 상태를 추적** |
| `ensure_workspaces` | 워크스페이스가 없으면 프롬프트를 띄우거나 `-auto-init`에 따라 `run_init_phases` 실행 |
| `copy_replays_to_workspaces` | 새로 만든 `.au`를 MANAGED와 UNMANAGED 워크스페이스에 `<test>_<lib>.au`로 복사 |
| `run_tests` | 다시 스캔한 뒤 `active_ws × selected_modes`를 `xargs -n4`로 넘겨 `perf_run_single.sh`를 병렬 실행 |
| `teardown_workspaces` | 스캔한 뒤 ws_name 단위로 `xargs -n1`로 `perf_teardown.sh`를 병렬 실행 |

`xargs ... bash -c "... \$1 ..." _` 패턴에서 `_`는 `$0` 자리를 채우는 더미입니다. `\$1`은 자식 bash가 해석하고, `${uniqueid}`와 `${DRY_RUN}`은 현재 셸이 미리 값으로 바꿔 넣습니다.

### 1.6 perf_main.sh에서 발견한 문제

| # | 문제 | 영향 |
|---|---|---|
| M1 | auto-init 경로에서 `ensure_workspaces`가 init **이전의** 스캔 결과를 유지함 | `copy_replays_to_workspaces`가 아무것도 복사하지 않음. `run_init_phases` 다음에 `scan_workspaces`를 다시 호출해야 함 |
| M2 | auto-init 경로에서 `generate_replays`가 두 번 실행됨 | 시간 낭비 |
| M3 | `-mode` 값을 검증하지 않음 | 오타가 그대로 `perf_run_single.sh`에 전달됨 |
| M4 | `teardown_worker_pid`를 설정하는 곳이 없음 | `_cleanup`의 wait 부분은 실행되지 않는 코드 |
| M5 | `scan_workspaces`가 `break 2` 이후의 루프 변수 값에 의존 | 동작은 정확하지만 읽는 사람이 놓치기 쉬움 |

---

## 2. -gen-replay 상세

### 2.1 호출 구조

```
perf_main.sh  (조합 계산, uniqueid 생성, 루프)
  └─ code/perf_generate_replay.sh  (호출 1회 = 파일 1개)
       └─ GenerateReplayScript/createReplay.pl  (템플릿 텍스트 치환)
```

### 2.2 perf_main.sh 쪽

- `do_gen_replay`를 가장 먼저 검사하므로 `-no-run`, `-t`를 같이 줘도 무시됩니다.
- 새 uniqueid를 만든 뒤 `generate_replays`만 실행합니다. `mkdir WORKSPACES_*`, `date_virtuosoVer.txt` 기록, `ensure_gdp_folders`는 실행하지 않습니다.
- 모드는 `managed unmanaged`로 하드코딩되어 있어서 **`-mode`가 무시됩니다.**
- **순차 실행이며 `-j`도 무시됩니다.** createReplay.pl이 공유 파일(`lcv.txt`, `replay.*.au`)을 덮어쓰기 때문에 **순차 실행이 필수**입니다.
- ⚠️ replay 생성에는 필요 없는데도 DRY_RUN<2이면 `ICM_SkillRoot`를 검사합니다.

### 2.3 perf_generate_replay.sh

| 단계 | 내용 |
|---|---|
| `-d` 선행 파싱 | `${!_i}` 간접 참조로 위치 인자를 훑어서, env.sh를 읽기 전에 DRY_RUN을 export함. 단독 실행을 위한 처리 |
| 부모 환경 확인 | `script_dir`가 없으면 종료 (common.sh를 읽기 전이라 echo 사용) |
| 인자 | `<testtype> <lib> <cell> <mode> <uniqueid>`. mode만 검증 |
| 서브셸 | `( cd GenerateReplayScript; ... )`로 cd가 바깥에 영향을 주지 않게 함. 안쪽의 error_exit는 서브셸의 종료 코드를 통해 전체로 전파됨 |
| 생성 | `run_cmd "perl createReplay.pl -lib -cell -template -manage -result"`. `perl`은 DRY_RUN=1에서도 **실제로 실행됨** |
| 이름 변경 | `replay.<t>_<l>_<m>.au` → `<t>_<l>_<m>.au`. 파일이 없으면 error_exit, 있으면 경고 없이 덮어씀 |

### 2.4 createReplay.pl (로컬 구버전)

1. `GetOptions`로 `lib`/`cell`/`template`만 정의합니다. `-manage`/`-result`는 경고만 출력하고 **무시**합니다.
2. 템플릿 파일(= testtype 이름)이 없으면 `Template Not Found`를 출력하고 **종료 코드 0으로** 끝납니다.
3. `test.spec`을 읽습니다. `-lib`를 준 경우에는 실제로 쓰이지 않습니다.
4. `lcv.txt`에 `"BM01" "VP_FULLCHIP" "schematic"`을 기록합니다. lib와 cell 개수가 다르면 종료 코드 0으로 끝납니다.
5. LCV 한 줄마다 `replay.<template><cnt>.au`를 만들면서 템플릿을 치환합니다.

| 치환 규칙 | 결과 예시 |
|---|---|
| `openDesign(…)` | `openDesign("BM01" "VP_FULLCHIP" "schematic" …)` |
| `hiStartLog(` | `hiStartLog("BM01_VP_FULLCHIP_schematic.log"` |
| `Replace_CellName_here` | `BM01_VP_FULLCHIP_schematic` |
| `Replace_Cell_here` | `VP_FULLCHIP` |
| `Replace_Lib_here` | `BM01` |
| `renameRefLib("_a" "_b" "_c")` | `renameRefLib("BM01_a" "BM01_b" "BM01_c")` |

### 2.5 신버전과 구버전의 차이

| 항목 | 로컬 구버전 | perf_generate_replay.sh가 기대하는 것 |
|---|---|---|
| `-manage`, `-result` | 지원하지 않음 | 필수 |
| 출력 파일 이름 | `replay.checkHier1.au` | `replay.checkHier_BM01_managed.au` |
| `changeLibRef` 템플릿 | 없음 | 필요 |

→ 로컬 사본으로 DRY_RUN 0이나 1로 실행하면 `Expected output not found`로 실패합니다.

### 2.6 이 모드의 특성

- 여기서 만든 uniqueid는 1회용입니다. 일반 run은 replay를 새 uniqueid로 **다시 생성**하므로, 이 모드는 주로 **내용 확인과 디버깅 용도**입니다.
- perl 쪽 에러(템플릿 없음, lib와 cell 개수 불일치)가 종료 코드 0으로 끝나서, 실패가 "Expected output not found"라는 간접적인 메시지로만 드러납니다.
- perf_main을 동시에 두 개 실행하면 `GenerateReplayScript/`의 파일이 서로 덮어써집니다.

---

## 3. 리플레이 7종 개요

생성되는 파일 수는 **7종 × lib 3개 × 모드 2개 = 42개**입니다. 템플릿은 테스트 종류 단위로 존재합니다.

| # | 테스트 | 측정 대상 | 템플릿 번호 | summary 기대 번호 | 로컬 템플릿 | 필요 lib (perf_init) |
|---|---|---|---|---|---|---|
| 1 | checkHier | Check → Hierarchy | Test1 | Test1 | ✅ | `<lib>` |
| 2 | renameRefLib | Rename Reference Library | Test2 | Test2 | ✅ | `<lib> _ORIGIN _TARGET` |
| 3 | replace | Edit → Replace (속성 일괄 변경) | **Test4** | Test3 | ✅ | `<lib>` |
| 4 | deleteAllMarker | Delete All Marker | **Test5** | Test4 | ✅ | `<lib>` |
| 5 | copyHierToEmpty | 빈 lib로 계층 복사 | **Test6** | Test5 | ✅ | `<lib> _CHIP _COPY` |
| 6 | copyHierToNonEmpty | 비어 있지 않은 lib로 계층 복사 | **Test7** | Test6 | ✅ | `<lib> _CHIP` |
| 7 | changeLibRef | Change Library Reference (규칙 기반) | – | Test7 | ❌ | `<lib> _ORIGIN _TARGET _MIX` |

### 리플레이 실행 전제

- `perf_run_single.sh:75`가 `vse_run -replay ./<test>_<lib>.au`를 **워크스페이스 디렉터리 안에서** 실행합니다.
- 그래서 템플릿의 `../../`는 `script_dir`를, `../managed.txt`는 `WORKSPACES_MANAGED/managed.txt`를 가리킵니다.

### 모든 템플릿에 공통인 구조

```skill
envLoadFile("../../code/.cdsenv")
load("../../code/perfFunctions.il")
code_path = "../../code/"   result_path = "../../result/"
load(strcat(code_path "date_virtuosoVer.il"))
ddAutoCtlSetVars(0 0 3 3)
... (테스트별 본문: t1 → 작업 → t2)
final = compareTime(t2 t1)
system(strcat("mkdir -p " result_path date_virtuosoVer(code_path)))
managed = <../managed.txt의 첫 줄에서 개행 제거>
fprintf → result/<uid>/Test<N>_<lib>_<managed>_<uid>.log
          "Test<N>_<lib>. Performance <설명> <managed> time <final>"
exit → geSaveAllForm에서 none 선택 → OK
```

---

## 4. 리플레이별 분석

### 4.1 [1/7] checkHier

**목적**: 최상위 schematic을 연 뒤 Check Hierarchy(계층 전체 검사와 저장)에 걸리는 시간을 측정합니다.

| 줄 | 내용 |
|---|---|
| L1 | `\o \p`: CDS.log 형식의 접두어. **7개 중 이 템플릿에만** 있음 (로그 복사 흔적) |
| L2–8 | 공통 환경 준비 |
| L13–14 | `t1` → `openDesign(... "a")`. **open이 측정 구간에 포함됨** |
| L18–19 | `LoadSamsungEnv()` → `hiFormDone(schSRCForm)` |
| L23–30 | `schHiCheckHier()` 폼 설정: checkAlways=t, checkRefLibs=t, openMode="edit", saveStrategy="Save all", closeErrorCVs=t → 실행 |
| L31 | 창 닫기 |
| L35–48 | t2, 결과 기록 (`Edit-Check-Hierarchy`) |
| L52–53 | `exit geSaveAllForm->none->value= t`: **한 줄로 합쳐짐** |

- `openMode=edit`와 `Save all` 조합 때문에 managed 모드에서는 계층 전체에서 체크아웃과 저장이 일어납니다. 두 모드의 차이가 가장 크게 드러나는 지점입니다.
- summary와 호환됩니다 ✅

**문제**: L1 `\o \p` / exit 줄 합쳐짐 / `compareTime`(초 단위)을 summary가 `elapsed_ms`로 표기 / 측정에 open이 포함됨 / `managed.txt` 출처 불명

---

### 4.2 [2/7] renameRefLib

**목적**: `<lib>_ORIGIN` 안의 인스턴스 참조를 `ORIGIN`에서 `TARGET`으로 일괄 변경하는 시간을 측정하고, 측정 후 되돌립니다.

| 줄 | 내용 |
|---|---|
| L12–20 | `t1` → BM01 open → LoadSamsungEnv → 닫기 → `hiDBoxOK(geDBox)`. **측정 대상과 무관한 open과 close가 측정에 포함됨** |
| L24 | `renameRefLib("BM01_ORIGIN" "BM01_TARGET" "BM01_ORIGIN")` |
| L28–41 | t2, 결과 기록 (`Rename Reference Library`) |
| L43–47 | `xlp4 opened ...` 진단 출력. `when(isCallable('ICM_runP4)`가 **주석 줄 끝에 붙어서** 조건 없이 실행되고 괄호도 맞지 않음 |
| L48–51 | Virtuoso PID에 **strace 부착** (측정 후라서 되돌리기만 추적) |
| L56 | 되돌리기: `renameRefLib("BM01_TARGET" "BM01_ORIGIN" "BM01_ORIGIN")` |
| L60–61 | exit 줄 합쳐짐 |

**`renameRefLib(fromLib toLib updateLib)`의 정의** (`legacy/3_func_new/code/init.sh:104-130`):
- fromLib와 toLib 각각에 대해 `ddGetObj`가 없으면 **에러를 출력하고 return(nil)**
- `ccpRenameReferenceLib(fromSpec toSpec updateList)` 호출

**문제**:
- unmanaged 모드에서 `ICM_runP4`를 호출하면 에러가 날 수 있습니다.
- strace 흔적이 남아 있습니다.
- managed 모드에서 되돌린 뒤에도 **체크아웃 상태가 남아서** 반복 run마다 측정 조건이 달라집니다.
- summary와 호환됩니다 ✅

---

### 4.3 [3/7] replace

**목적**: Edit → Replace로 계층 전체 인스턴스의 `test` 속성을 `MCR`로 바꾸고 저장하는 시간을 측정합니다.

| 줄 | 내용 |
|---|---|
| L5–6 | `functions.il`을 추가로 로드. 저장소에는 **`function.il`(단수형)**만 있음 |
| L13–14 | 준비: open → `AddInstProperty("test" "test")` (계층 전체를 재귀로 순회하며 `dbReplaceProp`, 편집 모드로 열기, 저장). 이전 run에서 바뀐 값을 **초기화**하는 역할도 함 |
| L17 | `xlp4 submit ... /user/virtuoso.catdm/USERS/CAT_DM/perfTest/managed/cadence_perf_ws_s.min.ju.mcr/...`: **다른 사용자의 경로가 하드코딩됨** |
| L22–23 | `t1` → openDesign. L13에서 연 창을 **닫지 않은 채 다시 엶** |
| L30–31 | **`schHiReplace()`가 주석 구분선 끝에 붙어서 실행되지 않음** |
| L32–38 | Replace 폼 설정: propName="other"→"test", condOp "==", propValue "*", newPropValue "MCR", searchScope "hierarchy", schRepSaveEdits=t → `schRepReplaceAll()` |
| L39–43 | 대화상자 OK 두 번, 폼 Cancel, 창 닫기, `hiDBoxCancel(geDBox)` |
| L47–60 | 결과 기록. **Test4** |
| L64–67 | exit. **7개 중 유일하게 올바른 형태** |

**문제**:
- **측정 대상인 Replace가 실행되지 않습니다 (치명적).**
- 체크인이 실패해서, managed 모드의 측정에 체크아웃 비용이 빠집니다.
- 번호가 맞지 않습니다 (Test4, 기대값 Test3).
- 참고할 수 있는 올바른 체크인 방식: func 테스트의 `replay_files_replace_*/replay_26.il` Step 6 (`ICM_Hier_View_CI`)

---

### 4.4 [4/7] deleteAllMarker

**목적**: Check Hierarchy로 마커를 만든 뒤, Delete All Marker로 계층 전체의 마커를 지우는 시간을 측정합니다.

| 줄 | 내용 |
|---|---|
| L12–29 | 준비 (측정 밖): open → LoadSamsungEnv → Check Hierarchy(edit, Save all) → 창 닫기. 마커를 생성함 |
| L30–33 | `ddsHiCloseData()` + `ddsiCloseDataButtonCB('all)` (**private 함수**)로 모든 데이터를 닫음 → 측정 구간에서 cold open 조건을 확보 |
| L34–37 | **측정 직전에 strace 부착** |
| L43–48 | `t1` → openDesign → `geHiDeleteAllMarker()`: type all, scope "hierarchy starting from top cellview", access mode edit, sourcesScope all |
| L49–50 | 창 닫기 → `hiDBoxOK(geDBox)` |
| L54–67 | 결과 기록. **Test5** |

**좋은 점**: 준비 단계를 측정 밖에 두고, Close Data로 cold open 조건을 만듭니다.

**문제**:
- **측정 구간 전체가 strace 아래에서 실행되어 시간이 왜곡됩니다.** 편차도 커집니다.
- 준비 단계에서 이미 체크아웃되므로 managed 모드의 측정에 체크아웃 비용이 빠집니다.
- 마커 수가 디자인에 따라 달라서 lib 간 비교는 의미가 약합니다.
- summary가 기대하는 Test4 자리에 **replace의 결과가 들어갑니다.**

---

### 4.5 [5/7] copyHierToEmpty

**목적**: 계층 전체를 빈 라이브러리 `<lib>_COPY`로 복사하는 시간을 측정합니다. 복사 전과 후에 COPY를 비웁니다.

| 줄 | 내용 |
|---|---|
| L12–19 | open → 환경 로드 → 닫기 (측정 밖) |
| L21–22 | 주석이 두 줄로 쪼개져서 `exits before execute copy operation.`이 코드로 해석됨 → unbound variable 에러 |
| L29–34 | 복사 전 비우기. `if(managed=="managed" then \i ICM_Sensitivity_popup(...)` … `;ddDeleteObj(...) )` → **`if(`의 닫는 괄호가 주석 안에 있음** |
| L38–39 | `t1` → `HierCopy("BM01" "VP_FULLCHIP" "" "BM01_COPY" list("DRAMLIB"))`. 측정 구간이 **7개 중 가장 순수함** |
| L43–56 | 결과 기록. **Test6** |
| L57–64 | 복사 후 비우기. `if(`가 주석 안에 있어서 ICM 호출이 **모드와 관계없이** 실행됨 |

원래 의도로 복원한 삭제 블록:
```skill
if(managed=="managed" then
    ICM_Sensitivity_popup("popup_L" "BM01_COPY" "" "" "" "")
    ICM_Delete_Lib("ICMDeleteLIB" "BM01_COPY" "" "" "" "")
    hiDBoxUser(ICM_delLibQuery nil 3)
    hiDBoxUser(ICM_intHierOkay nil 1)
)
cells = ddGetObj("BM01_COPY")~>cells
foreach(cell cells ddDeleteObj(cell))
```

**HierCopy 인자 (추정)**: (원본 lib, 최상위 셀, view(""=전체), 대상 lib, 제외할 lib 목록)

**문제**:
- **괄호 불일치 때문에 L29부터 파일 끝까지가 하나의 미완성 표현식이 되어 실행되지 않을 가능성이 높습니다.** exit도 실행되지 않으면 **vse_run이 멈출(hang) 수 있습니다.**
- 줄 중간의 `\i`는 SKILL에서 심볼 `i`로 읽혀서 에러를 낼 수 있습니다.
- `DRAMLIB`가 cds.lib에 정의되어 있는지 확인이 필요합니다.
- 번호가 맞지 않습니다 (Test6, 기대값 Test5).

---

### 4.6 [6/7] copyHierToNonEmpty

**목적**: 계층 전체를 이미 셀이 들어 있는 라이브러리 `<lib>_CHIP`으로 복사(덮어쓰기)하는 시간을 측정합니다. [5/7]과 비교하기 위한 짝 테스트입니다.

| 줄 | 내용 |
|---|---|
| L12–20 | `t1` → open → 환경 로드 → 닫기. [5/7]과 달리 **측정 구간 안에** 있음 |
| L21–23 | **`HierCopy(... "BM01_CHIP" ...)`가 주석 구분선 끝에 붙어서 실행되지 않음** |
| L27–40 | 결과 기록. **Test7** |

**문제**:
- **측정값이 open, 환경 로드, close 시간뿐입니다.** 에러 없이 조용히 틀리기 때문에 발견하기 어렵습니다.
- 짝 테스트([5/7])와 측정 구간의 정의가 다릅니다.
- **초기화 단계가 없습니다.** 고치고 나면 1회차 run은 체크인 상태에서 시작해서 체크아웃 비용이 포함되고, 2회차부터는 이미 체크아웃된 상태라서 빠집니다. 반복할수록 측정 조건이 달라집니다.
- 덮어쓰기 대화상자를 처리하는 줄이 없습니다 (HierCopy 구현에 따라 멈출 수 있음).
- Test7 결과가 summary에서 **changeLibRef 행**으로 들어갑니다.

**초기화 방안** (쉘 스크립트 쪽에서 처리 권장):

| 모드 | 방법 |
|---|---|
| managed | `_CHIP` 경로에 `xlp4 revert`를 실행해서 내용과 체크아웃 상태를 모두 depot 기준으로 복원 |
| unmanaged | init 때 원본을 따로 보관해 두고, run 전에 `rsync --delete`로 복원 |

---

### 4.7 [7/7] changeLibRef

**현재 상태**: 로컬에 perf 템플릿이 없습니다. 최근 커밋(`7f8f002`)에서 func 테스트의 이름을 바꾸면서 `PERF_TESTS`에 함께 추가된 것으로 보입니다.

**템플릿이 없어서 생기는 영향 (확인된 사실)**:
1. createReplay.pl이 `Template Not Found`를 출력하고 종료 코드 0으로 끝남
2. perf_generate_replay.sh가 `Expected output not found`로 error_exit
3. perf_main이 **중단됨** → `-test`를 지정하지 않은 기본 실행은 항상 실패합니다. run 경로에서는 Phase 1이 먼저 실행되므로 **다른 6개 테스트도 실행되지 않습니다.**

**`changeLibRef(rules)` 정의** (`legacy/3_func_new/code/init.sh:144-170`):
```skill
; rules: list(list(inLib fromLib toLib))
; fromLib가 'ALL이면 → 'fromLibAll (모든 참조 lib를 toLib로)
; 그 외에는     → 'fromLib fromLib
; inLib마다 ccpChangeRefsByRule(updateList rules nil t)  (cell과 view 이름은 유지)
```
func 테스트의 사용 예: `changeLibRef(list(list("ESD01_MIX" 'ALL "ESD02_MIX")))`

**예상되는 perf 템플릿 형태 (추정)**:
```skill
(환경 준비: renameRefLib와 같음)
t1=getCurrentTime()
changeLibRef(list(list("BM01_MIX" 'ALL "BM01_TARGET")))
t2=getCurrentTime()
(결과 기록 Test7, 되돌리기, exit)
```

**설계할 때 주의할 점**:
- `'ALL`은 basic, analogLib 같은 기본 라이브러리 참조까지 바꿉니다. `_MIX`가 ORIGIN과 TARGET 외의 lib를 참조한다면 unbound 인스턴스가 대량으로 생기므로, **바꿀 lib를 명시하는 규칙**을 써야 합니다.
- func 테스트의 `changeLibRef_revertICM`은 `xlp4 edit` → 원본을 cp로 덮어쓰기 → `xlp4 submit` 순서로 되돌립니다. 체크인까지 하는 점은 좋지만, **원본 경로가 하드코딩**(`/user/virtuoso.catdm/USERS/CAT_DM/paul_test/lib_MIX/`)되어 있고 submit할 때마다 depot 히스토리가 쌓입니다. `xlp4 revert`가 더 가볍습니다.
- Test7로 만들면 copyHierToNonEmpty와 **결과 파일 이름이 완전히 같아서** 병렬 실행 시 서로 덮어씁니다.

---

## 5. 공통 문제

### 5.1 줄 합쳐짐 오류

주석 구분선 `;-----` 끝에 코드가 붙어서 주석으로 처리되거나, 반대로 주석이 쪼개져서 코드로 해석되는 문제입니다.

| 테스트 | 위치 | 붙은 코드 | 결과 |
|---|---|---|---|
| checkHier | L52 | `exit` + 폼 조작 | 종료 대화상자 처리가 불확실 |
| renameRefLib | L44, L48 | `when(isCallable(...)`, `warn(...)` | 조건 없이 실행, 괄호 불일치 |
| renameRefLib | L60 | exit | 위와 같음 |
| replace | L31 | `schHiReplace()` | **측정 대상이 실행되지 않음** |
| deleteAllMarker | L34, L71 | `warn(...)`, exit | 경미함 |
| copyHierToEmpty | L22, L29–33, L59 | 쪼개진 주석, `if(` 블록 | **괄호 불일치로 이후 전체가 실행되지 않음** |
| copyHierToNonEmpty | L23, L44 | `HierCopy(...)`, exit | **측정 대상이 실행되지 않음** |

### 5.2 테스트 번호와 summary 결과 매핑

`perf_summary.sh`는 결과 파일을 `PERF_TESTS`의 배열 순서(1부터 시작)로 `Test{N}_{lib}_{mode}_{uid}.log`라는 이름으로 찾습니다.

| summary의 행 | 찾는 파일 | 실제로 그 파일을 쓰는 템플릿 |
|---|---|---|
| checkHier | Test1 | checkHier ✅ |
| renameRefLib | Test2 | renameRefLib ✅ |
| replace | Test3 | (없음) → Log not found |
| deleteAllMarker | Test4 | **replace** |
| copyHierToEmpty | Test5 | **deleteAllMarker** |
| copyHierToNonEmpty | Test6 | **copyHierToEmpty** (생성되지 않을 가능성이 높음) |
| changeLibRef | Test7 | **copyHierToNonEmpty** (changeLibRef가 추가되면 서로 덮어씀) |

→ **summary가 번호 대신 testtype 이름으로 결과 파일을 찾도록** 바꾸는 것이 근본적인 해결책입니다.

### 5.3 기타

| 문제 | 설명 |
|---|---|
| `managed.txt` | 모든 템플릿이 `../managed.txt`를 읽지만, 저장소의 스크립트 중 이 파일을 만드는 곳이 없음. 신버전의 `-manage` 옵션으로 대체되었을 가능성 (추정) |
| 저장소에 없는 참조 파일 | `code/.cdsenv`, `code/perfFunctions.il`, `code/date_virtuosoVer.il`, `code/functions.il` |
| 시간 단위 | SKILL의 `compareTime`은 초 단위인데 summary는 `elapsed_ms`로 기록 (perfFunctions.il에서 재정의했는지 확인 필요) |
| 측정 구간 불일치 | open과 환경 로드가 측정에 포함되는 테스트(1, 2, 3, 6)와 포함되지 않는 테스트(4, 5)가 섞여 있음 |
| 체크아웃 비용 누락 | 준비 단계에서 체크아웃된 상태로 측정이 시작됨 (3, 4, 6번 2회차 이후, 2번 반복 run) |
| 하드코딩된 경로 | replace의 xlp4 submit, changeLibRef/renameRefLib의 revertICM |
| `LoadSamsungEnv` | 정의(`legacy/.../init.sh:80-100`)가 이미 `hiFormDone(schSRCForm)`을 호출함 → 템플릿의 `hiFormDone(schSRCForm)`은 중복일 수 있음. 열린 셀뷰를 필요로 한다는 조건은 보이지 않음 |

---

## 6. 라이브러리 구성 최적화

### 6.1 lib 1개가 추가될 때마다 드는 비용 (`perf_init.sh:88-155`)

`gdp create library --from` → `gdp update config` → `gdp build workspace`(1차 sync) → `mv oa`, `chmod -R`, `cdsinfo.tag` 수정 → `xlp4 sync -f`(2차 sync)

즉 lib 하나마다 **디스크 사용량 2배와 전체 sync 2회**가 추가되고, teardown 비용도 함께 늘어납니다.

### 6.2 테스트별 판단

| 테스트 | 현재 | 필수 | 제거 후보 | 조건 |
|---|---|---|---|---|
| checkHier | `<lib>` | `<lib>` | – | – |
| renameRefLib | `<lib> _ORIGIN _TARGET` | `_ORIGIN`, `_TARGET` | **`<lib>`** | ORIGIN이 BM01을 참조하지 않아야 함. `_TARGET`은 `ddGetObj` 검사 때문에 **필수**이지만 최소 lib로 줄일 수 있음 |
| replace | `<lib>` | `<lib>` | – | – |
| deleteAllMarker | `<lib>` | `<lib>` | – | – |
| copyHierToEmpty | `<lib> _CHIP _COPY` | `<lib>`, `_COPY` | **`_CHIP`** | 템플릿에서 참조하지 않음. BM01 계층이 `_CHIP`을 참조하지 않아야 함 |
| copyHierToNonEmpty | `<lib> _CHIP` | 둘 다 | – | `_CHIP`은 BM01 계층과 겹치는 셀만 남겨 줄일 수 있음 |
| changeLibRef | `<lib> _ORIGIN _TARGET _MIX` | `_MIX`, toLib | **`<lib>`**, toLib가 아닌 나머지 하나 | MIX가 원래 참조하는 lib인지 확인 |

**가장 효과가 큰 것은 `<lib>`(BM01, FULLCHIP급) 제거입니다.** renameRefLib와 changeLibRef에서 BM01은 `LoadSamsungEnv()`용으로 열었다가 닫는 데만 쓰입니다.

### 6.3 `<lib>`을 제거하는 방법

| 안 | 방법 | 확인할 점 |
|---|---|---|
| A | openDesign을 `_ORIGIN`(또는 `_MIX`)의 작은 셀로 바꿈 | rename 전에 창을 닫아야 함 (현재 구조가 이미 그렇게 되어 있음) |
| B | openDesign을 없애고 `LoadSamsungEnv()`만 호출 | legacy 정의상 셀뷰가 필요 없어 보임 → **가능성 높음** |
| C | 어떤 안이든 `t1`을 작업 직전으로 이동 | 기존 측정값과 비교할 수 없으므로 기준선을 다시 잡아야 함 |

### 6.4 `_TARGET`을 가볍게 만드는 방법

| 안 | 방법 | 평가 |
|---|---|---|
| T1 | ORIGIN이 참조하는 셀(바인딩할 view)만 담은 최소 lib | **권장** |
| T2 | GDP에서 제외하고 읽기 전용 경로로 `DEFINE` | managed와 unmanaged의 조건이 비대칭이 됨 |
| T3 | cds.lib에서 ORIGIN과 같은 경로를 별칭으로 지정 | **비추천** (같은 물리 파일 공유, DM 충돌) |

### 6.5 확인용 CIW 스크립트

어떤 lib가 다른 lib를 참조하는지 확인할 때 사용합니다. `"BM01_ORIGIN"` 자리에 확인할 lib 이름을 넣으면 됩니다.
```skill
libId = ddGetObj("BM01_ORIGIN")
refs = nil
foreach(c libId~>cells
  foreach(v setof(x c~>views x~>name=="schematic")
    cv = dbOpenCellViewByType("BM01_ORIGIN" c~>name v~>name nil "r")
    foreach(i cv~>instances unless(member(i~>libName refs) refs = cons(i~>libName refs)))
    dbClose(cv)))
println(refs)
```

---

## 7. 권장 조치 우선순위

| 순위 | 조치 | 위치 | 이유 |
|---|---|---|---|
| 1 | changeLibRef 템플릿이 있는지 확인하고, 없으면 `PERF_TESTS`에서 제외 | `code/env.sh` | 지금은 기본 실행이 항상 실패함 |
| 2 | 줄 합쳐짐 오류 수정: replace L31, copyHierToEmpty L22/L29–34/L57–64, copyHierToNonEmpty L23, renameRefLib L44, 모든 exit | 서버 템플릿 | 3개 테스트의 측정이 성립하지 않음. 1개는 hang 가능 |
| 3 | deleteAllMarker와 renameRefLib의 strace 블록 제거 | 서버 템플릿 | 측정 왜곡 |
| 4 | summary가 testtype 이름으로 결과 파일을 찾도록 변경. 템플릿 번호도 정리 | `code/perf_summary.sh`, 템플릿 | 결과가 엉뚱한 테스트에 기록되거나 덮어써짐 |
| 5 | 하드코딩된 경로 제거 (replace의 submit → ICM 계층 체크인) | 서버 템플릿 | 다른 사용자의 워크스페이스에 영향을 줄 위험 |
| 6 | 반복 run 초기화를 쉘 스크립트로 이동 (managed: `xlp4 revert`, unmanaged: 원본에서 rsync) | `perf_run_single.sh` | 측정 조건의 일관성 |
| 7 | 측정 구간 통일 (`t1`을 작업 직전으로) | 서버 템플릿 | 테스트 간, 짝 테스트 간 비교 가능성 |
| 8 | lib 구성 최적화 (`<lib>` 제거, copyHierToEmpty의 `_CHIP` 제거) | `code/perf_init.sh` + 템플릿 | init과 teardown 비용 감소 |
| 9 | perf_main.sh의 M1(auto-init 재스캔), M3(`-mode` 검증) | `perf_main.sh` | 정확성 |
| 10 | 시간 단위 표기 확인 (초 vs ms) | `perf_summary.sh` 또는 perfFunctions.il | 결과 해석 |
