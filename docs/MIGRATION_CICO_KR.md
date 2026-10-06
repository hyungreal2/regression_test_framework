# MIGRATION — cico (`1_cico_sp` → `suites/cico`)

[MIGRATION_COMMON_KR.md](MIGRATION_COMMON_KR.md)을 먼저 읽습니다. 이 문서는 cico에만 해당하는 대응표, 의도한 차이,
판단 기준, 검증을 다룹니다.

---

## 1. 파일 대응표

| legacy (`1_cico_sp/`) | 저장소 | 분류 | 반영 방법 |
|---|---|---|---|
| `code/control` | `suites/cico/code/control` | 데이터 | **형식 변환**(§2.1) |
| `code/list` | `suites/cico/code/list` 1~N번 줄 | 데이터 | 그대로, 앞부분에(§2.2) |
| `code/list_Original_AllTestcases_256` | `suites/cico/code/list` N+1번 이후 | 데이터 | `list`에 없는 줄만, 원래 순서대로(§2.2) |
| `code/list_NoFast_144` | — | 백업 | 기준 legacy에서는 `list`와 같은 내용. `list`가 기준이며 이 파일은 반영하지 않음 |
| `code/template.il` | `suites/cico/code/template.il` | 데이터 | 그대로(현재 바이트 단위로 같음) |
| `code/validate.il` | `suites/cico/code/validate.il` | 데이터 | 그대로(현재 같음) |
| `code/Flat_list`, `code/Hierarchical_List` | 같은 이름 | 데이터 | 그대로(현재 같음) |
| `code/mgHierParse.il`, `code/virtuosoVer.il` | `shared/code/` (func와 공용) | 데이터 | 내용만 반영. 저장소 파일은 CRLF 줄 끝이며 내용은 같음 |
| `code/cdsLibMgr.il` | 배치하지 않음 (`CDS_LIB_MGR` 사이트 경로를 링크) | 데이터 | 반영하지 않음. 사본은 `archive/func/code/cdsLibMgr.il` |
| `code/generate_templates.py` | `shared/code/generate_templates.py` (func와 공용) | 프레임워크 | 동작만(§3) |
| `main.sh` | `suites/cico/main.sh` + `code/run_single_test.sh` | 프레임워크 | 동작만(§3) |
| `code/init.sh` | `suites/cico/code/init.sh` | 프레임워크 | 동작만(§3) |
| `code/teardown.sh` | `suites/cico/code/teardown.sh` | 프레임워크 | 동작만(§3) |
| `code/ICM_deleteProj.sh` | `suites/cico/code/teardown_all.sh -p <prefix> [-y]` | 프레임워크 | 동작만 |
| `code/summary.sh` | `suites/cico/code/summary.sh` | 프레임워크 | 판정 규칙만(§3) |
| `code/control_13Augest`, `code/final`, `code/final1`, `code/delte_fail`, `code/new_list_delete`, `code/init.sh_OA` | — | 백업 | 반영하지 않음 |

cico는 func의 `.cdsenv`(`shared/code/.cdsenv`)를 워크스페이스에 링크해서 씁니다. legacy cico `main.sh`는
`code/.cdsenv`를 복사했지만 legacy cico 디렉터리에는 그 파일이 없었습니다.

---

## 2. 데이터 파일 규칙

### 2.1 control: 화살표 형식 → 블록 형식

legacy는 한 줄에 `<문장> "\n" <문장> ... -> <단계 이름>` 형식입니다. 저장소 생성기는 블록 형식을 읽습니다.

legacy (`1_cico_sp/code/control`, 1~2행):
```
ddAutoCtlSetVars(0 0 3 3)  -> auto checkout on, auto checkin on
ddAutoCtlSetVars(0 0 0 3)  -> auto checkout off,auto checkin on
```
저장소 (`suites/cico/code/control`):
```
=== Start : auto checkout on, auto checkin on
ddAutoCtlSetVars(0 0 3 3)
=== End

=== Start : auto checkout off, auto checkin on
ddAutoCtlSetVars(0 0 0 3)
=== End
```

