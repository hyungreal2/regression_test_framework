# CAT - CICO 회귀 테스트 실행 가이드 (main.sh)

## 1. 이 프로그램은 무엇을 하는가?

`main.sh`는 **CICO (Check-In Check-Out) 회귀 테스트 자동화 도구**입니다.

ESD01 같은 IC 설계 라이브러리를 대상으로, Virtuoso 스크립트(replay .il 파일)를 생성하고 수십~수백 개의 테스트를 병렬로 실행한 뒤 결과를 요약합니다.

### 내부 동작 흐름 (단계별)

| 단계 | 내용 |
|------|------|
| 1. 환경 검증 | 입력값 확인, GDP 폴더 존재 확인/생성 |
| 2. 템플릿 생성 | `generate_templates.py` 실행 → replay `.il` 파일 자동 생성 |
| 3. 테스트 디렉토리 구성 | `regression_test_NNN/test_NNN/` 폴더 생성 및 replay 파일 배치 |
| 4. 병렬 테스트 실행 | `run_single_test.sh`를 `-j` 개수만큼 동시 실행 |
| 5. Teardown (선택) | 테스트 후 워크스페이스 삭제 |
| 6. 결과 요약 | `summary.sh` 실행 → pass/fail 집계 |

---

## 2. 사전 준비 (Prerequisites)

### 2.1 환경 변수 설정 (`code/env.sh` 편집)

| 변수 | 의미 | 예시 |
|------|------|------|
| `LIBNAME` | 테스트 대상 라이브러리 이름 | `ESD01` |
| `CELLNAME` | 테스트 대상 셀 이름 | `FULLCHIP` |
| `WS_PREFIX` | 워크스페이스 이름 앞에 붙는 접두사 | `cico_ws_<user>` |
| `PROJ_PREFIX` | GDP 프로젝트 이름 접두사 | `cico_<user>` |
| `FROM_LIB` | 원본 라이브러리 GDP 경로 | `/MEMORY/TEST/CAT/CAT_LIB/TEST_PRJ/rev1/oa` |
| `GDP_BASE` | 사용자별 GDP 작업 기반 경로 | `/MEMORY/TEST/CAT/CAT_WORKING/<user>` |
| `MAX_CASES` | 테스트 케이스 최대 번호 | `256` |
| `VSE_VERSION` | Virtuoso 버전 태그 | `IC251_ISR5-023_CAT` |

### 2.2 필요한 외부 도구

- `gdp` — IC Manage GDP 클라이언트 (PATH에 있어야 함)
- `xlp4` — Perforce 클라이언트 래퍼
- `python3` — 템플릿 생성 스크립트 실행
- Virtuoso (`vse_run` 또는 `vse_sub`) — 테스트 실행 엔진

### 2.3 GDP 접속 확인

```bash
gdp list /MEMORY/TEST/CAT/CAT_LIB
```

오류 없이 목록이 나오면 정상입니다.

---

## 3. 기본 사용법

### 옵션 목록

```
./main.sh [options]

  -h     | --help             도움말 출력
  -lib   | --library <name>   라이브러리 이름         (기본: env.sh의 LIBNAME)
  -ws    | --ws_name <name>   워크스페이스 이름 접두사 (기본: cico_ws_<user>)
  -proj  | --proj_prefix <p>  GDP 프로젝트 접두사   (기본: cico_<user>)
  -cell  | --cell <name>      셀 이름               (기본: env.sh의 CELLNAME)
  -m     | --max <n>          최대 테스트 번호 1~256  (기본: MAX_CASES)
  -c     | --cases <list>     실행할 테스트 번호 목록 (예: 1,3,5-9)
  -j     | --jobs <n>         병렬 실행 개수         (기본: 4)
  -d     | --dry-run [0|1|2]  Dry-run 수준
                                0 = 실제 실행
                                1 = gdp/xlp4/rm/vse 명령 스킵 (목업)
                                2 = 모든 명령 스킵 (출력만)
  -t     | --teardown         테스트 완료 후 워크스페이스 teardown
```

