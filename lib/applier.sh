#!/usr/bin/env bash
# shellcheck shell=bash
# ==========================================
# RPi4 Audio Setup - Config Applier Module
# Moduł aplikowania konfiguracji: bezpieczne wdrażanie plików
# ==========================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/core.sh"
source "$SCRIPT_DIR/backup.sh"
source "$SCRIPT_DIR/config_generator.sh"

# ==========================================
# APLIKOWANIE KONFIGURACJI
# ==========================================

# Aplikowanie daemon.conf
apply_daemon_conf() {
    local new_file="$STAGING_DIR/daemon.conf.new"
    
    if [[ ! -f "$new_file" ]]; then
        log "daemon.conf.new not found, run gen_configs first" "ERROR"
        return 1
    fi
    
    if [[ -f "$PULSE_DAEMON" ]]; then
        # Backup przed modyfikacją
        cp "$PULSE_DAEMON" "$STAGING_DIR/daemon.conf.bak"
        
        # Skomentuj stare linie naszych parametrów
        for param in "default-sample-format" "default-sample-rate" "alternate-sample-rate" \
                     "resample-method" "flat-volumes" "realtime-scheduling" "rlimit-rtprio" \
                     "exit-idle-time" "log-level"; do
            sed -i "s/^${param}[[:space:]]*=.*/#OLD_CONFIG: &/" "$PULSE_DAEMON"
        done
        
        # Dodaj nowe linie na końcu
        {
            echo ""
            echo "# === New Audio HQ Settings $(date) ==="
            grep -v "^#" "$new_file" | grep -v "^$"
        } >> "$PULSE_DAEMON"
        
        log "Modified $PULSE_DAEMON"
    else
        # Plik nie istnieje - utwórz nowy
        cp "$new_file" "$PULSE_DAEMON"
        log "Created $PULSE_DAEMON"
    fi
    
    echo -e "${COLORS[GREEN]}✅ Zmodyfikowano $PULSE_DAEMON${COLORS[NC]}"
}

