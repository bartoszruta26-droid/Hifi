#!/usr/bin/env bash
# shellcheck shell=bash
# ==========================================
# RPi4 Audio Setup - Interactive UI Module
# Moduł interfejsu użytkownika: menu, wybór modelu, konfiguracja jakości
# ==========================================

set -euo pipefail

# Guard przed wielokrotnym sourcingiem
[[ -n "${_UI_SH_LOADED:-}" ]] && return 0
readonly _UI_SH_LOADED=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==========================================
# ŁADOWANIE MODUŁÓW ZALEŻNYCH
# ==========================================
if [[ ! -f "$SCRIPT_DIR/core.sh" ]]; then
    echo "[BŁĄD] Nie znaleziono core.sh w $SCRIPT_DIR" >&2
    exit 1
fi
source "$SCRIPT_DIR/core.sh"

if [[ ! -f "$SCRIPT_DIR/backup.sh" ]]; then
    log "Nie znaleziono backup.sh" "ERROR"
    exit 1
fi
source "$SCRIPT_DIR/backup.sh"

if [[ ! -f "$SCRIPT_DIR/config_generator.sh" ]]; then
    log "Nie znaleziono config_generator.sh" "ERROR"
    exit 1
fi
source "$SCRIPT_DIR/config_generator.sh"

# ==========================================
# ZMIENNE SESJI
# ==========================================
declare -g MENU_LANG="${DEFAULT_MENU_LANG:-pl}"
declare -g HAT_MODEL_SELECTED=""

# ==========================================
# FUNKCJE UI
# ==========================================

print_header() {
    clear
    local version="3.0 (Modular)"

    if [[ "$MENU_LANG" == "en" ]]; then
        echo -e "${COLORS[CYAN]}=========================================="
        echo -e "🎧 RPi4 Audio HQ Setup (Trixie/Bookworm)"
        echo -e "Version: $version | R38 and other HAT support"
        echo -e "==========================================${COLORS[NC]}"
    else
        echo -e "${COLORS[CYAN]}=========================================="
        echo -e "🎧 RPi4 Audio HQ Setup (Trixie/Bookworm)"
        echo -e "Wersja: $version | Obsługa R38 i innych HAT"
        echo -e "==========================================${COLORS[NC]}"
    fi
    echo ""
}

# Wybór modelu DAC HAT
select_model() {
    print_header

    if [[ "$MENU_LANG" == "en" ]]; then
        echo -e "${COLORS[YELLOW]}⏳ Select DAC HAT model...${COLORS[NC]}"
        echo ""
        echo "Select your DAC HAT model:"
        echo " 1) R38 / Generic I2S DAC (PCM512x)"
        echo " 2) HiFiBerry DAC+ / DAC+ Pro / DAC+ Zero"
        echo " 3) HiFiBerry DAC+ HD (PCM1792A)   [768 kHz]"
        echo " 4) JustBoom DAC HAT"
        echo " 5) IQaudio DAC Pro / DAC+"
        echo " 6) Pimoroni DAC Shim (Generic I2S)"
        echo " 7) Allo Boss DAC"
        echo " 8) Allo Katana DAC                 [768 kHz]"
        echo " 9) Google Voice HAT                [max 48 kHz / 16 bit]"
        echo "10) AudioInjector (WM8731)           [max 96 kHz / 24 bit]"
        echo "11) Other / Custom (enter manually)"
        echo ""
        read -r -p "Your choice [1-11] (default 1): " hat_choice
    else
        echo -e "${COLORS[YELLOW]}⏳ Wybór modelu DAC HAT...${COLORS[NC]}"
        echo ""
        echo "Wybierz model swojego DAC HAT:"
        echo " 1) R38 / Generic I2S DAC (PCM512x)"
        echo " 2) HiFiBerry DAC+ / DAC+ Pro / DAC+ Zero"
        echo " 3) HiFiBerry DAC+ HD (PCM1792A)   [768 kHz]"
        echo " 4) JustBoom DAC HAT"
        echo " 5) IQaudio DAC Pro / DAC+"
        echo " 6) Pimoroni DAC Shim (Generic I2S)"
        echo " 7) Allo Boss DAC"
        echo " 8) Allo Katana DAC                 [768 kHz]"
        echo " 9) Google Voice HAT                [max 48 kHz / 16 bit]"
        echo "10) AudioInjector (WM8731)           [max 96 kHz / 24 bit]"
        echo "11) Inny / Własny (wpisz ręcznie)"
        echo ""
        read -r -p "Twój wybór [1-11] (domyślnie 1): " hat_choice
    fi

    # POPRAWKA: spójny overlay hifiberry-dacplus dla wszystkich modeli DAC+ (opcje 1 i 2)
    case ${hat_choice:-1} in
        1|2) HAT_MODEL="hifiberry-dacplus" ;;
        3)   HAT_MODEL="hifiberry-dacplushd" ;;
        4)   HAT_MODEL="justboom-dac" ;;
        5)   HAT_MODEL="iqaudio-dacplus" ;;
        6)   HAT_MODEL="i2s-dac" ;;
        7)   HAT_MODEL="allo-boss-dac-pcm512x-audio" ;;
        8)   HAT_MODEL="allo-katana-dac-audio" ;;
        9)   HAT_MODEL="googlevoicehat-soundcard" ;;
        10)  HAT_MODEL="audioinjector-wm8731-audio" ;;
        11)
            if [[ "$MENU_LANG" == "en" ]]; then
                read -r -p "Enter dtoverlay name (e.g., hifiberry-dacplus): " CUSTOM_HAT
            else
                read -r -p "Wpisz nazwę dtoverlay (np. hifiberry-dacplus): " CUSTOM_HAT
            fi
            HAT_MODEL="${CUSTOM_HAT:-hifiberry-dacplus}"
            ;;
        *)
            if [[ "$MENU_LANG" == "en" ]]; then
                echo "Invalid choice, using default (hifiberry-dacplus)."
            else
                echo "Nieprawidłowy wybór, użyto domyślnego (hifiberry-dacplus)."
            fi
            HAT_MODEL="hifiberry-dacplus"
            ;;
    esac

    if [[ "$MENU_LANG" == "en" ]]; then
        echo -e "Selected overlay: ${COLORS[GREEN]}$HAT_MODEL${COLORS[NC]}"
    else
        echo -e "Wybrano overlay: ${COLORS[GREEN]}$HAT_MODEL${COLORS[NC]}"
    fi

    HAT_MODEL_SELECTED="$HAT_MODEL"
    export HAT_MODEL

    echo "$HAT_MODEL"
}