---

## 4. 단계별 사용 예시

### Step 1: 동작 확인 (Dry-run)

실제 명령을 실행하지 않고 어떤 작업이 이루어지는지 미리 확인합니다.

```bash
./main.sh -d 2
```

### Step 2: 소수의 테스트 케이스 먼저 실행

```bash
./main.sh -c 1,2,3
```

또는 범위로 지정:

```bash
./main.sh -c 1-10
```

### Step 3: 전체 테스트 실행

```bash
./main.sh
```

기본값: `MAX_CASES`에 설정된 번호까지 전부 실행, 4개 병렬.

### Step 4: 병렬 수 조정

```bash
./main.sh -j 8
```

### Step 5: 완료 후 자동 teardown

```bash
./main.sh -t
```

---

## 5. 사용 목적별 예시

### 빠른 스모크 테스트 (1~5번만)

```bash
./main.sh -c 1-5
```

### 특정 셀만 테스트

```bash
./main.sh -cell MY_CELL -c 1-20
```

### CI 환경에서 자동 실행 (teardown 포함)

```bash
./main.sh -t -j 8
```

### 다른 라이브러리로 테스트

```bash
./main.sh -lib MY_LIB
```

### 워크스페이스 이름 커스터마이징

```bash
./main.sh -ws my_ws_prefix -proj my_proj_prefix
```

### 결과만 확인하고 환경 정리

```bash
# 이전에 실행한 결과 확인
ls regression_test_*/

# 워크스페이스 수동 teardown (테스트 없이)
./main.sh -d 2 -t   # dry-run으로 어떤 작업이 일어나는지 확인 먼저
./main.sh -t        # 실제 teardown
```

---

## 6. 로그 및 결과 확인

| 위치 | 내용 |
|------|------|
| `log/main.log.<timestamp>.txt` | 전체 실행 로그 |
| `regression_test_NNN/` | 테스트 케이스별 폴더 |
| `regression_test_NNN/test_NNN/` | 개별 테스트 폴더 (replay 파일 포함) |
| `CDS_log/<uniqueid>/` | Virtuoso CDS 실행 로그 |
| `result/<uniqueid>/` | 테스트 결과 데이터 |

### uniqueid 형식

```
YYYYMMDD_HHMMSS_<user>_<libname>[_<cellname>]
```

예: `20260422_093015_john_ESD01_FULLCHIP`

각 실행마다 고유한 ID가 생성되어, 여러 번 실행해도 결과가 겹치지 않습니다.

---

## 7. 자주 발생하는 오류와 해결 방법

| 오류 | 원인 | 해결 |
|------|------|------|
| `gdp list` 실패 | GDP 서버 접속 불가 | `gdp` 환경 설정 확인, VPN 연결 확인 |
| `from lib not found` | `FROM_LIB` 경로가 잘못됨 | `env.sh`의 `FROM_LIB` 값 확인 |
| `regression_num.txt` 오류 | 파일 손상 | 파일 삭제 후 재실행 (`rm regression_num.txt`) |
| Virtuoso 실행 실패 | `VSE_VERSION` 설정 오류 | `env.sh`의 `VSE_VERSION` 확인 |
| 병렬 실행 중 일부 실패 | GDP 서버 부하 | `-j` 값을 줄여서 실행 (예: `-j 2`) |

---

## 8. 중요 참고 사항

- **main.sh를 직접 `cd`해서 실행하지 마세요.** `script_dir`이 자동으로 스크립트 위치로 설정됩니다.
- **`--max`와 `--cases`는 동시에 사용할 수 없습니다.**
- Dry-run 레벨 1은 GDP/xlp4 명령을 스킵하므로 로컬 파일 조작만 테스트할 때 유용합니다.
- 테스트 실행 중 Ctrl+C를 누르면 자동으로 teardown worker가 정리됩니다.
