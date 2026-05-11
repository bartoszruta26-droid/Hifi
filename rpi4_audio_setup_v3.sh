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
    if apt-get install -y --no-install-recommends "$DEPS"; then
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
