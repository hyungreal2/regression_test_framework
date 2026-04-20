# CAT — 회귀 테스트 프레임워크 개선 내용
## `legacy/1_cico/main.sh` → `main.sh`

> English version: [IMPROVEMENTS_MAIN.md](IMPROVEMENTS_MAIN.md)
> 통합 문서: [IMPROVEMENTS_KR.md](IMPROVEMENTS_KR.md)

---

## 개요

| 항목 | Legacy (`1_cico/main.sh`) | 현재 (`main.sh`) |
|---|---|---|
| 코드 품질 | 포맷 없음, 들여쓰기 없음 | 구조화된 읽기 쉬운 Bash |
| 에러 처리 | `set -e`만 | `set -euo pipefail` + trap + `error_exit` |
| 공유 환경 | 각 스크립트가 변수 재선언 | `code/env.sh` + `code/common.sh` 한 번만 source |
| 경로 관리 | 상대 경로 (`../../code/`) | `${script_dir}/code/` — 어떤 디렉토리에서도 동작 |
| 테스트 실행 | 순차 `for` 루프 | `xargs -P` 병렬 워커 |
| VSE 호출 | `virtuoso` (바이너리 직접 호출) | `run_vse()` 래퍼 — `vse_run` / `vse_sub` 전환 가능 |
| Teardown 타이밍 | 각 테스트 루프 안에 인라인 | 백그라운드 워커 — 테스트와 동시 실행 |
| Dry-run | 없음 — 항상 실제 인프라 호출 | 3단계 `DRY_RUN` 시스템 |
| 로깅 | `echo`로 stdout만 | `tee`로 타임스탬프 포함 `log/main.log.*` 파일 저장 |
| 리플레이 파일 처리 | `cp` (원본 유지) | `mv` (원본 소비) |
| 회귀 디렉토리 명명 | 타임스탬프 기반 `regression_test_<user>_<date>` | 카운터 기반 `regression_test_001`, `002`, … |
| 정리 | 마지막에 `rm -rf` (debugMode 아닌 경우) | 별도의 `teardown.sh` + `teardown_all.sh` |
| 테스트 순서 | 숫자 정렬 (`sort -n`) | 사용자가 지정한 순서 유지 |

---

## 1. 진입점 및 공유 인프라

### Legacy — 모든 것이 인라인

```bash
# legacy/1_cico/main.sh (포맷 없는 원본 코드)
#!/bin/bash show_help() { ... } set -e
dateno=$(date +%Y%m%d_%H%M%S)
user_name=$(echo $USER)
max=256 cases="" ws_name=cadence_cico_ws_"$user_name"_"$dateno"
proj_name=cadence_cico_"$user_name"_"$dateno"
regression_test_name=regression_test_"$user_name"_"$dateno"
libname=ESD01 cellname=FULLCHIP
```

모든 변수가 스크립트 안에 인라인으로 정의됩니다.
기본값 변경 = 스크립트 직접 수정 필요.

### 현재 — 중앙화된 설정 + 공유 유틸리티

```bash
# main.sh
#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
export script_dir

source "${script_dir}/code/env.sh"    # 모든 변수: 경로, 기본값, DRY_RUN, VSE_MODE
source "${script_dir}/code/common.sh" # run_cmd(), run_vse(), log(), error_exit()
```

기본값은 `code/env.sh`에, 공유 함수는 `code/common.sh`에 위치합니다.
자식 스크립트는 `script_dir`을 상속하고 동일한 파일을 source — 단일 소스.

---

## 2. 에러 처리

### Legacy

```bash
set -e           # 오류 시 종료, 하지만 미설정 변수/파이프 실패는 처리 안 됨
# trap 없음 — CTRL+C 시 워크스페이스가 dangling 상태로 남음
# 명시적 에러 메시지 없음: 스크립트가 조용히 종료
```

### 현재