# Konfiguracja jakości audio
configure_quality() {
    local hat_model="${1:-$HAT_MODEL}"

    local dac_caps max_rate max_bit supported_rates
    dac_caps=$(get_dac_capabilities "$hat_model")
    IFS=':' read -r max_rate max_bit supported_rates <<< "$dac_caps"

    IFS=',' read -ra RATES_ARRAY <<< "$supported_rates"

    print_header

    if [[ "$MENU_LANG" == "en" ]]; then
        echo -e "${COLORS[CYAN]}⚙️  Audio Quality Configuration${COLORS[NC]}"
        echo -e "DAC Model   : ${COLORS[GREEN]}$hat_model${COLORS[NC]}"
        echo -e "Max Freq    : ${COLORS[GREEN]}${max_rate} Hz${COLORS[NC]}"
        echo -e "Max Bit     : ${COLORS[GREEN]}${max_bit} bit${COLORS[NC]}"
        echo ""

        # --- Sample Rate ---
        echo "Select default Sample Rate:"
        local idx=1
        declare -A rate_map
        for rate in "${RATES_ARRAY[@]}"; do
            local khz=$((rate / 1000))
            local label
            case $rate in
                44100)          label="Standard CD" ;;
                48000)          label="Video/Pro Standard" ;;
                88200|96000)    label="Hi-Res" ;;
                176400|192000)  label="High End" ;;
                352800|384000)  label="Ultra Hi-Res" ;;
                705600|768000)  label="Maximum (Experimental)" ;;
                *)              label="Custom" ;;
            esac
            echo "$idx) $rate Hz ($khz kHz) - $label"
            rate_map[$idx]=$rate
            idx=$((idx + 1))
        done
        echo ""

        local default_choice=${#RATES_ARRAY[@]}
        read -r -p "Your choice [1-$default_choice] (default $default_choice): " sr_choice

        # POPRAWKA: walidacja inputu z komunikatem przy nieprawidłowym wyborze
        if [[ "${sr_choice:-}" =~ ^[0-9]+$ ]] && [[ -v rate_map[$sr_choice] ]]; then
            SAMPLE_RATE="${rate_map[$sr_choice]}"
        else
            [[ -n "${sr_choice:-}" ]] && echo "Invalid choice, using maximum: ${RATES_ARRAY[-1]} Hz"
            SAMPLE_RATE="${RATES_ARRAY[-1]}"
        fi
        echo "Set Sample Rate: ${SAMPLE_RATE} Hz"
        echo ""

        # --- Bit Depth ---
        echo "Select Bit Depth:"
        echo "1) 16 bit (Standard CD)"
        echo "2) 24 bit (Hi-Res Audio)"
        local bit_max=2
        if [[ $max_bit -ge 32 ]]; then
            echo "3) 32 bit (Maximum Quality - Recommended)"
            bit_max=3
        fi
        echo ""
        read -r -p "Your choice [1-$bit_max] (default $bit_max): " bit_choice

        case ${bit_choice:-$bit_max} in
            1) BIT_DEPTH="16" ;;
            2) BIT_DEPTH="24" ;;
            3) BIT_DEPTH="32" ;;
            *)
                echo "Invalid choice, using maximum: ${max_bit} bit"
                BIT_DEPTH="$max_bit"
                ;;
        esac
        echo "Set Bit Depth: ${BIT_DEPTH} bit"
        echo ""

        # --- Resampling ---
        echo "Select PulseAudio Resampling Method:"
        echo "1) speex-float-1   (Fast, low quality)"
        echo "2) speex-float-5   (Good quality, balanced)"
        echo "3) speex-float-10  (Very good quality)"
        echo "4) soxr            (High quality)"
        echo "5) soxr-lq         (Low quality, less CPU)"
        echo "6) soxr-vhq        (Very high quality - Recommended)"
        echo ""
        read -r -p "Your choice [1-6] (default 6): " rs_choice

        case ${rs_choice:-6} in
            1) RESAMPLE_METHOD="speex-float-1" ;;
            2) RESAMPLE_METHOD="speex-float-5" ;;
            3) RESAMPLE_METHOD="speex-float-10" ;;
            4) RESAMPLE_METHOD="soxr" ;;
            5) RESAMPLE_METHOD="soxr-lq" ;;
            6) RESAMPLE_METHOD="soxr-vhq" ;;
            *) echo "Invalid choice, using soxr-vhq"; RESAMPLE_METHOD="soxr-vhq" ;;
        esac
        echo "Set Resample Method: ${RESAMPLE_METHOD}"
        echo ""

        # --- Mixer ---
        echo "Select Mixer Type:"
        echo "1) hardware  (Direct hardware control - Recommended)"
        echo "2) software  (PulseAudio software mixer)"
        echo "3) none      (No mixer - direct access, advanced)"
        echo ""
        read -r -p "Your choice [1-3] (default 1): " mixer_choice

        case ${mixer_choice:-1} in
            1) MIXER_TYPE="hardware" ;;
            2) MIXER_TYPE="software" ;;
            3) MIXER_TYPE="none" ;;
            *) echo "Invalid choice, using hardware"; MIXER_TYPE="hardware" ;;
        esac
        echo "Set Mixer Type: ${MIXER_TYPE}"
        echo ""

    else
        # Polski język
        echo -e "${COLORS[CYAN]}⚙️  Konfiguracja Jakości Dźwięku${COLORS[NC]}"
        echo -e "Model DAC         : ${COLORS[GREEN]}$hat_model${COLORS[NC]}"
        echo -e "Maks. częstotliwość: ${COLORS[GREEN]}${max_rate} Hz${COLORS[NC]}"
        echo -e "Maks. głębia bitowa: ${COLORS[GREEN]}${max_bit} bit${COLORS[NC]}"
        echo ""

        # --- Sample Rate ---
        echo "Wybierz domyślną częstotliwość próbkowania (Sample Rate):"
        local idx=1
        declare -A rate_map
        for rate in "${RATES_ARRAY[@]}"; do
            local khz=$((rate / 1000))
            local label
            case $rate in
                44100)          label="Standard CD" ;;
                48000)          label="Standard wideo/pro" ;;
                88200|96000)    label="Hi-Res" ;;
                176400|192000)  label="High End" ;;
                352800|384000)  label="Ultra Hi-Res" ;;
                705600|768000)  label="Maksymalna (Eksperymentalne)" ;;
                *)              label="Niestandardowa" ;;
            esac
            echo "$idx) $rate Hz ($khz kHz) - $label"
            rate_map[$idx]=$rate
            idx=$((idx + 1))
        done
        echo ""

        local default_choice=${#RATES_ARRAY[@]}
        read -r -p "Twój wybór [1-$default_choice] (domyślnie $default_choice): " sr_choice

        # POPRAWKA: walidacja inputu
        if [[ "${sr_choice:-}" =~ ^[0-9]+$ ]] && [[ -v rate_map[$sr_choice] ]]; then
            SAMPLE_RATE="${rate_map[$sr_choice]}"
        else
            [[ -n "${sr_choice:-}" ]] && echo "Nieprawidłowy wybór, użyto maksymalnej: ${RATES_ARRAY[-1]} Hz"
            SAMPLE_RATE="${RATES_ARRAY[-1]}"
        fi
        echo "Ustawiono Sample Rate: ${SAMPLE_RATE} Hz"
        echo ""

        # --- Bit Depth ---
        echo "Wybierz głębię bitową (Bit Depth):"
        echo "1) 16 bit (Standard CD)"
        echo "2) 24 bit (Hi-Res Audio)"
        local bit_max=2
        if [[ $max_bit -ge 32 ]]; then
            echo "3) 32 bit (Maksymalna jakość - Zalecane)"
            bit_max=3
        fi
        echo ""
        read -r -p "Twój wybór [1-$bit_max] (domyślnie $bit_max): " bit_choice

        case ${bit_choice:-$bit_max} in
            1) BIT_DEPTH="16" ;;
            2) BIT_DEPTH="24" ;;
            3) BIT_DEPTH="32" ;;
            *)
                echo "Nieprawidłowy wybór, użyto maksymalnej: ${max_bit} bit"
                BIT_DEPTH="$max_bit"
                ;;
        esac
        echo "Ustawiono Bit Depth: ${BIT_DEPTH} bit"
        echo ""

        # --- Resampling ---
        echo "Wybierz metodę resamplingu dla PulseAudio:"
        echo "1) speex-float-1   (Szybka, niska jakość)"
        echo "2) speex-float-5   (Dobra jakość, zbalansowana)"
        echo "3) speex-float-10  (Bardzo dobra jakość)"
        echo "4) soxr            (Wysoka jakość)"
        echo "5) soxr-lq         (Niska jakość, mniejsze CPU)"
        echo "6) soxr-vhq        (Bardzo wysoka jakość - Zalecane)"
        echo ""
        read -r -p "Twój wybór [1-6] (domyślnie 6): " rs_choice

        case ${rs_choice:-6} in
            1) RESAMPLE_METHOD="speex-float-1" ;;
            2) RESAMPLE_METHOD="speex-float-5" ;;
            3) RESAMPLE_METHOD="speex-float-10" ;;
            4) RESAMPLE_METHOD="soxr" ;;
            5) RESAMPLE_METHOD="soxr-lq" ;;
            6) RESAMPLE_METHOD="soxr-vhq" ;;
            *) echo "Nieprawidłowy wybór, użyto soxr-vhq"; RESAMPLE_METHOD="soxr-vhq" ;;
        esac
        echo "Ustawiono Resample Method: ${RESAMPLE_METHOD}"
        echo ""

        # --- Mixer ---
        echo "Wybierz typ miksera (Mixer Type):"
        echo "1) hardware  (Bezpośrednia kontrola sprzętu - Zalecane)"
        echo "2) software  (Mikser programowy PulseAudio)"
        echo "3) none      (Bez miksera - bezpośredni dostęp, zaawansowane)"
        echo ""
        read -r -p "Twój wybór [1-3] (domyślnie 1): " mixer_choice

        case ${mixer_choice:-1} in
            1) MIXER_TYPE="hardware" ;;
            2) MIXER_TYPE="software" ;;
            3) MIXER_TYPE="none" ;;
            *) echo "Nieprawidłowy wybór, użyto hardware"; MIXER_TYPE="hardware" ;;
        esac
        echo "Ustawiono Mixer Type: ${MIXER_TYPE}"
        echo ""
    fi

    # MPD converter — soxr jest zawsze najlepszy
    MPD_CONVERTER="soxr"

    if [[ "$MENU_LANG" == "en" ]]; then
        echo "MPD converter: ${MPD_CONVERTER}"
        echo ""
        read -r -p "Press Enter to return to menu..."
    else
        echo "Konwerter MPD: ${MPD_CONVERTER}"
        echo ""
        read -r -p "Naciśnij Enter, aby powrócić do menu..."
    fi

    export SAMPLE_RATE BIT_DEPTH RESAMPLE_METHOD MPD_CONVERTER MIXER_TYPE
}

