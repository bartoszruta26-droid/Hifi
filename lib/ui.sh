#!/usr/bin/env bash
# shellcheck shell=bash
# ==========================================
# RPi4 Audio Setup - Interactive UI Module
# Moduł interfejsu użytkownika: menu, wybór modelu, konfiguracja jakości
# ==========================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/core.sh"
source "$SCRIPT_DIR/backup.sh"
source "$SCRIPT_DIR/config_generator.sh"

# Zmienne sesji
declare -g MENU_LANG="${DEFAULT_MENU_LANG}"
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
        echo "1) R38 / Generic I2S DAC (Justboom DAC / PCM512x)"
        echo "2) HiFiBerry DAC+ / DAC+ Pro / DAC+ Zero"
        echo "3) HiFiBerry DAC+ HD (PCM1792A)"
        echo "4) JustBoom DAC HAT"
        echo "5) IQaudio DAC Pro / DAC+"
        echo "6) Pimoroni DAC Shim (Generic I2S)"
        echo "7) Allo Boss DAC"
        echo "8) Allo Katana DAC"
        echo "9) Google Voice HAT"
        echo "10) AudioInjector (WM8731)"
        echo "11) Other / Custom (enter manually)"
        echo ""
        read -r -p "Your choice [1-11] (default 1): " hat_choice
    else
        echo -e "${COLORS[YELLOW]}⏳ Wybór modelu DAC HAT...${COLORS[NC]}"
        echo ""
        echo "Wybierz model swojego DAC HAT:"
        echo "1) R38 / Generic I2S DAC (Justboom DAC / PCM512x)"
        echo "2) HiFiBerry DAC+ / DAC+ Pro / DAC+ Zero"
        echo "3) HiFiBerry DAC+ HD (PCM1792A)"
        echo "4) JustBoom DAC HAT"
        echo "5) IQaudio DAC Pro / DAC+"
        echo "6) Pimoroni DAC Shim (Generic I2S)"
        echo "7) Allo Boss DAC"
        echo "8) Allo Katana DAC"
        echo "9) Google Voice HAT"
        echo "10) AudioInjector (WM8731)"
        echo "11) Inny / Własny (wpisz ręcznie)"
        echo ""
        read -r -p "Twój wybór [1-11] (domyślnie 1): " hat_choice
    fi
    
    case $hat_choice in
        1|2) HAT_MODEL="hifiberry-dacplus" ;;
        3) HAT_MODEL="hifiberry-dacplushd" ;;
        4) HAT_MODEL="justboom-dac" ;;
        5) HAT_MODEL="iqaudio-dacplus" ;;
        6) HAT_MODEL="i2s-dac" ;;
        7) HAT_MODEL="allo-boss-dac-pcm512x-audio" ;;
        8) HAT_MODEL="allo-katana-dac-audio" ;;
        9) HAT_MODEL="googlevoicehat-soundcard" ;;
        10) HAT_MODEL="audioinjector-wm8731-audio" ;;
        11) 
            if [[ "$MENU_LANG" == "en" ]]; then
                read -r -p "Enter dtoverlay name (e.g., hifiberry-dac): " CUSTOM_HAT
            else
                read -r -p "Wpisz nazwę dtoverlay (np. hifiberry-dac): " CUSTOM_HAT
            fi
            HAT_MODEL="${CUSTOM_HAT:-hifiberry-dacplus}"
            ;;
        *) HAT_MODEL="hifiberry-dacplus" ;;
    esac
    
    if [[ "$MENU_LANG" == "en" ]]; then
        echo "Selected overlay: ${COLORS[GREEN]}$HAT_MODEL${COLORS[NC]}"
    else
        echo "Wybrano overlay: ${COLORS[GREEN]}$HAT_MODEL${COLORS[NC]}"
    fi
    
    HAT_MODEL_SELECTED="$HAT_MODEL"
    export HAT_MODEL
    
    echo "$HAT_MODEL"
}