```bash
set -euo pipefail
# -e  : 오류 시 종료
# -u  : 미설정 변수 참조 시 종료
# -o pipefail : 파이프 내 어떤 명령이라도 실패하면 파이프 전체 실패

# Trap: teardown worker를 항상 정리
_cleanup() {
    if [[ -n "${main_done_flag}" && ! -f "${main_done_flag}" ]]; then
        touch "${main_done_flag}" 2>/dev/null || true
    fi
    if [[ -n "${teardown_worker_pid}" ]]; then
        wait "${teardown_worker_pid}" 2>/dev/null || true
    fi
}
trap '_cleanup' EXIT INT TERM

# common.sh의 명시적 메시지
error_exit() { log "ERROR: $*"; exit 1; }
```

---

## 3. 경로 관리

### Legacy

```bash
# 현재 작업 디렉토리에 따라 경로가 달라짐
../../code/init.sh -ws $ws_name -proj $proj_name $libname
cp ../../code/cdsLibMgr.il $ws_name/
rm -rf code/$replays_folder
python3 code/generate_templates.py ...
```

특정 서브디렉토리에서 호출된다고 가정. 프로젝트 루트에서 실행하면 즉시 깨짐.

### 현재

```bash
# 모든 경로가 script_dir에 고정 — 시작 시 한 번만 결정
run_cmd "rm -rf \"${script_dir}/code/${replays_folder}\""
run_cmd "python3 \"${script_dir}/code/generate_templates.py\" ..."
run_cmd "mv -f \"${script_dir}/code/${replays_folder}/replay_${num}.il\" \"${testdir}/\""
```

어떤 작업 디렉토리에서 호출해도 올바르게 동작합니다.

---

## 4. 테스트 실행 — 순차 vs 병렬

### Legacy — 순차 for 루프

```bash
# legacy/1_cico/main.sh
for i in $tests; do
    three_digit_num=$(printf "%03d" $i)
    testdir=$(pwd)/"$regression_test_name"/test_$three_digit_num

    echo "Running test $three_digit_num in $testdir"
    (
        cd $testdir || exit 1
        ../../code/init.sh -ws $ws_name -proj $proj_name $libname || true
        cp ../../code/cdsLibMgr.il $ws_name/
        virtuoso -replay ../replay_$three_digit_num.il \
            -log ../../../CDS_log/$uniqueid/CDS_$three_digit_num".log" || true
        ../../code/teardown.sh -ws $ws_name -proj $proj_name
    )
done
```

한 번에 하나씩. 총 실행 시간 = 모든 테스트 시간의 합.

### 현재 — xargs 병렬 워커

```bash
# main.sh
printf "%s\n" "${tests[@]}" | \
    xargs -n1 -P"${jobs}" bash "${script_dir}/code/run_single_test.sh"
```

```
시간 ──────────────────────────────────────────────────────────►
  (legacy)
    test_001 ────────────────────────────────────────────────────►
                                                   test_002 ─────►

  (현재, -j 4)
    test_001 ██████████████████████████
    test_002 ██████████████████████████
    test_003 ██████████████████████████
    test_004 ██████████████████████████
    test_005               ████████████  ← 슬롯 해방 시 시작

  10개 테스트 × 5분 / 4 워커 ≈ 15분  (순차 대비 ~3배 빠름)
```

`run_single_test.sh`는 테스트 번호를 받고, `libname`, `regression_dir`, `uniqueid`는
export된 환경 변수로 전달 — 조율자와 깔끔하게 분리.

---

## 5. VSE 호출

### Legacy — 바이너리 직접 호출

```bash
# legacy/1_cico/main.sh (테스트 루프 안)
virtuoso \
    -replay ../replay_$three_digit_num.il \
    -log ../../../CDS_log/$uniqueid/CDS_$three_digit_num".log" || true
```

- `virtuoso` 바이너리에 하드코딩 — `vse_run`/`vse_sub` 전환 불가
- `|| true`로 에러를 조용히 무시
- 버전 지정 없음
- ICM 환경 설정 없음

### 현재 — run_vse() 래퍼

```bash
# code/run_single_test.sh
run_vse "./${testtype}_${lib}.au" "${script_dir}/CDS_log/${uniqueid}/..."
```