# Menu główne
main_menu() {
    while true; do
        print_header

        if [[ "$MENU_LANG" == "en" ]]; then
            echo -e "${COLORS[CYAN]}MAIN MENU:${COLORS[NC]}"
            if [[ -n "$HAT_MODEL_SELECTED" ]]; then
                echo -e "Selected DAC model: ${COLORS[GREEN]}$HAT_MODEL_SELECTED${COLORS[NC]}"
            else
                echo -e "Selected DAC model: ${COLORS[YELLOW]}None (select option 4)${COLORS[NC]}"
            fi
            echo ""
            echo " 0) 🌐 Change language (PL/EN)"
            echo " 1) 📦 Install packages"
            echo " 2) 💾 Backup current files"
            echo " 3) 👁️  Preview system files"
            echo " 4) ⚙️  Select HAT + Configure quality"
            echo " 5) 🚀 Generate configuration"
            echo " 6) 🔧 Apply configuration"
            echo " 7) 🔍 Compare backup with new files"
            echo " 8) 🔊 Audio Test"
            echo " 9) 🔄 Restore from backup"
            echo "10) 🧹 Cleanup old backups"
            echo "11) 🛑 Exit"
            echo ""
            read -r -p "Select option [0-11]: " choice
        else
            echo -e "${COLORS[CYAN]}MENU GŁÓWNE:${COLORS[NC]}"
            if [[ -n "$HAT_MODEL_SELECTED" ]]; then
                echo -e "Wybrany model DAC: ${COLORS[GREEN]}$HAT_MODEL_SELECTED${COLORS[NC]}"
            else
                echo -e "Wybrany model DAC: ${COLORS[YELLOW]}Brak (wybierz opcję 4)${COLORS[NC]}"
            fi
            echo ""
            echo " 0) 🌐 Zmień język (PL/EN)"
            echo " 1) 📦 Zainstaluj pakiety"
            echo " 2) 💾 Backup obecnych plików"
            echo " 3) 👁️  Podgląd plików systemowych"
            echo " 4) ⚙️  Wybierz HAT + Konfiguruj jakość"
            echo " 5) 🚀 Generuj konfigurację"
            echo " 6) 🔧 Zastosuj konfigurację"
            echo " 7) 🔍 Porównaj backup z nowymi plikami"
            echo " 8) 🔊 Test Dźwięku"
            echo " 9) 🔄 Przywróć z backupu"
            echo "10) 🧹 Wyczyść stare backupy"
            echo "11) 🛑 Wyjdź"
            echo ""
            read -r -p "Wybierz opcję [0-11]: " choice
        fi

        case ${choice:-} in
            0)
                if [[ "$MENU_LANG" == "en" ]]; then
                    MENU_LANG="pl"
                    echo "Zmieniono język na polski."
                else
                    MENU_LANG="en"
                    echo "Language changed to English."
                fi
                read -r -p "Press Enter to continue..."
                ;;
            1) install_packages ;;
            2) backup_files ;;
            3) preview_system_files ;;
            4)
                select_model
                HAT_MODEL_SELECTED="$HAT_MODEL"
                configure_quality "$HAT_MODEL_SELECTED"
                ;;
            5)
                if [[ -z "$HAT_MODEL_SELECTED" ]]; then
                    if [[ "$MENU_LANG" == "en" ]]; then
                        echo -e "${COLORS[RED]}⚠️  First select DAC model (option 4)!${COLORS[NC]}"
                    else
                        echo -e "${COLORS[RED]}⚠️  Najpierw wybierz model DAC (opcja 4)!${COLORS[NC]}"
                    fi
                    read -r -p "Enter..."
                else
                    gen_configs "$HAT_MODEL_SELECTED"
                    read -r -p "Press Enter to continue..."
                fi
                ;;
            6) apply_configs ;;
            7) compare_backups ;;
            8) test_audio ;;
            9) restore_backup_menu ;;
            10) cleanup_backups_menu ;;   # POPRAWKA: jawna opcja, widoczna w menu
            11)
                if [[ "$MENU_LANG" == "en" ]]; then
                    echo -e "${COLORS[GREEN]}✅ Exiting. Goodbye!${COLORS[NC]}"
                else
                    echo -e "${COLORS[GREEN]}✅ Wyjście. Do widzenia!${COLORS[NC]}"
                fi
                exit 0
                ;;
            *)
                if [[ "$MENU_LANG" == "en" ]]; then
                    echo "Invalid choice."
                else
                    echo "Nieprawidłowy wybór."
                fi
                read -r -p "Press Enter to continue..."
                ;;
        esac
    done
}

# Eksport funkcji
export -f print_header select_model configure_quality main_menu
export MENU_LANG HAT_MODEL_SELECTED
