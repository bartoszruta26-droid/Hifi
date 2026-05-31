#!/usr/bin/env bash
# shellcheck shell=bash
# ==========================================
# RPi4 Audio Setup - Config Applier Module
# Moduł aplikowania konfiguracji: bezpieczne wdrażanie plików
# ==========================================

set -euo pipefail

# Guard przed wielokrotnym sourcingiem
[[ -n "${_APPLIER_SH_LOADED:-}" ]] && return 0
readonly _APPLIER_SH_LOADED=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/core.sh"
source "$SCRIPT_DIR/backup.sh"
source "$SCRIPT_DIR/config_generator.sh"

# ==========================================
# APLIKOWANIE KONFIGURACJI
# ==========================================

# Atomowe zastąpienie pliku — bezpieczne przy przerwaniu (Ctrl+C, reboot)
_atomic_replace() {
    local src="$1"
    local dst="$2"
    local mode="${3:-644}"

    local tmp_file
    tmp_file="$(mktemp "${dst}.XXXXXX")"
    cp "$src" "$tmp_file"
    chmod "$mode" "$tmp_file"
    # mv jest atomowe na tym samym filesystem — nie może pozostawić pliku w stanie pośrednim
    mv "$tmp_file" "$dst"
}

# Backup pojedynczego pliku do katalogu backup (ujednolicona struktura)
_backup_single() {
    local src="$1"
    local label="$2"
    local ts
    ts="$(date +%Y%m%d_%H%M%S)"
    local backup_dir="$BACKUP_BASE/apply_${ts}"

    mkdir -p "$backup_dir"
    cp -a "$src" "$backup_dir/${label}"
    log "Backup before apply: $src → $backup_dir/${label}"
}

# ==========================================

# Aplikowanie daemon.conf
# POPRAWKA: atomowe zastąpienie przez mktemp + mv — idempotentne, bezpieczne
apply_daemon_conf() {
    local new_file="$STAGING_DIR/daemon.conf.new"

    if [[ ! -f "$new_file" ]]; then
        log "daemon.conf.new not found, run gen_configs first" "ERROR"
        return 1
    fi

    # Backup przed nadpisaniem (jeśli oryginał istnieje)
    [[ -f "$PULSE_DAEMON" ]] && _backup_single "$PULSE_DAEMON" "daemon.conf"

    # Upewnij się że katalog docelowy istnieje
    mkdir -p "$(dirname "$PULSE_DAEMON")"

    # Atomowe zastąpienie — brak bałaganu z #OLD_CONFIG po wielokrotnym uruchomieniu
    _atomic_replace "$new_file" "$PULSE_DAEMON" "644"

    log "Replaced $PULSE_DAEMON" "SUCCESS"
    echo -e "${COLORS[GREEN]}✅ Zastąpiono $PULSE_DAEMON${COLORS[NC]}"
}

# Aplikowanie default.pa
apply_default_pa() {
    local new_file="$STAGING_DIR/default.pa.new"

    if [[ ! -f "$new_file" ]]; then
        log "default.pa.new not found" "ERROR"
        return 1
    fi

    [[ -f "$PULSE_DEFAULT" ]] && _backup_single "$PULSE_DEFAULT" "default.pa"

    mkdir -p "$(dirname "$PULSE_DEFAULT")"
    _atomic_replace "$new_file" "$PULSE_DEFAULT" "644"

    log "Replaced $PULSE_DEFAULT" "SUCCESS"
    echo -e "${COLORS[GREEN]}✅ Zastąpiono $PULSE_DEFAULT${COLORS[NC]}"
}

# Aplikowanie mpd.conf
apply_mpd_conf() {
    local new_file="$STAGING_DIR/mpd.conf.new"

    if [[ ! -f "$new_file" ]]; then
        log "mpd.conf.new not found" "ERROR"
        return 1
    fi

    [[ -f "$MPD_CONF" ]] && _backup_single "$MPD_CONF" "mpd.conf"

    mkdir -p "$(dirname "$MPD_CONF")"
    _atomic_replace "$new_file" "$MPD_CONF" "640"

    # Ustaw uprawnienia właściciela MPD
    chown mpd:audio "$MPD_CONF" 2>/dev/null || true

    log "Replaced $MPD_CONF" "SUCCESS"
    echo -e "${COLORS[GREEN]}✅ Zastąpiono $MPD_CONF${COLORS[NC]}"
}

# Aplikowanie config.txt
apply_config_txt() {
    local new_file="$STAGING_DIR/config.txt.new"
    local target_cfg=""

    if [[ ! -f "$new_file" ]]; then
        log "config.txt.new not found" "ERROR"
        return 1
    fi

    if [[ -d "/boot/firmware" ]]; then
        target_cfg="$BOOT_CFG_DEFAULT"
    else
        target_cfg="$BOOT_CFG_LEGACY"
    fi

    [[ -f "$target_cfg" ]] && _backup_single "$target_cfg" "config.txt"

    mkdir -p "$(dirname "$target_cfg")"
    _atomic_replace "$new_file" "$target_cfg" "755"

    log "Replaced $target_cfg with overlay $HAT_MODEL" "SUCCESS"
    echo -e "${COLORS[GREEN]}✅ Zapisano dtoverlay=${HAT_MODEL}${COLORS[NC]}"
}

