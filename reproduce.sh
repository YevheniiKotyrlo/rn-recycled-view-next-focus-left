#!/usr/bin/env bash
# Exit 1 while Arrow Left from a View that reuses a recycled Android view goes to the old view's nextFocusLeft target,
# 0 once it goes to the view on its left, 2 when another step fails.
# Needs adb with one Android device attached (ANDROID_SERIAL picks one of several), node, yarn and a JDK.
set -u

package=com.reproducerapp
log_tag=RecycledFocusReproducer

fail_step() {
    echo "step failed: $1"
    exit 2
}

# Sets the named variable to a device property, without the carriage return adb's shell ends it with.
read_device_property() {
    local value
    value="$(adb shell getprop "$2")" || fail_step "adb shell getprop $2: ${value}"
    printf -v "$1" '%s' "${value//$'\r'/}"
}

dump_window() {
    adb shell uiautomator dump /sdcard/recycled-focus-reproducer.xml > /dev/null 2>&1
    adb exec-out cat /sdcard/recycled-focus-reproducer.xml > "$1" 2> /dev/null
    adb shell rm -f /sdcard/recycled-focus-reproducer.xml
}

# Prints the content-desc of the node that holds focus, or "none".
focused_label() {
    local hierarchy=$1 nodes label
    dump_window "${hierarchy}"
    nodes="$(tr '>' '\n' < "${hierarchy}")" || nodes=""
    label="$(sed -nE 's/.*content-desc="([^"]*)".* focused="true".*/\1/p' <<< "${nodes}")" || label=""
    label="${label%%$'\n'*}"
    echo "${label:-none}"
}

wait_for_label() {
    local hierarchy=$1 label=$2 attempt
    for ((attempt = 1; attempt <= 30; attempt += 1)); do
        dump_window "${hierarchy}"
        if grep -qF "content-desc=\"${label}\"" "${hierarchy}"; then
            return 0
        fi
        sleep 1
    done
    return 1
}

press() {
    adb shell input keyevent "$1" || fail_step "adb shell input keyevent $1"
    sleep 1
}

# Presses Arrow Right until the labelled view holds focus.
focus_by_arrow_right() {
    local hierarchy=$1 label=$2 attempt now
    for ((attempt = 1; attempt <= 6; attempt += 1)); do
        now="$(focused_label "${hierarchy}")"
        if [[ "${now}" == "${label}" ]]; then
            echo "focused: ${now}"
            return 0
        fi
        press KEYCODE_DPAD_RIGHT
    done
    fail_step "Arrow Right never focused \"${label}\" (focused: ${now})"
}

# Prints the last line MainActivity logged that holds the text, without logcat's prefix.
logged_line() {
    local log line
    log="$(adb logcat -d -s "${log_tag}:I" 2> /dev/null)" || log=""
    line="$(grep -F "$1" <<< "${log}")" || line=""
    line="${line##*$'\n'}"
    echo "${line#*"${log_tag}"*: }"
}

# Prints the line MainActivity logged for the subject's nativeID.
subject_log() {
    local attempt line
    for ((attempt = 1; attempt <= 10; attempt += 1)); do
        line="$(logged_line "$1: view instance")"
        if [[ -n "${line}" ]]; then
            echo "${line}"
            return 0
        fi
        sleep 1
    done
    return 1
}

# The verdict from what the run read: whether the new subject reuses the old subject's Android view, where Arrow Left
# from the old subject went, and where Arrow Left from the new subject went.
verdict() {
    local recycled=$1 control=$2 seen=$3
    if [[ "${control}" != "Target" ]]; then
        echo "step failed: Arrow Left from the old subject went to \"${control}\", not to its nextFocusLeft \"Target\""
        return 2
    fi
    if [[ "${recycled}" != "yes" ]]; then
        echo "step failed: the new subject did not reuse the old subject's Android view, so nothing was recycled"
        return 2
    fi
    case "${seen}" in
        Target)
            echo "SUMMARY: Arrow Left from the new subject, which has no nextFocusLeft, went to \"Target\", the old subject's nextFocusLeft; expected \"Neighbour\""
            return 1
            ;;
        Neighbour)
            echo "SUMMARY: Arrow Left from the new subject went to \"Neighbour\", the view on its left"
            return 0
            ;;
        *)
            echo "step failed: Arrow Left from the new subject went to \"${seen}\""
            return 2
            ;;
    esac
}

