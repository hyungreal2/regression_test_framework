# MIGRATION_WORKFLOW — 새 legacy(legacy′) 반영 작업 지시서

이 문서는 **이 저장소에 대한 사전 지식이 없는 작업자(LLM 에이전트 포함)** 가 새 legacy(legacy′)를 받아 저장소를 갱신할 때
처음 읽는 문서입니다. 무엇을 읽고, 어떤 순서로 하고, 무엇을 남겨야 하는지만 적습니다. 규칙과 근거는 아래 참조 문서에 있습니다.

| 문서 | 언제 읽나 |
|---|---|
| [MIGRATION_COMMON_KR.md](MIGRATION_COMMON_KR.md) | 항상, 가장 먼저 |
| [MIGRATION_CICO_KR.md](MIGRATION_CICO_KR.md) | `1_cico_sp`에 변경이 있을 때 |
| [MIGRATION_FUNC_KR.md](MIGRATION_FUNC_KR.md) | `3_func_sp`에 변경이 있을 때 |
| [MIGRATION_PERF_KR.md](MIGRATION_PERF_KR.md) | `2_perf_sp`에 변경이 있을 때 |
| `README.md` (저장소 루트) | 저장소 구조와 실행 방법이 필요할 때 |

---

## 0. 입력과 결과

- **입력**: legacy′ 디렉터리 경로 하나(이하 `<L′>`). 안에 `1_cico_sp`, `2_perf_sp`, `3_func_sp`가 있습니다
  (이름이 다르면 MIGRATION_COMMON §1의 방법으로 대응시킵니다).
- **기준**: 저장소의 `reference/legacy/` (이전에 반영한 legacy). 이것과 `<L′>`의 차이가 이번에 반영할 변경입니다.
- **결과**
  1. 작업 브랜치의 커밋들 (코드·데이터 반영, 문서, 기준 교체)
  2. 작업 보고서 `docs/migration_reports/<YYYYMMDD>.md` (§3 형식) — 커밋에 포함
- **하지 말 것**
  - `git push` (사람이 확인한 뒤 따로 합니다)
  - `reference/legacy/` 외의 `reference/` 하위 수정
  - 판단이 서지 않는 변경을 추측으로 반영 (보고서의 "사람 확인 필요"에 남김)
- **실행 환경**: 실제 `gdp`, `xlp4`, Virtuoso가 없어도 됩니다. 필요한 것은 bash, python3, perl, diff, sha256sum, git입니다.
  실행 확인은 dry-run과 `tools/mock/`으로 합니다.

---

## 1. 절차

각 단계를 끝내면 보고서에 결과를 적습니다.

### 단계 0 — 준비
```bash
git status --short                      # 비어 있어야 함
git switch -c migrate/$(date +%Y%m%d)
L=<L′ 절대 경로>; S=$(mktemp -d)          # S: 검증용 임시 디렉터리
```
`reference/legacy/`가 MIGRATION_COMMON 부록 A의 체크섬과 맞는지 확인합니다(MIGRATION_COMMON §2 단계 1).

### 단계 1 — 변경 목록
```bash
for s in 1_cico_sp 2_perf_sp 3_func_sp; do
  diff -rq --strip-trailing-cr reference/legacy/$s "$L/$s"
done | grep -vE '/(result|CDS_log|regression_test[^/]*|temp|replay)/|\.au |\.au$|\.swp|\.out|lcv\.txt|managed\.txt|date_virtuosoVer\.txt'
```
- `Files A and B differ` → 바뀐 파일, `Only in <L′>` → 새 파일, `Only in reference/legacy` → 지워진 파일.
- 바뀐 파일마다 `diff -u --strip-trailing-cr reference/legacy/<파일> "$L/<파일>"`로 내용을 봅니다.
- 줄 끝(CRLF/LF)만 다른 파일은 위 명령에 나오지 않습니다. 반영하지 않습니다.

### 단계 2 — 분류
변경마다 MIGRATION_COMMON §3 단계 3의 분류(A 데이터 / B 프레임워크 / C 사이트 값 / D 백업·미사용)와 suite 문서 §1 대응표의 저장소
파일을 정해 보고서 표에 적습니다. 대응표에 없는 새 파일은 진입 스크립트나 템플릿이 그 파일을 쓰는지(`grep`)로 판단합니다.

