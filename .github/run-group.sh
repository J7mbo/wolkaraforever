#!/bin/bash
# Throwaway (ci/ipa only): one group of validate.sh --full's rows, run from the repository
# root. Every suite in the group runs even after a failure; the group fails if any did.
# The device rows (pilot.sh, device_matrix.sh) and the signed device build need a real
# iPad or a signing team, so no group runs them.
set -uo pipefail

group=$1
known=$(mktemp)
sed -E 's/^[[:space:]]*#?[[:space:]]*//; s/[[:space:]]+(-|—).*$//' wolkaraforever/tools/known_platform_failures.txt \
    | grep -E '^[a-zA-Z_][a-zA-Z0-9_.]*$' | sort -u > "$known"

declare -a names=() results=()
run() {
    local name=$1 start=$SECONDS rc
    shift
    echo "::group::$name"
    "$@"
    rc=$?
    echo "::endgroup::"
    names+=("$name")
    if [ "$rc" = 0 ]; then results+=("PASS ($((SECONDS - start)) s)")
    else results+=("FAIL exit $rc ($((SECONDS - start)) s)"); echo "::error::$name failed (exit $rc)"; fi
}
# A platform suite passes when its only failures are on known_platform_failures.txt, as in
# validate.sh's run_platform_suite.
platform() {
    local name=$1 log rc mine
    shift
    log=$(mktemp)
    "$@" 2>&1 | tee "$log"
    rc=${PIPESTATUS[0]}
    mine=$(grep -E "^(FAIL|ERROR): " "$log" | sed -E 's/.*(FAIL|ERROR): [^(]*\(([^)]*)\).*/\2/' \
        | grep -vxFf "$known" | wc -l | tr -d ' ')
    if [ "$rc" = 0 ]; then return 0; fi
    if [ "$rc" = 1 ] && [ "$mine" = 0 ] && grep -qx PLATFORM_EMULATION_COMPLETE "$log"; then
        echo "only known platform failures"; return 0
    fi
    echo "$mine failure(s) not on the known list"; return 1
}

T=wolkaraforever/tools
case "$group" in
mac-tools)
    run "layer gate" $T/check_layers.sh
    for t in $T/tests/test_*.sh; do run "$(basename "$t" .sh)" "$t"; done
    run "External-JIT diagnostics" $T/test_external_jit_diagnostics.sh
    run "CurseForge contracts" $T/test_curseforge.sh
    run "app icon assets" $T/test_icon_assets.sh
    run "mobile add-on Lua" $T/test_mobile_addon.sh
    ;;
mac-builds)
    run "app language" $T/test_localization.sh
    run "local service retry (0006)" $T/test_local_service_retry.sh
    run "developer-service handoff" $T/test_authorization_handoff.sh
    run "ZIP extraction" $T/test_addon_archive.sh
    run "game file verification (CASC)" $T/test_wow_launcher.sh
    run "config and UI backup/restore" $T/test_forever_ui.sh
    run "bundled add-on package" $T/test_addon_package.sh
    ;;
sim-ui)
    run "launcher UI policy and baselines (both simulators)" $T/check_ui_policy.sh
    run "launcher pages" $T/test_wow_launcher_ui.sh
    ;;
sim-input)
    run "input, voice and config rules" $T/test_voice.sh
    run "controller command path" $T/test_controller_input.sh
    run "game sound (0065)" $T/test_audio_sim.sh
    ;;
touch-ipad|touch-iphone)
    run "on-screen controls" $T/test_touch_controls_ui.sh --self-test
    run "on-screen gamepad" $T/test_touch_gamepad_ui.sh --self-test
    run "on-screen gamepad input" $T/test_touch_gamepad_ui.sh --self-test-input
    ;;
platform-emulation)
    run "prepare" $T/prepare.sh
    run "platform emulation suite" platform "platform emulation suite" bash build/platform/tools/test_emulation.sh
    ;;
full-sim)
    run "translation adapters" platform "translation adapters" $T/test_translation_sim.sh
    run "add-on hub against the real page" $T/test_addon_hub_live.sh
    run "content-view sizing (0054)" $T/test_appkit_content_view.sh
    run "inactive Metal submission" $T/test_background_pacing_sim.sh
    run "enrolment reference in the Keychain" $T/test_enrollment_reference_sim.sh
    ;;
*) echo "unknown group $group"; exit 2 ;;
esac

echo
echo "== $group"
failed=0
for i in "${!names[@]}"; do
    printf '%-55s %s\n' "${names[$i]}" "${results[$i]}"
    case "${results[$i]}" in FAIL*) failed=1 ;; esac
done
exit $failed
