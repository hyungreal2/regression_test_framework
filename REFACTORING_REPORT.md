# CAT Regression Framework 리팩토링 보고서

**작성일**: 2026-03-30
**대상**: `main.sh`, `code/init.sh`, `code/teardown.sh` (v0 → 현재)
**저장소**: https://github.com/hyungreal2/regression_test_framework

---

## 1. 개요

기존 v0 스크립트들은 편집기 오류로 1줄로 붙어있었으며, 하드코딩된 경로·변수, 직렬 실행, dry-run 미지원, uniqueid 파일 의존성 등의 문제를 가지고 있었다. 이를 가독성, 유지보수성, 안전성, 재사용성 측면에서 전면 리팩토링하였다.

---

## 2. 공통 적용 사항 (전 스크립트)

| 항목 | v0 | 현재 |
|------|----|------|
| 오류 처리 | `set -e` | `set -euo pipefail` (미정의 변수·파이프 오류도 감지) |
| 변수 참조 | `$var` | `${var}` (모든 변수에 일관 적용) |
| 로그 출력 | `echo` 직접 호출 | `log()` / `warn()` / `error_exit()` 함수 사용 |
| 명령 실행 | 직접 실행 | `run_cmd()` 래퍼로 DRY_RUN 제어 |
| 환경 설정 | 스크립트마다 하드코딩 | `code/env.sh`로 중앙화 |
| 변수 명명 | 혼재 | `env.sh` 정의 변수: 대문자 / 스크립트 로컬: 소문자 |
| 명령 인자 인용 | 불규칙 | 모든 인자 `"${}"` 형식으로 통일 |

---

## 3. 파일별 변경 사항

### 3.1 `main.sh`

#### 구조 변경
- 단일 스크립트 → 함수 분리 (`validate_inputs`, `generate_templates`, `get_tests`, `create_regression_dir`, `prepare_tests`, `run_tests`)
- 테스트 실행 루프 → `code/run_single_test.sh`로 분리 (신규)
- teardown 로직 → `code/teardown_all.sh`로 분리 (신규)

#### uniqueid 처리 방식
| v0 | 현재 |
|----|------|
| `init.sh`에서 생성 후 파일(`/tmp/uniqueid_cico_$user`)에 저장 | `run_single_test.sh`에서 `test_id_timestamp_PID` 형식으로 생성 후 환경변수로 전달 |
| 하위 스크립트가 `source $uniqueid_path`로 읽음 | `export uniqueid` → 하위 프로세스가 직접 참조 |

#### 테스트 실행 방식
| v0 | 현재 |
|----|------|
| `for i in $tests` 직렬 실행 | `xargs -n1 -P${jobs}` 병렬 실행 |
| 병렬 수 고정 | `-j / --jobs <n>` 옵션으로 조정 가능 (기본값: 4) |

#### CLI 옵션
| v0 | 현재 |
|----|------|
| 옵션 없음 (변수 직접 수정) | `-h/--help`, `-ws/--ws_name`, `-proj/--proj_prefix`, `-cell/--cell`, `-m/--max`, `-c/--cases`, `-j/--jobs`, `-d/--dry-run`, `-t/--teardown` |

#### 버그 수정
- `regression_num.txt` 없을 때 카운터 초기화 누락 → 정상 처리
- `CDS_log/` 디렉토리 미생성 상태로 테스트 실행 → `mkdir -p CDS_log` 추가

---

### 3.2 `code/init.sh`

#### 인터페이스 변경
| v0 | 현재 |
|----|------|
| `-ws`, `-proj`, `-id` 인자로 ws/proj/uniqueid_path 수신 | `WS_PREFIX`, `PROJ_PREFIX`, `uniqueid` 환경변수로 수신 |
| 스크립트 내부에서 `uniqueid` 생성 (`date +%Y%m%d_%H%M%S`) | 호출자(run_single_test.sh)가 생성하여 export |
| `echo uniqueid=$uniqueid > $uniqueid_path` 파일 저장 | 환경변수 직접 사용, 파일 불필요 |

#### 하드코딩 경로 제거
| v0 | 현재 |
|----|------|
| `/MEMORY/TEST/CAT` 직접 기입 | `${GDP_BASE}` (env.sh) |
| `/MEMORY/TEST/testProj/testVar/oa` 직접 기입 | `${FROM_LIB}` (env.sh) |

#### 코드 정리
- `lib_from` / `lib_to` 구분 제거 (동일 값 사용)
- 모든 gdp 명령 앞에 `log` 메시지 추가
- `run_cmd` 래퍼 적용으로 DRY_RUN 지원

---

### 3.3 `code/teardown.sh`

#### 인터페이스 변경
| v0 | 현재 |
|----|------|
| `-ws`, `-proj`, `-id` 인자로 수신 | `uniqueid` 환경변수로 수신, ws/proj명 자동 조합 |
| `source $uniqueid_path`로 uniqueid 읽음 | `export uniqueid` 직접 참조 |

