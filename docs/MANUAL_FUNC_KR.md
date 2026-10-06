# func 기능 테스트 실행 가이드 (`func_main.sh`)

checkHier, renameRefLib, changeLibRef, replace, deleteAllMarkers, copyHierToEmpty, copyHierToNonEmpty 같은 Virtuoso 기능을
ICM 환경에서 시나리오별로 재생해 검증합니다. prod 배치 이름은 `3_func_mp`이고, 저장소에서는 `suites/func/`입니다.

---

## 1. 무엇을 하는가

mode마다 시나리오 목록 `code/list_<mode>`(변형은 `list_<mode>_<prefix>`)가 있고, 한 줄이 테스트 하나입니다.
단계의 SKILL 코드는 `code/func_control`, 테스트 틀은 `code/func_template.il`입니다.

```
replay 생성 (list 줄 + func_control + func_template_<mode>.il → code/replay_files_<id>/replay_NN.il)
   │  테스트마다 (병렬 -j)
   ├─ GDP 프로젝트·라이브러리·워크스페이스 생성 (code/func_init.sh)
   ├─ Virtuoso replay 실행 → result/<id>/test_NN_<ver>.log
   └─ 끝나면 백그라운드 teardown (code/func_teardown.sh)
판정 (code/func_summary.sh) → result/<id>/summary.txt
```

번호 자릿수는 list 줄 수의 자릿수입니다(17줄이면 `01`, 569줄이면 `001`).

---

## 2. 준비

cico와 같습니다([MANUAL_CICO_KR.md](MANUAL_CICO_KR.md) §2). 원본 라이브러리는 `FROM_LIB/<lib>`에서 복사됩니다.

---

## 3. 옵션

| 옵션 | 설명 |
|---|---|
| `-mode <mode>` | 필수. `checkHier` `renameRefLib` `changeLibRef` `replace` `deleteAllMarkers` `copyHierToEmpty` `copyHierToNonEmpty` |
| `-prefix <p>` | 변형 list (`oo`, `ox`, `xo`, `xx`, `oo_ox` 등) |
| `-lib`, `-cell` | 대상. checkHier/replace/deleteAllMarkers/renameRefLib/changeLibRef에서 필수 |
| `-fromLib`, `-toLib`, `-fromCell` | renameRefLib(`-fromLib -toLib`), changeLibRef(`-toLib`, `-fromLib` 기본 All), copyHier*(`-fromLib -fromCell -toLib`) |
| `-m <n>` / `-M <n>` | 시작 / 끝 번호 |
| `-c <목록>` | 지정 번호만 (`1,3,5-9`) |
| `-j <n>` | 병렬 수 (기본 4) |
| `-d [0\|1\|2]` | dry-run 단계 (기본 0, `-d`만 주면 2) |
| `-ws`, `-proj` | 워크스페이스 / 프로젝트 접두어 (기본 `func_ws_<user>` / `func_<user>`) |
| `-k` | teardown 생략 |
| `-t` | 호환용 (teardown은 기본) |

---

## 4. 사용 예

```bash
./func_main.sh -d 2 -mode checkHier -lib ESD01 -cell FULLCHIP -c 1-3       # 미리보기
./func_main.sh -mode checkHier -lib ESD01 -cell FULLCHIP                     # 전체
./func_main.sh -mode replace -prefix oo -lib ESD01 -cell FULLCHIP -c 1,3,5-9
./func_main.sh -mode renameRefLib -lib ESD01 -cell FULLCHIP -fromLib OldLib -toLib NewLib
./func_main.sh -mode copyHierToEmpty -fromLib SrcLib -fromCell top -toLib DstLib -k   # 환경을 남겨 조사
```

---

## 5. 결과와 판정

| 위치 | 내용 |
|---|---|
| `log/func_main.log.<시각>.txt` | 실행 로그 |
| `CDS_log/<id>/CDS_<mode>_NN.log` | Virtuoso 로그 |
| `result/<id>/test_NN_<ver>.log` | replay가 쓴 결과 |
| `result/<id>/summary.txt` | 판정 표와 실패 사유 |
| `result/<id>/run_args.txt` | 실행 조건 (mode, 대상, 버전, 원본 경로) |

`<id>` = `<mode>_<날짜>_<시각>_<사용자>`. 판정 규칙(legacy와 같음):
1. `End Time` 줄이 없으면 FAIL — "Log isn't fully scripted" (중간에 멈춤)
2. `=== ... ===` 섹션에 `Row_` 줄이 없으면 FAIL — "Expected row mismatch"
3. `FAIL`이 있으면 FAIL — check out/in 실패는 "*WARNING* ...", 그 밖은 "Fail detected"
4. 결과 파일이 없는 테스트는 FAIL — "No result log"

종료 코드는 판정과 무관합니다(실행·summary·teardown 실패만 반영). `summary.txt`를 봅니다.

---

## 6. 정리

| 상황 | 방법 |
|---|---|
| 보통 실행 | 자동 teardown. `regression_test_<mode>_NNN/`은 남음 → `./clean.sh` |
| `-k` 실행, teardown 실패 | `./code/func_teardown_all.sh regression_test_<mode>_NNN` (**clean.sh보다 먼저**). 실패하면 디렉터리를 남기고 rc 1 |
| 로컬 정리 | `./clean.sh` (teardown이 밀린 디렉터리는 지우지 않음) |

---

## 7. 자주 보는 오류

| 메시지 | 원인과 조치 |
|---|---|
| `-mode is required` / `-toLib is required for mode ...` | mode별 필수 인자 누락 |
| `List file not found: .../list_<mode>_<prefix>` | 없는 prefix |
| `--cases: N is out of range (1-M, lines of list_...)` | 번호 범위 |
| `ERROR: unmapped step` (exit 3) | list의 단계 이름에 맞는 `func_control` 블록이 없음 |
| `Some teardowns failed ... keeping <dir>` | gdp 상태 확인 후 같은 명령 재실행 |