# Walidacja konfiguracji MPD
validate_mpd_config() {
    if command -v mpd &>/dev/null; then
        if mpd --test "$MPD_CONF" &>/dev/null; then
            echo -e "${COLORS[GREEN]}✅ Konfiguracja MPD poprawna${COLORS[NC]}"
            return 0
        else
            echo -e "${COLORS[RED]}⚠️  Błąd walidacji konfiguracji MPD${COLORS[NC]}"
            return 1
        fi
    else
        log "MPD not installed, skipping validation" "WARN"
        return 0
    fi
}

# Główna funkcja aplikująca wszystkie konfiguracje
apply_configs() {
    print_header
    echo -e "${COLORS[RED]}⚠️  UWAGA: Ta operacja zmodyfikuje pliki systemowe!${COLORS[NC]}"

    # POPRAWKA: poprawny numer opcji — generowanie to opcja 5, nie 4
    if [[ ! -f "$STAGING_DIR/daemon.conf.new" ]]; then
        echo -e "${COLORS[RED]}⚠️  Najpierw wygeneruj konfigurację (Opcja 5)!${COLORS[NC]}"
        return 1
    fi

    read -r -p "Czy na pewno chcesz kontynuować? (tak/nie): " confirm
    if [[ "$confirm" != "tak" ]]; then
        echo "Anulowano."
        return 0
    fi

    echo "Zatrzymywanie usług..."
    systemctl stop mpd 2>/dev/null || true
    systemctl --user stop pulseaudio 2>/dev/null || true

    echo "Zastępowanie plików konfiguracyjnych..."

    apply_daemon_conf || { log "Failed to apply daemon.conf" "ERROR"; return 1; }
    apply_default_pa  || { log "Failed to apply default.pa" "ERROR"; return 1; }
    apply_mpd_conf    || { log "Failed to apply mpd.conf" "ERROR"; return 1; }
    apply_config_txt  || { log "Failed to apply config.txt" "ERROR"; return 1; }

    echo ""
    validate_mpd_config || {
        echo -e "${COLORS[YELLOW]}⚠️  Kontynuuję mimo błędu walidacji MPD${COLORS[NC]}"
    }

    echo ""
    echo "Restart usług..."
    systemctl daemon-reload

    local pa_status="nieaktywna"
    local mpd_status="nieaktywna"

    if systemctl --user is-active pulseaudio 2>/dev/null; then
        systemctl --user restart pulseaudio 2>/dev/null && pa_status="aktywna" || pa_status="błąd"
    elif systemctl is-active pulseaudio 2>/dev/null; then
        systemctl restart pulseaudio 2>/dev/null && pa_status="aktywna" || pa_status="błąd"
    else
        systemctl --user start pulseaudio 2>/dev/null && pa_status="aktywna" || \
        systemctl start pulseaudio 2>/dev/null && pa_status="aktywna" || \
        pa_status="błąd"
    fi

    if systemctl is-active mpd 2>/dev/null; then
        systemctl restart mpd 2>/dev/null && mpd_status="aktywna" || mpd_status="błąd"
    else
        systemctl start mpd 2>/dev/null && mpd_status="aktywna" || mpd_status="błąd"
    fi

    echo ""
    echo "Status usług:"
    case "$pa_status" in
        aktywna) echo -e "  ${COLORS[GREEN]}✅${COLORS[NC]} PulseAudio: aktywna" ;;
        błąd)    echo -e "  ${COLORS[YELLOW]}⚠️${COLORS[NC]} PulseAudio: błąd uruchomienia" ;;
        *)       echo -e "  ${COLORS[YELLOW]}⚠️${COLORS[NC]} PulseAudio: nieaktywna" ;;
    esac

    case "$mpd_status" in
        aktywna) echo -e "  ${COLORS[GREEN]}✅${COLORS[NC]} MPD: aktywna" ;;
        błąd)    echo -e "  ${COLORS[YELLOW]}⚠️${COLORS[NC]} MPD: błąd uruchomienia" ;;
        *)       echo -e "  ${COLORS[YELLOW]}⚠️${COLORS[NC]} MPD: nieaktywna" ;;
    esac

    echo ""
    echo -e "${COLORS[GREEN]}✅ Konfiguracja zastosowana!${COLORS[NC]}"
    echo ""
    echo -e "${COLORS[YELLOW]}⚠️  WAŻNE: Aby zmiany w config.txt zadziałały, konieczny jest RESTART.${COLORS[NC]}"

    log "Configuration applied successfully" "SUCCESS"

    read -r -p "Czy chcesz teraz zrestartować system? (tak/nie): " reboot_now
    if [[ "$reboot_now" == "tak" ]]; then
        systemctl reboot
    fi

    return 0
}

# Eksport funkcji
export -f _atomic_replace _backup_single
export -f apply_daemon_conf apply_default_pa apply_mpd_conf apply_config_txt
export -f validate_mpd_config apply_configs
