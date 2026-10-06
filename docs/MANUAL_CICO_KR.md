# cico 회귀 테스트 실행 가이드 (`main.sh`)

ICM/GDP 환경에서 Virtuoso의 checkout/checkin(CICO) 동작을 시나리오별로 재생해 검증합니다.
prod 배치 이름은 `1_cico_mp`이고, 저장소에서는 `suites/cico/`입니다. 아래 명령은 모두 이 디렉터리에서 실행합니다.

---

## 1. 무엇을 하는가

테스트 하나 = `code/list`의 한 줄입니다. 한 줄은 `1. auto checkout on, 2. auto checkin on, 3. Fast Checkout, ...`처럼 단계의 나열이고,
각 단계의 SKILL 코드는 `code/control`에 있습니다. 테스트마다 다음이 일어납니다.

```
replay 생성 (list 줄 + control + template.il → code/replay_files_<id>/replay_NNN.il)
   │
   ├─ GDP 프로젝트·라이브러리·워크스페이스 생성 (code/init.sh)
   ├─ cdsLibMgr.il, .cdsenv 링크
   ├─ Virtuoso replay 실행 (vse_run -nograph)  → 결과 파일 result/<id>/test_NNN_<ver>.log
   └─ 끝나면 백그라운드에서 teardown (code/teardown.sh)
summary (code/summary.sh)  → result/<id>/summary.txt
```

- 테스트 번호는 `code/list`의 줄 번호입니다. **1~144번은 legacy의 144개 케이스(legacy 순서)**, 145~256번은 Fast 계열입니다.
- 여러 테스트를 `-j`개씩 병렬로 돌립니다. 테스트마다 GDP 프로젝트와 워크스페이스가 따로 만들어집니다.

---

## 2. 준비

- 실행 환경에 `gdp`, `xlp4`, `vse_run`(또는 `vse_sub`)이 있고 `ICM_SkillRoot`가 설정되어 있어야 합니다.
- Python 3 (표준 라이브러리만 사용)
- 사이트 값(`GDP_BASE`, `FROM_LIB`, `VSE_VERSION`, `ICM_ENV`, `CDS_LIB_MGR`, `MAX_CASES`)은 배치된 `code/env.sh`에 들어 있습니다.
  저장소에서 고칠 때는 `site/<site>.env`를 고치고 `deploy.sh`로 다시 배치합니다.
- GDP 접속 확인: `gdp list <GDP_BASE>` 가 경로를 출력하면 됩니다.

---

## 3. 옵션

| 옵션 | 설명 | 기본값 |
|---|---|---|
| `-m <n>` | 1~n번 실행 | `MAX_CASES` (dev 144, prod 256) |
| `-c <목록>` | 지정 번호만 (`1,3,5-9`). 1 이상, list 줄 수 이하 | |
| `-j <n>` | 병렬 수 | 4 |
| `-lib <name>` / `-cell <name>` | 대상 라이브러리 / 셀 | `LIBNAME` / `CELLNAME` |
| `-ws <prefix>` / `-proj <prefix>` | 워크스페이스 / 프로젝트 이름 접두어 | `cico_ws_<user>` / `cico_<user>` |
| `-d [0\|1\|2]` | dry-run 단계. 값 없이 `-d`만 주면 2 | 0 |
| `-k` | teardown 생략 (GDP 프로젝트·워크스페이스·p4 client를 남김) | |
| `-debug` | teardown이 성공해도 `regression_test_NNN/`과 `code/replay_files_<id>/`를 남김 | |
| `-t` | 호환용 (teardown은 기본으로 실행) | |

`-m`과 `-c`는 함께 쓸 수 없습니다.

---

## 4. 단계별 사용

```bash
# 0. 무엇을 할지 보기 (아무것도 만들지 않음)
./main.sh -d 2 -c 1-3

# 1. 몇 개만 먼저
./main.sh -c 1-5

# 2. legacy 케이스 전체 (dev 기본) / 전체 256개 (prod 기본)
./main.sh

# 3. 병렬 수 늘리기
./main.sh -j 8

# 4. 실패를 조사하려고 GDP 환경을 남기기
./main.sh -c 17 -k -debug
#    조사가 끝나면 정리
./code/teardown_all.sh regression_test_NNN
```

---

## 5. 결과 보기

| 위치 | 내용 |
|---|---|
| `log/main.log.<시각>.txt` | 실행 전체 로그 |
| `CDS_log/<id>/CDS_NNN.log` | 테스트별 Virtuoso 로그 |
| `result/<id>_<도구버전>/test_NNN_<ver>.log` | replay가 쓴 결과 (`Row_<번호>_<lib>_<cell>: ... PASS/FAIL`) |
| `result/<id>_<도구버전>/summary.txt` | PASS/FAIL 표와 실패 줄 모음 |

`<id>` = `<날짜>_<시각>_<사용자>_<lib>[_<cell>]` 입니다.

**종료 코드**는 테스트가 실행되지 못했거나(init/Virtuoso 실패) summary 또는 teardown이 실패했을 때 0이 아닙니다.
PASS/FAIL 판정은 종료 코드에 들어가지 않으므로 반드시 `summary.txt`를 봅니다.

---

## 6. 정리

| 상황 | 방법 |
|---|---|
| 보통 실행 | 자동. teardown이 모두 성공하면 `regression_test_NNN/`과 replay 폴더도 지움 |
| `-k`로 실행했거나 teardown이 실패함 | `./code/teardown_all.sh regression_test_NNN` (대기열과 실패 목록을 읽어 재시도) |
| 디렉터리 없이 GDP에 프로젝트만 남음 | `./code/teardown_all.sh -p cico_<user>_` 로 후보 확인 → `-y`를 붙여 삭제 |
| 로컬 결과물 정리 | `./clean.sh` (`-n`이면 목록만). GDP가 남은 디렉터리는 지우지 않고 정리 명령을 알려 줌 |

`-p` 정리는 워크스페이스가 아직 없는 프로젝트를 후보로 봅니다. 다른 cico 실행이 돌고 있을 때는 쓰지 않습니다.

---

## 7. 자주 보는 오류

| 메시지 | 원인과 조치 |
|---|---|
| `ICM_SkillRoot is not set` | ICM 환경을 먼저 설정합니다 (`-d 2`는 이 검사를 하지 않음) |
| `--cases: N is out of range` | `code/list` 줄 수를 넘는 번호 |
| `-lib requires a value` | 옵션 값 누락 |
| `ERROR: unmapped step xN: "<이름>"` (생성기, exit 3) | list의 단계 이름에 해당하는 control 블록이 없음. control 또는 list를 고칩니다 |
| `gdp create project failed after 5 attempts` | GDP 서버 상태 확인. `GDP_PROJ_MAX_ATTEMPTS`로 횟수 조정 |
| `Teardown worker exited rc=1` | 실패한 id가 `regression_test_NNN/teardown_queue.txt.failed`에 있음. `teardown_all.sh`로 재시도 |
| `gdp did not answer ... keeping ...` | gdp가 응답하지 않아 삭제를 확인하지 못함. 디렉터리는 남겨 두었으니 gdp가 복구된 뒤 `teardown_all.sh` |
