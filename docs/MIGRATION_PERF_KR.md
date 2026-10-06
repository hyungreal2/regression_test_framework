# MIGRATION — perf (`2_perf_sp` → `suites/perf`)

[MIGRATION_COMMON_KR.md](MIGRATION_COMMON_KR.md)을 먼저 읽습니다. 이 문서는 perf에만 해당하는 대응표, 의도한 차이,
판단 기준, 검증을 다룹니다.

---

## 1. 파일 대응표

| legacy (`2_perf_sp/`) | 저장소 | 분류 | 반영 방법 |
|---|---|---|---|
| `GenerateReplayScript/checkHier`, `renameRefLib`, `replace`, `deleteAllMarker`, `copyHierToNonEmpty`, `copyHierToEmpty` | `suites/perf/GenerateReplayScript/` 같은 이름 | 데이터 | 테스트 내용만 반영, 틀은 저장소 유지(§2.1, §4) |
| `GenerateReplayScript/changeRefLib` | `suites/perf/GenerateReplayScript/changeLibRef` | 데이터 | 이름이 다름(테스트 이름 통일). 내용 반영은 위와 같음 |
| `GenerateReplayScript/createReplay.pl` | 같은 이름 | 데이터 | 저장소 확장 유지(§4 P6~P8) |
| `GenerateReplayScript/test.spec` | 같은 이름 | 데이터 | 그대로(현재 같음) |
| `GenerateReplayScript/lib_cell_view.txt` | `shared/code/env.sh`의 `PERF_LIBS`, `PERF_CELLS` | 사이트/설정 | 쌍을 같은 순서로 옮김. 파일 사본은 `archive/perf/` |
| `GenerateReplayScript/copyHierToEmpty_Test`, `renameRefLib_debug`, `1`, `lcv.txt` | — | 백업·생성물 | 반영하지 않음 |
| `code/perfFunctions.il` | 같은 이름 | 데이터 | 저장소 버전 유지 + legacy′ 변경 반영(§4 P9) |
| `code/functions.il`, `code/.cdsenv` | 같은 이름 | 데이터 | 그대로(현재 같음). perf 전용(cico·func의 `.cdsenv`와 다름) |
| `code/date_virtuosoVer.il` | 같은 이름 | 데이터 | 저장소에 `virtuosoVer()` 추가됨(§4 P5) |
| `code/cdsLibMgr.il` | 배치하지 않음 (`CDS_LIB_MGR` 링크) | 데이터 | 반영하지 않음 |
| `code/validate.il`, `code/sge_copyLibrary.il`, `code/.cdsinit`, `code/.cdslocal_project`, `code/.cdsenv2`, `code/1` | — | 미사용 | perf 템플릿이 로드하지 않음. 템플릿이 로드하기 시작하면 데이터로 추가 |
| `main.pl` | `perf_main.sh` (옵션, 조합 구성) + `code/perf_generate_replay.sh` | 프레임워크 | 동작만(§3) |
| `main.template` → 생성된 `main.sh` | `code/perf_run_single.sh` (+ `perf_main.sh` 3단계) | 프레임워크 | 동작만(§3) |
| `code/ICM_createProj.sh`, `README_CREATENEWMANWS` | `code/perf_init.sh` | 프레임워크 | 동작만(§3) |
| `code/ICM_deleteProj.sh`, `code/teardown.sh` | `code/perf_teardown.sh`, `code/perf_teardown_all.sh` | 프레임워크 | 동작만 |
| `code/summary.sh` | `code/perf_summary.sh`의 `write_legacy_summary` | 프레임워크 | 형식 유지(§3) |
| `code/init.sh`, `code/teardown.sh_paul`, `main.sh_ORG_*`, `main.template_ORG_*`, `README_PERF` | — | 백업·설명 | 반영하지 않음 |

`code/changeRefLib.il_mcr`, `code/changeRefLib_revertICM.il_mcr_modified`는 prod에서 추가된 SKILL로, changeLibRef 템플릿이 로드합니다(§4 P4).

---

## 2. 데이터 파일 규칙

### 2.1 replay 템플릿
legacy 템플릿과 저장소 템플릿의 **명령 줄**은 같아야 합니다. 저장소는 아래 틀이 다릅니다.

