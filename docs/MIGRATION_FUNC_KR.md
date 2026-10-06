# MIGRATION — func (`3_func_sp` → `suites/func`)

[MIGRATION_COMMON_KR.md](MIGRATION_COMMON_KR.md)을 먼저 읽습니다. 이 문서는 func에만 해당하는 대응표, 의도한 차이,
판단 기준, 검증을 다룹니다.

---

## 1. 파일 대응표

| legacy (`3_func_sp/`) | 저장소 | 분류 | 반영 방법 |
|---|---|---|---|
| `code/control` | `suites/func/code/func_control` | 데이터 | **그대로**(현재 바이트 단위로 같음). 이미 블록 형식 |
| `code/list_<mode>[_<prefix>]` | 같은 이름 | 데이터 | 그대로(현재 모두 같음) |
| `code/list_changeRefLib*` (3개) | `archive/func/code/` | 미사용 | 진입 스크립트의 mode 목록에 `changeRefLib`가 없어 쓰이지 않음. 반영하지 않음 |
| `code/template.il` | `suites/func/code/func_template.il` | 데이터 | 테스트 내용만 반영, 틀은 저장소 유지(§4 F1~F4) |
| `code/validate.il`, `code/sm_env.il` | 같은 이름 | 데이터 | 그대로(현재 같음) |
| `code/functions.il` | 같은 이름 | 데이터 | 그대로(현재 끝 빈 줄 하나만 다름) |
| `code/.cdsenv` | `shared/code/.cdsenv` (cico와 공용) | 데이터 | 그대로(현재 같음). cico도 이 파일을 쓰므로 두 suite에 맞는지 확인 |
| `code/date_virtuosoVer.il` | 쓰지 않음. 템플릿은 `virtuosoVer.il`(`shared/code`)을 로드 | 데이터 | §4 F3 |
| `code/generate_templates.py` | `shared/code/generate_templates.py` (cico와 공용) | 프레임워크 | 동작만(§3) |
| `main.sh` | `suites/func/func_main.sh` + `code/func_run_single.sh` | 프레임워크 | 동작만(§3) |
| `code/init.sh` | `suites/func/code/func_init.sh` | 프레임워크 | 동작만 |
| `code/teardown.sh` | `suites/func/code/func_teardown.sh` | 프레임워크 | 동작만 |
| `code/summary.sh` | `suites/func/code/func_summary.sh` | 프레임워크 | **판정 규칙은 legacy와 같게 유지**(§3.2) |

`mgHierParse.il`과 `virtuosoVer.il`은 legacy func에는 없고 prod에서 추가된 파일입니다(`shared/code`, cico와 공용).

---

## 2. 데이터 파일 규칙

### 2.1 control, list
- `func_control`은 legacy `control`과 같은 블록 형식이므로 legacy′ 파일을 그대로 덮어씁니다.
  단, 저장소 생성기는 같은 이름 블록을 이어 붙이고 `=== End`가 없는 블록도 받아들이므로(legacy와 같음) 경고가 나오면 legacy′의 의도인지 확인합니다.
- `list_<mode>*`도 그대로 덮어씁니다. 새 list 파일이 생기면 같은 이름으로 추가합니다.
  - 새 **mode**가 생기면(`list_<새 mode>`), `func_main.sh`의 mode 목록, 필수 인자 검사, `func_run_single.sh`의 라이브러리 선택(`case "${mode}"`),
    `-h` 도움말, README를 함께 고칩니다.
  - 새 **prefix**(변형)는 `-prefix <p>`로 바로 쓸 수 있습니다. `func_main.sh` 도움말의 prefix 목록만 고칩니다.

### 2.2 func_template.il
legacy 템플릿의 **테스트 내용**(로드하는 SKILL, 환경 설정, 시나리오 앞뒤 처리)이 바뀌면 반영합니다. 결과 파일을 만드는 **틀**(경로,
번호, 결과 폴더)은 저장소 방식을 유지합니다(§4).

legacy (`3_func_sp/code/template.il`, 발췌):
```
\i code_path = "../../../../code/"
\i result_path = "../../../../result/"
\i load(strcat(code_path "date_virtuosoVer.il"))
\i user_name = getShellEnvVar("USER")
\i inport = infile(strcat("../../../../temp/func_date_" user_name "_" mode))
\i gets(main_date inport) ...
\i system(strcat("mkdir -p " result_path mode "/" main_date ))
\i inport = infile(strcat("../../../../temp/CDS_PV_REG_NO_" user_name "_" mode))
\i gets(CDS_PV_REG_NO inport) ...
\i fd=outfile(strcat(result_path mode "/" main_date "/test_" CDS_PV_REG_NO "_" date_virtuosoVer(code_path mode) ".log") "w")
\i fprintf(fd strcat("Start Time: " getCurrentTime() "\n"))
\i ;;; Test Scenario::Begin
\i ;;; Test Scenario::End
\i fprintf(fd strcat("\nEnd Time: " getCurrentTime() "\n"))
```
저장소 (`suites/func/code/func_template.il`, 발췌):
```
\i code_path = "../../../code/"
\i result_path = "../../../result/"
\i load( strcat( code_path "virtuosoVer.il"))
\i load( strcat( code_path "mgHierParse.il"))
\i managed = "managed"
\i unique_result_folder = strcat( result_path CDS_PV_REG_RES_NO)
\i system(strcat("mkdir -p " unique_result_folder  ))
\i user_name = getShellEnvVar("USER")
\i fd=outfile(strcat( unique_result_folder "/test_" CDS_PV_REGGRESION_NO "_" virtuosoVer() ".log") "w")
\i fprintf(fd strcat("Start Time: " getCurrentTime() "\n"))
\i ;;; Test Scenario::Begin
\i ;;; Test Scenario::End
\i fprintf(fd strcat("End Time: " getCurrentTime() "\n"))
```
- 줄 `\i mode = "default"`은 남겨 둡니다. `func_main.sh`가 실행할 때 `mode = "<mode>"`로 바꾼 `func_template_<mode>.il`을 만듭니다
  (legacy 생성기가 읽던 `template_<mode>.il`에 해당).
