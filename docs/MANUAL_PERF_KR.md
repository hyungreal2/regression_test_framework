# perf 성능 테스트 실행 가이드 (`perf_main.sh`)

ICM 관리(MANAGED) 워크스페이스와 관리하지 않는(UNMANAGED) 워크스페이스에서 같은 Virtuoso 작업에 걸리는 시간을 잽니다.
prod 배치 이름은 `2_perf_mp`이고, 저장소에서는 `suites/perf/`입니다.

---

## 1. 무엇을 하는가

측정 하나 = **템플릿 × 라이브러리 × 모드**입니다.

- 템플릿 7개(`PERF_TESTS`): `checkHier` `renameRefLib` `changeLibRef` `replace` `deleteAllMarker` `copyHierToEmpty` `copyHierToNonEmpty`
- 라이브러리 3개(`PERF_LIBS`/`PERF_CELLS`): BM01(VP_FULLCHIP), BM02(FULLCHIP), BM03(XE_FULLCHIP_BASE)
- 모드: managed, unmanaged

템플릿×라이브러리마다 워크스페이스 한 쌍을 만들어 두고(init), 여러 번 측정한 뒤(run), 필요 없어지면 지웁니다(teardown).

```
init  (perf_init.sh, 한 번)   GDP 프로젝트 → MANAGED 워크스페이스 (WORKSPACES_MANAGED/<ws>)
                               └→ oa/를 옮겨 UNMANAGED 구성 (WORKSPACES_UNMANAGED/<ws>), 원본 사본 .oa_pristine 저장
run   (perf_run_single.sh, 매번)
      replay 생성 → 초기화(측정 제외) → vse_run → 걸린 시간 기록
        MANAGED  : xlp4 revert + sync (+ 덮어쓰기 거부 파일만 sync -f)
        UNMANAGED: .oa_pristine에서 rsync로 oa 복원
summary (perf_summary.sh)     시간 표, legacy 형식 summary.txt, 추세 데이터
teardown (perf_teardown.sh)   p4 client, GDP 워크스페이스·프로젝트, depot, 로컬 디렉터리
```

워크스페이스 이름은 `perf_<템플릿>_<lib>_<날짜>_<시각>_<사용자>`이고, `WORKSPACES_MANAGED/`에 있는 디렉터리가 곧 목록입니다.
같은 템플릿×라이브러리는 하나만 둡니다(이미 있으면 init이 건너뜀).

---

## 2. 준비

cico와 같습니다([MANUAL_CICO_KR.md](MANUAL_CICO_KR.md) §2). 추가로 UNMANAGED 복원에 `rsync`가 필요합니다.
같은 배포 디렉터리에서 perf 실행을 동시에 두 개 돌리지 않습니다(같은 워크스페이스를 서로 초기화합니다).

---

## 3. 옵션

| 옵션 | 설명 | 기본값 |
|---|---|---|
| `-lib <a,b>` | 라이브러리 | 전체 |
| `-test <a,b>` | 템플릿 | 전체 |
| `-mode <m[,m]>` | `managed`, `unmanaged` (둘 다 가능) | 둘 다 |
| `-common <a,b>` | 모든 워크스페이스에 더할 라이브러리 | |
| `-version <ver>` | Virtuoso 버전 | `VSE_VERSION` |
| `-j <n>` | 병렬 수 | 4 |
| `-d [0\|1\|2]` | dry-run 단계 (`-d`만 주면 2) | 0 |
| `-no-run` | init만 | |
| `-auto-init` | 워크스페이스가 없으면 묻지 않고 init | |
| `-t` | teardown (`-lib`/`-test` 적용). 실행과 함께 주면 측정이 실패해도 마지막에 실행 | |
| `-gen-replay` | replay만 생성 | |

---

## 4. 사용 예

```bash
./perf_main.sh -d 2                                           # 전체 흐름 미리보기

# 1) 워크스페이스 만들기 (한 번)
./perf_main.sh -no-run -lib BM01,BM02 -test checkHier,replace

# 2) 측정 (원하는 만큼 반복, 매번 새 결과 폴더)
./perf_main.sh
./perf_main.sh -lib BM01 -mode managed
./perf_main.sh -version IC251SM_ISR8_003-260902

# 3) 정리
./perf_main.sh -no-run -t -lib BM01                           # 일부
./perf_main.sh -no-run -t                                     # 전부

# 한 번에: init → 측정 → teardown
./perf_main.sh -auto-init -t -lib BM01 -test checkHier
```

---

## 5. 결과 보기

| 위치 | 내용 |
|---|---|
| `log/perf_main.log.<시각>.txt` | 실행 로그 |
| `CDS_log/<id>/<템플릿>_<lib>_<mode>.log` | Virtuoso 로그 |
| `CDS_log/<id>/timing.tsv`, `perf_summary.txt` | 스크립트가 잰 시간과 표 |
| `result/<id>/Test<N>_<lib>_<mode>_<ver>.log` | replay가 잰 시간 (`Test1_BM01. Performance ... managed time 123`) |
| `result/<id>/summary.txt` | 결과 파일을 모은 legacy 형식 요약 |
| `perf_metrics/<id>.json`, `.csv`, `history.jsonl`, `history.csv` | 추세 데이터 (실행마다 누적) |

`<id>` = `<날짜>_<시각>_<사용자>`. 종료 코드는 측정·summary·teardown 중 하나라도 실패하면 1이며, 시간 값 자체는 판정하지 않습니다.

---

## 6. 정리

| 상황 | 방법 |
|---|---|
| 워크스페이스 정리 | `./perf_main.sh -no-run -t [-lib ...] [-test ...]` |
| 로컬 디렉터리 없이 GDP에 프로젝트만 남음 | `./code/perf_teardown_all.sh` (목록과 확인 후 삭제, `-y`면 확인 생략). 생성 후 120분이 안 된 프로젝트와 진행 중인 init은 건드리지 않음(`-min-age`) |
| 로컬 결과물 | `./clean.sh` (실제 워크스페이스는 지우지 않음) |

---

## 7. 자주 보는 오류

| 메시지 | 원인과 조치 |
|---|---|
| `No workspaces found matching the specified filters` | init을 먼저 (`-no-run` 또는 `-auto-init`) |
| `MANAGED reset failed: xlp4 sync rc=...` | p4 서버/client 문제로 초기화 실패. 측정하지 않고 그 조합만 실패 처리됨 |
| `No pristine copy ... running without reset` | 예전에 만든 UNMANAGED라 원본 사본이 없음. 정리 후 다시 init |
| `No oa dir in MANAGED workspace after gdp build` | 라이브러리 생성 실패. GDP 로그 확인 |
| `Timing file not found` | 모든 측정이 실패함. 앞선 오류를 확인 |
| `gdp did not answer ... keeping ...` | gdp 응답 없음. 복구 후 `-no-run -t` 다시 |