legacy (`2_perf_sp/GenerateReplayScript/checkHier`, 끝부분 발췌):
```
t2=getCurrentTime()
final=compareTime(t2 t1)
system(strcat("mkdir -p " result_path date_virtuosoVer(code_path) ))

inport = infile(strcat(code_path "managed.txt"))
gets(managed inport)
managed = substring(managed 1 strlen(managed)-1)
close(inport)

fd=outfile(strcat(result_path date_virtuosoVer(code_path) "/Test1_Replace_Lib_here_" managed "_" date_virtuosoVer(code_path) ".log") "w")
fprintf(fd "Test1_Replace_Lib_here. Performance Edit-Check-Hierarchy %s time %d\n" managed final)
```
저장소 (`suites/perf/GenerateReplayScript/checkHier`, 같은 부분):
```
\i t2=getCurrentTime()
\i final=compareTime(t2 t1)
\i 
\i managed=""
\i 
\i unique_result_folder = strcat( result_path CDS_PV_REG_RES_NO)
\i system(strcat("mkdir -p " unique_result_folder ))
\i fd=outfile(strcat(unique_result_folder "/Test1_Replace_Lib_here_" managed "_" virtuosoVer() ".log") "w")
\i fprintf(fd "Test1_Replace_Lib_here. Performance Edit-Check-Hierarchy %s time %d\n" managed final)
```

legacy′ 템플릿을 반영할 때:
1. changeLibRef를 뺀 6개는 replay 로그 형식입니다. 첫 세 줄은 `\o `, `\p `, 빈 줄이고 그 뒤 **모든 줄** 앞에 `\i `를 붙입니다(빈 줄은 `\i `).
   **changeLibRef는 legacy처럼 일반 SKILL 줄**(머리 줄과 `\i ` 없음)입니다. 템플릿마다 현재 형식을 그대로 따릅니다.
2. `managed.txt`를 읽는 4줄(`inport = ...` ~ `close(inport)`)은 `managed=""` 한 줄로 둡니다. `createReplay.pl -manage`가 값을 채웁니다.
3. 결과 폴더는 `unique_result_folder = strcat( result_path CDS_PV_REG_RES_NO)` + `system(strcat("mkdir -p " unique_result_folder ))`로,
   결과 파일 이름의 버전은 `virtuosoVer()`로 둡니다. `createReplay.pl -result`가 `CDS_PV_REG_RES_NO`를 채웁니다.
4. `openDesign( "a")` 형태(라이브러리·셀 인자 없이 `"a"`만)를 유지합니다. `createReplay.pl`이 이 형태일 때만 `lcv.txt`의 lib/cell을 넣습니다.
5. `Test<N>_Replace_Lib_here`, `<LIB>_COPY` 같은 자리표시자는 legacy와 같게 둡니다(`createReplay.pl`이 치환).
6. 그 밖의 명령 줄 변경(GUI 동작, 측정 구간, 결과 문구)은 legacy′ 그대로 반영합니다.

### 2.2 테스트 이름과 라이브러리
- 테스트(템플릿) 목록과 순서는 `shared/code/env.sh`의 `PERF_TESTS`입니다. 순서는 **템플릿 안의 `Test<N>_Replace_Lib_here` 번호**
  (checkHier=1, renameRefLib=2, changeLibRef=3, replace=4, deleteAllMarker=5, copyHierToEmpty=6, copyHierToNonEmpty=7)입니다.
  legacy `main.pl`의 `@templates`는 copyHierToNonEmpty를 copyHierToEmpty 앞에 두지만, 결과 파일 이름과 추세 데이터는 템플릿 번호를
  쓰므로 번호 순서를 따릅니다. `changeRefLib`는 `changeLibRef`로 부릅니다. 새 템플릿이 생기면 그 템플릿의 번호 위치에 추가합니다.
- 각 테스트가 워크스페이스에 넣는 라이브러리는 `code/perf_init.sh`의 `perf_libs()`입니다
  (`<LIB>`, `<LIB>_ORIGIN`, `<LIB>_TARGET`, `<LIB>_MIX`, `<LIB>_CHIP`, `<LIB>_COPY` + 모든 워크스페이스에 `PERF_BASE_LIBS`(DRAMLIB)).
  legacy는 하나의 워크스페이스에 모든 라이브러리를 넣었습니다(`ICM_createProj.sh`의 `libs=`). legacy′ 템플릿이 새 라이브러리 이름을
  쓰기 시작하면 `perf_libs()`에 추가합니다. 모든 템플릿이 쓰는 라이브러리면 `PERF_BASE_LIBS`에 넣습니다.
- 라이브러리·셀 쌍(`lib_cell_view.txt`, `main.pl -lib/-cell`)은 `PERF_LIBS` / `PERF_CELLS`에 같은 순서로 둡니다.

