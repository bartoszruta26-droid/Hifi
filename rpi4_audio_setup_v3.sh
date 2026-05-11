#!/usr/bin/env bash
# shellcheck shell=bash
# ==========================================
# RPi4 Audio Setup - Main Entry Point
# Główny punkt wejścia skryptu
# Wersja 3.0 - Modularna, bezpieczna architektura
# ==========================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ładowanie modułów w odpowiedniej kolejności
source "$SCRIPT_DIR/lib/core.sh"
source "$SCRIPT_DIR/lib/backup.sh"
source "$SCRIPT_DIR/lib/config_generator.sh"
source "$SCRIPT_DIR/lib/applier.sh"
source "$SCRIPT_DIR/lib/ui.sh"

# ==========================================
# DODATKOWE FUNKCJE POMOCNICZE
# ==========================================

# Instalacja pakietów
install_packages() {
    print_header
    echo -e "${COLORS[YELLOW]}📦 Instalacja pakietów...${COLORS[NC]}"
    
    apt-get update -qq
    
    local DEPS="mpd pulseaudio pulseaudio-utils alsa-utils sox libsoxr-dev mpc"
    
    echo "Instalowanie: $DEPS"
    if apt-get install -y --no-install-recommends $DEPS; then
        echo -e "${COLORS[GREEN]}✅ Pakiety zainstalowane.${COLORS[NC]}"
        log "Packages installed successfully" "SUCCESS"
    else
        echo -e "${COLORS[RED]}⚠️  Błąd instalacji pakietów${COLORS[NC]}"
        log "Package installation failed" "ERROR"
        return 1
    fi
    
    # Wyłączenie PipeWire-Pulse jeśli aktywne (z ostrzeżeniem)
    if systemctl is-active --quiet pipewire-pulse 2>/dev/null; then
        echo ""
        echo -e "${COLORS[YELLOW]}⚠️  Wykryto PipeWire-Pulse. Czy chcesz go wyłączyć?${COLORS[NC]}"
        echo "   Uwaga: Może to wpłynąć na inne aplikacje audio."
        read -r -p "Wyłączyć PipeWire-Pulse? (tak/nie): " disable_pipewire
        
        if [[ "$disable_pipewire" == "tak" ]]; then
            systemctl --global mask pipewire-pulse.service 2>/dev/null || true
            systemctl mask pipewire-pulse.service 2>/dev/null || true
            systemctl stop pipewire-pulse 2>/dev/null || true
            echo -e "${COLORS[GREEN]}✅ PipeWire-Pulse wyłączony${COLORS[NC]}"
        fi
    fi
    
    echo ""
    read -r -p "Naciśnij Enter, aby kontynuować..."
}

# Test audio
test_audio() {
    print_header
    echo -e "${COLORS[CYAN]}🔊 Test Dźwięku${COLORS[NC]}"
    echo "Upewnij się, że głośniki są podłączone."
    echo ""
    
    echo "1. Lista urządzeń ALSA:"
    aplay -l 2>/dev/null | grep -i dac || echo "Nie wykryto DACa przez aplay."
    echo ""
    
    read -r -p "Naciśnij Enter, aby odtworzyć dźwięk testowy (sinus 440Hz)..."
    
    echo ""
    echo "2. Test ALSA (speaker-test):"
    if speaker-test -t sine -f 440 -l 3 2>&1; then
        echo -e "${COLORS[GREEN]}✅ Test ALSA zakończony${COLORS[NC]}"
    else
        echo -e "${COLORS[YELLOW]}⚠️  Błąd speaker-test. Czy usługa audio działa?${COLORS[NC]}"
    fi
    
    echo ""
    echo "3. Test PulseAudio:"
    if command -v paplay &>/dev/null; then
        echo "Generowanie krótkiego sygnału przez PulseAudio..."
        # Generuj prosty sygnał sinusoidalny
        if command -v sox &>/dev/null; then
            sox -n -r 44100 -c 2 /tmp/test_tone.wav synth 2 sine 440 2>/dev/null
            paplay /tmp/test_tone.wav 2>/dev/null && \
                echo -e "${COLORS[GREEN]}✅ Test PulseAudio zakończony${COLORS[NC]}" || \
                echo -e "${COLORS[YELLOW]}⚠️  PA nie odpowiada.${COLORS[NC]}"
            rm -f /tmp/test_tone.wav
        else
            echo "Sox nie zainstalowany, pominięto zaawansowany test."
        fi
    else
        echo "paplay nie dostępne."
    fi
    
    echo ""
    read -r -p "Naciśnij Enter, aby wrócić..."
}

# Podgląd pliku z możliwością wyboru
preview_system_files() {
    print_header
    
    if [[ "$MENU_LANG" == "en" ]]; then
        echo "Preview:"
        echo "1) Boot Config"
        echo "2) Pulse Daemon"
        echo "3) MPD Config"
        read -r -p "Select [1-3]: " sub
    else
        echo "Podgląd:"
        echo "1) Boot Config"
        echo "2) Pulse Daemon"
        echo "3) MPD Config"
        read -r -p "Wybierz [1-3]: " sub
    fi
    
    case $sub in
        1) 
            local boot_cfg=""
            if [[ -d "/boot/firmware" ]] && [[ -f "$BOOT_CFG_DEFAULT" ]]; then
                boot_cfg="$BOOT_CFG_DEFAULT"
            elif [[ -f "$BOOT_CFG_LEGACY" ]]; then
                boot_cfg="$BOOT_CFG_LEGACY"
            fi
            if [[ -n "$boot_cfg" ]]; then
                preview_file "$boot_cfg" "Boot Config"
            else
                echo -e "${COLORS[RED]}⚠️  Plik config.txt nie istnieje${COLORS[NC]}"
            fi
            ;;
        2) preview_file "$PULSE_DAEMON" "Pulse Daemon" ;;
        3) preview_file "$MPD_CONF" "MPD Config" ;;
        *) echo "Nieprawidłowy wybór." ;;
    esac
    
    echo ""
    read -r -p "Naciśnij Enter, aby kontynuować..."
}