#### 보안 개선
| v0 | 현재 |
|----|------|
| `chmod -R 777 $ws_local_path/.gdpxl` | `chmod -R u+w "${ws_local_path}/.gdpxl"` (최소 권한 원칙) |
| `rm -rf $ws_local_path` 직접 호출 | `safe_rm_rf()` 사용 (경로 안전 검사 포함) |

#### 버그 수정
- xlp4 client 삭제가 `ws_gdp_path` 조건 블록 안에 있어 ws를 찾지 못하면 client 삭제 누락 → 조건 블록 밖으로 이동
- `/tmp/null_$user_name` 임시 파일 사용 → `|| true` 패턴으로 대체

#### DRY_RUN 처리
| v0 | 현재 |
|----|------|
| DRY_RUN 미지원 | `gdp find` / `gdp list` 포함 전체 명령 `run_cmd` 캡처 방식으로 통일 |
| `gdp find` 결과를 직접 `$()` 캡처 | `ws_gdp_path=$(run_cmd "gdp find ...")` → dry-run 시 빈 문자열 반환 |

#### 기타
- `pushd` / `popd` 제거 (불필요한 디렉토리 스택 사용)
- `chmod` 에 `log` + `run_cmd` 적용

---

## 4. 신규 추가 파일

| 파일 | 역할 |
|------|------|
| `code/env.sh` | 환경 설정 중앙화 (경로, 버전, prefix 등) — git 미추적 |
| `code/env_sample.csh` | csh 사용자용 env 템플릿 (더미값) |
| `code/common.sh` | 공통 유틸리티: `log`, `warn`, `error_exit`, `run_cmd`, `safe_rm_rf`, `format_num` |
| `code/run_single_test.sh` | 단일 테스트 실행 (init → vse_sub → job_id 파싱 → bwait) |
| `code/teardown_all.sh` | regression 디렉토리 내 전체 테스트 일괄 teardown |
| `code/summary.sh` | CDS 로그 파싱 후 PASS/FAIL 요약 파일 생성 |
| `code/generate_templates.py` | `replay_001.il` ~ `replay_240.il` 템플릿 생성 (Python 3, 표준 라이브러리) |
| `clean.sh` | 생성 산출물 전체 제거 |
| `.gitignore` | `env.sh`, `regression_test_*/`, `CDS_log/` 등 제외 |
| `README.md` | 전체 사용법 문서 |

---

## 5. DRY_RUN 체계

v0에는 dry-run 개념이 없어 실제 환경 없이 스크립트 검증이 불가능했다.

| 레벨 | 동작 |
|------|------|
| `0` | 모든 명령 실제 실행 |
| `1` | `gdp`, `xlp4`, `rm`, `vse_sub`, `vse_run`, `bwait` 스킵 / `gdp build workspace`는 로컬 디렉토리 생성으로 모킹 |
| `2` | 모든 명령 스킵 (출력만) |

- dry-run 메시지는 **stderr**로 출력 → `result=$(run_cmd "cmd")` 패턴으로 출력 캡처 가능

---

## 6. `run_single_test.sh` 주요 변경 (신규 분리)

- uniqueid: `test_id_YYYYmmdd_HHMMSS_PID` 형식 (병렬 실행 시 충돌 방지)
- `ln -s` → `ln -sf` (기존 링크 덮어쓰기 안전 처리)
- `libname`, `regression_dir` 환경변수 유무 검증 추가
- `test_id` 정수 검증 추가
- `vse_sub` 출력 → `awk -F'[<>]' '{print $2}'`로 `job_id` 파싱
- `bwait -w "ended(${job_id})"` 으로 job 완료 대기

---

## 7. 커밋 이력 요약

| 커밋 | 내용 |
|------|------|
| `f7c9f68` | Initial commit (리포맷 + 초기 리팩토링) |
| `1dd6fbc` | WS_NAME → WS_PREFIX, ws_full → WS_NAME 명칭 정리 |
| `73e03c1` | 코드 리뷰 5개 이슈 수정 (CDS_log 생성, ln -sf, 검증, tmp 정리, 로컬 디렉토리 누수) |
| `d213e75` | DRY_RUN 서브프로세스 전파 버그 수정 |
| `1b96e22` | gdp find/list DRY_RUN 우회 버그 수정 |
| `8e89ce3` | 변수 소문자화, `${}` 전체 적용 |
| `c4b8dd1` | 모든 run_cmd 앞 log 메시지 추가 |
| `324e2ba` | chmod run_cmd 래퍼 적용 |
| `ebf969b` | 코드 리뷰 2차 수정 + summary.sh 추가 |
| `75b703a` | job_id awk 파싱, sleep 제거 |
| `dc41358` | init.sh 로컬 변수 소문자 적용 |
| `94c4415` | vse_run skip 목록 추가, perf_main.sh 추가 |
