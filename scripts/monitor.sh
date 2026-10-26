#!/usr/bin/env bash

set -u

CONTAINER="b4-2-agent"
INTERVAL=2
started=false

printf 'TIMESTAMP            %6s %6s %6s %7s %12s %10s %-6s\n' \
    "PID" "PPID" "TID" "CPU%" "CPU_TIME" "RSS(KB)" "STATE"
printf '%s\n' \
    '-------------------------------------------------------------------------------'

while true; do
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

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

    docker exec "$CONTAINER" \
        ps -eLo pid=,ppid=,tid=,pcpu=,time=,rss=,stat=,comm= |
        awk -v ts="$timestamp" '
            $8 == "agent-leak-app" {
                printf "%-20s %6s %6s %6s %7s %12s %10s %-6s\n",
                    ts, $1, $2, $3, $4, $5, $6, $7
                found=1
            }
            END {
                if (!found)
                    printf "%s  PROCESS_NOT_FOUND\n", ts
            }
        '

    sleep "$INTERVAL"
done