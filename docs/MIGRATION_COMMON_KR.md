# MIGRATION — 공통 (legacy′ → 저장소)

새 legacy(이하 **legacy′**)가 나왔을 때 그 변경을 이 저장소에 옮기기 위한 참조 문서입니다.
읽는 사람은 LLM 또는 사람이며, **이 문서 묶음과 legacy′ 디렉터리만으로** 작업할 수 있도록 썼습니다.

- 이 문서: 용어, 절차, 공통 규칙, 반드시 유지할 동작, 검증 게이트
- suite별 문서: [MIGRATION_CICO_KR.md](MIGRATION_CICO_KR.md) · [MIGRATION_FUNC_KR.md](MIGRATION_FUNC_KR.md) · [MIGRATION_PERF_KR.md](MIGRATION_PERF_KR.md)
  — 파일 대응표, 의도한 차이(양쪽 발췌), 판단 기준, suite 검증
- 작업할 때는 **이 문서 + 바뀐 suite의 문서**를 함께 읽습니다.

> 이 문서의 규칙은 기계적으로 적용하는 치환 스크립트가 아닙니다. legacy′의 변경을 읽고 저장소의
> 어느 파일, 어느 부분에 어떻게 반영할지 **판단할 때 참조하는 기준**입니다. 판단이 끝나면 아래
> 검증 게이트로 결과를 확인합니다.

---

## 1. 용어

