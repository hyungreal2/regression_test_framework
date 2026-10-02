# CAT — 성능 테스트 코드 분석 (v2)
## `perf_main.sh` 실행 흐름 · `-gen-replay` · 리플레이 7종

> 관련 문서: [MANUAL_PERF_KR.md](MANUAL_PERF_KR.md) · [IMPROVEMENTS_PERF_KR.md](IMPROVEMENTS_PERF_KR.md)

---

## 0. 분석 기준과 v1 대비 변경

### 0.1 자료

| 구분 | 스냅샷 | 성격 |
|---|---|---|
| **prod** | `2_perf_mp/` | 우리 코드가 실제로 배포되어 쓰이는 형태. **이 문서의 1차 기준** |
| **legacy** | `2_perf_sp/` (mcr_catdm) | legacy perf(`main.pl` + `main.template`)의 최신판 |
| repo | 저장소 루트, `code/` | 커밋 `9f24beb` 시점 |
| (폐기) | 저장소의 `GenerateReplayScript/` | v1의 기준이었던 로컬 사본. **손상본으로 판명** (0.3 참고) |

> **인용 규칙**: prod와 legacy 스냅샷은 저장소에서 추적하지 않는 로컬 자료입니다. 그래서 이 문서는 경로로 링크하지 않고, 근거가 필요한 부분을 **`legacy:<파일>` / `prod:<파일>` 표기와 함께 원문이나 diff로 직접 인용**합니다. 주요 인용은 [부록 A](#부록-a-legacy--prod-인용)에 모았습니다. 본문의 "L<n>"은 해당 스냅샷 파일의 줄 번호입니다.

prod와 repo를 비교한 결과는 다음과 같습니다.
- `perf_main.sh`와 `code/perf_*.sh`는 **동일**합니다.
- `code/env.sh`는 경로, 버전, `MAX_CASES` 값만 다릅니다.
  - `FROM_LIB`/`GDP_BASE`가 `/MEMORY/RT/...`이고, FROM_LIB는 `golden/oa`
  - `VSE_VERSION=IC251SM_ISR5_015-260513`, `ICM_ENV`는 testNewArch
- `code/common.sh`에서는 `vse_run`에 **`-nograph`**가 추가되어 있습니다.
- prod에만 있는 파일(저장소에서는 추적하지 않음):
  - `code/.cdsenv`, `perfFunctions.il`, `functions.il`, `date_virtuosoVer.il`
  - `copyHierToEmpty_revertICM.il`, `changeRefLib*.il_mcr*`
  - `GenerateReplayScript/` 전체

### 0.2 확인 범위

prod 템플릿 7종을 **모두** 직접 확인했습니다. 처음에는 deleteAllMarker, copyHierToEmpty, copyHierToNonEmpty, changeLibRef 4종을 읽지 못했지만, 읽기 권한을 추가한 뒤 확인을 마쳤습니다.

prod 템플릿 곳곳에 있는 `[EQUIV]` 주석은 **legacy와 동작을 맞추기 위해 수정한 지점**을 표시한 것입니다.

### 0.3 v1 분석에서 정정한 내용

v1의 기준이었던 로컬 `GenerateReplayScript/`는 두 가지가 섞인 **손상본**이었습니다. legacy의 디버그 템플릿(`renameRefLib_debug` 등)과, `\i` 접두어를 벗기는 과정에서 **줄이 합쳐진** 사본입니다. legacy와 prod에서는 다음 문제들이 **존재하지 않습니다.**

| v1 지적 | 실제 (legacy / prod) |
|---|---|
| replace: `schHiReplace()`가 주석 처리됨 | 정상 (legacy L33, prod L33) |
| copyHierToNonEmpty: `HierCopy` 주석 처리 | 정상 (legacy L26, prod L31) |
| copyHierToEmpty: `if(`의 괄호가 닫히지 않아 hang | `if(`…`)`가 정상 (legacy L47–53, prod L61–67) |
| renameRefLib: `when(isCallable…` 괄호 불일치, strace | `renameRefLib_debug`에만 있음. legacy 정본과 prod에는 없음 |
| deleteAllMarker: 측정 직전 strace 부착 | legacy와 prod 모두 없음 |
| exit 줄 합쳐짐 | legacy와 prod 모두 `exit` / `geSaveAllForm…` / `hiFormDone`이 정상적으로 분리됨 |
| checkHier: `\o \p`는 로그 복사 흔적 | CDS 로그 형식의 replay 헤더이며 정상. prod는 모든 줄이 `\i`로 시작 |
| replace: 다른 사용자 경로로 하드코딩된 `xlp4 submit` | legacy에서는 주석 처리, prod에서는 **삭제됨** |
| `managed.txt`를 만드는 곳이 없음 | legacy는 `main.sh`가 `code/managed.txt`에 기록. prod는 `createReplay.pl`이 `managed=""`를 값으로 **치환** |
| `perfFunctions.il`, `functions.il` 등이 없음 | prod `code/`에 있음 (저장소에서 추적하지 않을 뿐) |
| changeLibRef 템플릿이 없어서 perf_main 전체가 중단됨 | prod에는 `changeLibRef` 템플릿과 `.au` 6개가 있음. **prod에서는 해당하지 않음** |
| summary 결과가 테스트 번호 밀림으로 엉뚱한 테스트에 기록됨 | prod 기준으로는 **결과 파일 이름의 접미사가 달라서 아무 파일도 찾지 못함** (5.1) |
| renameRefLib: open이 측정 구간에 포함됨 | prod에서 `t1`을 연산 직전으로 옮김 (`[EQUIV]` 주석) |

---

## 1. perf_main.sh 실행 흐름

prod와 repo가 동일하므로 v1의 분석이 그대로 유효합니다.

### 1.1 초기화 단계

| 단계 | 위치 | 내용 |
|---|---|---|
| 셸 옵션 | L3 | `set -euo pipefail` |
| 경로 확정 | L5–6 | `script_dir`를 절대 경로로 구해서 export |
| 설정 로드 | L8–9 | `env.sh`, `common.sh` |
| 로그 | L14–17 | `exec > >(tee logfile) 2>&1` |
| 기본값 | L22–34 | jobs=4, do_run=true, selected_modes=(managed unmanaged) |
| 트랩 | L39–46 | `_cleanup`: `.trash` 삭제, `.gdp_ws_lock` 삭제 |
| 인자 파싱 | L134–194 | `-lib`/`-test`/`-common`은 콤마로 나눠 배열로. `-d`만 주면 DRY_RUN=2. `-j`는 MAX_JOBS로 상한 |
| export | L196–197 | `DRY_RUN`, `PERF_COMMON_LIBS` |
| 시작 조건 | L202–204 | DRY_RUN<2이면 `ICM_SkillRoot` 필수 |

lib와 cell 대응: BM01=VP_FULLCHIP, BM02=FULLCHIP, BM03=XE_FULLCHIP_BASE

### 1.2 모드 분기

| 경로 | 조건 | 실행 내용 |
|---|---|---|
| ① | `-gen-replay` | `generate_replays` |
| ② | `-no-run` (그리고 `-t` 없음) | `run_init_phases` = mkdir → `date_virtuosoVer.txt` 기록 → `ensure_gdp_folders` → `generate_replays` → `init_workspaces`(병렬) |
| ③ | 기본 | `ensure_workspaces` → 새 uniqueid → `generate_replays` → `copy_replays_to_workspaces` → `run_tests`(병렬) → `perf_summary.sh` → (`-t`) teardown |
| ④ | `-no-run -t` | `teardown_workspaces` |

### 1.3 perf_main.sh에서 발견한 문제 (v1과 동일)

| # | 문제 |
|---|---|
| M1 | auto-init 경로에서 init 이후에 다시 스캔하지 않아서 `copy_replays_to_workspaces`가 아무것도 복사하지 않음 |
| M2 | auto-init 경로에서 `generate_replays`가 두 번 실행됨 |
| M3 | `-mode` 값을 검증하지 않음 |
| M4 | `teardown_worker_pid`를 설정하는 곳이 없음 (실행되지 않는 코드) |
| M5 | `scan_workspaces`가 `break 2` 이후의 루프 변수 값에 의존 |
| M6 (신규) | `run_init_phases`가 `code/date_virtuosoVer.txt`를 쓰지만, prod 템플릿은 더 이상 `date_virtuosoVer()`를 쓰지 않음. legacy의 잔재 |

---

## 2. -gen-replay 상세 (prod 기준)

### 2.1 호출 구조

```
perf_main.sh → code/perf_generate_replay.sh → GenerateReplayScript/createReplay.pl
```
perf_main.sh와 perf_generate_replay.sh의 동작은 v1과 같습니다: 모드는 하드코딩되어 `-mode`가 무시되고, 순차 실행이라 `-j`도 무시되며, 같은 이름의 파일은 덮어씁니다.

### 2.2 prod createReplay.pl

```perl
GetOptions("lib=s","cell=s","template=s","manage=s","result=s")
open(replayOut, ">replay.$replayMid\_$lib\_$manage.au");      # → replay.checkHier_BM01_managed.au
s/(openDesign\()\s*"a"\s*(\))/$1$lcv "a" $2/g;              # openDesign("a") 또는 openDesign( "a")만 대상
s/(hiStartLog\()/$1"$tmplcv.log"/g;
s/Replace_CellName_here/$tmplcv/g;
s/Replace_Cell_here/$cell/g;
s/Replace_Lib_here/$lib/g;
s/(renameRefLib\()"(_\w+)"\s+"(_\w+)"\s+"(_\w+)"/$1"$lib$2" "$lib$3" "$lib$4"/g;
s/managed=""/managed="$manage"/g;                             # 신규: 모드를 값으로 넣음
s/CDS_PV_REG_RES_NO/"$result"/g;                              # 신규: uniqueid를 값으로 넣음
```

legacy와의 차이:

| 항목 | legacy | prod |
|---|---|---|
| 출력 이름 | `replay.<template><N>.au` (N은 lcv 줄 번호) | `replay.<template>_<lib>_<manage>.au` |
| mode 전달 | 실행 시 `code/managed.txt`를 읽음 | 생성 시 `managed="managed"`로 치환 |
| 결과 폴더 | `result/<date_virtuosoVer()>` = `<epoch>_<버전>` | `result/<uniqueid>` (perf_main의 uniqueid) |
| openDesign 치환 | `(openDesign\()(.*\))` (괄호 안 아무거나) | `"a"`만 있는 형태로 한정 |

**남아 있는 문제** (legacy와 prod 공통):
- 템플릿이 없거나 lib와 cell 개수가 다를 때 `exit`(종료 코드 0)로 끝납니다. 그래서 실패가 `perf_generate_replay.sh`의 "Expected output not found"로만 드러납니다.
- `lcv.txt`와 `replay.*.au`를 공유 디렉터리에 쓰므로 동시 실행이 불가능합니다.
- 실제 생성 결과를 확인해 봤습니다: `checkHier_BM01_managed.au`는 `openDesign("BM01" "VP_FULLCHIP" "schematic" "a" )`, `managed="managed"`, `result_path "20260611_191403_hyungreal.mcr"`로 **정상 치환**되어 있습니다.

---

## 3. 리플레이 7종 개요

### 3.1 공통 구조 (prod)

```skill
\o
\p
\i envLoadFile("../../code/.cdsenv")
\i load("../../code/perfFunctions.il")        ; openDesign, HierCopy, renameRefLib, LoadSamsungEnv, virtuosoVer
\i code_path = "../../code/"   result_path = "../../result/"
\i load(strcat(code_path "date_virtuosoVer.il"))
\i ddAutoCtlSetVars(0 0 3 3)
...  t1 → 작업 → t2
\i final=compareTime(t2 t1)                    ; 초 단위 (legacy README_PERF: "time <time in seconds>", 부록 A.4)
\i managed="managed"                           ; ← 치환된 값
\i unique_result_folder = strcat(result_path "<uniqueid>")
\i fd=outfile(strcat(unique_result_folder "/Test<N>_<lib>_" managed "_" virtuosoVer() ".log") "w")
\i fprintf(fd "Test<N>_<lib>. Performance <설명> %s time %d\n" managed final)
\i exit
\i geSaveAllForm->none->value= t
\i hiFormDone(geSaveAllForm)
```

결과 파일은 **`result/<uniqueid>/Test<N>_<lib>_<mode>_<Virtuoso버전>.log`**입니다. 파일 이름 끝이 uniqueid가 아니라 **버전 문자열**이라는 점에 주의해야 합니다(5.1).

### 3.2 prod perfFunctions.il의 함수 정의

| 함수 | 구현 | 의미 |
|---|---|---|
| `openDesign(lib cell view mode)` | `deOpenCellView(lib cell view viewType nil mode)` | **창을 엶**. 실패하면 메시지만 출력 |
| `HierCopy(srcLib srcCell srcView destLib skipLibs)` | `ccpCopyDesign(src dst t 'CCP_EXPAND_ALL skip nil list("schematic" "symbol"))` | 계층 전체를 확장해서 복사. **schematic과 symbol view만** 복사. `dst`는 `ddGetObj(destLib)`이므로 **대상 lib가 존재해야 함**. skip 목록에서 **존재하지 않는 lib는 조용히 제외** (legacy는 제외하지 않고 `gdmCreateSpecFromDDID(nil)` 에러. 부록 A.5) |
| `HierCopyToNewLib(...)` | `gdmCreateSpec(destLib …)`로 새 lib 지정 | 템플릿에서 쓰이지 않음 |
| `renameRefLib(from to update)` | `ccpRenameReferenceLib(fromSpec toSpec updateList)` | **존재 여부 검사가 없음** → lib가 없으면 `gdmCreateSpecFromDDID(nil)` 에러 |
| `LoadSamsungEnv()` | `schHiSRC("editOptions")` → SRC 옵션 설정 → **`hiFormDone(schSRCForm)`** | 셀뷰를 필요로 하지 않음. 템플릿의 `hiFormDone(schSRCForm)`은 **중복 호출** |
| `virtuosoVer()` | `getVersion(t)`에서 "sub-version"과 공백 제거 | 결과 파일 이름의 접미사 |
| `listHierLibCells(lib cell)` | 계층을 순회해서 `lib/cell` 목록 반환 | **lib 의존성을 확인하는 데 활용 가능** (6.4) |

### 3.3 테스트 목록

| # | 테스트 | 측정 대상 | 템플릿 번호 | `PERF_TESTS` 순서 | 필요 lib (perf_init) | prod 템플릿 |
|---|---|---|---|---|---|---|
| 1 | checkHier | Check → Hierarchy | Test1 | 1 | `<lib>` | ✅ 확인 |
| 2 | renameRefLib | Rename Reference Library | Test2 | 2 | `<lib> _ORIGIN _TARGET` | ✅ 확인 |
| 3 | replace | Edit → Replace | Test4 | **3** | `<lib>` | ✅ 확인 |
| 4 | deleteAllMarker | Delete All Marker | Test5 | **4** | `<lib>` | ✅ 확인 |
| 5 | copyHierToEmpty | 빈 lib로 계층 복사 | Test6 | **5** | `<lib> _CHIP _COPY` | ✅ 확인 |
| 6 | copyHierToNonEmpty | 비어 있지 않은 lib로 계층 복사 | Test7 | **6** | `<lib> _CHIP` | ✅ 확인 |
| 7 | changeLibRef | 규칙 기반 참조 변경 | **Test3** | **7** | `<lib> _ORIGIN _TARGET _MIX` | ✅ 확인 |

**번호 체계의 출처**: legacy `main.pl`의 기본 목록 순서(checkHier, renameRefLib, **changeRefLib**, replace, deleteAllMarker, …)를 따른 것입니다 (`legacy:main.pl` L89, 부록 A.1). 우리 `PERF_TESTS`는 changeLibRef를 **맨 뒤에** 두었기 때문에 3번부터 7번까지 번호가 어긋납니다.

---

## 4. 리플레이별 분석

### 4.1 [1/7] checkHier (prod 확인)

| 줄 | 내용 |
|---|---|
| L1–2 | `\o`, `\p`: replay 로그 헤더 |
| L4–9 | 공통 환경 준비 |
| L13–14 | `t1` → `openDesign(lib cell "schematic" "a")`. **open이 측정 구간에 포함됨** (legacy와 같음) |
| L18–19 | `LoadSamsungEnv()` → `hiFormDone(schSRCForm)` (중복) |
| L23–30 | `schHiCheckHier()`: checkAlways=t, checkRefLibs=t, openMode="edit", saveStrategy="Save all", closeErrorCVs=t → 실행 |
| L31 | 창 닫기 |
| L36–45 | t2, 결과 기록 `Edit-Check-Hierarchy` |
| L50–52 | exit → Save All 폼에서 none 선택 → OK |

- legacy와 기능이 동일합니다. 다른 점은 managed/result를 치환 방식으로 받는다는 것뿐입니다.
- 남은 지적:
  - 측정에 open 시간이 포함됩니다. legacy부터 그랬던 것이라 **의도된 정의**로 볼 수 있습니다. 다만 다른 테스트와 정의가 다르다는 점은 문서로 남겨 둘 필요가 있습니다.
  - managed 모드에서 Check Hierarchy를 실행하면 계층 전체가 체크아웃되는데, 이 상태가 다음 run까지 남습니다 (5.3).

### 4.2 [2/7] renameRefLib (prod 확인)

| 줄 | 내용 |
|---|---|
| L14–15 | 주석 `[EQUIV] t1 을 여기서 제거했다 … t1 은 연산 직전으로 복원 (legacy :25)` |
| L17 | `openDesign(BM01 …)`: **측정 구간 밖** |
| L22–25 | LoadSamsungEnv → 창 닫기 → `hiDBoxOK(geDBox)` |
| L31–32 | `t1` → `renameRefLib("BM01_ORIGIN" "BM01_TARGET" "BM01_ORIGIN")` |
| L37–46 | t2, 결과 기록 |
| L52 | 되돌리기 `renameRefLib("BM01_TARGET" "BM01_ORIGIN" "BM01_ORIGIN")` |
| L57–59 | exit |

- **측정 구간이 rename 한 번으로 순수하게 정리되었습니다.** v1에서 지적한 open 포함 문제와 strace 문제는 모두 해당하지 않습니다.
- 남은 지적:
  - 되돌리기는 참조만 원래대로 돌리고 **체크아웃 상태는 남깁니다** (managed). legacy는 매 replay 전에 `xlp4 revert`로 이 상태를 정리했는데, 우리 프레임워크에는 그런 단계가 없습니다 (5.3).
  - 함수에 존재 여부 검사가 없으므로 `_ORIGIN`과 `_TARGET`이 cds.lib에 없으면 에러가 납니다.
  - BM01을 여는 이유는 이제 **창과 DM 컨텍스트**를 만드는 것뿐입니다. `LoadSamsungEnv`는 셀뷰를 필요로 하지 않습니다 (6.2).

### 4.3 [3/7] replace (prod 확인)

| 줄 | 내용 |
|---|---|
| L8 | `functions.il` 로드 (prod에 있음. `AddInstProperty`를 제공) |
| L15–16 | 준비: open → `AddInstProperty("test" "test")` (계층을 재귀로 순회하며 속성을 설정하고 저장) |
| L21–22 | `t1` → `openDesign` (L15의 창이 열린 상태에서 **다시 엶**) |
| L27–28 | LoadSamsungEnv |
| L33–51 | `schHiReplace()` → Replace 폼 설정 → `schRepReplaceAll()` |
| L52–56 | 대화상자 OK 두 번, 폼 Cancel, 창 닫기, `hiDBoxCancel(geDBox)` |
| L61–71 | t2, 결과 기록 **Test4** |
| L76–79 | exit (`hiiSetCurrentForm('geSaveAllForm)` 포함) |

- 측정이 정상적으로 성립합니다. v1의 "schHiReplace 주석 처리"와 "하드코딩된 submit"은 해당하지 않습니다.
- 남은 지적:
  - **체크인 단계가 없습니다.** 준비 단계에서 `AddInstProperty`가 계층 전체를 체크아웃하고 저장하므로, managed 모드의 측정에는 **체크아웃 비용이 포함되지 않습니다.** legacy도 submit을 주석 처리해 두었으므로 같은 조건입니다. 의도된 정의인지 팀 확인이 필요합니다.
  - 창을 닫지 않은 채 같은 디자인을 다시 열기 때문에 측정 구간의 open은 **이미 메모리에 있는 데이터**를 엽니다.
  - Test4 번호와 `PERF_TESTS`의 3번째 자리가 맞지 않습니다 (5.1).

### 4.4 [4/7] deleteAllMarker (prod 확인)

| 줄 | 내용 |
|---|---|
| L14–20 | open → LoadSamsungEnv (측정 밖) |
| L25–33 | Check Hierarchy (edit, Save all) → 마커 생성 → 창 닫기 |
| L35–39 | `ddsHiCloseData` + `ddsiCloseDataButtonCB('all)` (private 함수) → 모든 데이터를 닫아 cold open 조건 확보 |
| L45–55 | `t1` → open → `geHiDeleteAllMarker()` (type all, 계층 전체, edit, sources all) → 창 닫기 → `hiDBoxOK(geDBox)` |
| L61–71 | t2, 결과 기록 **Test5** |
| L76–78 | exit |

- legacy와 기능이 동일하고, managed/result를 치환 방식으로 받는다는 점만 다릅니다. **strace는 없습니다.**
- 측정 구간에 cold open이 포함되는 것은 legacy부터의 정의입니다.
- 남은 지적:
  - 준비 단계의 Check Hierarchy에서 이미 체크아웃되므로, managed 측정에 체크아웃 비용이 빠집니다.
  - 마커 수가 디자인에 따라 달라서 lib 간 비교가 어렵습니다.
  - private 함수(`ddsiCloseDataButtonCB`)에 의존합니다.

### 4.5 [5/7] copyHierToEmpty (prod 확인)

| 줄 | 내용 |
|---|---|
| L9–11 | `[EQUIV]` 주석: `copyHierToEmpty_revertICM.il` 로드를 **주석으로 비활성화** |
| L16–24 | open → LoadSamsungEnv → 닫기 (측정 밖) |
| L26–32 | 복사 **전** 정리: `[EQUIV]` legacy에 없으므로 비활성화 (주석으로만 보존) |
| L37–39 | `t1` → `HierCopy("BM01" "VP_FULLCHIP" "" "BM01_COPY" list("DRAMLIB"))` → `hiDBoxUser(ICM_intHierQuestion nil 1)` |
| L44–53 | t2, 결과 기록 **Test6** |
| L56–59 | `[EQUIV]` legacy의 ICM GUI 정리 로직으로 되돌렸다는 주석. revertICM 호출은 주석으로 보존 |
| L61–67 | `if(managed=="managed" then` … `ICM_Sensitivity_popup` → `ICM_Delete_Lib` → 대화상자 → `ddDeleteObj(… "data.dm")` … `)` |
| L68–72 | 공통: `hiDBoxUser(...)` 두 번, COPY의 셀을 모두 `ddDeleteObj` |
| L77–79 | exit |

- 측정 구간은 HierCopy 한 번이고, legacy와 동일합니다.
- 지적:
  - ⚠️ **`\i` 접두어가 섞여 있습니다.** 파일이 `\o`/`\p` 헤더와 `\i` 줄로 이루어진 로그 형식인데, **L61의 `if(…then`과 L67의 `)`에만 `\i`가 없습니다** (legacy를 복원하면서 생긴 흔적). replay가 `\i` 줄만 입력으로 실행한다면 `if`가 사라지고, ICM 삭제 블록이 **unmanaged에서도 실행됩니다.** 반대로 `\i`가 없는 줄도 입력으로 받는다면 의도대로 동작합니다. 어느 쪽인지 **unmanaged 실행의 CDS_log**에서 `ICM_Sensitivity_popup` 호출 여부로 확인해야 합니다. 일관성을 위해 두 줄에도 `\i`를 붙이는 것이 안전합니다.
  - L68–69의 `hiDBoxUser(ICM_…)`는 `if` 바깥에 있어서, unmanaged 모드에서는 ICM 심볼이 없어 에러가 날 수 있습니다 (legacy와 같음).
  - **복사 전 정리가 없습니다.** 이전 run이 중간에 실패해서 복사 후 정리가 실행되지 않으면, 다음 run은 **비어 있지 않은 COPY에 복사**하게 됩니다(측정 조건이 바뀜). legacy는 run 전에 managed 워크스페이스를 원복했기 때문에 managed에서는 이 문제가 완화되었지만, 우리 프레임워크에는 그 단계가 없습니다 (5.3).
  - `HierCopy`가 `ddGetObj(destLib)`를 쓰므로 **`_COPY` lib가 (비어 있는 상태로) 반드시 존재해야** 합니다.
  - **DRAMLIB**: legacy 프로젝트에는 DRAMLIB가 포함되어 있습니다(`legacy:code/ICM_createProj.sh` L10–11, 부록 A.3). 우리 `perf_init.sh`는 `-common`으로 지정하지 않는 한 DRAMLIB를 넣지 않습니다. 그러면 prod `HierCopy`가 skip 목록에서 DRAMLIB를 **조용히 빼고**, DRAMLIB를 참조하는 인스턴스는 바인딩되지 않아서 **legacy와 다른 계층을 복사**하게 됩니다 (6.3).
  - 보존되어 있는 주석 `copyHierToEmpty_revertICM("…", managed)`에는 **콤마**가 있습니다. SKILL 인자는 공백으로 구분하므로, 이 주석을 그대로 되살리면 문법 오류가 날 수 있습니다.

### 4.6 [6/7] copyHierToNonEmpty (prod 확인)

| 줄 | 내용 |
|---|---|
| L13–14 | `[EQUIV]` 주석: `t1`을 open 앞에서 연산 직전으로 옮김 |
| L16–24 | open → LoadSamsungEnv → 닫기 (측정 밖) |
| L30–31 | `t1` → `HierCopy("BM01" "VP_FULLCHIP" "" "BM01_CHIP" list("DRAMLIB"))` |
| L36–45 | t2, 결과 기록 **Test7** |
| L51–53 | exit |

- 측정 구간이 [5/7]과 같은 정의(HierCopy 한 번)로 정리되었습니다.
- 남은 지적:
  - **템플릿 안에 초기화가 없습니다.** legacy는 `main.sh`가 매 replay 전에 managed 워크스페이스를 `xlp4 revert`와 `sync`로 원복했습니다. 우리 프레임워크에는 이 단계가 없어서 **2회차 run부터 측정 조건이 달라집니다**(체크아웃 상태가 남고, CHIP이 이미 덮어써져 있음) (5.3).
  - [5/7]과 달리 HierCopy 뒤에 대화상자 처리(`hiDBoxUser(ICM_intHierQuestion …)`)가 없습니다. 덮어쓸 때 ICM 질문 대화상자가 뜬다면 replay가 멈출 수 있으므로 CDS_log로 확인이 필요합니다.
  - DRAMLIB 문제는 [5/7]과 같습니다.

### 4.7 [7/7] changeLibRef (prod 확인)

prod 템플릿은 `\o`/`\p`/`\i` 없이 **순수 SKILL**로 작성되어 있습니다 (legacy와 같은 형식).

| 줄 | 내용 |
|---|---|
| L1–5 | 공통 환경 준비 |
| L6–7 | **`changeRefLib.il_mcr`**, **`changeRefLib_revertICM.il_mcr_modified`** 로드 → 함수 정의 확보 |
| L13–20 | `[EQUIV]` 주석: openDesign을 `"a"`만 있는 형태로 되돌린 이유 (createReplay.pl의 치환 패턴에 걸려야 lib/cell이 들어감) |
| L22–30 | `openDesign(BM01 …)` → LoadSamsungEnv → 닫기 (측정 밖) |
| L36–37 | `t1` → `changeRefLib(list(list("BM01_MIX" 'ALL "BM01_MIX")))` |
| L42–51 | t2, 결과 기록 **Test3** |
| L56 | 되돌리기 `changeRefLib_revertICM("BM01_MIX" managed)` |
| L61–63 | exit |

- **함수 정의는 정상적으로 로드됩니다.** v2에서 걱정한 "정의 미로드"는 해당하지 않습니다. 템플릿이 호출하는 이름도 정의된 이름(`changeRefLib`)과 같습니다. 테스트 이름만 `changeLibRef`입니다.
- **규칙**: inLib=`_MIX`, fromLib=`'ALL`, toLib=`_MIX`. MIX 라이브러리 안의 모든 참조를 **MIX 자기 자신을 가리키도록** 바꿉니다. `'ALL`이므로 basic, analogLib, DRAMLIB에 대한 참조도 MIX로 바뀝니다. legacy부터의 정의입니다.
- **되돌리기** (`_mcr_modified` 판):
  - managed: `xlp4 sync <lib>/...#1` → `edit` → `sync`(head) → `resolve -ay` → `submit` 순서로, **rev #1 내용을 새 리비전으로 제출**해서 원복합니다. 경로 의존은 없지만 실행할 때마다 depot 히스토리가 쌓입니다. `xlp4 resolve -ay`에 경로가 없어서 **워크스페이스 전체**의 pending resolve에 적용됩니다.
  - unmanaged: 하드코딩된 `/user/virtuoso.catdm/USERS/CAT_DM/paul_test/lib_MIX/`에서 cp합니다. prod 환경(`/MEMORY/RT/...`)에 이 경로가 없다면 **cp가 조용히 실패**합니다. 그러면 MIX는 변경된 상태로 남고, **2회차 unmanaged run에서는 바꿀 참조가 없어서 측정값이 비정상적으로 작아집니다.**
- ⚠️ **결과 파일 이름 버그** (L49):
  ```skill
  "/Test3_Replace_Lib_here" managed "_" virtuosoVer()
  ```
  lib 이름 뒤에 `_`가 빠져서 `Test3_BM01managed_<버전>.log`가 됩니다. 다른 템플릿의 `Test<N>_<lib>_<mode>_…` 형식과 다르므로, 5.1의 수집 로직을 고치더라도 **이 테스트만 따로 누락됩니다.** legacy에는 `_`가 있었으므로 **prod로 옮기면서 생긴 회귀**입니다 (부록 A.6의 diff). `"/Test3_Replace_Lib_here_"`로 고쳐야 합니다.
- 주석의 오래된 정보:
  - L34의 주석은 `Test2`라고 적혀 있지만 실제 기록은 Test3입니다.
  - L19의 `perfFunctions.il:189-211` 참조는 legacy의 줄 번호입니다. prod의 perfFunctions.il에는 changeRefLib가 없습니다.
- 번호: **Test3** (legacy와 같음). `PERF_TESTS`에서는 7번째입니다.

---

## 5. 공통 문제 (prod 기준으로 다시 정리)

### 5.1 perf_summary의 결과 수집이 동작하지 않음 (확인된 사실)

`perf_summary.sh`의 `export_metrics`는 다음 이름으로 결과 파일을 찾습니다.
```
result/<uniqueid>/Test<N>_<lib>_<mode>_<uniqueid>.log      (N = PERF_TESTS에서의 순서)
```
그런데 prod 템플릿이 쓰는 이름은 이렇습니다.
```
result/<uniqueid>/Test<N>_<lib>_<mode>_<virtuosoVer()>.log  (N = legacy 번호)
```
1. **접미사가 다릅니다** (uniqueid ≠ Virtuoso 버전 문자열). 그래서 **모든 테스트가 "Log not found"로 빠지고** `perf_metrics/*.json`에 아무것도 기록되지 않습니다.
2. 접미사를 맞추더라도 번호가 어긋납니다. `PERF_TESTS`가 changeLibRef를 맨 뒤에 둔 반면 템플릿은 legacy 번호(changeRefLib=3)를 씁니다.
3. changeLibRef 템플릿은 lib 이름 뒤의 `_`가 빠져서 `Test3_<lib><mode>_…`로 기록합니다 (4.7). 1과 2를 고쳐도 이 테스트만 누락됩니다.

참고로 summary의 첫 부분(`perf_summary.txt`)은 `perf_run_single.sh`가 기록한 **`timing.tsv`**(쉘에서 잰 시간, Virtuoso 기동 시간 포함)를 사용하므로 정상적으로 동작합니다. 즉 지금 prod에서 보이는 시간은 **SKILL이 측정한 작업 시간이 아니라 vse_run 전체의 실행 시간**입니다.

**수정안** (둘 중 하나, 또는 둘 다):
- (a) `PERF_TESTS`를 legacy 순서로 맞춥니다: `checkHier renameRefLib changeLibRef replace deleteAllMarker copyHierToEmpty copyHierToNonEmpty`. 이렇게 하면 템플릿 번호(changeLibRef=Test3 확인됨)와 1~7이 일치합니다.
- (b) `export_metrics`가 `Test${N}_${ll}_${mm}_*.log`처럼 **glob으로 찾고**, 버전 문자열은 `tool_ver` 필드로 기록합니다.

### 5.2 시간 단위
`compareTime`은 **초 단위**입니다. legacy README에 "time in seconds"라고 명시되어 있습니다. `perf_summary.sh`는 이 값을 `elapsed_ms`로 기록하므로 **필드 이름과 단위가 틀립니다.**

### 5.3 run 사이의 워크스페이스 초기화가 없음

legacy `main.template`은 **매 replay 전에** managed 워크스페이스를 원복했습니다(`legacy:main.template` L123–164, 원문은 부록 A.2).
```bash
xlp4 opened -a //depot/VSM/cadence_perf/rev01/...   → 열린 파일이 없어질 때까지 워크스페이스별로 xlp4 revert -C <ws>
xlp4 sync ...                                       → "Can't clobber writable file" 목록을 모아서 xlp4 -x <list> sync -f
```
우리 `perf_run_single.sh`에는 이 단계가 **없습니다.** 그래서 다음 문제가 생깁니다.

| 테스트 | 2회차 run 이후에 생기는 일 |
|---|---|
| checkHier, deleteAllMarker, replace | 이전 run에서 체크아웃한 셀이 그대로 남은 상태에서 시작 |
| renameRefLib | 되돌린 뒤에도 ORIGIN이 체크아웃된 상태로 남음 |
| copyHierToNonEmpty | 이전 run에서 덮어쓴 CHIP과 체크아웃 상태가 남음 |
| copyHierToEmpty | 복사 후 정리에만 의존. 이전 run이 중간에 실패하면 비어 있지 않은 COPY에서 시작 |
| changeLibRef | managed는 템플릿의 revert에 의존 (submit 방식이라 depot 히스토리가 쌓임). **unmanaged는 하드코딩 경로 때문에 원복에 실패할 가능성이 높음** |

legacy도 **unmanaged 모드에서는 초기화를 하지 않았습니다.** unmanaged에서는 copyHierToNonEmpty만 영향을 받습니다(이전 run의 결과로 덮어써진 상태에서 시작). 같은 내용으로 다시 덮어쓰는 것이므로 측정 조건의 차이는 작다고 볼 수 있습니다.

**수정안**: managed 모드일 때 `perf_run_single.sh`에서 vse_run 직전에 legacy와 같은 revert와 sync를 실행합니다. 범위는 워크스페이스 자신으로 한정합니다(`xlp4 -c <ws_name> revert //...`, `xlp4 -c <ws_name> sync -f`).

### 5.4 `-nograph` (prod common.sh)
prod는 `vse_run … -nograph`로 실행합니다. 템플릿은 `deOpenCellView`(창 열기), `hiCloseWindow`, `schHiCheckHier`, `schHiReplace`, `geHiDeleteAllMarker`, `ddsHiCloseData` 같은 **GUI 폼과 창 함수**에 의존합니다. nograph 모드에서 이 함수들이 정상 동작하는지 **CDS_log로 확인**해야 합니다. legacy는 `-nograph` 없이 실행했습니다.

### 5.5 배포 형태와 저장소의 차이
prod 동작에 필수인 파일들이 **저장소에서 추적되지 않습니다.**
- `GenerateReplayScript/` 전체 (gitignore 대상)
- `code/.cdsenv`, `perfFunctions.il`, `functions.il`, `date_virtuosoVer.il`, revert 관련 `.il`

템플릿을 고쳐도 리뷰와 이력이 남지 않습니다. 이번처럼 **손상된 사본을 정본으로 착각하는** 일도 생길 수 있습니다. 민감한 경로가 들어 있지 않다면 저장소에서 추적하는 것을 권장합니다.

### 5.6 기타
- `hiFormDone(schSRCForm)` 중복 호출 (모든 템플릿): `LoadSamsungEnv`가 이미 폼을 닫습니다.
- `date_virtuosoVer.il` 로드와 `date_virtuosoVer.txt` 기록은 prod에서 쓰이지 않는 잔재입니다.

---

## 6. 라이브러리 구성 최적화 (prod 정의 반영)

### 6.1 비용
lib 하나가 추가될 때마다 `gdp create library --from` → config 추가 → build(1차 sync) → `mv oa` + `chmod` + `cdsinfo.tag` 수정 → `xlp4 sync -f`(2차 sync)가 실행됩니다. 디스크 사용량은 2배가 됩니다.

### 6.2 테스트별 판단

| 테스트 | 현재 | 필수 | 제거·축소 후보 | 근거 |
|---|---|---|---|---|
| checkHier | `<lib>` | `<lib>` | – | |
| renameRefLib | `<lib> _ORIGIN _TARGET` | `_ORIGIN`, `_TARGET` | **`<lib>`** | `renameRefLib`가 두 lib의 spec을 만들므로 둘 다 필수. BM01은 측정 밖에서 열기만 함 |
| replace | `<lib>` | `<lib>` | – | |
| deleteAllMarker | `<lib>` | `<lib>` | – | |
| copyHierToEmpty | `<lib> _CHIP _COPY` | `<lib>`, `_COPY` | **`_CHIP`** | 템플릿에서 참조하지 않음 (legacy는 모든 lib를 담은 단일 워크스페이스였던 데서 넘어온 흔적으로 보임) |
| copyHierToNonEmpty | `<lib> _CHIP` | 둘 다 | `_CHIP` 축소 | 덮어쓰는 셀 수가 비용을 결정. 계층과 겹치는 셀만 남겨도 됨 |
| changeLibRef | `<lib> _ORIGIN _TARGET _MIX` | `_MIX` | **`<lib>`**, 그리고 MIX가 참조하지 않는 lib | `'ALL`→MIX 규칙이라 toLib는 MIX 자신. ORIGIN/TARGET은 MIX가 **변경 전에 참조하는 lib라서 바인딩에 필요할 때만** 필요 |

`<lib>`(BM01 계열, FULLCHIP급)를 빼는 것이 효과가 가장 큽니다. prod에서는 renameRefLib의 측정 구간이 이미 정리되었으므로, 남은 이점은 **init과 teardown 비용 감소**입니다.

**`<lib>`을 제거하는 방법**: `LoadSamsungEnv`는 셀뷰를 필요로 하지 않으므로(3.2), openDesign과 창 닫기 두 줄을 없애거나 대상 lib의 작은 셀을 열도록 바꾸면 됩니다. 다만 `ddAutoCtlSetVars`와 DM 컨텍스트를 초기화할 때 셀뷰가 열려 있어야 하는지는 실행해서 확인해야 합니다.

### 6.3 DRAMLIB (신규)
legacy 프로젝트 구성(`legacy:code/ICM_createProj.sh`, 부록 A.3)에는 DRAMLIB가 포함되어 있습니다. 템플릿 3종이 `HierCopy(... list("DRAMLIB"))`로 DRAMLIB를 전제합니다. 우리 구성에서는 **`-common DRAMLIB`를 줘야만** 포함됩니다. `-common` 옵션이 원래 이 용도로 만들어진 것으로 보이며, 기본값에 넣거나 문서에 필수 옵션으로 명시하는 것을 권장합니다. DRAMLIB가 빠지면 다음 문제가 생깁니다.
- checkHier, deleteAllMarker: 바인딩되지 않은 인스턴스 때문에 에러와 마커 구성이 legacy와 달라짐
- copyHier 계열: 복사하는 계층이 달라짐

### 6.4 의존성 확인 방법
prod `perfFunctions.il`의 `listHierLibCells`를 CIW에서 실행하면 계층이 실제로 어떤 lib를 참조하는지 볼 수 있습니다.
```skill
load("../../code/perfFunctions.il")
foreach(p listHierLibCells("BM01" "VP_FULLCHIP") println(p))   ; "lib/cell" 목록 → lib 이름만 모으면 의존 lib 집합
```
`_MIX`나 `_ORIGIN`도 같은 방식으로 확인할 수 있습니다. 셀 단위로 확인하려면 lib의 셀마다 실행해야 합니다.

---

## 7. 권장 조치 우선순위 (v2)

| 순위 | 조치 | 위치 | 근거 |
|---|---|---|---|
| 1 | `export_metrics`의 결과 파일 탐색 수정 (glob 또는 접미사 통일) + `PERF_TESTS`를 legacy 순서로 정렬 | `code/perf_summary.sh`, `code/env.sh` | 지금은 SKILL 측정값이 **하나도 수집되지 않음** (5.1) |
| 2 | managed run 전 워크스페이스 원복 (revert, sync) | `code/perf_run_single.sh` | legacy에 있던 단계가 빠져서 반복 run의 조건이 달라짐 (5.3) |
| 3 | changeLibRef 결과 파일 이름의 `_` 누락 수정, unmanaged revert의 하드코딩 경로 교체 | prod `changeLibRef` 템플릿, `changeRefLib_revertICM.il_mcr_modified` | 이 테스트만 수집에서 빠지고, unmanaged 2회차부터 측정값이 왜곡됨 (4.7) |
| 4 | `-nograph`에서 GUI 폼 함수가 동작하는지 CDS_log로 확인 | prod `common.sh` | 측정 성립 여부 (5.4) |
| 5 | DRAMLIB를 기본 lib 구성에 포함 | `code/perf_init.sh` 또는 기본 `-common` | legacy와 같은 계층 조건 (6.3) |
| 6 | `elapsed_ms`를 초 단위에 맞게 수정 | `code/perf_summary.sh` | 단위 오류 (5.2) |
| 7 | 템플릿과 SKILL 파일을 저장소에서 추적 | `.gitignore`, `GenerateReplayScript/`, `code/*.il` | 배포 형태와 저장소 간의 차이 (5.5) |
| 8 | lib 구성 최적화 (`<lib>` 제거, copyHierToEmpty의 `_CHIP` 제거) | `code/perf_init.sh` + 템플릿 | init과 teardown 비용 (6.2) |
| 9 | copyHierToEmpty의 `if(` / `)` 두 줄에 `\i` 접두어 추가 | prod `copyHierToEmpty` 템플릿 | 로그 형식 replay에서 `if`가 무시되면 unmanaged에서도 ICM 삭제가 실행됨 (4.5) |
| 10 | perf_main.sh의 M1, M3, M6 정리 | `perf_main.sh` | 정확성 |

---

## 부록 A. legacy / prod 인용

본문의 근거가 되는 원문입니다. diff는 `-` = legacy, `+` = prod이며, 템플릿 diff는 prod의 줄머리 `\i ` 접두어를 제거한 뒤 비교했습니다.

### A.1 테스트 번호의 출처 — `legacy:main.pl` L88–90

```perl
if($mode=~ /^$/) {
    @templates = ('checkHier','renameRefLib','changeRefLib','replace','deleteAllMarker','copyHierToNonEmpty','copyHierToEmpty');
}
```
템플릿 안의 `Test<N>` 번호는 이 목록에서 copyHier 두 개의 순서만 바꾼 것과 같습니다: checkHier=1, renameRefLib=2, changeRefLib=3, replace=4, deleteAllMarker=5, copyHierToEmpty=6, copyHierToNonEmpty=7.

### A.2 매 replay 전 managed 원복 — `legacy:main.template`

L112–117 (모드 기록):
```bash
for managed in ${man_folders[@]}; do
    for replay in ${replay_files[@]}; do
        ori_path=$(pwd)
        testdir=$(pwd)/$managed/$ws_name  # absolute path
	rm -f code/managed.txt
	echo $managed > code/managed.txt
```

L123–164 (워크스페이스 원복):
```bash
			# init the workspace (making sure no opened files and sync the files to latest)
			if [[ $managed == "managed" ]]; then
				# revert opened files
				while true; do
					mapfile -t lines < <(xlp4 opened -a //depot/VSM/cadence_perf/rev01/...)
					if [ ${#lines[@]} -eq 0 ]; then
						echo "No opened files found. Done."
						break
					fi
					workspaces=($(printf "%s\n" "${lines[@]}" | awk -F@ '{print $2}' | awk '{print $1}' | sort -u))
					for ws in "${workspaces[@]}"; do
						echo "Reverting all files in workspace: $ws"
						xlp4 revert -C "$ws" //depot/VSM/cadence_perf/rev01/... 2>/dev/null
					done
					echo "Rechecking..."
				done

				# sync the files to latest
				xlp4 sync ... 2>&1 | grep "Can't clobber writable file" | sed "s/^Can't clobber writable file //" > $clobber_file
				if [[ $(wc -l < $clobber_file) -gt 0 ]]; then
					xlp4 -x $clobber_file sync -f
				fi
				rm -rf $clobber_file
			fi

            # Run virtuoso replay (Cadence Virtuoso)
      	    vse_run -v $virtuoso_version -replay ../../code/replay/$replay -log ../../CDS_log/$replay"_"$managed".log"
```
(echo 줄과 주석 처리된 `gdp rebuild` 줄은 생략)

### A.3 legacy 프로젝트의 lib 구성 — `legacy:code/ICM_createProj.sh` L10–11

```bash
# libs=(DRAMLIB BM01 BM01_CHIP BM01_COPY BM01_ORIGIN BM01_TARGET BM02 BM02_CHIP BM02_COPY BM02_ORIGIN BM02_TARGET BM03 BM03_CHIP BM03_COPY BM03_ORIGIN BM03_TARGET)
libs=(DRAMLIB BM02_CHIP BM02_TARGET)
```
전체 구성(주석 처리된 줄)과 부분 구성 모두 **DRAMLIB로 시작**합니다. 모든 lib를 담은 **단일 워크스페이스**를 전제로 합니다.

### A.4 시간 단위 — `legacy:README_PERF` L46–47

```
Test7_BM01_managed_1775604261_IC25.1-64b.ISR5.EA.23.log
Test7_BM01. Performance Copy Hierarchy to Non-empty Library managed time <time in seconds>
```

### A.5 `HierCopy`의 skip 목록 처리 — `perfFunctions.il`

```diff
     ;; skip list
-    skip = gdmCreateSpecList()
-    foreach(lib skipLibs
-      gdmAddSpecToSpecList(
-        gdmCreateSpecFromDDID(ddGetObj(lib))
-        skip
+    skip = nil
+
+    when(skipLibs
+      skip = gdmCreateSpecList()
+      foreach(lib skipLibs
+        let((libObj)
+          libObj = ddGetObj(lib)
+          when(libObj
+            gdmAddSpecToSpecList(
+              gdmCreateSpecFromDDID(libObj)
+              skip
+            )
+          )
+        )
       )
     )
     ;; Hier copy
     ccpCopyDesign(src dst t 'CCP_EXPAND_ALL skip nil list("schematic" "symbol"))
```
legacy는 cds.lib에 없는 lib(예: DRAMLIB)가 skip 목록에 있으면 `gdmCreateSpecFromDDID(nil)`에서 에러가 납니다. prod는 그 lib를 **조용히 제외**합니다.

### A.6 템플릿 diff (legacy → prod)

**renameRefLib** — 측정 구간은 같고, 결과 기록 방식만 바뀌었습니다:
```diff
 ;# Open Design
+;# [EQUIV] t1 을 여기서 제거했다. legacy renameRefLib:12 는 openDesign 을
+;#         측정 구간 밖에 둔다. t1 은 연산 직전으로 복원 (legacy :25).
 ...
 t2=getCurrentTime()
 final=compareTime(t2 t1)
-system(strcat("mkdir -p " result_path date_virtuosoVer(code_path) ))
-inport = infile(strcat(code_path "managed.txt"))
-gets(managed inport)
-managed = substring(managed 1 strlen(managed)-1)
-close(inport)
-fd=outfile(strcat(result_path date_virtuosoVer(code_path) "/Test2_Replace_Lib_here_" managed "_" date_virtuosoVer(code_path) ".log") "w")
+managed=""
+unique_result_folder = strcat( result_path CDS_PV_REG_RES_NO)
+system(strcat("mkdir -p " unique_result_folder ))
+fd=outfile(strcat( unique_result_folder "/Test2_Replace_Lib_here_" managed "_" virtuosoVer() ".log") "w")
```
copyHierToNonEmpty도 같은 형태입니다(`[EQUIV]` 주석 + 결과 기록부 교체). 나머지 템플릿도 결과 기록부는 똑같이 바뀌었습니다.

**changeRefLib → changeLibRef** — 함수 정의 로드가 추가되었고, **결과 파일 이름에서 `_`가 빠졌습니다**:
```diff
 load( strcat( code_path "date_virtuosoVer.il"))
+load( strcat( code_path "changeRefLib.il_mcr"))
+load( strcat( code_path "changeRefLib_revertICM.il_mcr_modified"))
 ...
-fd=outfile(strcat(result_path date_virtuosoVer(code_path) "/Test3_Replace_Lib_here_" managed "_" date_virtuosoVer(code_path) ".log") "w")
+fd=outfile(strcat(unique_result_folder "/Test3_Replace_Lib_here" managed "_" virtuosoVer() ".log") "w")
```

### A.7 `createReplay.pl` (legacy → prod, 주석과 빈 줄 제외)

```diff
+$manage = "";
+$result = "";
 GetOptions("lib=s" => \$_library,
 	   "cell=s" => \$_cell,
-	   "template=s" => \$template
+	   "template=s" => \$template,
+       "manage=s" => \$manage,
+       "result=s" => \$result
     );
 ...
-    open(replayOut, ">replay.$replayMid$cnt.au");
 ...
+    open(replayOut, ">replay.$replayMid\_$lib\_$manage.au");
 ...
-        s/(openDesign\()(.*\))/$1$lcv $2/g;
+        s/(openDesign\()\s*"a"\s*(\))/$1$lcv "a" $2/g;
 ...
+        s/managed=""/managed="$manage"/g;
+        s/CDS_PV_REG_RES_NO/"$result"/g;
```