# Porównywanie backupów z nowymi plikami
compare_backups() {
    print_header
    
    local LATEST
    LATEST=$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d -printf "%T@ %p\n" 2>/dev/null | sort -nr | head -n1 | cut -d" " -f2-)
    
    if [[ -z "$LATEST" ]]; then
        if [[ "$MENU_LANG" == "en" ]]; then
            echo "No backup found!"
        else
            echo "Brak backupu!"
        fi
        read -r -p "Enter..."
        return 1
    fi
    
    echo -e "${COLORS[CYAN]}Porównywanie z backupem: $LATEST${COLORS[NC]}"
    echo ""
    
    # Sprawdź wygenerowane pliki
    local files_to_compare=(
        "daemon.conf.new:$PULSE_DAEMON"
        "default.pa.new:$PULSE_DEFAULT"
        "mpd.conf.new:$MPD_CONF"
    )
    
    for pair in "${files_to_compare[@]}"; do
        IFS=':' read -r new_file orig_file <<< "$pair"
        local new_path="$STAGING_DIR/$new_file"
        
        if [[ -f "$new_path" ]] && [[ -f "$orig_file" ]]; then
            echo -e "${COLORS[YELLOW]}--- $orig_file ---${COLORS[NC]}"
            compare_files "$orig_file" "$new_path" || true
            echo ""
        fi
    done
    
    # Config.txt
    local boot_cfg=""
    if [[ -d "/boot/firmware" ]] && [[ -f "$BOOT_CFG_DEFAULT" ]]; then
        boot_cfg="$BOOT_CFG_DEFAULT"
    elif [[ -f "$BOOT_CFG_LEGACY" ]]; then
        boot_cfg="$BOOT_CFG_LEGACY"
    fi
    
    if [[ -f "$STAGING_DIR/config.txt.new" ]] && [[ -n "$boot_cfg" ]]; then
        echo -e "${COLORS[YELLOW]}--- $boot_cfg ---${COLORS[NC]}"
        compare_files "$boot_cfg" "$STAGING_DIR/config.txt.new" || true
        echo ""
    fi
    
    read -r -p "Naciśnij Enter, aby kontynuować..."
}

# Przywracanie z backupu
restore_backup_menu() {
    print_header
    
    echo -e "${COLORS[YELLOW]}🔄 Przywracanie z backupu${COLORS[NC]}"
    echo ""
    
    # Znajdź wszystkie backupy
    local backups=()
    while IFS= read -r dir; do
        backups+=("$dir")
    done < <(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d -printf "%T@ %p\n" 2>/dev/null | sort -nr | cut -d" " -f2-)
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        echo -e "${COLORS[RED]}⚠️  Brak dostępnych backupów${COLORS[NC]}"
        read -r -p "Enter..."
        return 1
    fi
    
    echo "Dostępne backupy:"
    local idx=1
    for bkp in "${backups[@]}"; do
        echo "$idx) $bkp"
        ((idx++))
    done
    echo ""
    
    read -r -p "Wybierz backup do przywrócenia [1-${#backups[@]}]: " choice
    
    if [[ -v "backups[$((choice-1))]" ]]; then
        local selected="${backups[$((choice-1))]}"
        echo ""
        echo -e "${COLORS[YELLOW]}⚠️  Ta operacja nadpisze obecne pliki konfiguracyjne!${COLORS[NC]}"
        read -r -p "Czy na pewno chcesz przywrócić? (tak/nie): " confirm
        
        if [[ "$confirm" == "tak" ]]; then
            restore_from_backup "$selected"
        else
            echo "Anulowano."
        fi
    else
        echo "Nieprawidłowy wybór."
    fi
    
    read -r -p "Enter..."
}

# Czyszczenie starych backupów
cleanup_backups_menu() {
    print_header
    
    echo -e "${COLORS[YELLOW]}🧹 Czyszczenie starych backupów${COLORS[NC]}"
    echo ""
    
    read -r -p "Ile ostatnich backupów zachować? (domyślnie 5): " keep_count
    keep_count="${keep_count:-5}"
    
    cleanup_old_backups "$keep_count"
    
    read -r -p "Enter..."
}

# Funkcja pomocnicza do czyszczenia
cleanup() {
    log "Script exiting, cleaning up..."
    if [[ -d "$STAGING_DIR" ]]; then
        rm -rf "$STAGING_DIR"
    fi
}

trap cleanup EXIT

# ==========================================
# PROGRAM GŁÓWNY
# ==========================================

main() {
    # Sprawdzenie uprawnień root
    if ! check_root; then
        exit 1
    fi
    
    # Inicjalizacja
    init_dirs
    
    log "=== RPi4 Audio Setup v3.0 Started ==="
    
    # Uruchomienie menu głównego
    main_menu
}

# Start programu
main "$@"