변환할 때 지켜야 하는 legacy 생성기의 해석(`1_cico_sp/code/generate_templates.py`의 control 파싱):
- `->`가 없는 줄과 빈 줄은 무시합니다.
- 단계 이름은 **마지막** `->` 뒤입니다(`rfind`). 앞부분이 코드입니다.
- 이름의 쉼표 주변 공백은 `", "` 하나로 정리합니다(`auto checkout off,auto checkin on` → `auto checkout off, auto checkin on`).
  저장소 생성기도 블록 이름에 같은 정리를 하지만, 블록에는 정리된 이름을 씁니다.
- 코드는 공백으로 둘러싸인 ` "\n" `에서 나눠 한 줄에 문장 하나씩 씁니다. 저장소 생성기가 블록의 줄들을 다시
  ` "\n" `로 이어 붙이므로 replay 결과가 같습니다.
- 코드 안의 다른 `"\n"`(예: `fprintf(fd "...: %s\n" ...)`의 문자열 안)은 나누지 않습니다. 앞뒤가 공백인 ` "\n" `만 구분자입니다.
- legacy에서 같은 이름이 두 줄에 나오면 **뒤의 줄이 이깁니다**(dict 덮어쓰기). 블록으로 옮길 때는 뒤의 것 하나만 씁니다.
  (블록 형식에서 같은 이름이 두 번 나오면 저장소 생성기는 이어 붙이므로, 두 블록을 만들면 결과가 달라집니다.)
- 머리말 주석(`#`로 시작)은 블록 밖에 둡니다. 생성기는 블록 밖의 줄을 무시합니다.

legacy′에 새 단계가 생기면 같은 규칙으로 블록을 하나 추가합니다. 단계의 코드가 바뀌면 그 블록의 줄만 바꿉니다.

### 2.2 list: legacy 순서 + Fast 계열

저장소 `list`는 다음과 정확히 같아야 합니다.
```bash
{ sed 's/\r$//' <L>/code/list
  sed 's/\r$//' <L>/code/list_Original_AllTestcases_256 | grep -vxFf <(sed 's/\r$//' <L>/code/list)
} > suites/cico/code/list
```
- 1~N번(N = legacy `list` 줄 수, 현재 144)은 legacy 케이스를 legacy 순서대로 둡니다. 테스트 번호(= 줄 번호)와
  결과의 `Row_<번호>_...` 이름이 legacy와 같아집니다.
- 그 뒤에 `list_Original_AllTestcases_256`에만 있는 줄(현재 112줄, Fast 계열)을 그 파일의 순서대로 붙입니다.
- legacy′에서 두 파일 중 하나라도 바뀌면 위 명령으로 다시 만듭니다.
- N이 바뀌면 Fast 계열의 번호가 모두 밀립니다(예: N 144→145이면 Fast는 146~257). 테스트 번호는 결과의 `Row_<번호>` 이름과
  사람들이 쓰는 `-c` 번호이므로, 보고서 "사람 확인 필요"에 이전→새 번호 대응을 적습니다.
- legacy′의 `list`에 새로 생긴 줄이 Fast 계열처럼 보여도(이름에 `Fast`) legacy′가 `list`에 넣었다면 `list`(1~N번)에 둡니다. 의도를 확인하도록
  보고서에 적습니다.
- N이 바뀌면 `site/dev.env`의 `MAX_CASES`(dev 기본 = legacy 케이스 수)와 `main.sh` 도움말, README의 "1~144" 표현을 함께 고칩니다.
  `site/prod.env`의 `MAX_CASES`는 전체 줄 수입니다.

### 2.3 template.il