### 2.3 SKILL
- `perfFunctions.il`: legacy′의 변경을 반영하되 §4 P9의 저장소 수정은 유지합니다. legacy′에서 `changeRefLib`, `Exec`,
  `changeRefLib_revertICM`이 바뀌면 `code/changeRefLib.il_mcr`(앞의 하나)와 `code/changeRefLib_revertICM.il_mcr_modified`(뒤의 둘)에 반영합니다.
- `date_virtuosoVer.il`: legacy′의 `date_virtuosoVer` 변경은 반영하고, 저장소에만 있는 `virtuosoVer()` 프로시저는 남깁니다.

---

## 3. 프레임워크 대응 (동작만 옮김)

| legacy 동작 | 저장소에서의 구현 |
|---|---|
| `main.pl -lib "<libs>" -cell "<cells>" -mode "<templates>" -manage "<modes>" -version <ver>` | `perf_main.sh -lib -test -mode -version` (`-common`, `-j`, `-d`, `-t`, `-no-run`, `-auto-init`, `-gen-replay` 추가) |
| `main.pl`이 `rm replay*.au` 후 템플릿마다 `createReplay.pl` (라이브러리 여러 개를 한 번에) | `perf_generate_replay.sh`가 조합(템플릿×라이브러리×모드)마다 `createReplay.pl -lib -cell -template -manage -result`. 그 조합의 이전 출력만 지움 |
| `main.pl`이 `main.template`의 `man_folders`, `virtuoso_version`, `replay_files`를 채워 `main.sh` 생성 | `perf_main.sh`가 조합 목록을 만들고 `perf_run_single.sh`를 병렬 실행 |
| 워크스페이스 하나(`cadence_perf_ws`)를 `ICM_createProj.sh`로 수동 생성, UNMANAGED는 `README_CREATENEWMANWS` 절차로 수동 복사 | `perf_init.sh`가 조합마다 project → variant → libtype → config → library(`--location=oa/{{library}}`) → build workspace, UNMANAGED 자동 구성(§3.1) |
| `managed.txt`에 현재 모드를 써서 replay가 읽음 | replay에 `managed="<mode>"`를 생성 시 치환 |
| MANAGED 실행 전: 열린 파일 revert(반복), `xlp4 sync`, "Can't clobber" 파일만 `sync -f` | 같음(`perf_run_single.sh`의 `reset_managed_ws`). sync가 다른 이유로 실패하면 측정하지 않고 실패 |
| UNMANAGED 실행 전: 초기화 없음 | `.oa_pristine`에서 `rsync -a --delete`로 복원(§3.1) |
| `vse_run -v <ver> -replay ... -log CDS_log/<replay>_<mode>.log` | `run_vse` (`-nograph`), 로그 `CDS_log/<id>/<test>_<lib>_<mode>.log`, 측정 시간 `timing.tsv` |
| `summary.sh <폴더>`: 결과 폴더의 파일마다 이름 → 내용 → `" "` | `perf_summary.sh`의 `write_legacy_summary` (같은 형식, `result/<id>/summary.txt`) + 시간 표 + `perf_metrics/` |
| `ICM_deleteProj.sh -prefix`, `teardown.sh` | `perf_main.sh -no-run -t` (로컬 워크스페이스 기준), `perf_teardown_all.sh` (GDP 기준 고아 정리) |

### 3.1 UNMANAGED 구성과 복원
`perf_init.sh`가 MANAGED를 만든 뒤:
1. `cds.libicm` → UNMANAGED `cds.lib`로 복사하고 경로의 `WORKSPACES_MANAGED`를 `WORKSPACES_UNMANAGED`로 바꿈
2. MANAGED `oa/`를 UNMANAGED로 옮기고 `chmod -R ug+w`
3. 모든 `cdsinfo.tag`의 `DMTYPE p4` → `DMTYPE none`
4. `cp -a oa .oa_pristine` (복원 원본)
5. MANAGED는 `xlp4 sync -f`로 `oa/`를 다시 받음

legacy′의 `README_CREATENEWMANWS`(수동 절차)가 바뀌면 1~3을 그에 맞게 고칩니다. 4·5와 실행 전 복원은 저장소 추가 동작이므로 유지합니다.

---

## 4. 의도한 차이 (되돌리지 말 것)

