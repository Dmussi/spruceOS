#!/bin/sh
# Powkiddy V10 device functions. Everything the base OS decides is in
# dArkMossCommon.sh; this file holds what is particular to this unit.

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/dArkMossCommon.sh"

# The rk817 codec switches to the jack itself on the OGA 1.1 kernel, and there
# is no jack state file for spruce to read, so the base's path is left alone.
# UNVERIFIED: on this V10 the jack switch reads inverted (seen under the
# NextUI port, which had to flip it). If headphones stay silent, this is where
# a watcher on the rk817 jack input goes.
apply_playback_path() {
    :
}

# device_init from dArkMossCommon.sh, plus a boot timing record: spruce's own
# start-up takes ~7 s on a V10 (first log), so where a slow boot spends its time
# is before spruce, in the kernel and systemd. Written to darkmoss_debug.log.
device_init() {
    v10_boot_timing &
    migrate_platform_files
    resolve_pad_node
    log_message "$PLATFORM: TF2 is ${SD_DEV:-<unresolved>} at $SD_MOUNTPOINT"
    resolve_key_event_node
    setup_mainui_alias
    if [ -n "$DARKMOSS_SEED_SYSTEM_JSON" ] && [ ! -f "$SYSTEM_JSON" ] && [ -f "$SYSTEM_JSON_DEFAULT" ]; then
        cp "$SYSTEM_JSON_DEFAULT" "$SYSTEM_JSON"
    fi
    set_backlight "$(get_backlight_level)"
    darkmoss_wifi_up
    /mnt/SDCARD/spruce/scripts/bluetooth.sh boot &
    darkmoss_debug_dump
    clear_stale_pmic_power_en &
}

v10_boot_timing() {
    _up="$(cut -d' ' -f1 /proc/uptime)"
    log_message "$PLATFORM: spruce started ${_up}s after the kernel"
    sleep 45
    {
        echo "================ boot timing $(date) ================"
        echo "--- spruce started at uptime ${_up}s"
        echo "--- systemd-analyze"
        systemd-analyze 2>&1
        echo "--- systemd-analyze blame (top 25)"
        systemd-analyze blame 2>&1 | head -25
        echo "--- systemd-analyze critical-chain"
        systemd-analyze critical-chain 2>&1 | head -30
        echo "--- dmesg: slowest gaps"
        dmesg 2>/dev/null | awk -F'[][]' '{t=$2+0; if (NR>1 && t-p>0.5) printf "%.2fs gap before: %s\n", t-p, $0; p=t}' | head -20
    } >> "$DARKMOSS_DEBUG_LOG" 2>&1
}

# idlemon's default node is the power key here. The js node, because
# emulators write rumble to the event node.
set_event_arg_for_idlemon() {
    EVENT_ARG="-e $(readlink -f /dev/input/by-path/platform-odroidgo2-joypad-joystick)"
}

device_get_charging_status() {
    if grep -qs "^1$" /sys/class/power_supply/ac/online /sys/class/power_supply/usb/online; then
        if [ "$(cat "$BATTERY/capacity" 2>/dev/null)" = "100" ]; then
            echo "Full"
        else
            echo "Charging"
        fi
    else
        echo "Discharging"
    fi
}

# The memory clock must not move: every change stalls the bus and the sound
# crackles (measured on a V10). The 4.4 kernel's dmc offers no "performance"
# governor, so every CPU mode pins it with "userspace" at its top frequency.
set_dram_governor() {
    [ -n "$DRAM_DEVFREQ_DIR" ] && [ -d "$DRAM_DEVFREQ_DIR" ] || return 0
    _top=$(tr ' ' '\n' < "$DRAM_DEVFREQ_DIR/available_frequencies" 2>/dev/null | grep -v '^$' | sort -n | tail -1)
    [ -n "$_top" ] || return 0
    echo userspace > "$DRAM_DEVFREQ_DIR/governor" 2>/dev/null
    echo "$_top" > "$DRAM_DEVFREQ_DIR/userspace/set_freq" 2>/dev/null
    echo "$_top" > "$DRAM_DEVFREQ_DIR/min_freq" 2>/dev/null
}

# This pad's udev numbering (RetroArch autoconfig "GO-Advance Gamepad (rev 1.1)"):
# select 12, R2 15. No stick clicks, so fast forward goes on R2.
set_default_ra_hotkeys() {
    RA_FILE="/mnt/SDCARD/Saves/ra-configs/retroarch-$PLATFORM.cfg"

    log_message "Resetting RetroArch hotkeys to Spruce defaults."

    update_ra_config_file_with_new_setting "$RA_FILE" \
        "input_enable_hotkey_btn = \"12\"" \
        "input_exit_emulator_btn = \"0\"" \
        "input_fps_toggle_btn = \"2\"" \
        "input_load_state_btn = \"4\"" \
        "input_save_state_btn = \"5\"" \
        "input_menu_toggle = \"f1\"" \
        "input_menu_toggle_btn = \"3\"" \
        "input_quit_gamepad_combo = \"0\"" \
        "input_toggle_fast_forward_btn = \"15\"" \
        "input_screenshot_btn = \"nul\"" \
        "input_shader_toggle_btn = \"nul\"" \
        "input_state_slot_decrease_btn = \"nul\"" \
        "input_state_slot_increase_btn = \"nul\"" \
        "input_toggle_slowmotion_btn = \"nul\""
}