# Aplikowanie default.pa
apply_default_pa() {
    local new_file="$STAGING_DIR/default.pa.new"
    
    if [[ ! -f "$new_file" ]]; then
        log "default.pa.new not found" "ERROR"
        return 1
    fi
    
    if [[ -f "$PULSE_DEFAULT" ]]; then
        cp "$PULSE_DEFAULT" "$STAGING_DIR/default.pa.bak"
        
        # Sprawdź które moduły już są załadowane i dodaj brakujące
        while IFS= read -r line; do
            # Pomiń komentarze i puste linie
            [[ "$line" =~ ^# ]] && continue
            [[ -z "$line" ]] && continue
            
            # Sprawdź czy CAŁA linia już istnieje
            if ! grep -qxF "$line" "$PULSE_DEFAULT"; then
                echo "$line" >> "$PULSE_DEFAULT"
                log "Added module: $line"
            fi
        done < "$new_file"
        
        log "Modified $PULSE_DEFAULT"
    else
        # Utwórz minimalny plik
        cat > "$PULSE_DEFAULT" << 'EOF'
#!/usr/bin/pulseaudio -nF
EOF
        cat "$new_file" >> "$PULSE_DEFAULT"
        log "Created $PULSE_DEFAULT"
    fi
    
    echo -e "${COLORS[GREEN]}✅ Zmodyfikowano $PULSE_DEFAULT${COLORS[NC]}"
}

# Aplikowanie mpd.conf
apply_mpd_conf() {
    local new_file="$STAGING_DIR/mpd.conf.new"
    
    if [[ ! -f "$new_file" ]]; then
        log "mpd.conf.new not found" "ERROR"
        return 1
    fi
    
    if [[ -f "$MPD_CONF" ]]; then
        cp "$MPD_CONF" "$STAGING_DIR/mpd.conf.bak"
        
        # Usuń nasze stare parametry
        sed -i '/^samplerate_converter/d' "$MPD_CONF"
        sed -i '/^audio_buffer_size/d' "$MPD_CONF"
        sed -i '/^replaygain/d' "$MPD_CONF"
        sed -i '/^auto_update/d' "$MPD_CONF"
        sed -i '/^zeroconf_enabled/d' "$MPD_CONF"
        
        # Dodaj nowe parametry z nowego pliku
        grep -E "^(samplerate_converter|audio_buffer_size|replaygain|auto_update|zeroconf_enabled)" "$new_file" >> "$MPD_CONF"
        
        log "Modified $MPD_CONF"
    else
        cp "$new_file" "$MPD_CONF"
        log "Created $MPD_CONF"
    fi
    
    # Ustaw uprawnienia
    chown mpd:audio "$MPD_CONF" 2>/dev/null || true
    chmod 640 "$MPD_CONF"
    
    echo -e "${COLORS[GREEN]}✅ Zmodyfikowano $MPD_CONF${COLORS[NC]}"
}

# Aplikowanie config.txt
apply_config_txt() {
    local new_file="$STAGING_DIR/config.txt.new"
    local target_cfg=""
    
    if [[ ! -f "$new_file" ]]; then
        log "config.txt.new not found" "ERROR"
        return 1
    fi
    
    # Określ docelowy plik
    if [[ -d "/boot/firmware" ]]; then
        target_cfg="$BOOT_CFG_DEFAULT"
    else
        target_cfg="$BOOT_CFG_LEGACY"
    fi
    
    # Backup
    if [[ -f "$target_cfg" ]]; then
        local backup_file
        backup_file="$BACKUP_BASE/config.txt.$(date +%Y%m%d_%H%M%S).bak"
        cp "$target_cfg" "$backup_file"
        echo "Backup utworzony: $backup_file"
        
        # Kopiuj cały plik (już zmodyfikowany przez generator)
        cp "$new_file" "$target_cfg"
        
        log "Modified $target_cfg with overlay $HAT_MODEL"
    else
        # Plik nie istnieje - utwórz nowy
        cp "$new_file" "$target_cfg"
        log "Created $target_cfg"
    fi
    
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
    
    # Sprawdź czy pliki staging istnieją
    if [[ ! -f "$STAGING_DIR/daemon.conf.new" ]]; then
        echo -e "${COLORS[RED]}⚠️  Najpierw wygeneruj konfigurację (Opcja 4)!${COLORS[NC]}"
        return 1
    fi
    
    read -r -p "Czy na pewno chcesz kontynuować? (tak/nie): " confirm
    if [[ "$confirm" != "tak" ]]; then
        echo "Anulowano."
        return 0
    fi
    
    echo "Zatrzymywanie usług..."
    systemctl stop mpd pulseaudio 2>/dev/null || true
    
    echo "Modyfikowanie plików konfiguracyjnych..."
    
    # Aplikuj każdy plik
    apply_daemon_conf || { log "Failed to apply daemon.conf" "ERROR"; return 1; }
    apply_default_pa || { log "Failed to apply default.pa" "ERROR"; return 1; }
    apply_mpd_conf || { log "Failed to apply mpd.conf" "ERROR"; return 1; }
    apply_config_txt || { log "Failed to apply config.txt" "ERROR"; return 1; }
    
    # Walidacja
    echo ""
    validate_mpd_config || {
        echo -e "${COLORS[YELLOW]}⚠️  Kontynuuję mimo błędu walidacji MPD${COLORS[NC]}"
    }
    
    # Restart usług
    echo ""
    echo "Restart usług..."
    systemctl daemon-reload
    
    local pa_status="nieaktywna"
    local mpd_status="nieaktywna"
    
    # PulseAudio - sprawdź czy działa jako user service
    if systemctl --user is-active pulseaudio 2>/dev/null; then
        systemctl --user restart pulseaudio 2>/dev/null && pa_status="aktywna"
    elif systemctl is-active pulseaudio 2>/dev/null; then
        systemctl restart pulseaudio 2>/dev/null && pa_status="aktywna"
    else
        # Spróbuj uruchomić
        systemctl --user start pulseaudio 2>/dev/null && pa_status="aktywna" || \
        systemctl start pulseaudio 2>/dev/null && pa_status="aktywna" || \
        pa_status="błąd"
    fi
    
    # MPD
    if systemctl is-active mpd 2>/dev/null; then
        systemctl restart mpd 2>/dev/null && mpd_status="aktywna"
    else
        systemctl start mpd 2>/dev/null && mpd_status="aktywna" || mpd_status="błąd"
    fi
    
    # Status
    echo ""
    echo "Status usług:"
    case "$pa_status" in
        aktywna)  echo -e "  ${COLORS[GREEN]}✅${COLORS[NC]} PulseAudio: aktywna" ;;
        błąd)     echo -e "  ${COLORS[YELLOW]}⚠️${COLORS[NC]} PulseAudio: błąd uruchomienia" ;;
        *)        echo -e "  ${COLORS[YELLOW]}⚠️${COLORS[NC]} PulseAudio: nieaktywna" ;;
    esac
    
    case "$mpd_status" in
        aktywna)  echo -e "  ${COLORS[GREEN]}✅${COLORS[NC]} MPD: aktywna" ;;
        błąd)     echo -e "  ${COLORS[YELLOW]}⚠️${COLORS[NC]} MPD: błąd uruchomienia" ;;
        *)        echo -e "  ${COLORS[YELLOW]}⚠️${COLORS[NC]} MPD: nieaktywna" ;;
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
export -f apply_daemon_conf apply_default_pa apply_mpd_conf apply_config_txt validate_mpd_config apply_configs
