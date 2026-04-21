# CAT - Performance 테스트 실행 가이드 (perf_main.sh)

## 1. 이 프로그램은 무엇을 하는가?

`perf_main.sh`는 **Virtuoso 기능별 처리 시간(Performance) 측정 자동화 도구**입니다.

여러 라이브러리와 테스트 타입 조합으로 Virtuoso 동작을 실행하고, 각 테스트에 걸린 시간을 측정하여 요약 리포트를 생성합니다.

각 테스트는 **Managed 워크스페이스**와 **Unmanaged 워크스페이스** 두 가지 모드로 실행되며, 두 환경 간 성능 차이를 비교할 수 있습니다.

### Managed vs Unmanaged 워크스페이스

| 구분 | Managed | Unmanaged |
|------|---------|-----------|
| 타입 | ICM 관리 (DMTYPE: p4) | 로컬 전용 (DMTYPE: none) |
| 위치 | `WORKSPACES_MANAGED/<ws_name>/` | `WORKSPACES_UNMANAGED/<ws_name>/` |
| 특징 | GDP/Perforce에 등록됨 | GDP에 미등록, xlp4 sync 완료 후 독립 |

### 내부 동작 흐름 (단계별)

| 단계 | 내용 |
|------|------|
| 1. Replay 생성 | `perf_generate_replay.sh` → `.au` 파일 생성 (결과 경로 하드코딩) |
| 2. 워크스페이스 초기화 | `perf_init.sh` → GDP 프로젝트/라이브러리/워크스페이스 생성 |
| 3. Replay 배포 | 생성된 `.au` 파일을 각 워크스페이스에 복사 |
| 4. 테스트 실행 | `perf_run_single.sh` → Virtuoso 실행 + 경과 시간 기록 |
| 5. Teardown (선택) | `perf_teardown.sh` → 워크스페이스 삭제 |
| 6. 결과 요약 | `perf_summary.sh` → 테스트별 소요 시간 테이블 출력 |

### 워크스페이스 추적 방식

세션 파일 없이 **디렉토리 스캔 방식**으로 워크스페이스를 추적합니다.

- 활성 워크스페이스는 `WORKSPACES_MANAGED/` 디렉토리에 존재
- 각 라이브러리/테스트 조합에는 워크스페이스가 **최대 1개**만 존재 가능
- 같은 조합이 이미 있으면 init을 자동으로 스킵

```
WORKSPACES_MANAGED/
  perf_checkHier_BM01_20260422_093015_john/   ← 워크스페이스 1개
  perf_renameRefLib_BM02_20260422_093020_john/ ← 워크스페이스 1개
```

---

## 2. 사전 준비 (Prerequisites)

### 2.1 환경 변수 설정 (`code/env.sh` 편집)

| 변수 | 의미 | 예시 |
|------|------|------|
| `PERF_PREFIX` | 워크스페이스 이름 접두사 | `perf` |
| `PERF_GDP_BASE` | Perf 전용 GDP 경로 | `<GDP_BASE>/perf` |
| `PERF_LIBS` | 테스트 라이브러리 목록 | `(BM01 BM02 BM03)` |
| `PERF_CELLS` | 각 라이브러리에 대응하는 셀 이름 | `(VP_FULLCHIP FULLCHIP XE_FULLCHIP_BASE)` |
| `PERF_TESTS` | 테스트 타입 목록 | `(checkHier renameRefLib ...)` |
| `GDP_BASE` | 사용자별 GDP 기반 경로 | `/MEMORY/TEST/CAT/CAT_WORKING/<user>` |
| `FROM_LIB` | 원본 라이브러리 GDP 경로 | `/MEMORY/TEST/CAT/CAT_LIB/TEST_PRJ/rev1/oa` |
| `VSE_VERSION` | Virtuoso 버전 태그 | `IC251_ISR5-023_CAT` |

**중요:** `PERF_LIBS`와 `PERF_CELLS`의 순서가 일치해야 합니다.  
예: `PERF_LIBS[0]=BM01` ↔ `PERF_CELLS[0]=VP_FULLCHIP`

### 2.2 필요한 외부 도구

- `gdp` — IC Manage GDP 클라이언트 (PATH에 있어야 함)
- `xlp4` — Perforce 클라이언트 래퍼
- `python3` — Replay 파일 생성용
- Virtuoso (`vse_run` 또는 `vse_sub`) — 테스트 실행 엔진
- `createReplay.pl` — Replay `.au` 파일 생성 Perl 스크립트