### 단계 3 — 반영
suite 문서의 §2(데이터 규칙), §3(프레임워크 대응), §4(의도한 차이)를 보고 반영합니다. 충돌하면 MIGRATION_COMMON §5 우선순위를 따릅니다.
- 데이터 파일: 기준→legacy′의 diff를 저장소 파일의 해당 부분에 옮깁니다. 저장소 파일이 legacy와 형식이 다르면(cico control 블록,
  perf 템플릿 `\i` 등) 형식 규칙을 지킵니다.
- 프레임워크 스크립트: 바뀐 **동작**을 찾아 저장소 스크립트에 구현합니다. 줄 단위로 옮기지 않습니다.
- MIGRATION_COMMON §6 "반드시 유지할 동작"을 깨지 않습니다.

### 단계 4 — 검증 (모두 통과해야 다음 단계)
| 게이트 | 어디에 | 통과 기준 |
|---|---|---|
| G0 문법 | MIGRATION_COMMON §7 | 출력 없음 |
| G1 생성 | 각 suite 문서 §5.1 | rc 0, `unmapped` 없음 |
| G2 legacy′ 1:1 | 각 suite 문서 §5.2 (perf §5.1) — **`<L>` 자리에 `<L′>`** | cico `differ=0`, func `differ=0`, perf 잔여는 P4(changeLibRef `load` 2줄)뿐. `compared`가 기대값과 같아야 함 |
| G3 실행 | MIGRATION_COMMON §7 G3, 각 suite 문서 §5.3 | dry-run 2 rc 0. 가능하면 mock 단계 0 |
| G4 prod 비교 | MIGRATION_COMMON §7 G4 | prod 스냅샷(`reference/prod/`)이 있을 때만. 없으면 "생략"으로 보고 |

G2는 **반영한 뒤 legacy′와** 비교합니다(기준 legacy가 아님). 실패하면 단계 3으로 돌아갑니다.

### 단계 5 — 문서
- 사용법이 바뀌었으면 `README.md`, `docs/MANUAL_<SUITE>_KR.md`
- 새 의도한 차이를 만들었으면 suite MIGRATION 문서 §4에 양쪽 발췌와 이유
- 테스트 수, 템플릿 목록 같은 사실이 바뀌었으면 `docs/IMPROVEMENTS_*_KR.md`

### 단계 6 — 기준 교체
```bash
for s in 1_cico_sp 2_perf_sp 3_func_sp; do rm -rf reference/legacy/$s; cp -r "$L/$s" reference/legacy/$s; done
(cd reference/legacy && <MIGRATION_COMMON 부록 A의 명령>) > "$S/manifest.txt"
```
MIGRATION_COMMON 부록 A의 체크섬 블록을 `$S/manifest.txt` 내용으로 바꿉니다. 그 뒤 G2를 기준(`reference/legacy`)으로 한 번 더 돌려
같은 결과가 나오는지 확인합니다.

### 단계 7 — 커밋
MIGRATION_COMMON §2 단계 7처럼 나눠 커밋하고, 마지막 커밋에 보고서를 포함합니다. push하지 않습니다.

---

## 2. 막혔을 때

- 반영 방법이 문서에 없고 §5 우선순위로도 정해지지 않으면: 그 변경은 반영하지 않고 보고서 "사람 확인 필요"에 legacy′ 발췌,
  관련 저장소 파일·줄, 생각한 선택지를 적습니다. 나머지 변경은 계속 진행합니다.
- 게이트가 문서와 다르게 동작하면(명령 오류, 기대값 불일치의 원인이 반영이 아닌 경우): 문서를 고치지 말고 보고서에 그대로 적습니다.
- 문서의 내용이 실제 코드와 다르면: 코드가 기준입니다. 보고서의 "문서 불일치"에 적습니다.

---

## 3. 보고서 형식 (`docs/migration_reports/<YYYYMMDD>.md`)

```markdown
# legacy′ 반영 보고서 (<날짜>)

- legacy′: <경로 또는 출처>
- 기준: reference/legacy (반영 전 커밋 <hash>)
- 결과 커밋: <hash 목록>

## 1. 변경 목록과 처리
| # | legacy′ 파일 | 변경 요약 | 분류 | 반영 위치 | 판단 근거 (문서 절) |
|---|---|---|---|---|---|

## 2. 반영하지 않은 변경
| legacy′ 파일 | 이유 |

## 3. 검증 결과
| 게이트 | 결과 (숫자 그대로) |
|---|---|
| G0 | |
| G1 | |
| G2 cico | compared=… differ=… |
| G2 func | compared=… differ=… |
| G2 perf | compared=… with_residual=… (잔여 내용) |
| G3 | |
| G4 | |

## 4. 사람 확인 필요
## 5. 문서 불일치
```