main() {
    local here app
    here="$(cd "$(dirname "$0")" && pwd)"
    app="${here}/ReproducerApp"
    work="$(mktemp -d)"
    trap 'rm -rf "${work}"' EXIT

    local system node_version java_version
    system="$(uname -sm)"
    node_version="$(node --version 2>&1)" || fail_step "node --version: ${node_version}"
    java_version="$(java -version 2>&1)" || fail_step "java -version: ${java_version}"
    echo "${system}, node ${node_version}, ${java_version%%$'\n'*}"

    local device_state
    device_state="$(adb get-state 2>&1)"
    [[ "${device_state}" == "device" ]] || fail_step "adb get-state: ${device_state}"
    local model release sdk abi
    read_device_property model ro.product.model
    read_device_property release ro.build.version.release
    read_device_property sdk ro.build.version.sdk
    read_device_property abi ro.product.cpu.abi
    echo "device: ${model}, Android ${release} (API ${sdk}), ${abi}"

    local install_output react_native_version
    install_output="$(cd "${app}" && yarn install --frozen-lockfile --non-interactive 2>&1)" ||
        { printf '%s\n' "${install_output}" | tail -n 20; fail_step "yarn install"; }
    react_native_version="$(cd "${app}" && node -p 'require("react-native/package.json").version' 2>&1)" ||
        fail_step "reading react-native's version: ${react_native_version}"
    echo "react-native ${react_native_version}"

    echo "== ./gradlew :app:assembleRelease -PreactNativeArchitectures=${abi}"
    local build_output
    build_output="$(cd "${app}/android" && ./gradlew --no-daemon --console=plain :app:assembleRelease \
        "-PreactNativeArchitectures=${abi}" 2>&1)" ||
        { printf '%s\n' "${build_output}" | tail -n 40; fail_step "the release build"; }

    local apk install_result
    apk="${app}/android/app/build/outputs/apk/release/app-release.apk"
    if command -v cygpath > /dev/null; then
        apk="$(cygpath -m "${apk}")"
    fi
    install_result="$(adb install -r "${apk}" 2>&1)" || fail_step "adb install: ${install_result}"
    adb shell am force-stop "${package}"
    adb logcat -c || fail_step "adb logcat -c"
    adb shell am start -W -n "${package}/.MainActivity" > /dev/null || fail_step "starting ${package}"

    local hierarchy="${work}/hierarchy.xml" flag_line
    wait_for_label "${hierarchy}" "Old subject" || fail_step "the app showed no \"Old subject\""
    flag_line="$(logged_line "enableViewRecycling")"
    echo "${flag_line}"

    echo "== 1. Arrow Right to the old subject (nextFocusLeft = Target), then Arrow Left"
    focus_by_arrow_right "${hierarchy}" "Old subject"
    press KEYCODE_DPAD_LEFT
    local control
    control="$(focused_label "${hierarchy}")"
    echo "Arrow Left from the old subject focused: ${control}"

    echo "== 2. The old subject unmounts; a new subject without nextFocusLeft mounts"
    local old_line new_line recycled=no
    if wait_for_label "${hierarchy}" "New subject"; then
        old_line="$(subject_log subject-old)" || fail_step "MainActivity logged nothing for subject-old"
        new_line="$(subject_log subject-new)" || fail_step "MainActivity logged nothing for subject-new"
        echo "${old_line}"
        echo "${new_line}"
        local old_instance="${old_line#*view instance }" new_instance="${new_line#*view instance }"
        [[ "${old_instance%%,*}" == "${new_instance%%,*}" ]] && recycled=yes
        echo "the new subject reuses the old subject's Android view: ${recycled}"

        echo "== 3. Arrow Right to the new subject, then Arrow Left"
        focus_by_arrow_right "${hierarchy}" "New subject"
        press KEYCODE_DPAD_LEFT
    elif [[ "${control}" == "Target" ]]; then
        fail_step "the app showed no \"New subject\""
    fi
    local seen
    seen="$(focused_label "${hierarchy}")"
    echo "Arrow Left from the new subject focused: ${seen}"

    verdict "${recycled}" "${control}" "${seen}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
