#!/usr/bin/env bash
# Run on macOS host; records Linux task state and kernel wait channel.
set -u
CONTAINER=b4-2-agent
INTERVAL=2
seen_running=0
printf '%-19s %7s %7s %7s %-6s %-28s %12s\n' TIMESTAMP PID PPID TID STATE WCHAN CPU_TICKS
printf '%s\n' '-------------------------------------------------------------------------------------------------'
while :; do
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  status=$(docker inspect --format '{{.State.Status}}' "$CONTAINER" 2>/dev/null || true)
  if [ "$status" != running ]; then
    if [ "$seen_running" -eq 1 ]; then
      exit_info=$(docker inspect --format 'ExitCode={{.State.ExitCode}} OOMKilled={{.State.OOMKilled}}' "$CONTAINER" 2>/dev/null || true)
      printf '%s CONTAINER_EXITED status=%s %s\n' "$ts" "${status:-NOT_FOUND}" "$exit_info"
      break
    fi
    printf '%s CONTAINER_NOT_RUNNING status=%s\n' "$ts" "${status:-NOT_FOUND}"
    break
  fi
  seen_running=1
  data=$(docker exec "$CONTAINER" bash -c '
    for pid in $(ps -C agent-leak-app -o pid=); do
      ppid=$(ps -p "$pid" -o ppid= | tr -d " ")
      for task in /proc/"$pid"/task/*; do
        [ -r "$task/stat" ] || continue
        tid=${task##*/}
        stat=$(cat "$task/stat")
        rest=${stat##*) }
        read -r -a f <<< "$rest"
        state=${f[0]}
        ticks=$((f[11] + f[12]))
        wchan=$(cat "$task/wchan" 2>/dev/null || printf unavailable)
        printf "%s %s %s %s %s %s\n" "$pid" "$ppid" "$tid" "$state" "$wchan" "$ticks"
      done
    done
  ' 2>/dev/null) || data=''
  if [ -z "$data" ]; then
    printf '%s PROCESS_NOT_FOUND_OR_UNREADABLE\n' "$ts"
  else
    while read -r pid ppid tid state wchan ticks; do
      printf '%-19s %7s %7s %7s %-6s %-28s %12s\n' "$ts" "$pid" "$ppid" "$tid" "$state" "$wchan" "$ticks"
    done <<< "$data"
  fi
  sleep "$INTERVAL"
done