```bash
# code/common.sh — run_vse()
run_vse() {
    local replay_file="$1" log_file="$2"
    if [[ "${VSE_MODE}" == "sub" ]]; then
        vse_out=$(vse_sub -v "${VSE_VERSION}" -env "${ICM_ENV}" \
                          -replay "${replay_file}" -log "${log_file}")
        job_id=$(...)
        # bjobs 10초마다 폴링: DONE → 성공, EXIT → 실패
        while true; do
            stat=$(bjobs -noheader -o stat "${job_id}")
            [[ "${stat}" == "DONE" ]] && break
            [[ "${stat}" == "EXIT" ]] && error_exit "VSE job failed"
            sleep 10
        done
    else
        run_cmd "vse_run -v \"${VSE_VERSION}\" -env \"${ICM_ENV}\" \
                         -replay \"${replay_file}\" -log \"${log_file}\""
    fi
}
```

스크립트 수정 없이 런타임에 전환:
```bash
VSE_MODE=sub ./main.sh -m 10     # 배치 제출 + bjobs 폴링
VSE_MODE=run ./main.sh -m 10     # 동기 vse_run
```

---

## 6. Teardown 전략

### Legacy — 인라인, 블로킹

```bash
# 테스트 루프 안
(
    cd $testdir || exit 1
    ...
    ../../code/teardown.sh -ws $ws_name -proj $proj_name
)
# test_001 teardown이 완료되어야 test_002가 시작됨
```

Teardown이 테스트 시작을 블로킹합니다. 또한 스크립트가 루프 중간에 중단되면
남은 모든 워크스페이스가 leak됩니다.

### 현재 — 백그라운드 큐 워커

```
main.sh (포그라운드)              teardown_worker.sh (백그라운드)
─────────────────────             ──────────────────────────────
test_001 완료                     teardown_queue.txt 폴링 (2초)
  → uniquetestid_001 큐 추가 ──► dequeue → teardown.sh
test_002 완료
  → uniquetestid_002 큐 추가 ──► dequeue → teardown.sh
...
touch main_done.flag         ──► 플래그 + 빈 큐 확인 → 종료
```

Teardown과 테스트 실행이 동시에 진행됩니다.
main.sh가 강제 종료되어도 `_cleanup()` trap이 done flag를 설정하여 워커가 깔끔하게 종료됩니다.

---

## 7. 회귀 디렉토리 관리

### Legacy

```bash
# 타임스탬프 기반 — 실행마다 이름이 달라짐
regression_test_name=regression_test_"$user_name"_"$dateno"

# 마지막에 삭제 (debug 모드 아닌 경우)
rm -rf $regression_test_name || true
```

이전 실행의 기록이 없습니다. 매 실행마다 예측 불가능한 이름의 디렉토리를 만들고 끝에 삭제합니다.

### 현재

```bash
# 카운터 기반: regression_test_001, 002, ...
create_regression_dir() {
    num=$(<"${script_dir}/regression_num.txt")   # 마지막 카운터 읽기
    while true; do
        num=$(printf "%03d" $(( (10#${num} + 1) % 1000 )))
        dir="${script_dir}/regression_test_${num}"
        [[ ! -d "${dir}" ]] && break             # 사용 가능한 다음 번호 찾기
    done
    echo "${num}" > "${script_dir}/regression_num.txt"
    regression_dir="${dir}"
}
```

예측 가능한 순차 이름. `teardown_all.sh`로 명시적으로 삭제하기 전까지 보존됩니다.

---

## 8. DRY_RUN 시스템

### Legacy — 없음

모든 실행이 실제 GDP / p4 / VSE 호출을 시도합니다.
스크립트 로직 자체를 테스트하려면 전체 인프라가 필요했습니다.

### 현재 — 3단계

```
레벨 2 : 출력만  — log "[DRY-RUN:2] Would: <cmd>"
레벨 1 : 목업    — gdp/xlp4/rm/vse 건너뜀; 로컬 워크스페이스 디렉토리 생성
레벨 0 : 프로덕션 — 모든 명령 실행
```

```bash
# 실행 없이 main.sh가 무엇을 할지 미리보기
./main.sh -d 2

# 로컬 목업 워크스페이스로 전체 스모크 테스트
./main.sh -m 5 -d 1
```

---

## 9. 로깅

### Legacy

```bash
echo "Running test $three_digit_num in $testdir"
echo "All selected tests finished."
# 타임스탬프 없음, 로그 파일 없음, 중앙 로그 없음
```