| 용어 | 뜻 |
|---|---|
| legacy (기준) | 이 저장소가 마지막으로 맞춰 둔 legacy 스냅샷. **저장소의 `reference/legacy/`에 커밋되어 있습니다**(`1_cico_sp`, `2_perf_sp`, `3_func_sp`. 실행 결과물·생성 replay·편집기 임시 파일은 `.gitignore`로 제외). 파일 체크섬은 [부록 A](#부록-a-기준-legacy-체크섬) |
| legacy′ | 새로 받은 legacy. 같은 세 디렉터리 구조 |
| 저장소 | 이 git 저장소. `shared/`, `suites/{cico,perf,func}/`, `site/`, `deploy.sh`, `tools/` |
| prod 배치 | `deploy.sh`가 만드는 `1_cico_mp`, `2_perf_mp`, `3_func_mp`. 저장소 suite 디렉터리와 같은 구조 |
| 데이터 파일 | 테스트 내용을 정하는 파일. SKILL(`.il`), control, list, replay 템플릿, `createReplay.pl`, `.cdsenv`, 셀 목록 |
| 프레임워크 스크립트 | 실행 흐름을 정하는 셸/Perl 스크립트. legacy `main.sh`, `main.pl`, `main.template`, `init.sh`, `teardown.sh`, `summary.sh` 등 |

legacy′의 suite 디렉터리 이름이 다르면(예: `1_cico`) 내용으로 대응시킵니다. cico는 `code/control`과
`code/list`, perf는 `GenerateReplayScript/createReplay.pl`, func는 `code/list_<mode>*`가 있는 쪽입니다.

---

## 2. 작업 절차

### 단계 1 — 기준 확인
1. 기준 legacy는 `reference/legacy/`입니다. legacy′는 저장소 밖이나 `reference/` 아래 다른 이름(git이 무시함)에 둡니다.
   `reference/` 아래에서는 `reference/legacy/`만 추적되고, `reference/prod/` 등 나머지는 추적되지 않습니다.
2. 기준 legacy가 부록 A와 맞는지 확인합니다.
   ```bash
   cd reference/legacy && sha256sum <경로> | cut -c1-16      # 부록 A의 값과 비교
   ```
3. 체크섬이 다르면(누군가 기준을 손댔다면) `git log -- reference/legacy`로 마지막 반영 시점을 확인하고, 그 커밋의 기준과
   legacy′를 비교합니다. 기준을 쓸 수 없으면 legacy′를 **저장소 파일과 직접** 비교합니다. 이때 suite 문서의
   "의도한 차이" 목록이 기준 역할을 하며, 목록에 없는 차이만 legacy′의 새 변경으로 봅니다.

### 단계 2 — 변경 목록 만들기
```bash
diff -rq --strip-trailing-cr <기준>/1_cico_sp <legacy′>/1_cico_sp     # perf, func도 같은 방식
diff -u  --strip-trailing-cr <기준>/<파일> <legacy′>/<파일>             # 바뀐 파일마다
```
- 줄 끝(CRLF/LF)만 다른 파일은 변경이 아닙니다. 저장소 파일의 줄 끝은 그대로 둡니다.
- 실행 결과물(`result/`, `CDS_log/`, `regression_test/`, `*.au`, `*.out`, `code/replay/`, `temp/`,
  `code/managed.txt`, `code/date_virtuosoVer.txt`, `GenerateReplayScript/lcv.txt`)과 편집기 임시 파일(`.*.swp`)은 무시합니다.

### 단계 3 — 변경마다 분류
| 분류 | 예 | 처리 |
|---|---|---|
| A. 데이터 파일 | control, list, `template.il`, `validate.il`, `functions.il`, perf 템플릿, `createReplay.pl` | suite 문서의 대응표에 있는 저장소 파일에 **내용을 반영**합니다. 형식 변환이 필요한 파일(cico control 등)은 그 규칙을 따릅니다 |
| B. 프레임워크 스크립트 | legacy `main.sh`, `init.sh`, `teardown.sh`, `summary.sh`, `main.pl`, `main.template` | 줄 단위로 옮기지 않습니다. 바뀐 **동작**(새 옵션, 새 GDP 단계, 새 판정 규칙 등)을 찾아 suite 문서의 "스크립트 대응"에 적힌 저장소 스크립트에 같은 동작을 구현합니다 |
| C. 사이트 값 | GDP 경로(`/VSM/...`), 원본 라이브러리 경로, Virtuoso 버전 | `site/*.env`와 `shared/code/env.sh` 값으로 반영합니다(§4) |
| D. 백업·미사용 | `control_13Augest`, `final`, `init.sh_OA`, `*_ORG_*`, `teardown.sh_paul`, `.cdsenv2` 등 | 반영하지 않습니다. 단, legacy′의 진입 스크립트가 그 파일을 새로 참조하기 시작했다면 A나 B로 다시 분류합니다 |

### 단계 4 — 반영
- suite 문서의 대응표와 "의도한 차이"를 보면서 반영합니다.
- legacy′의 변경과 의도한 차이가 같은 부분에 걸치면 §5의 우선순위로 판단합니다.
- 새 파일이 생기면, 두 개 이상의 suite가 쓰는 경우에만 `shared/`에 두고 각 suite에서 상대 링크로 연결합니다.
  한 suite만 쓰면 그 suite 디렉터리에 둡니다.

### 단계 5 — 검증
§7의 게이트를 모두 실행합니다. 실패하면 단계 4로 돌아갑니다.

### 단계 6 — 문서
- 사용법이 바뀌면 `README.md`와 해당 `docs/MANUAL_<SUITE>_KR.md`를 고칩니다.
- 새 의도한 차이가 생기면 suite MIGRATION 문서의 "의도한 차이"에 양쪽 발췌와 이유를 추가합니다.
- 반영이 끝나면 기준을 legacy′로 바꿉니다: `reference/legacy/`의 내용을 legacy′로 교체하고(세 suite 디렉터리 전체.
  `.gitignore`가 실행 결과물을 거름), [부록 A](#부록-a-기준-legacy-체크섬)를 다시 만듭니다(부록 A 머리말의 명령을 `reference/legacy`에서 실행).
  이전 기준은 git 이력에 남습니다.

### 단계 7 — 커밋
공용(`shared/`, `site/`, `deploy.sh`, `tools/`), cico, func, perf, 문서, 기준 교체(`reference/legacy/` + 부록 A)로 나눠 커밋합니다.
메시지에 legacy′의 어떤 파일 변경을 반영했는지 적습니다. push는 따로 확인을 받은 뒤 합니다.

---

## 3. 저장소 구조와 공용 규칙

```
shared/            두 개 이상의 suite가 쓰는 파일 (suite 디렉터리에서 상대 링크)
  clean.sh                   suite별 정리 (suites/*/clean.sh가 링크)
  code/env.sh                설정. site 값의 기본은 site/dev.env와 같음
  code/common.sh             log, run_cmd(DRY_RUN), run_vse, gdp 도우미
  code/generate_templates.py cico·func replay 생성기
  code/teardown_worker.sh    cico·func 백그라운드 teardown
  code/mgHierParse.il · virtuosoVer.il · .cdsenv   cico·func 공용 SKILL/환경
suites/cico/  = 1_cico_mp      suites/perf/ = 2_perf_mp      suites/func/ = 3_func_mp
site/dev.env · prod.env        사이트마다 다른 값 (KEY=value)
deploy.sh                      suite + site → prod 배치
tools/compare_deploy.sh        배치본과 prod 스냅샷 비교
tools/mock/gdp · xlp4          로컬 실행용 mock (gdp는 object 등록부)
archive/                       prod에 있었지만 쓰지 않는 파일 (배치 안 함)
```

- **링크 규칙**: suite 디렉터리의 공용 파일은 `../../shared/...` 상대 링크입니다. `deploy.sh`가 링크를 실제
  파일로 풀어 배치합니다. 링크 대상을 고치면 그 파일을 쓰는 모든 suite가 바뀝니다.
- **site 값**: `MAX_CASES`, `FROM_LIB`, `GDP_BASE`, `VSE_VERSION`, `ICM_ENV`, `CDS_LIB_MGR`만 사이트마다 다릅니다.
  `shared/code/env.sh`는 dev 값을 그대로 가지며, `deploy.sh`가 같은 키의 줄을 사이트 파일의 줄로 바꿉니다.
  키를 추가하면 `env.sh`, `site/dev.env`, `site/prod.env` 세 곳에 모두 넣어야 배포 검증을 통과합니다.
- **덮어쓰기 변수**: 실행 중에 기본값을 바꾸는 값은 `CAT_*` 이름으로만 받습니다
  (`CAT_VSE_VERSION`, `CAT_WS_PREFIX`, `CAT_PROJ_PREFIX`, `CAT_FUNC_WS_PREFIX`, `CAT_FUNC_PROJ_PREFIX`).
  셸에 우연히 있는 `VSE_VERSION` 같은 일반 이름은 쓰지 않습니다.
- **suite 판정**: `clean.sh`는 같은 디렉터리의 `perf_main.sh` / `func_main.sh` / `main.sh`로 suite를 판단합니다.
  진입 스크립트 이름을 바꾸면 안 됩니다.

---

## 4. legacy의 고정값 → 저장소 변수

legacy 스크립트와 SKILL에 박혀 있는 값이 legacy′에서 바뀌면 아래 위치를 고칩니다.

| legacy에 있는 값 (예) | 저장소 위치 |
|---|---|
| GDP 루트 `/VSM/<proj>` (legacy `init.sh`, `ICM_createProj.sh`) | `GDP_BASE`(site) + `CICO_GDP_BASE` / `FUNC_GDP_BASE` / `PERF_GDP_BASE`(env.sh) |
| 원본 라이브러리 `/VSM/demo/rev1/oa/<lib>` (`--from`) | `FROM_LIB`(site) |
| Virtuoso 버전 (legacy perf `main.template`의 `virtuoso_version`, `vse_run -v`) | `VSE_VERSION`(site, 세 suite 공통). perf는 `-version`으로도 지정 |
| 사용자 이름 접두어 `cadence_cico_<user>`, `cadence_cico_ws_<user>` | `PROJ_PREFIX` / `WS_PREFIX`(env.sh, `-proj` / `-ws`). func는 `FUNC_*`, perf는 `PERF_PREFIX` |
| cico 기본 라이브러리·셀 | `LIBNAME`, `CELLNAME`(env.sh) |
| perf 라이브러리·셀 쌍 (`lib_cell_view.txt`, `main.pl -lib/-cell`) | `PERF_LIBS`, `PERF_CELLS`(env.sh, 같은 순서로 짝) |
| perf 템플릿 목록 (`main.pl`의 `@templates`) | `PERF_TESTS`(env.sh, 템플릿의 `Test<N>` 번호 순서. 이름은 `changeRefLib` → `changeLibRef`) |
| perf 템플릿별 라이브러리 (legacy는 한 워크스페이스에 전부) | `perf_main.sh`의 조합 구성 + `PERF_BASE_LIBS`(DRAMLIB) |
| `cdsLibMgr.il` 경로 | `CDS_LIB_MGR`(site). legacy처럼 suite에 복사해 두지 않습니다 |
| ICM 환경 스크립트 | `ICM_ENV`(site) |
| cico 테스트 수 상한 | `MAX_CASES`(site). dev 144 = legacy 케이스, prod 256 |

---

## 5. 판단 우선순위

legacy′의 변경과 저장소의 의도한 차이가 부딪히면 다음 순서로 판단합니다.

1. **테스트 내용은 legacy′가 이깁니다.** 무엇을 열고, 어떤 GUI 동작을 하고, 무엇을 검증하고, 결과에 어떤 줄을
   쓰는지는 legacy′를 따릅니다. 저장소의 replay가 legacy′ 생성기의 replay와 같아야 합니다(§7 G2).
2. **실행 틀은 저장소가 이깁니다.** 경로 계산, 결과 폴더 이름, 번호 전달 방식, 로그 위치, 병렬 실행, dry-run,
   teardown, 오류 처리는 저장소 방식을 유지하고 legacy′의 의도만 그 틀 안에서 구현합니다.
3. **legacy′가 저장소가 이미 고친 결함을 다른 방식으로 고쳤다면** 결과가 같은지 확인하고, 같으면 저장소 쪽을
   유지합니다. legacy′ 쪽이 더 넓게 고쳤으면 그 부분만 더합니다.
4. **legacy′가 저장소에 없는 기능을 추가했다면** 같은 동작을 저장소 틀로 구현하고, dry-run 0/1/2에서 각각
   어떻게 동작해야 하는지까지 정합니다(§6의 DRY_RUN 규칙).
5. 판단이 서지 않으면 반영하지 말고 사람에게 묻습니다. 묻는 내용에 legacy′ 발췌와 저장소 발췌를 함께 붙입니다.

---

## 6. 반드시 유지할 동작 (회귀 금지)

legacy′를 반영하면서 아래 동작이 깨지면 안 됩니다. 각 항목은 legacy나 이전 prod에서 실제로 문제가 됐던 것입니다.

### 실행과 오류 처리
- 진입 스크립트(`main.sh`, `func_main.sh`, `perf_main.sh`)는 `script_dir`을 한 번 정해 export하고, 자식은 그것만 씁니다.
- 테스트가 실패해도 summary와 teardown은 실행됩니다. 최종 종료 코드는 테스트 → summary → teardown 순서로
  처음 0이 아닌 값입니다(perf는 하나라도 실패면 1). PASS/FAIL **판정**은 종료 코드에 반영하지 않습니다(legacy와 같음).
- `( ... ) || rc=$?` 서브셸 안에서는 `set -e`가 꺼지므로, 멈춰야 하는 단계마다 `|| exit 1`을 붙입니다.
- 값이 필요한 옵션은 값이 없으면 "requires a value"로 멈춥니다. `-j`는 1 이상, 번호 목록은 1 이상 list 줄 수 이하.
- `-h`는 로그 파일을 만들지 않습니다.

### DRY_RUN
- 0 = 모두 실행, 1 = `gdp` / `xlp4` / `rm` / `vse_*`를 건너뛰고 mock 디렉터리를 만듦(`--location` 반영),
  2 = 출력만 하고 아무것도 만들지 않음.
- 새 명령은 `run_cmd`로 실행합니다. 단계 2에서 실제로 생기지 않는 디렉터리로 `cd`하지 않습니다.
- 값을 **읽기만** 하는 gdp 조회(`gdp list`, `gdp find`)는 판단에 쓰일 때 `run_cmd` 없이 직접 호출합니다.

### GDP / teardown
- `gdp create library`에는 `--location=oa/{{library}}`를 붙입니다. 라이브러리가 워크스페이스의 `oa/<lib>`에 놓여야 합니다.
- teardown 순서는 revert → 미결 CL 삭제 → p4 client 삭제 → GDP 워크스페이스 삭제 → (확인 후) 로컬 디렉터리를 `.trash`로
  → GDP 프로젝트 삭제 → depot obliterate 입니다(legacy 순서).
- gdp 조회 결과가 **비어 있다고 "없음"으로 판단하지 않습니다.** `gdp_path_state`(exists/gone/unknown)와
  `gdp_ws_state`(registered/gone/unknown)를 쓰고, unknown이면 지우지 않거나(정리 sweep) 시도한 뒤 실패로 셉니다.
  - `gdp list <경로>`는 object가 있으면 그 경로를 출력합니다. 끝이 `/`이면 하위 object도 출력합니다.
- teardown은 멱등입니다. 이미 지워진 프로젝트는 성공으로 봅니다.
- teardown 대기열은 덧붙이기만 합니다. 실패한 id는 `<queue>.failed`에 남고, `teardown_all.sh` / `func_teardown_all.sh`가
  대기열·`.failed`·`run_prefixes`를 읽어 다시 정리합니다.
- 정리 sweep(`teardown_all.sh -p`, `perf_teardown_all.sh`)은 조회가 하나라도 실패하면 아무것도 지우지 않고,
  확인(`-y`) 없이는 후보만 보여 줍니다.

### 생성기 (`shared/code/generate_templates.py`)
- control 블록이 없는 단계가 있으면 replay는 만들되 **exit 3**으로 실행을 막습니다. 매핑 누락이 조용히 지나가면 안 됩니다.
- `=== End`가 없는 블록, 같은 이름이 두 번 나오는 블록은 legacy처럼 받아들이고 경고합니다(같은 이름은 파일 순서대로 이어 붙임).
- `CDS_PV_REGGRESION_NO`는 replay 파일 이름과 같은 자릿수로 바꿉니다(cico 3자리, func는 list 줄 수의 자릿수).

### 배포
- 배포는 git이 추적하는 파일만, 링크를 풀어서 복사합니다. 커밋 안 된 변경이 섞이면 경고하고 `.deploy_info`에 남깁니다.
- prod 스냅샷과 비교한 차이는 의도한 수정뿐이어야 하고, 스크립트 실행 권한 차이는 0이어야 합니다(§7 G4).

---

## 7. 검증 게이트

아래 명령은 저장소 루트에서 실행합니다. `<L>`은 legacy′ 디렉터리, `$S`는 임시 디렉터리입니다.

### G0 — 문법
```bash
for f in $(git ls-files '*.sh') tools/mock/gdp tools/mock/xlp4; do bash -n "$f" || echo "BAD $f"; done
python3 -m py_compile shared/code/generate_templates.py
```

### G1 — 생성기 실행과 매핑 누락 0
cico와 func의 모든 list에 대해 생성기가 rc 0이고 `ERROR: unmapped step`이 없어야 합니다. 명령은 suite 문서의 검증 절에 있습니다.

### G2 — legacy′ 생성기와 1:1
legacy′의 생성기로 만든 replay와 저장소 생성기로 만든 replay를 비교합니다. 비교 방법과 허용되는 차이는 suite마다 다릅니다.
- cico: 1~N번(legacy′ list 줄 수) **바이트 단위로 같음**
- func: 모든 list의 시나리오 본문(`;;; Test Scenario::Begin` ~ `End`)이 같음
- perf: 7개 템플릿 × 라이브러리마다, 정규화 뒤 남는 차이가 suite 문서의 "허용 차이"뿐

### G3 — 실행 확인 (mock)
```bash
for s in cico perf func; do ./deploy.sh "$s" dev "$S/$s"; done
export ICM_SkillRoot=/x
(cd "$S/cico" && bash main.sh -d 2 -c 1-3)                                   # rc 0
(cd "$S/func" && bash func_main.sh -d 2 -mode checkHier -lib L -cell C -c 1-3) # rc 0
(cd "$S/perf" && bash perf_main.sh -d 2)                                     # rc 0
```
단계 0 mock 실행(`PATH=$PWD/tools/mock:$PATH`, `vse_run`·`rsync`는 exit 0 스텁)으로 init → 실행 → teardown 후 mock 등록부
(`MOCK_GDP_STATE` 파일)에 project/workspace가 남지 않는지도 확인합니다. `MOCK_GDP_DOWN=1`로 teardown하면 rc 1이고 아무것도
지워지지 않아야 합니다.

### G4 — prod 배치 비교
```bash
for s in cico:1_cico_mp perf:2_perf_mp func:3_func_mp; do
  ./deploy.sh "${s%%:*}" prod "$S/d_${s%%:*}"
  tools/compare_deploy.sh "$S/d_${s%%:*}" <prod 스냅샷>/"${s#*:}"
done
```
차이가 이번에 반영한 변경과 이미 알려진 의도한 수정뿐인지, `Exec bit differs` 줄이 없는지 확인합니다.

---

## 부록 A. 기준 legacy 체크섬

`reference/legacy/`의 파일별 SHA-256 앞 16자리입니다. 실행 결과물과 편집기 임시 파일은 뺐습니다.
기준을 바꿀 때는 `reference/legacy/`에서 아래 명령으로 다시 만들어 이 부록을 교체합니다.

```bash
for s in 1_cico_sp 2_perf_sp 3_func_sp; do
  find "$s" -type f \( -path "*/code/*" -o -path "*/GenerateReplayScript/*" -o -name "main.*" -o -name "README*" \) \
    -not -name "*.au" -not -name "*.swp" -not -path "*/code/replay/*" -not -name "*.out" \
    -not -name date_virtuosoVer.txt -not -name managed.txt -not -name lcv.txt \
    | sort | xargs sha256sum | awk '{print substr($1,1,16)"  "$2}'
done
```

```
51ecfd69e1186897  1_cico_sp/code/Flat_list
f7de2947c64cb643  1_cico_sp/code/Hierarchical_List
897d4bf651bd1e86  1_cico_sp/code/ICM_deleteProj.sh
ced871b0145b87f7  1_cico_sp/code/cdsLibMgr.il
dd9e98709fe985b0  1_cico_sp/code/control
802e5011651cb351  1_cico_sp/code/control_13Augest
47acc8aa84082ac9  1_cico_sp/code/delte_fail
1b843f0204ff404d  1_cico_sp/code/final
3b924e4fbf610a5f  1_cico_sp/code/final1
8c4cd874de60881d  1_cico_sp/code/generate_templates.py
83f57987bcc3be13  1_cico_sp/code/init.sh
53a53cf8c0243a93  1_cico_sp/code/init.sh_OA
4ab4b1aef3ef06a8  1_cico_sp/code/list
4ab4b1aef3ef06a8  1_cico_sp/code/list_NoFast_144
8124b0d717af1f23  1_cico_sp/code/list_Original_AllTestcases_256
eef1061253348b21  1_cico_sp/code/mgHierParse.il
bd3350328d1be3d8  1_cico_sp/code/new_list_delete
7bdfdf57bd4f385d  1_cico_sp/code/summary.sh
60a07253a8a2a91f  1_cico_sp/code/teardown.sh
a366a6677c4b22d4  1_cico_sp/code/template.il
aa31d95f30de9d46  1_cico_sp/code/validate.il
f69d3df84b37f9a9  1_cico_sp/code/virtuosoVer.il
8f5df2e07af33165  1_cico_sp/main.sh
a6fff8d80050c5d4  2_perf_sp/GenerateReplayScript/1
ac72a2dd0f25cc0a  2_perf_sp/GenerateReplayScript/changeRefLib
e2e565d3a692099c  2_perf_sp/GenerateReplayScript/checkHier
5d8fdfe01e356d21  2_perf_sp/GenerateReplayScript/copyHierToEmpty
3932c1d6a06d6fe1  2_perf_sp/GenerateReplayScript/copyHierToEmpty_Test
4f6e1a0daa01349a  2_perf_sp/GenerateReplayScript/copyHierToNonEmpty
32bc3f95d01a3ed1  2_perf_sp/GenerateReplayScript/createReplay.pl
6cbef64017e0c155  2_perf_sp/GenerateReplayScript/deleteAllMarker
8835b8e79068b028  2_perf_sp/GenerateReplayScript/lib_cell_view.txt
7b2e1351415a6a3c  2_perf_sp/GenerateReplayScript/renameRefLib
33e356a644ff7249  2_perf_sp/GenerateReplayScript/renameRefLib_debug
a6fff8d80050c5d4  2_perf_sp/GenerateReplayScript/replace
5c8e7259efb83838  2_perf_sp/GenerateReplayScript/test.spec
18b21309b3fe56b6  2_perf_sp/README_CREATENEWMANWS
babfe2057be7c230  2_perf_sp/README_PERF
f5c83e0f7214beac  2_perf_sp/code/.cdsenv
f5c83e0f7214beac  2_perf_sp/code/.cdsenv2
e3b0c44298fc1c14  2_perf_sp/code/.cdsinit
3a30ecef0a5a28bf  2_perf_sp/code/.cdslocal_project
4673bee4671eeb26  2_perf_sp/code/1
b65dfa4101df27a0  2_perf_sp/code/ICM_createProj.sh
897d4bf651bd1e86  2_perf_sp/code/ICM_deleteProj.sh
ced871b0145b87f7  2_perf_sp/code/cdsLibMgr.il
75d6731aac297451  2_perf_sp/code/date_virtuosoVer.il
56e24a6509cd12e5  2_perf_sp/code/functions.il
48353d0c036e8f0b  2_perf_sp/code/init.sh
a2eec05f8edb7118  2_perf_sp/code/perfFunctions.il
7da71e25ee617bfd  2_perf_sp/code/sge_copyLibrary.il
a7dd06a69d1f527d  2_perf_sp/code/summary.sh
c903ef3dd8586a37  2_perf_sp/code/teardown.sh
dc439c3770921aa7  2_perf_sp/code/teardown.sh_paul
da25151de2f3b52d  2_perf_sp/code/validate.il
16311ccb24983fff  2_perf_sp/main.pl
282bec0cd120e853  2_perf_sp/main.sh
ca9a952d9e0743ca  2_perf_sp/main.sh_ORG_15June
f9efd247232e20ec  2_perf_sp/main.template
b38be70785ea2cbe  2_perf_sp/main.template_ORG_15June
4e1f6e83c26c1763  3_func_sp/code/.cdsenv
1add5a3fae9b1adc  3_func_sp/code/control
d81bd651b864c096  3_func_sp/code/date_virtuosoVer.il
f692cf977011d37d  3_func_sp/code/functions.il
bae367d1f2d963d1  3_func_sp/code/generate_templates.py
85ccd90d2416a3d8  3_func_sp/code/init.sh
77b75af5ca485262  3_func_sp/code/list_changeLibRef
397b2cbd66a0c688  3_func_sp/code/list_changeLibRef_oo
77b75af5ca485262  3_func_sp/code/list_changeLibRef_oo_ox
ce87721f3aa21aad  3_func_sp/code/list_changeLibRef_ox
0c916143bd051cea  3_func_sp/code/list_changeLibRef_xo
2a3b861ae9c53fec  3_func_sp/code/list_changeLibRef_xx
4cf36180d6888bc6  3_func_sp/code/list_changeRefLib
acf3abcb17470c6a  3_func_sp/code/list_changeRefLib_oo
5003f979d0643399  3_func_sp/code/list_changeRefLib_ox
5dfc2729251bc11a  3_func_sp/code/list_checkHier
36ab403b2a8490b0  3_func_sp/code/list_checkHier_oo
5dfc2729251bc11a  3_func_sp/code/list_checkHier_oo_ox
6383cb7f6fea1304  3_func_sp/code/list_checkHier_ox
52aa8234aefebae7  3_func_sp/code/list_checkHier_xo
4e189878a9b0be78  3_func_sp/code/list_checkHier_xx
8604ffa43318968e  3_func_sp/code/list_deleteAllMarkers
d04b3f8627292a8d  3_func_sp/code/list_deleteAllMarkers_oo
8604ffa43318968e  3_func_sp/code/list_deleteAllMarkers_oo_ox
94980b83c21f44f9  3_func_sp/code/list_deleteAllMarkers_ox
6ae09b19f78d8d59  3_func_sp/code/list_deleteAllMarkers_xo
e1f58f979b433334  3_func_sp/code/list_deleteAllMarkers_xx
746aaa1f7f4c562f  3_func_sp/code/list_renameRefLib
a2c464fc8ecdec51  3_func_sp/code/list_renameRefLib_oo
622c6afb98eb6925  3_func_sp/code/list_renameRefLib_oo_ox
bf2836c61098cb94  3_func_sp/code/list_renameRefLib_ox
bdb0a64c57bf704f  3_func_sp/code/list_renameRefLib_xo
b06ba0e06e1ed605  3_func_sp/code/list_renameRefLib_xx
64e9a9c165de54a5  3_func_sp/code/list_replace
3372554bb805d040  3_func_sp/code/list_replace_oo
64e9a9c165de54a5  3_func_sp/code/list_replace_oo_ox
a19be8ce071d9a3e  3_func_sp/code/list_replace_ox
6a52fd62a8fb1150  3_func_sp/code/list_replace_xo
8ac7d664669b4071  3_func_sp/code/list_replace_xx
b215c2334e1f8398  3_func_sp/code/sm_env.il
f0ef4db204e8e5a7  3_func_sp/code/summary.sh
32765e27e3325519  3_func_sp/code/teardown.sh
38f82ab10226bc94  3_func_sp/code/template.il
79f31deee6b2db97  3_func_sp/code/validate.il
7c3120ad04d3f616  3_func_sp/main.sh
```