현재 legacy와 바이트 단위로 같습니다. legacy′의 변경을 그대로 반영합니다. 다만 생성기가 치환하는 자리표시자
(`CDS_PV_REGGRESION_NO`, `CDS_PV_REG_RES_NO`)와 `;;; Test Scenario::Begin/End` 표지는 유지되어야 합니다.
legacy′가 이 이름을 바꾸면 `shared/code/generate_templates.py`의 치환도 함께 바꾸고, func 템플릿과의 호환을 확인합니다.

### 2.4 SKILL 파일

`validate.il`, `mgHierParse.il`, `virtuosoVer.il`은 내용만 옮깁니다. `mgHierParse.il`과 `virtuosoVer.il`은 func도 쓰므로
legacy′의 func 쪽(또는 prod) 버전과 다르면 두 suite에 모두 맞는지 확인합니다. 다르게 필요하면 공용을 그만두고 suite별 파일로 나눕니다.

---

## 3. 프레임워크 대응 (동작만 옮김)

| legacy 동작 | 저장소에서의 구현 |
|---|---|
| `main.sh` 옵션 `-m`, `-c`, `-ws`, `-proj`, `-lib`, `-cell`, `-debug` | 같은 옵션. `-debug`(=`-keep-artifacts`)는 성공한 teardown 뒤의 산출물 삭제를 건너뜀. 추가: `-j`, `-d`, `-k` |
| 실행마다 `cadence_cico_<user>_<시각>` 프로젝트 하나를 테스트마다 다시 만들고 지움 (순차) | 테스트마다 `PROJ_PREFIX_<uniquetestid>` (`<번호>_<시각>_<pid>`). `xargs -P`로 병렬 |
| `virtuoso -replay ... -log CDS_log/<id>/CDS_NNN.log` | `run_vse`(`vse_run -v VSE_VERSION -nograph`, 또는 `VSE_MODE=sub`) |
| `cp code/cdsLibMgr.il`, `cp code/.cdsenv` 워크스페이스로 | `ln -sf CDS_LIB_MGR`, `ln -sf code/.cdsenv` |
| `init.sh`: project → variant → libtype → config → library(`--location=oa/{{library}}`) → update → build workspace | 같은 순서. project 생성은 `create_gdp_project`(재시도). 경로는 `CICO_GDP_BASE` |
| `init.sh`의 "중단되면 이렇게 지우라" 안내 | `teardown_hint` (프로젝트 생성 직후, init 끝) |
| `teardown.sh`: revert → client 삭제 → workspace 삭제 → rm → project 삭제 → obliterate | 같은 순서 + 미결 CL 삭제, 단계 실패 집계, 멱등, GDP 확인 후 `.trash` 이동 |
| 테스트마다 끝나면 바로 teardown | 백그라운드 `teardown_worker.sh`가 대기열로 처리. `-k`면 건너뛰고 `teardown_all.sh`로 나중에 |
| 끝에 `regression_test_*`, `code/<replays>` 삭제 (`-debug`면 유지) | teardown이 모두 성공했을 때만 삭제 (`-debug`면 유지) |
| `summary.sh <id>`: `result/<id>/*.log`에서 `FAIL`이 있으면 FAIL, 실패 줄 모음 | 같은 판정. `summary.txt` 형식 유지 |
| `ICM_deleteProj.sh -prefix` | `teardown_all.sh -p <prefix>` (워크스페이스가 등록된 프로젝트는 건너뜀, `-y` 없으면 후보만) |

legacy′에서 위 동작이 바뀌면 오른쪽 구현을 고칩니다. 예:
- init에 GDP 단계가 추가됨 → `init.sh`에 같은 순서로 `run_cmd`를 추가하고, teardown이 그 object를 지우는지 확인합니다
  (project `--recursive` 삭제로 하위 object는 함께 지워집니다).