### 현재

```bash
# main.sh — 모든 stdout/stderr를 타임스탬프 로그 파일로 리다이렉트
mkdir -p "${script_dir}/log"
logfile="${script_dir}/log/main.log.$(date +%Y%m%d_%H%M%S).txt"
exec > >(tee "${logfile}") 2>&1

# common.sh — 모든 메시지는 log()를 통해
log() { echo "[$(date +%H:%M:%S)] $*"; }
```

터미널과 로그 파일이 동일한 출력을 동시에 받습니다.
`log/` 디렉토리에 로그가 누적되어 실행 비교에 활용됩니다.

---

## 10. 상세 사용법 비교

### Legacy 옵션

```
./main.sh [OPTIONS]
  -m, --max N          최대 케이스 번호                 (기본값: 256)
  -c, --cases LIST     쉼표 구분 또는 범위
  -ws, --ws_name NAME  워크스페이스 이름                (기본값: cadence_cico_ws_<user>_<date>)
  -proj, --proj_name   프로젝트 이름                    (기본값: cadence_cico_<user>_<date>)
  -lib, --libname      라이브러리 이름                  (기본값: ESD01)
  -cell, --cellname    셀 이름
  -debug               regression_test_*과 replay 폴더 보존
  -h, --help
```

### 현재 옵션

```
./main.sh [옵션]
  -h  | --help                도움말 출력
  -ws | --ws_name  <name>     워크스페이스 접두사         (기본값: env.sh의 $WS_PREFIX)
  -proj| --proj_prefix <p>    프로젝트 접두사             (기본값: env.sh의 $PROJ_PREFIX)
  -cell| --cell    <name>     셀 이름                     (기본값: env.sh의 $CELLNAME)
  -m  | --max      <n>        테스트 1~N 실행             (기본값: env.sh의 $MAX_CASES)
  -c  | --cases    <list>     특정 테스트: 1,3,5-9
  -j  | --jobs     <n>        병렬 워커 수                (기본값: 4)
  -d  | --dry-run  [0|1|2]    Dry-run 레벨               (기본값: env.sh의 $DRY_RUN)
  -t  | --teardown            테스트 후 백그라운드 teardown
```

주요 차이:
- `-j` / `--jobs`: 새로 추가 — 병렬 수 제어
- `-d` / `--dry-run`: 새로 추가 — 3단계 dry-run
- `-t` / `--teardown`: 인라인 teardown 대체 (선택 사항)
- `-debug`: 제거 — teardown은 이제 `-t`와 `teardown_all.sh`로 명시적 처리
- `-lib`: 제거 — libname은 `env.sh`에서 한 번만 설정

---

## 11. 주요 파일 변경 내역

| 파일 | Legacy | 현재 |
|---|---|---|
| `main.sh` | 148줄, 포맷 없음, 모든 로직 인라인 | 구조화, 모듈화, 자식 스크립트에 위임 |
| `code/env.sh` | 없음 — 변수들이 main.sh에 인라인 | 중앙 설정: 모든 경로, 기본값, `DRY_RUN`, `VSE_MODE` |
| `code/common.sh` | 없음 | `run_cmd()`, `run_vse()`, `log()`, `error_exit()`, `_mock_gdp_workspace()` |
| `code/init.sh` | 하드코딩 경로, DRY_RUN 없음, script_dir 없음 | `script_dir` 기반, DRY_RUN 인식, `error_exit` |
| `code/run_single_test.sh` | 없음 — 테스트 루프가 main.sh에 인라인 | 테스트당 전용 스크립트: init + run_vse + teardown 큐 추가 |
| `code/teardown_worker.sh` | 없음 — teardown이 테스트 루프에 인라인 | 백그라운드 큐 워커 |
| `code/teardown_all.sh` | `code/ICM_deleteProj.sh` (수동) | 회귀 디렉토리 순회, 테스트당 `teardown.sh` 호출 |
| `code/summary.sh` | 마지막에 호출: `code/summary.sh $uniqueid` | DRY_RUN 포함: `bash summary.sh -d ${DRY_RUN} ${uniqueid}` |
