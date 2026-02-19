# Ralph Agent

Claude Code에서 구현 계획을 자동으로 실행하는 플러그인. 태스크 목록을 주면 순서대로 구현하고, 검증 통과할 때까지 스스로 고치고, 다음 태스크로 넘어간다.

## 왜 쓰는가

- **자동 연속 실행**: 태스크를 하나 끝내면 다음 태스크로 자동 진행. 사람이 매번 다음 지시를 내릴 필요 없음
- **검증 게이팅**: 테스트/린트가 통과해야만 태스크를 완료로 표시. 검증 없이 "다 했어요"라고 멈추지 못함
- **루프 감지**: 같은 파일을 5번 이상 수정하면 경고를 띄우고 전략 재고를 유도
- **파일 보호**: `.env`, `*.pem`, `*.key` 같은 민감 파일에 쓰기 차단
- **컨텍스트 보존**: 대화가 압축되어도 현재 진행 상태와 검증 명령어를 다시 주입

## 설치

Claude Code에서 두 명령어를 실행한다:

```bash
# 1. 마켓플레이스 등록
/plugin marketplace add tmdgusya/roach-loop

# 2. 플러그인 설치
/plugin install ralph-agent@ralph-agent-marketplace
```

업데이트:
```bash
/plugin update ralph-agent
```

## 빠른 시작

두 가지 워크플로우가 있다. 상황에 맞는 걸 고르면 된다.

### Ralph 워크플로우 — 직접 태스크 목록을 만들어 실행

태스크 목록을 직접 작성하고, Ralph가 순서대로 구현한다. Git은 직접 관리한다.

**1단계: 계획 파일 생성**

```bash
/ralph-agent:ralph-init
```

**2단계: 태스크 작성**

생성된 `IMPLEMENTATION_PLAN.md`를 열고 태스크를 채운다:

```markdown
# Implementation Plan

## Tasks
- [ ] SQLAlchemy User 모델 생성 (id, email, name, created_at)
- [ ] POST /users 엔드포인트 구현 (입력 검증 포함)
- [ ] GET /users/:id 엔드포인트 구현 (404 처리)
- [ ] 전체 엔드포인트 pytest 테스트 작성
```

**3단계: 검증 명령어 설정**

프로젝트 루트에 `AGENTS.md`를 만든다:

```markdown
# Verification Commands
- `pytest tests/ -v`
- `ruff check .`
```

**4단계: 실행**

```bash
/ralph-agent:ralph
```

Ralph가 첫 번째 미완료 태스크(`- [ ]`)부터 구현을 시작한다. 각 태스크마다 검증 명령어를 실행하고, 통과하면 `- [x]`로 표시한 뒤 다음 태스크로 넘어간다.

### Geoff 워크플로우 — 스펙에서 자동 계획 + Git 관리

`specs/` 디렉토리에 요구사항을 작성하면, 계획을 자동 생성하고 Git 커밋/태그까지 해준다.

**1단계: 스펙 작성**

```bash
mkdir specs
```

`specs/` 안에 요구사항 파일을 만든다:

```markdown
# specs/user-auth.md

## Feature: User Authentication

### Requirements
- 이메일/비밀번호로 회원가입
- JWT 토큰으로 로그인
- 비밀번호는 bcrypt로 해싱
```

**2단계: 계획 생성**

```bash
/ralph-agent:gplan
```

스펙을 분석해서 `IMPLEMENTATION_PLAN.md`를 자동 생성한다.

**3단계: 빌드**

```bash
/ralph-agent:gbuild
```

태스크를 구현하고, 테스트 통과 후 자동으로 `git commit → push → tag (0.0.0, 0.0.1, ...)`까지 처리한다.

### 어떤 워크플로우를 쓸까?

| 상황 | 추천 | 명령어 |
|------|------|--------|
| 직접 태스크 목록을 관리하고 싶다 | Ralph | `/ralph-agent:ralph-init` → `/ralph-agent:ralph` |
| Git 커밋을 직접 하고 싶다 | Ralph | `/ralph-agent:ralph` |
| 스펙 문서가 있고 자동 계획이 필요하다 | Geoff | `/ralph-agent:gplan` → `/ralph-agent:gbuild` |
| 자동 Git 커밋 + 버전 태그가 필요하다 | Geoff | `/ralph-agent:gplan` → `/ralph-agent:gbuild` |

## 실전 사용 팁

### 좋은 태스크 작성법

태스크가 구체적이고 독립적이면 Ralph의 성공률이 크게 올라간다.

| 나쁜 예 | 좋은 예 |
|---------|---------|
| "인증 작업" | "JWT 기반 POST /auth/login 엔드포인트 구현" |
| "테스트 추가" | "User 모델 CRUD에 대한 pytest 테스트 작성" |
| "리팩토링" | "UserService에서 DB 로직을 UserRepository로 분리" |