### 2.3 GDP 접속 확인

```bash
gdp list /MEMORY/TEST/CAT/CAT_LIB
```

오류 없이 목록이 나오면 정상입니다.

---

## 3. 기본 사용법

### 옵션 목록

```
./perf_main.sh [options]

  -h            도움말 출력
  -lib <list>   테스트할 라이브러리 (쉼표 구분, 기본: 전체)
                  유효값: BM01 BM02 BM03
  -test <list>  실행할 테스트 타입 (쉼표 구분, 기본: 전체)
                  유효값: checkHier renameRefLib replace deleteAllMarker
                          copyHierToEmpty copyHierToNonEmpty
  -common <list> 모든 테스트 조합에 추가되는 공통 라이브러리 (어떤 이름도 허용)
  -mode <mode>  실행 모드 (기본: 둘 다 실행)
                  managed | unmanaged
  -j <n>        병렬 실행 개수 (기본: 4)
  -d [0|1|2]    Dry-run 수준
                  0 = 실제 실행
                  1 = gdp/xlp4/rm/vse 명령 스킵 (목업)
                  2 = 모든 명령 스킵 (출력만)
  -gen-replay   Replay 파일만 생성 (init/run 없음)
  -no-run       Init 단계만 실행 (테스트 실행 스킵)
  -t            Teardown 실행 (-lib/-test 필터 적용)
  -auto-init    워크스페이스 없을 때 자동으로 init 실행 (프롬프트 없음)
```

---

## 4. 단계별 사용 예시

### Step 0: Dry-run으로 동작 확인

```bash
./perf_main.sh -d 2
```

어떤 명령이 실행될지 미리 출력만 됩니다. 실제 GDP/파일 변경 없음.

### Step 1: 워크스페이스 초기화 (처음 실행 시)

```bash
./perf_main.sh -no-run -lib BM01,BM02 -test checkHier,renameRefLib
```

- GDP에 프로젝트/라이브러리 생성
- Managed + Unmanaged 워크스페이스 디렉토리 구성
- 이미 존재하는 조합은 자동 스킵

완료 후 워크스페이스 확인:

```bash
ls WORKSPACES_MANAGED/
```

### Step 2: 테스트 실행

```bash
./perf_main.sh -lib BM01,BM02 -test checkHier,renameRefLib
```

실행할 때마다 새로운 uniqueid가 생성되어 결과가 독립적으로 저장됩니다.

특정 모드만 실행:

```bash
./perf_main.sh -lib BM01 -test checkHier -mode managed
```

### Step 3: 결과 확인

```
CDS_log/<uniqueid>/
  timing.tsv              ← 테스트별 경과 시간 (raw)
  perf_summary.txt        ← 형식화된 요약 리포트
  checkHier_BM01_managed.log    ← Virtuoso 실행 로그
  checkHier_BM01_unmanaged.log
```

`perf_summary.txt` 예시:

```
Performance Summary (20260422_093015_john)
================================================================
Test (testtype/lib)          Mode         Elapsed
----------------------------------------------------------------
checkHier/BM01               managed      00:02:34
checkHier/BM01               unmanaged    00:01:58
renameRefLib/BM02            managed      00:03:10
renameRefLib/BM02            unmanaged    00:02:45
----------------------------------------------------------------

Total  (4 tests)                          00:10:27
Average                                   00:02:36
```

### Step 4: 워크스페이스 teardown

특정 조합만 정리:

```bash
./perf_main.sh -no-run -t -lib BM01 -test checkHier
```

전체 정리:

```bash
./perf_main.sh -no-run -t
```

---

## 5. 사용 목적별 예시

### 처음 환경 구성부터 테스트까지 한 번에

```bash
./perf_main.sh -auto-init -t -lib BM01 -test checkHier
```

- 워크스페이스 없으면 자동으로 init
- 테스트 완료 후 자동 teardown

### 반복 측정 (동일 워크스페이스로 여러 번 실행)

워크스페이스는 한 번만 초기화하고 테스트만 반복합니다.

```bash
# 최초 1회: 워크스페이스 초기화
./perf_main.sh -no-run -lib BM01 -test checkHier

# 이후 반복 실행: 매번 새로운 결과 저장
./perf_main.sh -lib BM01 -test checkHier
./perf_main.sh -lib BM01 -test checkHier
```

### Managed 모드만 측정

```bash
./perf_main.sh -mode managed
```