- `;;; Test Scenario::Begin` / `End`, `End Time` 줄은 지우거나 이름을 바꾸면 안 됩니다. 생성기와 `func_summary.sh`가 기댑니다.

---

## 3. 프레임워크 대응 (동작만 옮김)

### 3.1 실행 흐름

| legacy 동작 | 저장소에서의 구현 |
|---|---|
| 옵션 `-mode -prefix -lib -cell -fromLib(기본 All) -toLib -fromCell -min -max -cases` | 같은 옵션(`-m`=min, `-M`=max, `-c`). 추가: `-j -d -k -ws -proj` |
| mode별 필수 인자 검사 | 같은 규칙(`func_main.sh`의 `_validate_mode_args`) |
| `pad_width = list 줄 수의 자릿수` | 같음. 디렉터리·replay·CDS 로그·결과 파일 번호가 모두 이 자릿수 |
| `regression_test/<mode>/test_NN`, 실행 전에 `rm -rf regression_test/$mode` | `regression_test_<mode>_NNN/test_NN`, 원자적 `mkdir`. 이전 디렉터리는 지우지 않음(`clean.sh`) |
| 번호와 날짜를 `temp/CDS_PV_REG_NO_*`, `temp/func_date_*` 파일로 replay에 전달 | 생성기가 `CDS_PV_REGGRESION_NO`, `CDS_PV_REG_RES_NO`를 replay에 직접 치환 |
| `virtuoso -replay` 순차 실행 | `run_vse`, `xargs -P` 병렬 |
| `cp code/cdsLibMgr.il` | `ln -sf CDS_LIB_MGR` |
| 테스트마다 `init.sh` / `teardown.sh` | `func_init.sh` / 백그라운드 `teardown_worker.sh` + `func_teardown.sh`. `-k`면 `func_teardown_all.sh`로 나중에 |
| 이름에 mode를 붙임(`<ws>_<mode>`, `<proj>_<mode>`) | `uniqueid`에 mode가 들어가고, 테스트마다 `<uniqueid>_<번호>_<pid>` |
| `summary.sh $mode/$dateno` | `func_summary.sh -t "<번호들>" <mode> <uniqueid> <result_folder_id>` |

### 3.2 판정 규칙 (`func_summary.sh`)
legacy `3_func_sp/code/summary.sh`와 **같은 순서, 같은 문구**입니다. legacy′가 판정을 바꾸면 그대로 따라 고칩니다.
1. `End Time` 줄이 없음 → FAIL "Log isn't fully scripted"
2. `=== ... ===` 섹션에 `Row_` 줄이 하나도 없음 → FAIL "Expected row mismatch" (legacy awk 그대로)
3. `Check out FAIL` → "*WARNING* Check out Fail detected", `Check in FAIL` → "*WARNING* Check in Fail detected", 그 밖의 `FAIL` → "Fail detected" (모두 FAIL로 집계)
4. 그 밖 → PASS

저장소 추가 동작(유지):
- 선택한 테스트 중 결과 파일이 없으면 "No result log ..." 로 FAIL에 셉니다.
- 판정 대상은 `result/<id>/test_*.log`이고 번호는 숫자로 비교합니다(자릿수 무관).
- 종료 코드는 판정과 무관하게 0입니다(summary 자체가 실패할 때만 0이 아님).

legacy′가 다시 "기대 행 수" 같은 상수 비교를 도입하더라도, 그 상수는 mode·셀에 따라 달라지므로(예: checkHier 10~12) 상수를 진입
스크립트에 박지 말고 legacy′의 규칙을 `func_summary.sh` 안에 구현합니다.

---

## 4. 의도한 차이 (되돌리지 말 것)