**원칙:**
- 하나의 태스크 = 하나의 검증 가능한 결과
- 다른 태스크 완료 여부에 의존하지 않게 작성
- 30분~2시간 분량이 적당

### 검증 명령어 설정

`AGENTS.md`에 쓰는 검증 명령어는 **빠른 것부터** 배치한다:

```markdown
# Verification Commands
- `ruff check .`          # 린트 (빠름)
- `mypy src/`             # 타입 체크 (중간)
- `pytest tests/ -v`      # 테스트 (느림)
```

Ralph는 이 명령어를 **모두** 통과해야 태스크를 완료로 표시한다. 하나라도 실패하면 코드를 고치고 재시도한다.

### 반복 횟수 제한

오래 돌릴 때는 반복 횟수를 제한할 수 있다:

```bash
# 5개 태스크만 처리하고 멈춤
/ralph-agent:ralph --max-iterations=5

# 태스크 사이에 사용자 확인을 받으면서 진행
/ralph-agent:loop ralph max=5 pause=true
```

### 중간에 멈추기

작업 중 `stop` 또는 `cancel`을 입력하면 현재 태스크 완료 후 멈춘다. 진행 상태는 `IMPLEMENTATION_PLAN.md`에 저장되므로, 나중에 `/ralph-agent:ralph`로 이어서 할 수 있다.

## 유의할 점

### `.harness/` 디렉토리

Ralph 실행 중 프로젝트 루트에 `.harness/` 디렉토리가 생긴다:

```
.harness/
├── state.json          # 세션 상태 (현재 태스크, 검증 결과 등)
├── edit-tracker.json   # 파일별 수정 횟수 (루프 감지용)
└── trace-log.jsonl     # 모든 도구 호출 로그
```

이 디렉토리는 **세션 상태 추적용**이다. `.gitignore`에 추가하는 것을 권장한다:

```
.harness/
```

### 루프 감지 동작

같은 파일을 5회(기본값) 이상 수정하면 경고가 뜬다:

> "⚠ src/api.py를 5번 수정했습니다. 멈추고 접근 방식을 재고하세요."

이건 에이전트가 같은 실수를 반복하는 "둠 루프"를 막기 위한 장치다. 경고 후 에이전트는 다른 전략을 시도한다.

### Stop Hook 동작

Ralph는 다음 두 조건을 만족해야 멈출 수 있다:

1. **검증 명령어가 실행되었고 통과했을 것**
2. **미완료 태스크(`- [ ]`)가 없을 것**

조건을 못 채우면 멈추는 것 자체가 차단되고, 미충족 항목이 표시된다.

### 파일 보호

`.env`, `.env.*`, `*.pem`, `*.key`, `credentials.*` 패턴의 파일은 쓰기가 차단된다. 의도적으로 이 파일에 써야 한다면 harness 설정에서 `file_protection`을 비활성화해야 한다.

## 트러블슈팅

### "No IMPLEMENTATION_PLAN.md found"

계획 파일이 없다. `/ralph-agent:ralph-init`으로 템플릿을 생성하고 태스크를 채운다.

### "No verification commands found"

`AGENTS.md` 파일이 없거나 검증 명령어가 비어 있다. 프로젝트 루트에 `AGENTS.md`를 만들고 테스트/린트 명령어를 추가한다.

### 검증이 계속 실패한다

Ralph는 실패 시 자동으로 코드를 수정하고 재시도한다. 하지만 반복 실패가 지속되면:

- 태스크 범위가 너무 넓은지 확인 → 더 작은 단위로 분할
- 검증 명령어가 현재 환경에서 실행 가능한지 확인 (의존성 설치 등)
- 루프 감지 경고가 떴다면, 태스크 설명을 더 구체적으로 수정

### Ralph가 갑자기 멈췄다

세션 제한이나 네트워크 문제로 중단될 수 있다. 진행 상태는 `IMPLEMENTATION_PLAN.md`에 저장되어 있으므로 `/ralph-agent:ralph`를 다시 실행하면 마지막 미완료 태스크부터 이어서 진행한다.

## 명령어 레퍼런스

| 명령어 | 설명 |
|--------|------|
| `/ralph-agent:ralph-init` | `IMPLEMENTATION_PLAN.md` 템플릿 생성 |
| `/ralph-agent:ralph` | 태스크 순차 실행 (Git 없음) |
| `/ralph-agent:gplan` | `specs/`를 분석해 구현 계획 자동 생성 |
| `/ralph-agent:gbuild` | 태스크 실행 + 자동 Git 커밋/태그 |
| `/ralph-agent:loop <agent> max=N pause=true` | 반복 횟수 제한 + 일시정지 옵션 |
| `/ralph-agent:spec` | 대화형으로 스펙 파일 생성 |

## 라이선스

MIT
