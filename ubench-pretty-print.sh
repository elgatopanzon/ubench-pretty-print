#!/usr/bin/env bash
#
# /**
#  * @author      : ElGatoPanzon
#  * @file        : ubench-pretty-print
#  * @created     : 2026-02-28
#  * @description : Wraps ubench benchmarks and reformats output into comparison tables
#  */

set -uo pipefail

# defaults
USE_COLOR=1
SHOW_RAW=0

# colors (populated only when USE_COLOR=1)
BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

usage() {
    echo "Usage: $0 [options] <benchmark_executable> [args...]" >&2
    echo "" >&2
    echo "Options:" >&2
    echo "  --no-colour, --no-color   Disable ANSI colors, use text indicators instead" >&2
    echo "                            (+) fastest, (-) slowest, (~) statistically similar" >&2
    echo "  --show-raw-output         Show raw benchmark output before comparison tables" >&2
    exit 1
}

# parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-colour|--no-color)
            USE_COLOR=0
            BOLD=''; GREEN=''; RED=''; YELLOW=''; CYAN=''; RESET=''
            shift
            ;;
        --show-raw-output)
            SHOW_RAW=1
            shift
            ;;
        -h|--help)
            usage
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage
            ;;
        *)
            break
            ;;
    esac
done

# convert a time value+unit to nanoseconds via awk
to_ns() {
    local val="$1" unit="$2"
    case "$unit" in
        ns) printf '%s' "$val" ;;
        us) awk "BEGIN { printf \"%.9g\", $val * 1000 }" ;;
        ms) awk "BEGIN { printf \"%.9g\", $val * 1000000 }" ;;
        s)  awk "BEGIN { printf \"%.9g\", $val * 1000000000 }" ;;
        *)  printf '%s' "$val" ;;
    esac
}

# convert nanoseconds to best-fit display string
# thresholds: <1000ns -> ns, <1000000ns -> us, <1000000000ns -> ms, else -> s
ns_to_display() {
    local ns="$1"
    awk "BEGIN {
        ns = $ns + 0
        if (ns < 1000) {
            printf \"%.3gns\", ns
        } else if (ns < 1000000) {
            printf \"%.3gus\", ns / 1000
        } else if (ns < 1000000000) {
            printf \"%.3gms\", ns / 1000000
        } else {
            printf \"%.3gs\", ns / 1000000000
        }
    }"
}

