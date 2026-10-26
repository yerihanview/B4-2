#!/usr/bin/env bash

# CPU 측정 방식 개선 frorm scripts/monitor_memory.sh
# CPU%: 실행 이후 누적 평균 대신 직전 측정 구간의 사용률로 변경
# CPU_TIME: 초 단위로 환산하고 소수점 둘째 자리까지 표시
# PID, PPID, TID, RSS, STATE: 유지
# 출력 형식: 헤더 한 번, 고정 폭 텍스트, 행별 Timestamp 유지
# 프로세스별 CPU 사용률과 스레드별 CPU 사용률을 구분해 계산


set -u

CONTAINER="b4-2-agent"
INTERVAL=2

started=false
CLK_TCK=100

# PID:TID별 직전 CPU tick과 측정 시각
prev_ticks=()
prev_times=()

printf '%-19s %6s %6s %6s %8s %11s %10s %-6s\n' \
    "TIMESTAMP" "PID" "PPID" "TID" "CPU%" "CPU_TIME(s)" "RSS(KB)" "STATE"

printf '%s\n' \
    '--------------------------------------------------------------------------------'

while true; do
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    now=$(date '+%s.%N')

    status=$(docker inspect \
        --format '{{.State.Status}}' "$CONTAINER" 2>/dev/null)

    if [[ "$status" != "running" ]]; then
        if [[ "$started" == false ]]; then
            sleep "$INTERVAL"
            continue
        fi

        exit_info=$(docker inspect \
            --format 'ExitCode={{.State.ExitCode}} OOMKilled={{.State.OOMKilled}}' \
            "$CONTAINER" 2>/dev/null)

        printf '%s  CONTAINER_EXITED status=%s %s\n' \
            "$timestamp" "${status:-NOT_FOUND}" "$exit_info"
        break
    fi

    started=true

    # 스레드별 CPU tick을 포함한 데이터 수집
    data=$(docker exec "$CONTAINER" bash -c '
        for pid in $(ps -C agent-leak-app -o pid=); do
            ppid=$(ps -p "$pid" -o ppid= | tr -d " ")

            for task in /proc/"$pid"/task/*; do
                [[ -r "$task/stat" ]] || continue

                tid=${task##*/}

                # stat의 comm 필드에는 공백이 포함될 수 있으므로
                # 마지막 ")" 이후의 필드만 분리한다.
                stat=$(cat "$task/stat")
                rest=${stat##*) }

                read -r -a fields <<< "$rest"

                state=${fields[0]}

                # 원본 stat의 14, 15번 필드
                utime=${fields[11]}
                stime=${fields[12]}

                ticks=$((utime + stime))

                # RSS는 프로세스 단위 값
                rss=$(ps -p "$pid" -o rss= | tr -d " ")

                printf "%s %s %s %s %s %s\n" \
                    "$pid" "$ppid" "$tid" "$ticks" "$rss" "$state"
            done
        done
    ' 2>/dev/null)

    if [[ -z "$data" ]]; then
        printf '%s  PROCESS_NOT_FOUND\n' "$timestamp"
        sleep "$INTERVAL"
        continue
    fi

    while read -r pid ppid tid ticks rss state; do
        [[ -z "${pid:-}" ]] && continue

        key=$((pid * 10000000 + tid))

        cpu_time=$(awk -v ticks="$ticks" -v hz="$CLK_TCK" \
            'BEGIN {printf "%.2f", ticks / hz}')

        cpu_pct="-"

        if [[ -n "${prev_ticks[$key]+x}" ]]; then
            cpu_pct=$(awk \
                -v current="$ticks" \
                -v previous="${prev_ticks[$key]}" \
                -v now="$now" \
                -v before="${prev_times[$key]}" \
                -v hz="$CLK_TCK" '
                BEGIN {
                    elapsed = now - before
                    if (elapsed > 0)
                        printf "%.1f", ((current - previous) / hz) / elapsed * 100
                    else
                        printf "-"
                }')
        fi

        printf '%-19s %6s %6s %6s %8s %11s %10s %-6s\n' \
            "$timestamp" "$pid" "$ppid" "$tid" \
            "$cpu_pct" "$cpu_time" "$rss" "$state"

        prev_ticks[$key]="$ticks"
        prev_times[$key]="$now"

    done <<< "$data"

    sleep "$INTERVAL"
done