| # | 위치 | legacy | 저장소 | 이유 |
|---|---|---|---|---|
| P1 | 템플릿 형식 | 일반 SKILL 줄 (checkHier만 `\o`/`\p` 머리) | changeLibRef를 뺀 6개는 `\o`/`\p` 머리 + 줄마다 `\i `, changeLibRef는 일반 SKILL 줄 | prod에서 바꾼 형식. 실행 명령은 같음. changeLibRef 형식 통일은 실제 ICM 환경 확인 전까지 보류 |
| P2 | 현재 모드 | `managed.txt` 파일 읽기 | `managed=""` → 생성 시 치환 | 병렬 실행 시 파일 경쟁 제거 |
| P3 | 결과 폴더·버전 | `result_path date_virtuosoVer(code_path)`, 파일 이름에 `date_virtuosoVer` | `unique_result_folder`(`CDS_PV_REG_RES_NO` = 실행 id), `virtuosoVer()` | 실행마다 고유한 결과 폴더 |
| P4 | changeLibRef 로드 | 함수가 `perfFunctions.il` 안에 있음 | `load( strcat( code_path "changeRefLib.il_mcr"))`, `load( strcat( code_path "changeRefLib_revertICM.il_mcr_modified"))` | legacy `perfFunctions.il`의 `changeRefLib`, `Exec`, `changeRefLib_revertICM`을 prod가 이 두 파일로 옮김. 템플릿 명령 줄은 legacy와 같음. **§5 G2의 유일한 허용 차이** |
| P5 | `date_virtuosoVer.il` | `date_virtuosoVer`만 | `virtuosoVer()` 추가 | P3에서 사용 |
| P6 | `createReplay.pl` 옵션 | `-lib -cell -template` | `-manage <mode>`, `-result <id>` 추가 | P2·P3 치환 |
| P7 | `createReplay.pl` 출력 이름 | `replay.<템플릿><번호>.au` (라이브러리 순번) | `replay.<템플릿>_<lib>_<mode>.au` | 조합별 생성 |
| P8 | `createReplay.pl` openDesign 치환 | `s/(openDesign\()(.*\))/$1$lcv $2/` | `s/(openDesign\()\s*"a"\s*(\))/$1$lcv "a" $2/` | 인자가 이미 있는 openDesign에 lib/cell이 중복으로 들어가지 않게 함 |
| P9 | `perfFunctions.il` | `HierCopy`가 빈 skip 목록도 spec 목록으로, 없는 라이브러리도 그대로 추가. `changeRefLib`·`Exec`·`changeRefLib_revertICM` 포함 | `HierCopy`는 비면 `nil`, 없는 라이브러리는 건너뜀. 세 함수는 P4의 두 파일로 이동 | 없는 라이브러리로 `ccpCopyDesign`이 실패하던 문제. legacy′가 세 함수를 고치면 P4의 파일에 반영 |
| P10 | 템플릿 이름 | `changeRefLib` | `changeLibRef` | 테스트 이름 통일(func의 mode 이름과 같음) |
| P11 | changeLibRef / copyHierToEmpty 템플릿 | — | `;# [EQUIV]` 주석으로 legacy와 같게 되돌린 지점 설명, 비활성 코드는 주석으로 보존 | 주석만 다름. 명령 줄은 legacy와 같음 |
| P12 | 워크스페이스 | 하나를 계속 사용 | 조합마다 하나, `WORKSPACES_MANAGED/UNMANAGED/<perf_<test>_<lib>_<id>>` | 조합별 독립 측정 |
| P13 | 실행 전 복원 | MANAGED만 | MANAGED + UNMANAGED(`.oa_pristine`) | 매 측정을 같은 데이터에서 시작 |
| P14 | 전역 replay 삭제 | `rm replay*.au` | 조합별 이전 출력만 삭제 | 동시 실행 시 다른 실행의 replay를 지우지 않음 |

---

## 5. 검증

### 5.1 G2 — 템플릿 1:1 (정규화 비교)
legacy′와 저장소의 `createReplay.pl`로 7개 템플릿 × `PERF_LIBS` × 두 모드를 생성하고, 의도한 틀 차이(P1~P3)와 주석을 정규화한 뒤
비교합니다. 남는 차이는 **changeLibRef의 `load` 2줄(P4)뿐**이어야 합니다(현재: 42개 중 6개, 모두 P4).