[[ $# -lt 1 ]] && usage

BENCH_EXE="$1"; shift

if [[ ! -x "$BENCH_EXE" ]]; then
    echo "Error: '$BENCH_EXE' is not executable or not found" >&2
    exit 1
fi

TMP_OUTPUT=$(mktemp /tmp/ubench-XXXXXX.txt)
trap 'rm -f "$TMP_OUTPUT"' EXIT

echo "Running: $BENCH_EXE $*"
echo ""

bench_exit=0
"$BENCH_EXE" "$@" > "$TMP_OUTPUT" 2>&1 || bench_exit=$?

echo ""
echo -e "${BOLD}${CYAN}══ BENCHMARK COMPARISON ══${RESET}"

# ─── parse raw output ──────────────────────────────────────────────────────

declare -A bench_mean      # suite.bench -> "X.XXXus"
declare -A bench_mean_ns   # suite.bench -> nanoseconds as float string
declare -A bench_ci        # suite.bench -> CI percentage string
declare -A bench_status    # suite.bench -> ok|failed|ci_exceeded
declare -A suite_seen
declare -A suite_benches   # suite -> space-separated bench names
declare -A suite_raw_lines # suite -> newline-separated raw output lines
declare -a suite_order

ci_exceeded_next=0
pending_ci_line=""

while IFS= read -r line; do
    # [ RUN      ] suite.name
    if [[ "$line" =~ ^\[\ RUN[[:space:]]+\][[:space:]]([^.]+)\.(.+)$ ]]; then
        suite="${BASH_REMATCH[1]}"
        if [[ -z "${suite_seen[$suite]+_}" ]]; then
            suite_order+=("$suite")
            suite_seen[$suite]=1
            suite_benches[$suite]=""
        fi

    # confidence interval X% exceeds maximum permitted Y%
    elif [[ "$line" == *"confidence interval"*"exceeds"* ]]; then
        ci_exceeded_next=1
        pending_ci_line="$line"

    # [       OK ] suite.name (mean X.XXXus, confidence interval +- Y.YYYY%)
    # [  FAILED  ] suite.name (mean X.XXXus, confidence interval +- Y.YYYY%)
    elif [[ "$line" =~ ^\[[[:space:]]*(OK|FAILED)[[:space:]]*\][[:space:]]([^.]+)\.([^[:space:]]+)[[:space:]]+\(mean[[:space:]]+([0-9.]+)(ns|us|ms|s),[[:space:]]+confidence[[:space:]]+interval[[:space:]]+\+-[[:space:]]+([0-9.]+)%\)$ ]]; then
        status="${BASH_REMATCH[1]}"
        suite="${BASH_REMATCH[2]}"
        name="${BASH_REMATCH[3]}"
        mean_val="${BASH_REMATCH[4]}"
        mean_unit="${BASH_REMATCH[5]}"
        ci="${BASH_REMATCH[6]}"
        key="${suite}.${name}"

        bench_mean[$key]="${mean_val}${mean_unit}"
        bench_mean_ns[$key]=$(to_ns "$mean_val" "$mean_unit")
        bench_ci[$key]="$ci"

        if [[ "$status" == "FAILED" && $ci_exceeded_next -eq 1 ]]; then
            bench_status[$key]="ci_exceeded"
        elif [[ "$status" == "FAILED" ]]; then
            bench_status[$key]="failed"
        else
            bench_status[$key]="ok"
        fi
        ci_exceeded_next=0

        # accumulate raw lines for this suite (CI warning + result line)
        if [[ -n "$pending_ci_line" ]]; then
            suite_raw_lines[$suite]+="$pending_ci_line"$'\n'
            pending_ci_line=""
        fi
        suite_raw_lines[$suite]+="$line"$'\n'

        if [[ -z "${suite_benches[$suite]}" ]]; then
            suite_benches[$suite]="$name"
        else
            suite_benches[$suite]+=" $name"
        fi
    fi
done < "$TMP_OUTPUT"

# ─── output comparison tables ──────────────────────────────────────────────

total_ok=0
total_failed=0
total_ci=0
max_table_width=0

# print N dashes
dashn() { printf '%*s' "$1" '' | tr ' ' '-'; }
# print N bar chars
barn() { printf '%*s' "$1" '' | tr ' ' '═'; }

for suite in "${suite_order[@]}"; do
    benches="${suite_benches[$suite]:-}"
    [[ -z "$benches" ]] && continue

    read -ra bench_list <<< "$benches"

    # first pass: find fastest/slowest among OK benchmarks
    winner_key=""
    winner_ns=""
    slowest_key=""
    slowest_ns=""

    for bench in "${bench_list[@]}"; do
        key="${suite}.${bench}"
        status="${bench_status[$key]:-unknown}"
        if [[ "$status" == "ok" ]]; then
            ns="${bench_mean_ns[$key]:-0}"
            if [[ -z "$winner_key" ]]; then
                winner_key="$key"; winner_ns="$ns"
                slowest_key="$key"; slowest_ns="$ns"
            else
                if awk "BEGIN { exit !($ns < $winner_ns) }"; then
                    winner_key="$key"; winner_ns="$ns"
                fi
                if awk "BEGIN { exit !($ns > $slowest_ns) }"; then
                    slowest_key="$key"; slowest_ns="$ns"
                fi
            fi
        fi
    done

    # compute method column width from longest name
    # in no-color mode, we append " (+)" / " (-)" / " (~)" to names, so add 4 chars
    max_method=6  # "Method"
    for bench in "${bench_list[@]}"; do
        [[ ${#bench} -gt $max_method ]] && max_method=${#bench}
    done
    [[ $USE_COLOR -eq 0 ]] && max_method=$((max_method + 4))
    CM=$max_method
    CMEAN=12
    CCI=10
    CRATIO=8
    CSTATUS=8
    # table width: | col | col | ... | = 2 + CM + 3 + CMEAN + 3 + CCI + 3 + CRATIO + 3 + CSTATUS + 2
    TABLE_WIDTH=$((CM + CMEAN + CCI + CRATIO + CSTATUS + 16))
    [[ $TABLE_WIDTH -gt $max_table_width ]] && max_table_width=$TABLE_WIDTH

    echo ""
    if [[ $SHOW_RAW -eq 1 && -n "${suite_raw_lines[$suite]:-}" ]]; then
        echo "  Raw output:"
        while IFS= read -r raw_line; do
            [[ -n "$raw_line" ]] && printf "    %s\n" "$raw_line"
        done <<< "${suite_raw_lines[$suite]}"
        echo ""
    fi
    echo -e "${BOLD}### ${CYAN}${suite}${RESET}"
    printf "| %-${CM}s | %-${CMEAN}s | %-${CCI}s | %-${CRATIO}s | %-${CSTATUS}s |\n" \
        "Method" "Mean" "CI" "Ratio" "Status"
    printf "|%s|%s|%s|%s|%s|\n" \
        "$(dashn $((CM+2)))" "$(dashn $((CMEAN+2)))" \
        "$(dashn $((CCI+2)))" "$(dashn $((CRATIO+2)))" \
        "$(dashn $((CSTATUS+2)))"

    # calculate percentage difference between fastest and slowest
    # statistically similar if: <= 2.5% difference OR <= 5ns absolute difference
    stat_similar=0
    if [[ -n "$winner_ns" && -n "$slowest_ns" && "$winner_key" != "$slowest_key" ]]; then
        abs_diff=$(awk "BEGIN { printf \"%.9g\", $slowest_ns - $winner_ns }")
        pct_diff=$(awk "BEGIN {
            diff = (($slowest_ns - $winner_ns) / $winner_ns) * 100
            printf \"%.4f\", diff
        }")
        # absolute floor: 5ns difference is noise regardless of percentage
        if awk "BEGIN { exit !($abs_diff <= 5) }"; then
            stat_similar=1
        elif awk "BEGIN { exit !($pct_diff <= 2.5) }"; then
            stat_similar=1
        fi
    fi

    # second pass: print rows with normalized time, formatted CI, ratio, and row colors
    for bench in "${bench_list[@]}"; do
        key="${suite}.${bench}"
        ci="${bench_ci[$key]:-?}"
        status="${bench_status[$key]:-unknown}"

        # normalize mean time from stored ns value
        ns="${bench_mean_ns[$key]:-}"
        if [[ -n "$ns" ]]; then
            mean=$(ns_to_display "$ns")
        else
            mean="N/A"
        fi

        # format CI to 1 decimal place (max 4 digits: e.g. 12.3% not 12.345%)
        if [[ "$ci" == "?" ]]; then
            ci_fmt="?"
        else
            ci_fmt=$(awk "BEGIN { printf \"%.1f\", $ci }")
        fi

        # ratio relative to slowest baseline (slowest=1.00x, faster=higher)
        if [[ "$status" == "ok" && -n "$slowest_ns" && -n "${bench_mean_ns[$key]:-}" ]]; then
            ratio=$(awk "BEGIN {
                v = ${bench_mean_ns[$key]} + 0
                if (v > 0) printf \"%.2fx\", $slowest_ns / v
                else print \"N/A\"
            }")
        else
            ratio="N/A"
        fi

        case "$status" in
            ok)          status_str="OK";   ((total_ok++)) ;;
            ci_exceeded) status_str="CI!";  ((total_ci++)); ((total_failed++)) ;;
            failed)      status_str="FAIL"; ((total_failed++)) ;;
            *)           status_str="?" ;;
        esac

        # row color/indicator: yellow/~=statistically similar, green/+=fastest, red/-=slowest
        row_color=""
        row_prefix=" "
        if [[ $stat_similar -eq 1 && "$status" == "ok" ]]; then
            row_color="$YELLOW"
            row_prefix="~"
        elif [[ "$key" == "$winner_key" && "$winner_key" != "$slowest_key" ]]; then
            row_color="$GREEN"
            row_prefix="+"
        elif [[ "$key" == "$slowest_key" && "$winner_key" != "$slowest_key" ]]; then
            row_color="$RED"
            row_prefix="-"
        fi

        if [[ $USE_COLOR -eq 1 ]]; then
            printf "%b| %-${CM}s | %-${CMEAN}s | %-${CCI}s | %-${CRATIO}s | %-${CSTATUS}s |%b\n" \
                "$row_color" "$bench" "$mean" "+-${ci_fmt}%" "$ratio" "$status_str" "$RESET"
        else
            # append indicator to method name: "methodname (+)"
            if [[ "$row_prefix" != " " ]]; then
                method_display="${bench} (${row_prefix})"
            else
                method_display="$bench"
            fi
            printf "| %-${CM}s | %-${CMEAN}s | %-${CCI}s | %-${CRATIO}s | %-${CSTATUS}s |\n" \
                "$method_display" "$mean" "+-${ci_fmt}%" "$ratio" "$status_str"
        fi
    done

    unset bench_list
done

# ─── summary ───────────────────────────────────────────────────────────────

total_benches=$((total_ok + total_failed))
[[ $max_table_width -lt 40 ]] && max_table_width=40
bar_width=$((max_table_width + 4))

echo ""
echo -e "${BOLD}${CYAN}$(barn $bar_width)${RESET}"
if [[ $total_failed -gt 0 ]]; then
    printf "${BOLD} SUMMARY:${RESET} %d total | ${GREEN}%d OK${RESET} | ${RED}%d FAIL${RESET}" \
        "$total_benches" "$total_ok" "$total_failed"
    [[ $total_ci -gt 0 ]] && printf " (CI: %d)" "$total_ci"
    echo ""
else
    printf "${BOLD} SUMMARY:${RESET} %d total | ${GREEN}%d OK${RESET}\n" "$total_benches" "$total_ok"
fi
echo -e "${BOLD}${CYAN}$(barn $bar_width)${RESET}"

exit "$bench_exit"