# Konfiguracja jakości audio
configure_quality() {
    local hat_model="${1:-$HAT_MODEL}"
    
    # Pobierz możliwości DAC
    local dac_caps max_rate max_bit supported_rates
    dac_caps=$(get_dac_capabilities "$hat_model")
    IFS=':' read -r max_rate max_bit supported_rates <<< "$dac_caps"
    
    # Parsowanie dostępnych rate do tablicy
    IFS=',' read -ra RATES_ARRAY <<< "$supported_rates"
    
    print_header
    
    if [[ "$MENU_LANG" == "en" ]]; then
        echo -e "${COLORS[CYAN]}⚙️  Audio Quality Configuration${COLORS[NC]}"
        echo -e "DAC Model: ${COLORS[GREEN]}$hat_model${COLORS[NC]}"
        echo -e "Max Frequency: ${COLORS[GREEN]}${max_rate} Hz${COLORS[NC]}"
        echo -e "Max Bit Depth: ${COLORS[GREEN]}${max_bit} bit${COLORS[NC]}"
        echo ""
        
        # Sample Rate selection
        echo "Select default Sample Rate:"
        local idx=1
        declare -A rate_map
        for rate in "${RATES_ARRAY[@]}"; do
            local khz=$((rate / 1000))
            local label
            case $rate in
                44100) label="Standard CD" ;;
                48000) label="Video/Pro Standard" ;;
                88200|96000) label="Hi-Res" ;;
                176400|192000) label="High End" ;;
                352800|384000) label="Ultra Hi-Res" ;;
                705600|768000) label="Maximum (Experimental)" ;;
                *) label="Custom" ;;
            esac
            echo "$idx) $rate Hz ($khz kHz) - $label"
            rate_map[$idx]=$rate
            ((idx++))
        done
        echo ""
        
        local default_choice=${#RATES_ARRAY[@]}
        read -r -p "Your choice [1-$default_choice] (default $default_choice): " sr_choice
        
        if [[ -v rate_map[$sr_choice] ]]; then
            SAMPLE_RATE="${rate_map[$sr_choice]}"
        else
            SAMPLE_RATE="${RATES_ARRAY[-1]}"
        fi
        
        echo "Set Sample Rate: ${SAMPLE_RATE} Hz"
        echo ""
        
        # Bit Depth selection
        echo "Select Bit Depth:"
        echo "1) 16 bit (Standard CD)"
        echo "2) 24 bit (Hi-Res Audio)"
        if [[ $max_bit -ge 32 ]]; then
            echo "3) 32 bit (Maximum Quality - Recommended)"
            local bit_max=3
        else
            local bit_max=2
        fi
        echo ""
        read -r -p "Your choice [1-$bit_max] (default $bit_max): " bit_choice
        
        case $bit_choice in
            1) BIT_DEPTH="16" ;;
            2) BIT_DEPTH="24" ;;
            3) BIT_DEPTH="32" ;;
            *) BIT_DEPTH="$max_bit" ;;
        esac
        
        echo "Set Bit Depth: ${BIT_DEPTH} bit"
        echo ""
        
        # Resampling method
        echo "Select PulseAudio Resampling Method:"
        echo "1) speex-float-1 (Fast, low quality)"
        echo "2) speex-float-5 (Good quality, balanced)"
        echo "3) speex-float-10 (Very good quality)"
        echo "4) soxr (High quality)"
        echo "5) soxr-lq (Low quality, less CPU)"
        echo "6) soxr-vhq (Very high quality - Recommended)"
        echo ""
        read -r -p "Your choice [1-6] (default 6): " rs_choice
        case $rs_choice in
            1) RESAMPLE_METHOD="speex-float-1" ;;
            2) RESAMPLE_METHOD="speex-float-5" ;;
            3) RESAMPLE_METHOD="speex-float-10" ;;
            4) RESAMPLE_METHOD="soxr" ;;
            5) RESAMPLE_METHOD="soxr-lq" ;;
            6) RESAMPLE_METHOD="soxr-vhq" ;;
            *) RESAMPLE_METHOD="soxr-vhq" ;;
        esac
        echo "Set Resample Method: ${RESAMPLE_METHOD}"
        echo ""
        
        # Mixer type
        echo "Select Mixer Type:"
        echo "1) hardware (Direct hardware control)"
        echo "2) software (PulseAudio software mixer)"
        echo "3) none (No mixer - direct access)"
        echo ""
        read -r -p "Your choice [1-3] (default 1): " mixer_choice
        case $mixer_choice in
            1) MIXER_TYPE="hardware" ;;
            2) MIXER_TYPE="software" ;;
            3) MIXER_TYPE="none" ;;
            *) MIXER_TYPE="hardware" ;;
        esac
        echo "Set Mixer Type: ${MIXER_TYPE}"
        echo ""
        
    else
        # Polski język
        echo -e "${COLORS[CYAN]}⚙️  Konfiguracja Jakości Dźwięku${COLORS[NC]}"
        echo -e "Model DAC: ${COLORS[GREEN]}$hat_model${COLORS[NC]}"
        echo -e "Maksymalna częstotliwość: ${COLORS[GREEN]}${max_rate} Hz${COLORS[NC]}"
        echo -e "Maksymalna głębia bitowa: ${COLORS[GREEN]}${max_bit} bit${COLORS[NC]}"
        echo ""
        
        # Sample Rate selection
        echo "Wybierz domyślną częstotliwość próbkowania (Sample Rate):"
        local idx=1
        declare -A rate_map
        for rate in "${RATES_ARRAY[@]}"; do
            local khz=$((rate / 1000))
            local label
            case $rate in
                44100) label="Standard CD" ;;
                48000) label="Standard wideo/pro" ;;
                88200|96000) label="Hi-Res" ;;
                176400|192000) label="High End" ;;
                352800|384000) label="Ultra Hi-Res" ;;
                705600|768000) label="Maksymalna (Eksperymentalne)" ;;
                *) label="Niestandardowa" ;;
            esac
            echo "$idx) $rate Hz ($khz kHz) - $label"
            rate_map[$idx]=$rate
            ((idx++))
        done
        echo ""
        
        local default_choice=${#RATES_ARRAY[@]}
        read -r -p "Twój wybór [1-$default_choice] (domyślnie $default_choice): " sr_choice
        
        if [[ -v rate_map[$sr_choice] ]]; then
            SAMPLE_RATE="${rate_map[$sr_choice]}"
        else
            SAMPLE_RATE="${RATES_ARRAY[-1]}"
        fi
        
        echo "Ustawiono Sample Rate: ${SAMPLE_RATE} Hz"
        echo ""
        
        # Bit Depth selection
        echo "Wybierz głębię bitową (Bit Depth):"
        echo "1) 16 bit (Standard CD)"
        echo "2) 24 bit (Hi-Res Audio)"
        if [[ $max_bit -ge 32 ]]; then
            echo "3) 32 bit (Maksymalna jakość - Zalecane)"
            local bit_max=3
        else
            local bit_max=2
        fi
        echo ""
        read -r -p "Twój wybór [1-$bit_max] (domyślnie $bit_max): " bit_choice
        
        case $bit_choice in
            1) BIT_DEPTH="16" ;;
            2) BIT_DEPTH="24" ;;
            3) BIT_DEPTH="32" ;;
            *) BIT_DEPTH="$max_bit" ;;
        esac
        
        echo "Ustawiono Bit Depth: ${BIT_DEPTH} bit"
        echo ""
        
        # Resampling method
        echo "Wybierz metodę resamplingu dla PulseAudio:"
        echo "1) speex-float-1 (Szybka, niska jakość)"
        echo "2) speex-float-5 (Dobra jakość, zbalansowana)"
        echo "3) speex-float-10 (Bardzo dobra jakość)"
        echo "4) soxr (Wysoka jakość)"
        echo "5) soxr-lq (Niska jakość, mniejsze CPU)"
        echo "6) soxr-vhq (Bardzo wysoka jakość - Zalecane)"
        echo ""
        read -r -p "Twój wybór [1-6] (domyślnie 6): " rs_choice
        case $rs_choice in
            1) RESAMPLE_METHOD="speex-float-1" ;;
            2) RESAMPLE_METHOD="speex-float-5" ;;
            3) RESAMPLE_METHOD="speex-float-10" ;;
            4) RESAMPLE_METHOD="soxr" ;;
            5) RESAMPLE_METHOD="soxr-lq" ;;
            6) RESAMPLE_METHOD="soxr-vhq" ;;
            *) RESAMPLE_METHOD="soxr-vhq" ;;
        esac
        echo "Ustawiono Resample Method: ${RESAMPLE_METHOD}"
        echo ""
        
        # Mixer type
        echo "Wybierz typ miksera (Mixer Type):"
        echo "1) hardware (Bezpośrednia kontrola sprzętu)"
        echo "2) software (Mikser programowy PulseAudio)"
        echo "3) none (Bez miksera - bezpośredni dostęp)"
        echo ""
        read -r -p "Twój wybór [1-3] (domyślnie 1): " mixer_choice
        case $mixer_choice in
            1) MIXER_TYPE="hardware" ;;
            2) MIXER_TYPE="software" ;;
            3) MIXER_TYPE="none" ;;
            *) MIXER_TYPE="hardware" ;;
        esac
        echo "Ustawiono Mixer Type: ${MIXER_TYPE}"
        echo ""
    fi
    
    # Automatyczne dopasowanie MPD converter
    if [[ "$RESAMPLE_METHOD" == soxr* ]]; then
        MPD_CONVERTER="soxr"
    else
        MPD_CONVERTER="soxr"  # soxr jest najlepszy niezależnie od wyboru
    fi
    
    if [[ "$MENU_LANG" == "en" ]]; then
        echo "Adjusted MPD converter: ${MPD_CONVERTER}"
        echo ""
        read -r -p "Press Enter to return to menu..."
    else
        echo "Dostosowano konwerter MPD: ${MPD_CONVERTER}"
        echo ""
        read -r -p "Naciśnij Enter, aby powrócić do menu..."
    fi
    
    # Eksportuj zmienne
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
            echo "0) 🌐 Change language (PL/EN)"
            echo "1) 📦 Install packages"
            echo "2) 💾 Backup current files"
            echo "3) 👁️ Preview system files"
            echo "4) ⚙️ Select HAT + Configure quality"
            echo "5) 🚀 Generate configuration"
            echo "6) 🔧 Apply configuration"
            echo "7) 🔍 Compare backup with new files"
            echo "8) 🔊 Audio Test"
            echo "9) 🔄 Restore from backup"
            echo "10) 🛑 Exit"
            echo ""
            read -r -p "Select option [0-10]: " choice
        else
            echo -e "${COLORS[CYAN]}MENU GŁÓWNE:${COLORS[NC]}"
            if [[ -n "$HAT_MODEL_SELECTED" ]]; then
                echo -e "Wybrany model DAC: ${COLORS[GREEN]}$HAT_MODEL_SELECTED${COLORS[NC]}"
            else
                echo -e "Wybrany model DAC: ${COLORS[YELLOW]}Brak (wybierz opcję 4)${COLORS[NC]}"
            fi
            echo ""
            echo "0) 🌐 Zmień język (PL/EN)"
            echo "1) 📦 Zainstaluj pakiety"
            echo "2) 💾 Backup obecnych plików"
            echo "3) 👁️ Podgląd plików systemowych"
            echo "4) ⚙️ Wybierz HAT + Konfiguruj jakość"
            echo "5) 🚀 Generuj konfigurację"
            echo "6) 🔧 Zastosuj konfigurację"
            echo "7) 🔍 Porównaj backup z nowymi plikami"
            echo "8) 🔊 Test Dźwięku"
            echo "9) 🔄 Przywróć z backupu"
            echo "10) 🛑 Wyjdź"
            echo ""
            read -r -p "Wybierz opcję [0-10]: " choice
        fi
        
        case $choice in
            0)
                if [[ "$MENU_LANG" == "en" ]]; then
                    MENU_LANG="pl"
                    echo "Zmieniono język na polski (Polish)"
                else
                    MENU_LANG="en"
                    echo "Language changed to English"
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
            10)
                if [[ "$MENU_LANG" == "en" ]]; then
                    echo -e "${COLORS[GREEN]}✅ Exiting. Goodbye!${COLORS[NC]}"
                else
                    echo -e "${COLORS[GREEN]}✅ Wyjście. Do widzenia!${COLORS[NC]}"
                fi
                exit 0
                ;;
            11) cleanup_backups_menu ;;
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