- teardown에 단계가 추가됨 → `teardown.sh`에 `_try`로 추가해 실패가 집계되게 합니다.
- summary 판정이 바뀜 → `summary.sh`를 고치고 `summary.txt` 형식을 legacy′와 맞춥니다.
- 새 옵션 → `main.sh`의 인자 처리(`need_arg`), 도움말, README를 함께 고칩니다.

---

## 4. 의도한 차이 (되돌리지 말 것)

| # | 위치 | legacy | 저장소 | 이유 |
|---|---|---|---|---|
| C1 | control 형식 | 화살표 한 줄 | 블록 | 저장소 생성기 형식. replay 결과는 같음 |
| C2 | control 내용 | — | legacy와 같은 단계 이름 체계 | prod에 있던 다른 이름 체계(`ddBatchCheckout`, `Save-triggered Checkin`, `... Expect Fail CI` 등)는 list와 맞지 않아 256개 중 235개 replay에 매핑 누락을 만들었음. 그 이름들을 되살리지 않습니다 |
| C3 | list | 144줄 | 256줄(1~144 legacy + Fast 112) | §2.2 |
| C4 | 프로젝트/워크스페이스 이름 | `cadence_cico_*_<시각>` 실행당 하나 | 테스트당 하나(`<번호>_<시각>_<pid>`) | 병렬 실행 |
| C5 | GDP 경로 | `/VSM/<proj>` | `${CICO_GDP_BASE}/<proj>` | site 값 |
| C6 | 산출물 삭제 조건 | 항상(`-debug` 제외) | teardown 성공 시에만 | 실패 시 `teardown_all.sh`가 디렉터리를 읽어야 함 |
| C7 | regression 디렉터리 | `regression_test_<user>_<시각>` | `regression_test_NNN`, 원자적 `mkdir`로 확보 | 동시 실행 시 공유 방지 |
| C8 | 종료 코드 | 항상 0 근처(`|| true`) | 테스트 실행 실패/summary/teardown 반영 | 판정 FAIL은 legacy처럼 반영하지 않음 |

---

## 5. 검증

### 5.1 G1 — 생성기
```bash
./deploy.sh cico dev "$S/c"
(cd "$S/c" && python3 code/generate_templates.py --result_folder R --libname E --results N)   # rc 0, 경고 없음
ls "$S/c/code/N" | wc -l                                                                     # = list 줄 수
```

### 5.2 G2 — legacy′와 1:1 (바이트 단위)
```bash
cp -r <L> "$S/leg"
(cd "$S/leg" && python3 code/generate_templates.py --result_folder R --libname E --results L)
n=0; d=0; for f in "$S/leg/code/L"/*.il; do n=$((n+1)); cmp -s "$f" "$S/c/code/N/$(basename "$f")" || { d=$((d+1)); echo "DIFF $(basename "$f")"; }; done
echo "compared=$n differ=$d (expected compared=$(grep -c . <L>/code/list))"   # compared = legacy′ list 줄 수, differ = 0
```
- `compared`가 legacy′ list 줄 수보다 적으면 legacy′ 생성기가 실패한 것입니다(통과로 보지 않음).
- 같은 `--result_folder`와 `--libname`을 양쪽에 줍니다. `--cellname`을 주면 양쪽 모두에 줍니다.
- 차이가 나면 `diff`로 보고, control 변환(§2.1)이나 list 순서(§2.2)를 먼저 의심합니다.

### 5.3 G3 — 실행
```bash
(cd "$S/c" && ICM_SkillRoot=/x bash main.sh -d 2 -c 1-3)       # rc 0
(cd "$S/c" && ICM_SkillRoot=/x bash main.sh -d 1 -c 1-2)       # rc 0, regression_test_* 생성
```
mock 단계 0(공통 문서 §7 G3)으로 2개 병렬 실행 → 자동 teardown 후 등록부에 프로젝트가 남지 않는지,
`-k` 실행 후 `teardown_all.sh <dir>`로 정리되는지 확인합니다.