| # | 위치 | legacy | 저장소 | 이유 |
|---|---|---|---|---|
| F1 | 템플릿 경로 깊이 | `../../../../code/`, `../../../../result/` | `../../../code/`, `../../../result/` | 실행 위치가 `regression_test_<mode>_NNN/test_NN/<ws>`(한 단계 얕음) |
| F2 | 번호·결과 폴더 전달 | `temp/` 파일을 replay가 읽음 | 생성기 치환 `CDS_PV_REGGRESION_NO`, `CDS_PV_REG_RES_NO` | 병렬 실행 시 temp 파일 경쟁 제거. 번호 자릿수는 legacy처럼 `pad_width` |
| F3 | 버전 문자열 | `date_virtuosoVer(code_path mode)` (날짜+버전, 파일에 기록) | `virtuosoVer()` | 결과 폴더가 실행마다 고유하므로 날짜가 필요 없음 |
| F4 | 추가 로드·변수 | — | `mgHierParse.il` 로드, `managed = "managed"` | 시나리오 SKILL이 사용 |
| F5 | `End Time` 앞 `\n` | `"\nEnd Time: "` | `"End Time: "` | 판정은 `End Time` 문자열만 봄. 결과 동일 |
| F6 | `func_control` 297행 `cond(... ddAutoCtlSetVars ...)` | 활성 | 활성 | prod에서 주석 처리돼 ICM Checkin 뒤 auto 설정이 복원되지 않았음. legacy대로 유지 |
| F7 | 판정 | legacy summary.sh | 같은 규칙 + 결과 파일 없는 테스트 FAIL | prod의 "모드별 기대 행 수" 상수 비교(12/6/11/4/12)는 셀마다 행 수가 달라 오판했음. 되살리지 않음 |
| F8 | regression 디렉터리 | 다음 실행이 지움 | 남김(`clean.sh`, `func_teardown_all.sh`) | `-k` 실행과 실패한 teardown을 나중에 정리하기 위해 |

---

## 5. 검증

### 5.1 G1 — 모든 list 생성
```bash
./deploy.sh func dev "$S/f"; cd "$S/f"
for l in code/list_*; do
  b=${l#code/list_}; m=${b%%_*}; p=""; [[ "$b" == *_* ]] && p="--prefix ${b#*_}"
  sed "s/mode *= *\"[^\"]*\"/mode = \"$m\"/g" code/func_template.il > "code/func_template_$m.il"
  python3 code/generate_templates.py --mode "$m" $p --libname L --cellname C --fromLib F --toLib T --fromCell FC \
    --workspace code --results "R_$b" --result_folder X >/dev/null || echo "FAIL $b"
done                                # FAIL 줄이 없어야 함 (unmapped 단계가 있으면 exit 3)
```

### 5.2 G2 — legacy′와 시나리오 본문 1:1
legacy′ 생성기에도 같은 인자를 줍니다(legacy 생성기는 `template_<mode>.il`을 읽으므로 같은 `sed`로 만들어 둡니다).
```bash
cp -r <L> "$S/lf"; cd "$S/lf"
for l in code/list_*; do
  b=${l#code/list_}; m=${b%%_*}; p=""; [[ "$b" == *_* ]] && p="--prefix ${b#*_}"
  [[ "$m" == changeRefLib ]] && continue           # 저장소 mode 목록에 없음
  sed "s/mode *= *\"[^\"]*\"/mode = \"$m\"/g" code/template.il > "code/template_$m.il"
  python3 code/generate_templates.py --mode "$m" $p --libname L --cellname C --fromLib F --toLib T --fromCell FC \
    --results "RL_$b" >/dev/null 2>&1
done
body(){ awk '/;;; Test Scenario::Begin/{f=1;next} /;;; Test Scenario::End/{f=0} f' "$1"; }
n=0; d=0; for f in "$S"/lf/code/RL_*/*.il; do n=$((n+1))
  b=$(basename "$(dirname "$f")"); b=${b#RL_}
  cmp -s <(body "$f") <(body "$S/f/code/R_$b/$(basename "$f")") || { d=$((d+1)); echo "DIFF $b/$(basename "$f")"; }
done
expected=$(cat $(ls code/list_* | grep -v '/list_changeRefLib') | grep -c .)
echo "compared=$n differ=$d (expected compared=$expected)"   # compared = expected, differ = 0 (현재 기준 legacy: 8221)
```
본문 밖(템플릿 틀)의 차이는 §4 F1~F5뿐이어야 합니다. 한 파일을 골라 `diff`로 확인합니다.

### 5.3 G3 — 실행
```bash
(cd "$S/f" && ICM_SkillRoot=/x bash func_main.sh -d 2 -mode checkHier -lib L -cell C -c 1-3)   # rc 0
```
mock 단계 0(공통 문서 §7 G3)으로 `-mode replace -c 1-2` 실행 → teardown 후 등록부가 비는지, `-k` 실행 후
`func_teardown_all.sh <dir>`로 정리되는지, `MOCK_GDP_DOWN=1`이면 rc 1과 디렉터리 보존인지 확인합니다.
판정 규칙을 바꿨다면 결과 파일을 손으로 몇 개 만들어(`End Time` 없음, 행 없는 섹션, `Check in FAIL`, 정상) `func_summary.sh`의
출력이 legacy′ `summary.sh`의 출력과 같은지 비교합니다.
