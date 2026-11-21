#!/usr/bin/env python3
"""Throwaway (ci/ipa only): candidate fix for lost fixture output.

`simctl launch --console` relays the app's output through the simulator, and that relay
sometimes drops the tail of it: a run that logged its PASS line and exited normally was
reported as a failure. This rewrites each test script's
    xcrun simctl launch --terminate-running-process --console "$SIM_ID" BUNDLE ARGS 2>&1 | tee "$LOG"
into
    fixture_launch "$LOG" BUNDLE ARGS
which has the app write stdout and stderr straight into files, waits for that process to exit,
then adds that process's own entries from the simulator's system log, and writes it all to $LOG
so every later grep works unchanged.
It also puts a time limit on every xcrun and codesign call, so a hung compiler or
simulator step fails within minutes and names itself instead of stalling the job.
"""
import re
import sys

HELPER = r'''
# A time limit on every xcrun and codesign call (the compiler, simctl install and launch): a
# stuck one fails within minutes and says which step it was, instead of hanging the job.
FIXTURE_STEP_LIMIT=${FIXTURE_STEP_LIMIT:-300}
with_limit() {
    local label=$1 ticks=0 pid
    shift
    "$@" &
    pid=$!
    while kill -0 "$pid" 2> /dev/null; do
        sleep 0.2
        ticks=$((ticks + 1))
        if (( ticks >= FIXTURE_STEP_LIMIT * 5 )); then
            echo "time limit: '$label' still running after ${FIXTURE_STEP_LIMIT} s, stopping it" >&2
            pkill -9 -P "$pid" 2> /dev/null || true
            kill -9 "$pid" 2> /dev/null || true
            wait "$pid" 2> /dev/null || true
            return 124
        fi
    done
    wait "$pid"
}
xcrun() {
    local label="xcrun $1 $2 $3"
    if [[ "${1:-} ${3:-}" == "--sdk clang" ]]; then
        fixture_compile "$@"
        return
    fi
    echo "step: $label" >&2
    with_limit "$label" command xcrun "$@"
}

# A fixture compile is skipped when its output exists and nothing it reads has changed: the same
# arguments, the same source files and the same headers in every -I folder. The second call of a
# suite (the gamepad's --self-test-input) then reuses the first call's binary.
fixture_compile() {
    local arg out= previous=
    local -a inputs=()
    for arg in "$@"; do
        if [[ "$previous" == -o ]]; then out=$arg
        elif [[ "$arg" == -I* && -d "${arg#-I}" ]]; then inputs+=("${arg#-I}")
        elif [[ -f "$arg" ]]; then inputs+=("$arg")
        fi
        previous=$arg
    done
    local key
    key=$({ printf '%s\n' "$@"; find "${inputs[@]}" -type f -print0 | sort -z | xargs -0 shasum; } | shasum | cut -d' ' -f1)
    if [[ -n "$out" && -f "$out" && "$(cat "$out.inputs" 2> /dev/null)" == "$key" ]]; then
        echo "step: compile of $out reused, nothing it reads has changed" >&2
        return 0
    fi
    echo "step: compile of ${out:-a fixture}" >&2
    rm -f "$out.inputs"
    with_limit "compile of ${out:-a fixture}" command xcrun "$@"
    [[ -z "$out" ]] || printf '%s\n' "$key" > "$out.inputs"
}
codesign() { with_limit "codesign $*" command codesign "$@"; }
# The fixture's output, without the simulator's console relay (it can drop the end of a run):
# the app writes stdout and stderr straight to files, we wait for that process to exit, and the
# process's own entries in the simulator's system log are added, matched by its pid.
fixture_launch() {
    local log=$1 bundle=$2 line pid waited=0
    shift 2
    rm -f "$log.stdout" "$log.stderr"
    line=$(xcrun simctl launch --terminate-running-process --stdout="$PWD/$log.stdout" \
        --stderr="$PWD/$log.stderr" "$SIM_ID" "$bundle" "$@")
    pid=${line##*: }
    echo "$line"
    [[ "$pid" =~ ^[0-9]+$ ]] || { echo "fixture_launch: no pid in: $line"; return 1; }
    while kill -0 "$pid" 2> /dev/null; do
        sleep 0.5
        waited=$((waited + 1))
        if (( waited >= 600 )); then
            echo "fixture_launch: $bundle ($pid) still running after 300 s"
            kill -9 "$pid" 2> /dev/null || true
            break
        fi
    done
    {
        cat "$log.stdout" "$log.stderr" 2> /dev/null || true
        echo "--- the system log of $bundle ($pid) ---"
        xcrun simctl spawn "$SIM_ID" log show --last 15m --style compact \
            --predicate "processIdentifier == $pid" 2> /dev/null || true
    } | tee "$log"
}
'''

LAUNCH = re.compile(
    r'xcrun simctl launch --terminate-running-process --console "\$SIM_ID" (\S+)'
    r'((?:[^\n|]|\\\n)*?) 2>&1 \| tee "(\$\w+)"')

PREPARE_CHECK = r'''
# The prepared tree is reused when nothing it is made from has changed: the committed platform/,
# every file of ours outside it (tracked or new, ignored ones excepted), the local signing values
# and the generator's environment. Every suite calls this script, and rebuilding an identical tree
# each time cost minutes per run. WOLKARA_PREPARE_FRESH=1 rebuilds it regardless.
fingerprint=$({
    git rev-parse HEAD:platform
    git ls-files -z -co --exclude-standard -- . ':!platform' | sort -z | xargs -0 shasum 2> /dev/null || true
    cat local.env platform/local.env 2> /dev/null || true
    env | grep -E '^(TOLKARA_|DEVELOPMENT_TEAM=)' | sort || true
} | shasum | cut -d' ' -f1)
if [ -z "${WOLKARA_PREPARE_FRESH:-}" ] && [ -d "$dest" ] && [ "$(cat "$dest/.prepared-from" 2> /dev/null)" = "$fingerprint" ]; then
    echo "prepare: $dest reused, nothing it is made from has changed"
    exit 0
fi
'''

for path in sys.argv[1:]:
    text = open(path).read()
    if path.endswith('prepare.sh'):
        trap = "trap 'rm -rf \"$lock\"' EXIT HUP INT TERM\n"
        done = 'pinned=$(git rev-parse --short upstream/main'
        if trap not in text or done not in text:
            sys.exit(f"{path}: the lock or the final line moved; update fixture-launch.py")
        text = text.replace(trap, trap + PREPARE_CHECK, 1)
        text = text.replace(done, 'printf \'%s\\n\' "$fingerprint" > "$dest/.prepared-from"\n' + done, 1)
        open(path, 'w').write(text)
        print(f"{path}: an unchanged prepared tree is reused")
        continue
    text, count = LAUNCH.subn(lambda m: f'fixture_launch "{m.group(3)}" {m.group(1)}{m.group(2)}', text)
    if count == 0:
        sys.exit(f"{path}: no console launch found")
    anchor = '. wolkaraforever/tools/simulators.sh\n'
    if anchor not in text:
        sys.exit(f"{path}: no simulators.sh line to put the helper after")
    text = text.replace(anchor, anchor + HELPER, 1)
    open(path, 'w').write(text)
    print(f"{path}: {count} launch(es) now go through fixture_launch")
