# B4-2 — Linux 프로세스 장애 분석

코디세이 B4-2 미션 「컴퓨터가 갑자기 느려지거나 멈췄을 때 원인 찾아 고치기」의 실험 및 분석 결과를 정리한 저장소입니다.

Docker에서 제공된 `agent-leak-app`을 실행하고, Linux 프로세스·스레드 상태와 애플리케이션 로그를 함께 관측하여 **Memory/OOM, CPU Latency, Deadlock** 세 장애를 분석했습니다. 장애별 Before/After 비교, 근거, 조치 및 검증 한계는 GitHub Issues에 기록했습니다.

## 분석 보고서

| 장애 | Before 관측 | After 조치 및 관측 | 상세 보고서 |
|---|---|---|---|
| Memory/OOM | Heap 증가 후 275MB에서 MemoryGuard 종료 선언; `ExitCode=137`, `OOMKilled=false` | `MEMORY_LIMIT` 256→512, CPU 설정 80→40; 525MB에서 Cleanup 반복, 관측 당시 실행 유지 | [Issue #1](https://github.com/yerihanview/B4-2/issues/1) |
| CPU Latency | 내부 `Current Load`가 51.82%에 도달하고 임계값 위반 기록; `ExitCode=143` | `CPU_MAX_OCCUPY` 80→40; 40%에서 Cooldown, 이후 작업 재개 | [Issue #2](https://github.com/yerihanview/B4-2/issues/2) |
| Deadlock | 두 Worker가 서로 다른 Lock을 보유한 채 상대 Lock을 기다림; 프로세스 생존, 작업 정체 | `MULTI_THREAD_ENABLE` true→false; 동일한 순환 대기가 관측되지 않고 CPU/Memory 작업 진행 | [Issue #3](https://github.com/yerihanview/B4-2/issues/3) |

> 이 저장소의 조치는 **장애 경로 완화 또는 우회(Workaround)**에 해당합니다. 애플리케이션 바이너리의 내부 결함을 수정했다는 의미가 아닙니다.

## 실습 환경

- 호스트: macOS, VS Code 터미널
- 컨테이너 실행: Docker (OrbStack)
- 컨테이너 OS: Ubuntu 22.04
- 애플리케이션: `agent-leak-app` (Linux x86-64 실행 파일)
- 컨테이너 이름: `b4-2-agent`
- 포트 매핑: `127.0.0.1:15034:15034`
- 실행 설정: `compose.yaml`, `.env`

모니터링 스크립트는 **macOS 호스트에서 실행**하며 `docker exec`로 컨테이너 내부의 Linux 프로세스 및 `/proc` 정보를 수집합니다.

## 프로젝트 구성

```text
.
├── docker/
│   └── Dockerfile
├── compose.yaml
├── scripts/
│   ├── monitor.sh             # 초기 범용 프로세스/스레드 관측
│   ├── monitor_memory.sh      # Memory 실험용 (monitor.sh의 구분본)
│   ├── monitor_cpu.sh         # /proc CPU tick 기반 구간별 CPU 관측
│   └── monitor_deadlock.sh    # 스레드 상태·wchan·CPU_TICKS 관측
└── evidence/
    ├── startup/               # 초기 부팅 및 종료 기록
    ├── monitor/               # Memory/OOM 관측 로그
    ├── cpu/                   # CPU Before/After 로그
    └── deadlock/
        ├── before-app.log
        ├── before-monitor.log
        ├── before-ps.log
        ├── after-app.log
        └── after-monitor.log
```

## 실행 및 재현

프로젝트의 실행 파일과 런타임 디렉터리를 준비한 환경에서 `.env` 값을 지정한 후 컨테이너를 생성합니다. 애플리케이션 바이너리와 키 파일은 저장소에 포함되어 있다고 가정하지 않습니다.

```bash
docker compose up -d --build
docker ps -a --filter "name=^/b4-2-agent$"
docker exec b4-2-agent printenv MEMORY_LIMIT CPU_MAX_OCCUPY MULTI_THREAD_ENABLE
```

환경변수를 변경하면 **기존 컨테이너에 자동 반영되지 않으므로 재생성**해야 합니다.

```bash
docker compose up -d --force-recreate --no-deps agent
```

| 실험 조건 | `MEMORY_LIMIT` | `CPU_MAX_OCCUPY` | `MULTI_THREAD_ENABLE` |
|---|---:|---:|---|
| Memory Before | 256 | 80 | false |
| Memory After | 512 | 40 | false |
| CPU Before | 512 | 80 | false |
| CPU After | 512 | 40 | false |
| Deadlock Before | 512 | 40 | true |
| Deadlock After | 512 | 40 | false |

설정 변경 후에는 애플리케이션 로그와 해당 모니터링 스크립트 출력을 함께 수집합니다. 각 실험의 구체적인 절차와 결과는 연결된 Issue를 기준으로 합니다.

## 주요 관측 방법

- **Memory:** 부모·자식 프로세스를 구분해 RSS 변화를 추적하고, MemoryGuard 및 Cleanup 로그와 대조
- **CPU:** `/proc/<PID>/task/<TID>/stat`의 CPU tick 변화로 구간별 사용률을 계산하고, 애플리케이션 내부 `Current Load`와 구분
- **Deadlock:** PID/TID별 `STATE`, `wchan`, `CPU_TICKS` 및 `ps -L`의 CPU/RSS를 확인하고, Lock 보유·대기 로그와 교차 검증

RSS는 **프로세스 단위 값**이므로 각 스레드 행의 RSS를 합산하지 않습니다. `futex_wait`나 낮은 CPU 사용률만으로 Deadlock을 확정하지 않습니다.

## 검증 결과와 한계

**Memory/OOM:** `OOMKilled=false`와 MemoryGuard 로그가 확인되므로 Linux OOM Killer에 의한 종료라고 단정하지 않았습니다. 설정 변경 후에도 메모리 증가와 Cleanup은 반복됩니다.

**CPU Latency:** 임계값 위반 및 종료 코드 143은 관측했지만, Watchdog이 직접 SIGTERM을 보냈다는 로그는 확보하지 못했습니다. Linux 관측에서도 OS CPU 과점유는 입증하지 못했습니다. `Current Load`는 애플리케이션 내부 지표입니다.

**Deadlock:** 두 Worker의 순환 대기 로그, `futex_wait` 지속, CPU 시간 정체와 RSS 정체를 확보했습니다. 다만 Linux TID와 애플리케이션 Worker 이름의 직접 매핑 및 소스코드 수준 Lock 분석은 수행하지 않았습니다. 멀티스레드 비활성화는 근본 수정이 아닌 우회 조치입니다.

## 증거 및 보고서 링크

- [Issue #1 — Memory/OOM 분석](https://github.com/yerihanview/B4-2/issues/1)
- [Issue #2 — CPU Latency 분석](https://github.com/yerihanview/B4-2/issues/2)
- [Issue #3 — Deadlock 분석](https://github.com/yerihanview/B4-2/issues/3)
- [Memory 증거](evidence/monitor/)
- [CPU 증거](evidence/cpu/)
- [Deadlock 증거](evidence/deadlock/)
- [모니터링 스크립트](scripts/)

**실험일:** 2026-10-26