### 공통 라이브러리 추가 (모든 테스트에 포함)

```bash
./perf_main.sh -lib BM01 -common COMMON_LIB1,COMMON_LIB2
```

`-common`으로 지정한 라이브러리는 사전 등록된 이름이 아니어도 허용됩니다.

### Replay 파일만 생성 (실행 없음)

```bash
./perf_main.sh -gen-replay -lib BM01 -test checkHier
```

생성 결과: `GenerateReplayScript/checkHier_BM01_managed.au` 등

### 전체 조합 실행 + teardown

```bash
./perf_main.sh -auto-init -t -j 8
```

---

## 6. 주요 개념 이해

### uniqueid

- 형식: `YYYYMMDD_HHMMSS_<user>`
- **Init 단계**: 워크스페이스 이름에 포함 (`perf_checkHier_BM01_<uniqueid>`)
- **Run 단계**: CDS 로그 및 결과 저장 경로에 포함 (`CDS_log/<uniqueid>/`)
- 실행할 때마다 새로 생성되므로 결과가 겹치지 않습니다

### Replay 파일 (.au)

- Virtuoso에 전달되는 자동화 스크립트
- 내부에 결과 저장 경로(uniqueid 포함)가 **하드코딩**되어 있음
- 따라서 매번 실행 시 새로 생성 후 워크스페이스에 배포됩니다

### 워크스페이스 명명 규칙

```
perf_<testtype>_<lib>_<uniqueid>
예: perf_checkHier_BM01_20260422_093015_john
```

---

## 7. 로그 및 결과 파일 위치

| 위치 | 내용 |
|------|------|
| `log/perf_main.log.<timestamp>.txt` | 전체 실행 로그 |
| `WORKSPACES_MANAGED/<ws_name>/` | Managed 워크스페이스 디렉토리 |
| `WORKSPACES_UNMANAGED/<ws_name>/` | Unmanaged 워크스페이스 디렉토리 |
| `GenerateReplayScript/*.au` | 생성된 Replay 파일 |
| `CDS_log/<uniqueid>/timing.tsv` | 테스트별 경과 시간 (탭 구분) |
| `CDS_log/<uniqueid>/perf_summary.txt` | 형식화된 성능 요약 리포트 |
| `CDS_log/<uniqueid>/<testtype>_<lib>_<mode>.log` | 개별 Virtuoso 실행 로그 |
| `result/<uniqueid>/` | 테스트 결과 데이터 |

---

## 8. 자주 발생하는 오류와 해결 방법

| 오류 메시지 | 원인 | 해결 방법 |
|-------------|------|-----------|
| `No workspaces found... Run init first with -no-run` | 워크스페이스가 없는 상태에서 테스트 실행 시도 | `./perf_main.sh -no-run -lib <lib> -test <test>` 로 먼저 초기화 |
| `Unknown lib: XYZ` | `-lib`에 등록되지 않은 라이브러리 지정 | `env.sh`의 `PERF_LIBS` 확인 (`-common`은 제한 없음) |
| `Unknown test: XYZ` | `-test`에 존재하지 않는 테스트 타입 지정 | `env.sh`의 `PERF_TESTS` 확인 |
| `gdp build workspace failed after 5 attempts` | GDP 서버 부하 또는 네트워크 문제 | 잠시 후 재시도, 또는 IT 지원 요청 |
| `Workspace not found via gdp find` | 워크스페이스가 GDP에 등록되지 않음 | `WORKSPACES_MANAGED/` 디렉토리 수동 확인, 필요 시 teardown 후 재초기화 |
| `.gdp_ws_lock` 파일 남아있음 | 이전 실행이 비정상 종료됨 | `rm .gdp_ws_lock` 후 재실행 |

---

## 9. 중요 참고 사항

- **`--max`와 `--cases`는 perf_main.sh에 없습니다.** 테스트 범위는 `-lib`, `-test`, `-mode`로 지정합니다.
- **Ctrl+C를 누르면** `_cleanup()` trap이 실행되어 lock 파일이 자동 정리됩니다.
- **같은 라이브러리/테스트 조합**으로 init을 여러 번 실행해도 기존 워크스페이스를 덮어쓰지 않습니다 (스킵됩니다).
- **Replay 파일은 실행할 때마다 자동으로 재생성**됩니다. 수동으로 생성할 필요가 없습니다.
- `gdp build workspace`는 GDP 서버 부하를 줄이기 위해 **순차 직렬화**(flock)되어 실행됩니다.