```bash
# usage: bash gate.sh <legacy′ 2_perf_sp> <저장소 suites/perf> <작업 디렉터리>
L="$1"; R="$2"; S="$3"
LIBS=(BM01 BM02 BM03); CELLS=(VP_FULLCHIP FULLCHIP XE_FULLCHIP_BASE)     # = PERF_LIBS / PERF_CELLS
TESTS="checkHier:checkHier renameRefLib:renameRefLib changeRefLib:changeLibRef replace:replace deleteAllMarker:deleteAllMarker copyHierToNonEmpty:copyHierToNonEmpty copyHierToEmpty:copyHierToEmpty"
mkdir -p "$S" && rm -rf "$S/L" "$S/R" && cp -r "$L/GenerateReplayScript" "$S/L" && cp -r "$R/GenerateReplayScript" "$S/R" || { echo "setup failed"; exit 2; }
( cd "$S/L" && for t in $TESTS; do perl createReplay.pl -lib "${LIBS[*]}" -cell "${CELLS[*]}" -template "${t%%:*}"; done ) >/dev/null 2>&1
( cd "$S/R" && for t in $TESTS; do for i in 0 1 2; do for m in managed unmanaged; do
    perl createReplay.pl -lib "${LIBS[$i]}" -cell "${CELLS[$i]}" -template "${t#*:}" -manage "$m" -result RID; done; done; done ) >/dev/null 2>&1
# legacy: managed.txt 읽기와 date_virtuosoVer 결과 경로 → 저장소 형태
norm_l(){ sed 's/\r$//' "$1" | sed -E \
  -e 's/^\\i ?//' -e '/^\\[op] *$/d' \
  -e '/^inport = infile\(strcat\(code_path "managed.txt"\)\)/,/^close\(inport\)/d' \
  -e '/^system\(strcat\("mkdir -p " result_path date_virtuosoVer\(code_path\) \)\) *$/d' \
  -e 's/strcat\(result_path date_virtuosoVer\(code_path\) /strcat(unique_result_folder /' \
  -e 's/date_virtuosoVer\(code_path\) "\.log"/virtuosoVer() ".log"/' \
  -e '/^ *;/d' ; }
# 저장소: "\i ", 생성된 managed/결과 폴더 줄, 주석 제거
norm_r(){ sed 's/\r$//' "$1" | sed -E \
  -e 's/^\\i ?//' -e '/^\\[op] *$/d' -e '/^managed="(un)?managed"$/d' \
  -e '/^unique_result_folder = strcat\( result_path "RID"\)$/d' \
  -e '/^system\(strcat\("mkdir -p " unique_result_folder \)\)$/d' \
  -e '/^ *;/d' ; }
total=0; bad=0
for t in $TESTS; do for i in 0 1 2; do for m in managed unmanaged; do
  total=$((total+1))
  lf="$S/L/replay.${t%%:*}$((i+1)).au"; rf="$S/R/replay.${t#*:}_${LIBS[$i]}_$m.au"
  if [[ ! -s "$lf" || ! -s "$rf" ]]; then bad=$((bad+1)); echo "=== ${t#*:} ${LIBS[$i]} $m: replay not generated"; continue; fi
  out=$(diff -B -w <(norm_l "$lf") <(norm_r "$rf"))
  if [[ -n "$out" ]]; then bad=$((bad+1)); echo "=== ${t#*:} ${LIBS[$i]} $m"; echo "$out"; fi
done; done; done
echo "compared=$total with_residual=$bad"
```
- 새 템플릿이 생기면 `TESTS`에 `<legacy 이름>:<저장소 이름>`을 추가합니다. 라이브러리·셀이 바뀌면 `LIBS`/`CELLS`를 `env.sh`와 맞춥니다.
- 주석 줄(`;`로 시작)은 비교에서 뺐으므로, 주석만 바뀐 legacy′ 변경은 이 게이트에 나타나지 않습니다. 주석도 반영할지는 직접 판단합니다.
- 정규화 규칙에 걸리지 않는 새 틀 차이가 생기면, 먼저 그것이 의도한 차이인지 판단하고 §4에 추가한 뒤 정규화를 고칩니다.

### 5.2 G3 — 실행
```bash
./deploy.sh perf dev "$S/p"
(cd "$S/p" && ICM_SkillRoot=/x bash perf_main.sh -d 2)                                         # rc 0
(cd "$S/p" && ICM_SkillRoot=/x bash perf_main.sh -d 1 -auto-init -lib BM01 -test checkHier -t) # rc 0, 워크스페이스 0개로 끝남
```
mock 단계 0(공통 문서 §7 G3)으로 `-no-run` init → 실행 → `-t` teardown 후 등록부와 `WORKSPACES_*`가 비는지,
`perf_teardown_all.sh`가 워크스페이스 없는 오래된 프로젝트만 고아로 분류하는지, `MOCK_GDP_DOWN=1`이면 아무것도 지우지 않는지 확인합니다.
