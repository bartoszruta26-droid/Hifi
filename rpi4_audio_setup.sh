#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

# ==========================================
# Konfiguracja Audio RPi4 + HAT (Max Quality)
# Autor: AI Assistant | Wersja: 2.2 (CLI + Menu + PL/EN)
# Przeznaczenie: Debian Trixie/Bookworm, PulseAudio + MPD
# Obsługa: R38 HAT i inne popularne DAC HAT
# ==========================================

# Ścieżki systemowe
BOOT_CFG="/boot/firmware/config.txt"
# Fallback dla starszych obrazów
if [ ! -d "/boot/firmware" ]; then
  BOOT_CFG="/boot/config.txt"
fi

PULSE_DAEMON="/etc/pulse/daemon.conf"
PULSE_DEFAULT="/etc/pulse/default.pa"
MPD_CONF="/etc/mpd.conf"
STAGING_DIR="/tmp/rpi_audio_staging"
BACKUP_BASE="$HOME/.rpi_audio_backup"
LOG_FILE="$HOME/.rpi_audio_script.log"

# Domyślne wartości najwyższej jakości audio
SAMPLE_RATE="768000"
BIT_DEPTH="32"
RESAMPLE_METHOD="soxr-vhq"
MPD_CONVERTER="soxr"
MIXER_TYPE="hardware"
VOLUME_CURVE="logarithmic"
DITHER_ENABLED="yes"
BUFFER_SIZE="40960"
CLOCK_SOURCE="internal"
OUTPUT_FORMAT="float64le"
ZERO_CROSSING="yes"
SOFT_CLIP="yes"
HAT_MODEL="justboom-dac"
# Dodatkowe parametry wysokiej jakości
CLOCK_MODE="master"
OUTPUT_DELAY="0"
AUTO_MUTE="no"
VOLUME_GAIN="0"
DEEMPHASIS="auto"
CHANNEL_MODE="stereo"

# Język menu (domyślnie polski)
MENU_LANG="pl"

# Kolory dla CLI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Sprawdzenie uprawnień
if [ "$(id -u)" -ne 0 ]; then
  if [ "$MENU_LANG" = "en" ]; then
    echo -e "${RED}⚠️  ERROR: Script requires root privileges.${NC}"
    echo -e "Run with: ${CYAN}sudo bash $0${NC}"
  else
    echo -e "${RED}⚠️  BŁĄD: Skrypt wymaga uprawnień roota.${NC}"
    echo -e "Uruchom komendą: ${CYAN}sudo bash $0${NC}"
  fi
  exit 1
fi

# Logowanie
log() { 
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
  echo -e "${BLUE}[LOG]${NC} $1"
}

# Tworzenie katalogu tymczasowego
mkdir -p "$STAGING_DIR" "$BACKUP_BASE"

# ==========================================
# FUNKCJE POMOCNICZE
# ==========================================

print_header() {
  clear
  if [ "$MENU_LANG" = "en" ]; then
    echo -e "${CYAN}=========================================="
    echo -e "🎧 RPi4 Audio HQ Setup (Trixie/Bookworm)"
    echo -e "Version: 2.1 | R38 and other HAT support"
    echo -e "==========================================${NC}"
  else
    echo -e "${CYAN}=========================================="
    echo -e "🎧 RPi4 Audio HQ Setup (Trixie/Bookworm)"
    echo -e "Wersja: 2.1 | Obsługa R38 i innych HAT"
    echo -e "==========================================${NC}"
  fi
  echo ""
}

backup_files() {
  local TS
  TS=$(date +%Y%m%d_%H%M%S)
  local DIR="$BACKUP_BASE/$TS"
  mkdir -p "$DIR"
  
  echo -e "${YELLOW}📦 Tworzenie kopii zapasowej...${NC}"
  for f in "$BOOT_CFG" "$PULSE_DAEMON" "$PULSE_DEFAULT" "$MPD_CONF"; do
    if [ -f "$f" ]; then
      cp -a "$f" "$DIR/"
      log "Backup: $f -> $DIR/"
      echo "  ✅ $f"
    else
      echo "  ⚠️  $f (nie istnieje, pominięto)"
    fi
  done
  echo -e "${GREEN}✅ Backup utworzony w: $DIR${NC}"
}

preview_file() {
  local file="$1"
  local title="$2"
  if [ -f "$file" ]; then
    echo -e "${CYAN}--- Podgląd: $title ($file) ---${NC}"
    head -n 50 "$file"
    echo -e "${CYAN}---------------------------------------${NC}"
    read -r -p "Naciśnij Enter, aby kontynuować..."
  else
    echo -e "${RED}⚠️  Plik nie istnieje: $file${NC}"
  fi
}

compare_files() {
  local orig="$1"
  local new="$2"
  if [ -f "$orig" ] && [ -f "$new" ]; then
    diff -u "$orig" "$new" > "$STAGING_DIR/diff_output.txt" 2>&1 || true
    if [ -s "$STAGING_DIR/diff_output.txt" ]; then
      echo -e "${YELLOW}Różnice:${NC}"
      cat "$STAGING_DIR/diff_output.txt"
    else
      echo -e "${GREEN}🟢 Brak różnic. Pliki są identyczne.${NC}"
    fi
  else
    echo -e "${RED}⚠️  Brak pliku backupu lub nowego pliku.${NC}"
  fi
}

# ==========================================
# BAZA DANYCH MOŻLIWOŚCI DAC HAT
# ==========================================

# Definicja możliwości każdego modelu DAC
# Format: MAX_SAMPLE_RATE:MAX_BIT_DEPTH:SUPPORTED_RATES
# SUPPORTED_RATES to lista dostępnych częstotliwości oddzielona przecinkami

declare -A DAC_CAPABILITIES=(
  ["justboom-dac"]="384000:32:44100,48000,88200,96000,176400,192000,352800,384000"
  ["hifiberry-dacplus"]="384000:32:44100,48000,88200,96000,176400,192000,352800,384000"
  ["hifiberry-dacplushd"]="768000:32:44100,48000,88200,96000,176400,192000,352800,384000,705600,768000"
  ["iqaudio-dacplus"]="384000:32:44100,48000,88200,96000,176400,192000,352800,384000"
  ["i2s-dac"]="384000:32:44100,48000,88200,96000,176400,192000,352800,384000"
  ["allo-boss-dac-pcm512x-audio"]="384000:32:44100,48000,88200,96000,176400,192000,352800,384000"
  ["allo-katana-dac-audio"]="768000:32:44100,48000,88200,96000,176400,192000,352800,384000,705600,768000"
  ["googlevoicehat-soundcard"]="48000:16:8000,16000,22050,24000,32000,44100,48000"
  ["audioinjector-wm8731-audio"]="96000:24:8000,16000,22050,24000,32000,44100,48000,88200,96000"
)

# Domyślne wartości dla nieznanego DAC
DEFAULT_MAX_RATE="384000"
DEFAULT_MAX_BIT="32"
DEFAULT_RATES="44100,48000,88200,96000,176400,192000,352800,384000"

get_dac_capabilities() {
  local hat_model="$1"
  
  if [[ -v DAC_CAPABILITIES["$hat_model"] ]]; then
    echo "${DAC_CAPABILITIES[$hat_model]}"
  else
    echo "$DEFAULT_MAX_RATE:$DEFAULT_MAX_BIT:$DEFAULT_RATES"
  fi
}

# ==========================================
# KONFIGURACJA PARAMETRÓW JAKOŚCI
# ==========================================

configure_quality() {
  local hat_model="${1:-justboom-dac}"
  
  # Pobierz możliwości DAC
  local dac_caps
  dac_caps=$(get_dac_capabilities "$hat_model")
  
  local max_rate max_bit supported_rates
  IFS=':' read -r max_rate max_bit supported_rates <<< "$dac_caps"
  
  print_header
  
  # Komunikaty w zależności od języka
  if [ "$MENU_LANG" = "en" ]; then
    echo -e "${CYAN}⚙️  Audio Quality Configuration${NC}"
    echo -e "DAC Model: ${GREEN}$hat_model${NC}"
    echo -e "Max Frequency: ${GREEN}${max_rate} Hz${NC}"
    echo -e "Max Bit Depth: ${GREEN}${max_bit} bit${NC}"
    echo ""
    
    # Parsing available rates to array
    IFS=',' read -ra RATES_ARRAY <<< "$supported_rates"
    
    # Building menu with available options
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
      SAMPLE_RATE="${RATES_ARRAY[$(( ${#RATES_ARRAY[@]} - 1 ))]}"
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

    # Output format selection
    echo "Select Output Format:"
    echo "1) s16le (16-bit Integer)"
    echo "2) s24le (24-bit Integer)"
    if [[ $max_bit -ge 32 ]]; then
      echo "3) s32le (32-bit Integer)"
      echo "4) float32le (32-bit Float - Recommended)"
      echo "5) float64le (64-bit Float - Highest Precision)"
      local fmt_max=5
    else
      echo "3) float32le (32-bit Float - Recommended)"
      echo "4) float64le (64-bit Float - Highest Precision)"
      local fmt_max=4
    fi
    echo ""
    read -r -p "Your choice [1-$fmt_max] (default 4): " fmt_choice
    case $fmt_choice in
      1) OUTPUT_FORMAT="s16le" ;;
      2) OUTPUT_FORMAT="s24le" ;;
      3) 
        if [[ $max_bit -ge 32 ]]; then
          OUTPUT_FORMAT="s32le"
        else
          OUTPUT_FORMAT="float32le"
        fi
        ;;
      4) 
        if [[ $max_bit -ge 32 ]] || [[ $fmt_choice -eq 4 && $fmt_max -eq 5 ]]; then
          OUTPUT_FORMAT="float32le"
        else
          OUTPUT_FORMAT="float64le"
        fi
        ;;
      5) OUTPUT_FORMAT="float64le" ;;
      *) OUTPUT_FORMAT="float32le" ;;
    esac
    echo "Set Output Format: ${OUTPUT_FORMAT}"
    echo ""

    # Mixer type selection
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

    # Volume curve selection
    echo "Select Volume Curve:"
    echo "1) logarithmic (Logarithmic - natural for human ear)"
    echo "2) linear (Linear - uniform change)"
    echo ""
    read -r -p "Your choice [1-2] (default 1): " curve_choice
    case $curve_choice in
      1) VOLUME_CURVE="logarithmic" ;;
      2) VOLUME_CURVE="linear" ;;
      *) VOLUME_CURVE="logarithmic" ;;
    esac
    echo "Set Volume Curve: ${VOLUME_CURVE}"
    echo ""

    # Dithering
    echo "Dithering (dither noise during bit-depth conversion):"
    echo "1) Enabled (Recommended when converting 24/32 -> lower)"
    echo "2) Disabled (Clean signal, possible artifacts)"
    echo ""
    read -r -p "Your choice [1-2] (default 1): " dither_choice
    case $dither_choice in
      1) DITHER_ENABLED="yes" ;;
      2) DITHER_ENABLED="no" ;;
      *) DITHER_ENABLED="yes" ;;
    esac
    echo "Set Dither: ${DITHER_ENABLED}"
    echo ""

    # Buffer size
    echo "Audio Buffer Size (in kB):"
    echo "1) 10240 (10MB - Low latency)"
    echo "2) 20480 (20MB - Balanced)"
    echo "3) 40960 (40MB - High stability)"
    echo "4) 81920 (80MB - Maximum stability, higher latency)"
    echo ""
    read -r -p "Your choice [1-4] (default 2): " buffer_choice
    case $buffer_choice in
      1) BUFFER_SIZE="10240" ;;
      2) BUFFER_SIZE="20480" ;;
      3) BUFFER_SIZE="40960" ;;
      4) BUFFER_SIZE="81920" ;;
      *) BUFFER_SIZE="20480" ;;
    esac
    echo "Set Buffer Size: ${BUFFER_SIZE} kB"
    echo ""

    # Clock source
    echo "Clock Source:"
    echo "1) internal (Internal DAC clock)"
    echo "2) external (External clock - if available)"
    echo "3) auto (Automatic selection)"
    echo ""
    read -r -p "Your choice [1-3] (default 1): " clock_choice
    case $clock_choice in
      1) CLOCK_SOURCE="internal" ;;
      2) CLOCK_SOURCE="external" ;;
      3) CLOCK_SOURCE="auto" ;;
      *) CLOCK_SOURCE="internal" ;;
    esac
    echo "Set Clock Source: ${CLOCK_SOURCE}"
    echo ""

    # Zero Crossing
    echo "Zero Crossing (volume change only at wave zeroing):"
    echo "1) Enabled (Avoids clicks when changing volume)"
    echo "2) Disabled (Immediate volume change)"
    echo ""
    read -r -p "Your choice [1-2] (default 1): " zc_choice
    case $zc_choice in
      1) ZERO_CROSSING="yes" ;;
      2) ZERO_CROSSING="no" ;;
      *) ZERO_CROSSING="yes" ;;
    esac
    echo "Set Zero Crossing: ${ZERO_CROSSING}"
    echo ""

    # Soft Clip
    echo "Soft Clip (soft signal clipping):"
    echo "1) Enabled (Gentle clipping, less audible artifacts)"
    echo "2) Disabled (Hard clip - sharp clipping)"
    echo ""
    read -r -p "Your choice [1-2] (default 2): " sc_choice
    case $sc_choice in
      1) SOFT_CLIP="yes" ;;
      2) SOFT_CLIP="no" ;;
      *) SOFT_CLIP="no" ;;
    esac
    echo "Set Soft Clip: ${SOFT_CLIP}"
    echo ""

    # Resampling method selection
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

    # DAC mode (Master/Slave)
    echo "DAC Clock Mode:"
    echo "1) Slave (DAC receives clock from CPU - default)"
    echo "2) Master (DAC generates clock for CPU - better sync)"
    echo "3) Auto (Automatic selection based on hardware)"
    echo ""
    read -r -p "Your choice [1-3] (default 1): " clock_mode_choice
    case $clock_mode_choice in
      1) CLOCK_MODE="slave" ;;
      2) CLOCK_MODE="master" ;;
      3) CLOCK_MODE="auto" ;;
      *) CLOCK_MODE="slave" ;;
    esac
    echo "Set Clock Mode: ${CLOCK_MODE}"
    echo ""

    # Output Delay
    echo "Output Delay (in ms):"
    echo "1) 0 ms (No delay - default)"
    echo "2) 10 ms (Light delay)"
    echo "3) 20 ms (Standard)"
    echo "4) 50 ms (Large delay)"
    echo "5) 100 ms (Maximum)"
    echo ""
    read -r -p "Your choice [1-5] (default 1): " delay_choice
    case $delay_choice in
      1) OUTPUT_DELAY="0" ;;
      2) OUTPUT_DELAY="10" ;;
      3) OUTPUT_DELAY="20" ;;
      4) OUTPUT_DELAY="50" ;;
      5) OUTPUT_DELAY="100" ;;
      *) OUTPUT_DELAY="0" ;;
    esac
    echo "Set Output Delay: ${OUTPUT_DELAY} ms"
    echo ""

    # Auto Mute
    echo "Auto Mute (mute when no signal):"
    echo "1) Enabled (Power saving, no background noise)"
    echo "2) Disabled (Continuous signal hold)"
    echo ""
    read -r -p "Your choice [1-2] (default 1): " auto_mute_choice
    case $auto_mute_choice in
      1) AUTO_MUTE="yes" ;;
      2) AUTO_MUTE="no" ;;
      *) AUTO_MUTE="yes" ;;
    esac
    echo "Set Auto Mute: ${AUTO_MUTE}"
    echo ""

    # Volume Gain
    echo "Volume Gain (in dB):"
    echo "1) 0 dB (No gain - default)"
    echo "2) +3 dB (Light gain)"
    echo "3) +6 dB (Medium gain)"
    echo "4) +9 dB (Large gain)"
    echo "5) +12 dB (Maximum gain - watch for clipping)"
    echo ""
    read -r -p "Your choice [1-5] (default 1): " gain_choice
    case $gain_choice in
      1) VOLUME_GAIN="0" ;;
      2) VOLUME_GAIN="3" ;;
      3) VOLUME_GAIN="6" ;;
      4) VOLUME_GAIN="9" ;;
      5) VOLUME_GAIN="12" ;;
      *) VOLUME_GAIN="0" ;;
    esac
    echo "Set Volume Gain: ${VOLUME_GAIN} dB"
    echo ""

    # De-emphasis
    echo "De-emphasis (50/15μs correction filter):"
    echo "1) Off (Default - most recordings)"
    echo "2) On (For old CD recordings with pre-emphasis)"
    echo "3) Auto (Automatic detection of metadata flag)"
    echo ""
    read -r -p "Your choice [1-3] (default 1): " deemphasis_choice
    case $deemphasis_choice in
      1) DEEMPHASIS="off" ;;
      2) DEEMPHASIS="on" ;;
      3) DEEMPHASIS="auto" ;;
      *) DEEMPHASIS="off" ;;
    esac
    echo "Set De-emphasis: ${DEEMPHASIS}"
    echo ""

    # Channel Mode
    echo "Channel Mode:"
    echo "1) Stereo (Default - left/right)"
    echo "2) Mono (Summing to one channel)"
    echo "3) Reverse Stereo (Swap L/R channels)"
    echo ""
    read -r -p "Your choice [1-3] (default 1): " channel_choice
    case $channel_choice in
      1) CHANNEL_MODE="stereo" ;;
      2) CHANNEL_MODE="mono" ;;
      3) CHANNEL_MODE="reverse" ;;
      *) CHANNEL_MODE="stereo" ;;
    esac
    echo "Set Channel Mode: ${CHANNEL_MODE}"
    echo ""
    
  else
    # Polski język - oryginalny kod
    echo -e "${CYAN}⚙️  Konfiguracja Jakości Dźwięku${NC}"
    echo -e "Model DAC: ${GREEN}$hat_model${NC}"
    echo -e "Maksymalna częstotliwość: ${GREEN}${max_rate} Hz${NC}"
    echo -e "Maksymalna głębia bitowa: ${GREEN}${max_bit} bit${NC}"
    echo ""
    
    # Parsowanie dostępnych rate do tablicy
    IFS=',' read -ra RATES_ARRAY <<< "$supported_rates"
    
    # Budowanie menu z dostępnymi opcjami
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
      SAMPLE_RATE="${RATES_ARRAY[$(( ${#RATES_ARRAY[@]} - 1 ))]}"
    fi
    
    echo "Ustawiono Sample Rate: ${SAMPLE_RATE} Hz"
    echo ""

    # Wybór głębi bitowej (Bit Depth)
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

    # Wybór formatu wyjściowego PulseAudio - dopasowany do możliwości DAC
    echo "Wybierz format wyjściowy (Output Format):"
    echo "1) s16le (16-bit Integer)"
    echo "2) s24le (24-bit Integer)"
    if [[ $max_bit -ge 32 ]]; then
      echo "3) s32le (32-bit Integer)"
      echo "4) float32le (32-bit Float - Zalecane)"
      echo "5) float64le (64-bit Float - Najwyższa precyzja)"
      local fmt_max=5
    else
      echo "3) float32le (32-bit Float - Zalecane)"
      echo "4) float64le (64-bit Float - Najwyższa precyzja)"
      local fmt_max=4
    fi
    echo ""
    read -r -p "Twój wybór [1-$fmt_max] (domyślnie 4): " fmt_choice
    case $fmt_choice in
      1) OUTPUT_FORMAT="s16le" ;;
      2) OUTPUT_FORMAT="s24le" ;;
      3) 
        if [[ $max_bit -ge 32 ]]; then
          OUTPUT_FORMAT="s32le"
        else
          OUTPUT_FORMAT="float32le"
        fi
        ;;
      4) 
        if [[ $max_bit -ge 32 ]] || [[ $fmt_choice -eq 4 && $fmt_max -eq 5 ]]; then
          OUTPUT_FORMAT="float32le"
        else
          OUTPUT_FORMAT="float64le"
        fi
        ;;
      5) OUTPUT_FORMAT="float64le" ;;
      *) OUTPUT_FORMAT="float32le" ;;
    esac
    echo "Ustawiono Output Format: ${OUTPUT_FORMAT}"
    echo ""

    # Wybór typu miksera
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

    # Wybór krzywej głośności
    echo "Wybierz krzywą głośności (Volume Curve):"
    echo "1) logarithmic (Logarytmiczna - naturalna dla ludzkiego ucha)"
    echo "2) linear (Liniowa - równomierna zmiana)"
    echo ""
    read -r -p "Twój wybór [1-2] (domyślnie 1): " curve_choice
    case $curve_choice in
      1) VOLUME_CURVE="logarithmic" ;;
      2) VOLUME_CURVE="linear" ;;
      *) VOLUME_CURVE="logarithmic" ;;
    esac
    echo "Ustawiono Volume Curve: ${VOLUME_CURVE}"
    echo ""

    # Dithering
    echo "Dithering (szum ditherujący przy konwersji bit-depth):"
    echo "1) Włączony (Zalecane przy konwersji 24/32 -> niższe)"
    echo "2) Wyłączony (Czysty sygnał, możliwe artefakty)"
    echo ""
    read -r -p "Twój wybór [1-2] (domyślnie 1): " dither_choice
    case $dither_choice in
      1) DITHER_ENABLED="yes" ;;
      2) DITHER_ENABLED="no" ;;
      *) DITHER_ENABLED="yes" ;;
    esac
    echo "Ustawiono Dither: ${DITHER_ENABLED}"
    echo ""

    # Rozmiar bufora
    echo "Rozmiar bufora audio (Audio Buffer Size w kB):"
    echo "1) 10240 (10MB - Niskie opóźnienie)"
    echo "2) 20480 (20MB - Zbalansowane)"
    echo "3) 40960 (40MB - Wysoka stabilność)"
    echo "4) 81920 (80MB - Maksymalna stabilność, wyższe opóźnienie)"
    echo ""
    read -r -p "Twój wybór [1-4] (domyślnie 2): " buffer_choice
    case $buffer_choice in
      1) BUFFER_SIZE="10240" ;;
      2) BUFFER_SIZE="20480" ;;
      3) BUFFER_SIZE="40960" ;;
      4) BUFFER_SIZE="81920" ;;
      *) BUFFER_SIZE="20480" ;;
    esac
    echo "Ustawiono Buffer Size: ${BUFFER_SIZE} kB"
    echo ""

    # Źródło zegara
    echo "Źródło zegara (Clock Source):"
    echo "1) internal (Wewnętrzny zegar DAC)"
    echo "2) external (Zewnętrzny zegar - jeśli dostępny)"
    echo "3) auto (Automatyczny wybór)"
    echo ""
    read -r -p "Twój wybór [1-3] (domyślnie 1): " clock_choice
    case $clock_choice in
      1) CLOCK_SOURCE="internal" ;;
      2) CLOCK_SOURCE="external" ;;
      3) CLOCK_SOURCE="auto" ;;
      *) CLOCK_SOURCE="internal" ;;
    esac
    echo "Ustawiono Clock Source: ${CLOCK_SOURCE}"
    echo ""

    # Zero Crossing
    echo "Zero Crossing (zmiana głośności tylko przy zerowaniu fali):"
    echo "1) Włączony (Unika kliknięć przy zmianie głośności)"
    echo "2) Wyłączony (Natychmiastowa zmiana głośności)"
    echo ""
    read -r -p "Twój wybór [1-2] (domyślnie 1): " zc_choice
    case $zc_choice in
      1) ZERO_CROSSING="yes" ;;
      2) ZERO_CROSSING="no" ;;
      *) ZERO_CROSSING="yes" ;;
    esac
    echo "Ustawiono Zero Crossing: ${ZERO_CROSSING}"
    echo ""

    # Soft Clip
    echo "Soft Clip (miękkie przycinanie sygnału):"
    echo "1) Włączony (Łagodne przycinanie, mniej słyszalne artefakty)"
    echo "2) Wyłączony (Hard clip - ostre przycinanie)"
    echo ""
    read -r -p "Twój wybór [1-2] (domyślnie 2): " sc_choice
    case $sc_choice in
      1) SOFT_CLIP="yes" ;;
      2) SOFT_CLIP="no" ;;
      *) SOFT_CLIP="no" ;;
    esac
    echo "Ustawiono Soft Clip: ${SOFT_CLIP}"
    echo ""

    # Wybór metody resamplingu PulseAudio
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

    # Tryb pracy DAC (Master/Slave)
    echo "Tryb pracy DAC (Clock Mode):"
    echo "1) Slave (DAC otrzymuje zegar od CPU - domyślne)"
    echo "2) Master (DAC generuje zegar dla CPU - lepsza synchronizacja)"
    echo "3) Auto (Automatyczny wybór na podstawie sprzętu)"
    echo ""
    read -r -p "Twój wybór [1-3] (domyślnie 1): " clock_mode_choice
    case $clock_mode_choice in
      1) CLOCK_MODE="slave" ;;
      2) CLOCK_MODE="master" ;;
      3) CLOCK_MODE="auto" ;;
      *) CLOCK_MODE="slave" ;;
    esac
    echo "Ustawiono Clock Mode: ${CLOCK_MODE}"
    echo ""

    # Output Delay (opóźnienie wyjścia w ms)
    echo "Opóźnienie wyjścia audio (Output Delay w ms):"
    echo "1) 0 ms (Brak opóźnienia - domyślne)"
    echo "2) 10 ms (Lekkie opóźnienie)"
    echo "3) 20 ms (Standardowe)"
    echo "4) 50 ms (Duże opóźnienie)"
    echo "5) 100 ms (Maksymalne)"
    echo ""
    read -r -p "Twój wybór [1-5] (domyślnie 1): " delay_choice
    case $delay_choice in
      1) OUTPUT_DELAY="0" ;;
      2) OUTPUT_DELAY="10" ;;
      3) OUTPUT_DELAY="20" ;;
      4) OUTPUT_DELAY="50" ;;
      5) OUTPUT_DELAY="100" ;;
      *) OUTPUT_DELAY="0" ;;
    esac
    echo "Ustawiono Output Delay: ${OUTPUT_DELAY} ms"
    echo ""

    # Auto Mute (automatyczne wyciszenie przy braku sygnału)
    echo "Auto Mute (wyciszenie przy braku sygnału):"
    echo "1) Włączony (Oszczędność energii, brak szumów tła)"
    echo "2) Wyłączony (Ciągłe podtrzymanie sygnału)"
    echo ""
    read -r -p "Twój wybór [1-2] (domyślnie 1): " auto_mute_choice
    case $auto_mute_choice in
      1) AUTO_MUTE="yes" ;;
      2) AUTO_MUTE="no" ;;
      *) AUTO_MUTE="yes" ;;
    esac
    echo "Ustawiono Auto Mute: ${AUTO_MUTE}"
    echo ""

    # Volume Boost/Gain (wzmocnienie sygnału w dB)
    echo "Wzmocnienie głośności (Volume Gain w dB):"
    echo "1) 0 dB (Brak wzmocnienia - domyślne)"
    echo "2) +3 dB (Lekkie wzmocnienie)"
    echo "3) +6 dB (Średnie wzmocnienie)"
    echo "4) +9 dB (Duże wzmocnienie)"
    echo "5) +12 dB (Maksymalne wzmocnienie - uważaj na przesterowania)"
    echo ""
    read -r -p "Twój wybór [1-5] (domyślnie 1): " gain_choice
    case $gain_choice in
      1) VOLUME_GAIN="0" ;;
      2) VOLUME_GAIN="3" ;;
      3) VOLUME_GAIN="6" ;;
      4) VOLUME_GAIN="9" ;;
      5) VOLUME_GAIN="12" ;;
      *) VOLUME_GAIN="0" ;;
    esac
    echo "Ustawiono Volume Gain: ${VOLUME_GAIN} dB"
    echo ""

    # De-emphasis (filtr korekcyjny)
    echo "De-emphasis (filtr korekcyjny 50/15μs):"
    echo "1) Wyłączony (Domyślne - większość nagrań)"
    echo "2) Włączony (Dla starych nagrań CD z pre-emphasis)"
    echo "3) Auto (Automatyczna detekcja flagi w metadanych)"
    echo ""
    read -r -p "Twój wybór [1-3] (domyślnie 1): " deemphasis_choice
    case $deemphasis_choice in
      1) DEEMPHASIS="off" ;;
      2) DEEMPHASIS="on" ;;
      3) DEEMPHASIS="auto" ;;
      *) DEEMPHASIS="off" ;;
    esac
    echo "Ustawiono De-emphasis: ${DEEMPHASIS}"
    echo ""

    # Tryb kanałów (Mono/Stereo)
    echo "Tryb kanałów (Channel Mode):"
    echo "1) Stereo (Domyślne - lewy/prawy)"
    echo "2) Mono (Sumowanie do jednego kanału)"
    echo "3) Reverse Stereo (Zamiana kanałów L/R)"
    echo ""
    read -r -p "Twój wybór [1-3] (domyślnie 1): " channel_choice
    case $channel_choice in
      1) CHANNEL_MODE="stereo" ;;
      2) CHANNEL_MODE="mono" ;;
      3) CHANNEL_MODE="reverse" ;;
      *) CHANNEL_MODE="stereo" ;;
    esac
    echo "Ustawiono Channel Mode: ${CHANNEL_MODE}"
    echo ""
  fi
  
  # Automatyczne dopasowanie MPD
  if [[ "$RESAMPLE_METHOD" == soxr* ]]; then
    MPD_CONVERTER="soxr"
  else
    MPD_CONVERTER="soxr"
  fi
  
  if [ "$MENU_LANG" = "en" ]; then
    echo "Adjusted MPD converter: ${MPD_CONVERTER}"
    echo ""
    read -r -p "Press Enter to return to menu..."
  else
    echo "Dostosowano konwerter MPD: ${MPD_CONVERTER}"
    echo ""
    read -r -p "Naciśnij Enter, aby powrócić do menu..."
  fi
}

# ==========================================
# WYBÓR MODELU DAC HAT
# ==========================================

select_model() {
  local result_var="${1:-}"
  print_header
  if [ "$MENU_LANG" = "en" ]; then
    echo -e "${YELLOW}⏳ Select DAC HAT model...${NC}"
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
    echo -e "${YELLOW}⏳ Wybór modelu DAC HAT...${NC}"
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
    1) HAT_MODEL="justboom-dac" ;; # Często działa z R38
    2) HAT_MODEL="hifiberry-dacplus" ;;
    3) HAT_MODEL="hifiberry-dacplushd" ;;
    4) HAT_MODEL="justboom-dac" ;;
    5) HAT_MODEL="iqaudio-dacplus" ;;
    6) HAT_MODEL="i2s-dac" ;; # Pimoroni DAC Shim używa generic I2S
    7) HAT_MODEL="allo-boss-dac-pcm512x-audio" ;;
    8) HAT_MODEL="allo-katana-dac-audio" ;;
    9) HAT_MODEL="googlevoicehat-soundcard" ;;
    10) HAT_MODEL="audioinjector-wm8731-audio" ;;
    11) 
      if [ "$MENU_LANG" = "en" ]; then
        read -r -p "Enter dtoverlay name (e.g., hifiberry-dac): " CUSTOM_HAT
      else
        read -r -p "Wpisz nazwę dtoverlay (np. hifiberry-dac): " CUSTOM_HAT
      fi
      HAT_MODEL="${CUSTOM_HAT:-justboom-dac}"
      ;;
    *) HAT_MODEL="justboom-dac" ;;
  esac
  
  if [ "$MENU_LANG" = "en" ]; then
    echo "Selected overlay: ${HAT_MODEL}"
  else
    echo "Wybrano overlay: ${HAT_MODEL}"
  fi
  
  # Jeśli podano zmienną wynikową, ustaw ją, inaczej wypisz na stdout
  if [ -n "$result_var" ]; then
    printf -v "$result_var" '%s' "$HAT_MODEL"
  else
    echo "$HAT_MODEL"
  fi
}

# ==========================================
# GENEROWANIE KONFIGURACJI
# ==========================================

gen_configs() {
  local hat_model="${1:-$HAT_MODEL}"
  
  print_header
  echo -e "${YELLOW}⏳ Generowanie plików konfiguracyjnych...${NC}"
  
  # Użyj wybranego modelu lub wybierz go jeśli nie podano
  if [ -z "$hat_model" ] || [ "$hat_model" = "justboom-dac" ]; then
    select_model hat_model
  fi
  
  HAT_MODEL="$hat_model"
  echo "Używam modelu: ${HAT_MODEL}"

  # 1. PulseAudio daemon.conf - przygotuj listę parametrów do modyfikacji
  cat > "$STAGING_DIR/daemon_changes.txt" << EOF
# Optymalizacja: Max Quality (User Selected)
# Sample Rate: ${SAMPLE_RATE} Hz | Bit Depth: ${BIT_DEPTH} bit
# Output Format: ${OUTPUT_FORMAT} | Resample: ${RESAMPLE_METHOD}
# Mixer: ${MIXER_TYPE} | Volume Curve: ${VOLUME_CURVE}
# Dither: ${DITHER_ENABLED} | Buffer: ${BUFFER_SIZE} kB
# Clock: ${CLOCK_SOURCE} | Zero Crossing: ${ZERO_CROSSING} | Soft Clip: ${SOFT_CLIP}
default-sample-format = ${OUTPUT_FORMAT}
default-sample-rate = ${SAMPLE_RATE}
alternate-sample-rate = 96000
avoid-resampling = yes
resample-method = ${RESAMPLE_METHOD}
enable-lfe-remixing = no
flat-volumes = no
realtime-scheduling = yes
rlimit-rtprio = 20
exit-idle-time = -1
log-level = error
EOF

  # 2. PulseAudio default.pa - przygotuj listę modułów do dodania
  cat > "$STAGING_DIR/default_pa_changes.txt" << 'EOF'
# Moduły dodane przez skrypt audio HQ
load-module module-native-protocol-unix
load-module module-udev-detect tsched=0
load-module module-combine-sink
load-module module-intended-roles
load-module module-always-sink
EOF

  # 3. MPD mpd.conf - przygotuj parametry do modyfikacji
  cat > "$STAGING_DIR/mpd_changes.txt" << EOF
# MPD - Wysoka jakość + PulseAudio
# Konwerter: ${MPD_CONVERTER} | Mixer: ${MIXER_TYPE}
# Buffer: ${BUFFER_SIZE} kB | Zero Crossing: ${ZERO_CROSSING}
samplerate_converter "${MPD_CONVERTER}"
audio_buffer_size "${BUFFER_SIZE}"
replaygain "album"
auto_update "yes"
auto_update_depth "3"
zeroconf_enabled "no"
EOF

  # 4. Przygotowanie config.txt (TYLKO JEDEN overlay!)
  if [ -f "$BOOT_CFG" ]; then
    cp "$BOOT_CFG" "$STAGING_DIR/config.txt.orig"
    cp "$BOOT_CFG" "$STAGING_DIR/config.txt.preview"
  else
    touch "$STAGING_DIR/config.txt.preview"
  fi

  # === KLUCZOWA POPRAWKA ===
  # Usuń WSZYSTKIE stare dtoverlay audio i dtparam=audio
  sed -i '/^dtoverlay=.*\(dac\|audio\|hifiberry\|justboom\|iqaudio\|allo\|pcm512x\)/d' "$STAGING_DIR/config.txt.preview"
  sed -i '/^dtparam=audio=/d' "$STAGING_DIR/config.txt.preview"

  # Dodaj tylko jeden, czysty overlay na końcu sekcji [all] lub na dole
  {
    echo ""
    echo "# === Audio HAT - dodane przez skrypt $(date '+%Y-%m-%d %H:%M') ==="
    echo "dtoverlay=${HAT_MODEL}"
    echo "dtparam=audio=off"
  } >> "$STAGING_DIR/config.txt.preview"

  echo -e "${GREEN}✅ Przygotowano config.txt z tylko jednym dtoverlay=${HAT_MODEL}${NC}"
  echo -e "${GREEN}✅ Pliki wygenerowane w: $STAGING_DIR${NC}"
  log "Wygenerowano konfiguracje (SR: $SAMPLE_RATE, RS: $RESAMPLE_METHOD)."
}
install_packages() {
  print_header
  echo -e "${YELLOW}📦 Instalacja pakietów...${NC}"
  
  apt-get update -qq
  
  DEPS="mpd pulseaudio pulseaudio-utils alsa-utils sox libsoxr-dev"
  # Sprawdź czy dialog jest potrzebny (używamy tylko CLI w tej wersji, ale zostawiamy jako opcję)
  # Jeśli użytkownik chce TUI, można dopisać 'dialog'
  
  echo "Instalowanie: $DEPS"
  apt-get install -y --no-install-recommends "$DEPS"
  
  # Wyłączenie PipeWire-Pulse jeśli aktywne
  if systemctl is-active --quiet pipewire-pulse 2>/dev/null; then
    echo "Wyłączanie PipeWire-Pulse..."
    systemctl --global mask pipewire-pulse.service 2>/dev/null || true
    systemctl mask pipewire-pulse.service 2>/dev/null || true
    systemctl stop pipewire-pulse 2>/dev/null || true
  fi
  
  echo -e "${GREEN}✅ Pakiety zainstalowane.${NC}"
  log "Pakiety zainstalowane."
}

apply_configs() {
  print_header
  echo -e "${RED}⚠️  UWAGA: Ta operacja zmodyfikuje pliki systemowe!${NC}"
  read -r -p "Czy na pewno chcesz kontynuować? (tak/nie): " confirm
  if [ "$confirm" != "tak" ]; then
    echo "Anulowano."
    return 0
  fi
  
  # Sprawdź czy pliki staging istnieją
  if [ ! -f "$STAGING_DIR/daemon_changes.txt" ]; then
    echo -e "${RED}⚠️  Najpierw wygeneruj konfigurację (Opcja 4)!${NC}"
    return 1
  fi

  echo "Zatrzymywanie usług..."
  systemctl stop mpd pulseaudio 2>/dev/null || true

  echo "Modyfikowanie plików konfiguracyjnych..."
  
  # 1. Modyfikacja /etc/pulse/daemon.conf - tylko konkretne linie
  if [ -f "$PULSE_DAEMON" ]; then
    cp "$PULSE_DAEMON" "$STAGING_DIR/daemon.conf.bak"
    # Skomentuj stare linie i dodaj nowe
    for param in "default-sample-format" "default-sample-rate" "alternate-sample-rate" \
                 "avoid-resampling" "resample-method" "enable-lfe-remixing" \
                 "flat-volumes" "realtime-scheduling" "rlimit-rtprio" \
                 "exit-idle-time" "log-level"; do
      sed -i "s/^${param}[[:space:]]*=.*/#OLD: &/" "$PULSE_DAEMON"
    done
    # Dodaj nowe linie na końcu pliku
    echo "" >> "$PULSE_DAEMON"
    echo "# Nowe ustawienia audio HQ $(date)" >> "$PULSE_DAEMON"
    grep -v "^#" "$STAGING_DIR/daemon_changes.txt" >> "$PULSE_DAEMON"
    echo "✅ Zmodyfikowano $PULSE_DAEMON"
  else
    echo "⚠️  Brak pliku $PULSE_DAEMON, tworzenie nowego..."
    cp "$STAGING_DIR/daemon_changes.txt" "$PULSE_DAEMON"
  fi

  # 2. Modyfikacja /etc/pulse/default.pa - dodaj brakujące moduły
  if [ -f "$PULSE_DEFAULT" ]; then
    cp "$PULSE_DEFAULT" "$STAGING_DIR/default.pa.bak"
    # Sprawdź które moduły już są załadowane i dodaj brakujące
    while IFS= read -r line; do
      # Pomiń komentarze
      [[ "$line" =~ ^# ]] && continue
      # Sprawdź czy CAŁA linia (z parametrami) już istnieje w pliku
      if ! grep -qF "$line" "$PULSE_DEFAULT"; then
        echo "$line" >> "$PULSE_DEFAULT"
        echo "  Dodano: $line"
      fi
    done < "$STAGING_DIR/default_pa_changes.txt"
    echo "✅ Zmodyfikowano $PULSE_DEFAULT"
  else
    echo "⚠️  Brak pliku $PULSE_DEFAULT, tworzenie nowego..."
    cat > "$PULSE_DEFAULT" << 'EOF'
#!/usr/bin/pulseaudio -nF
EOF
    cat "$STAGING_DIR/default_pa_changes.txt" >> "$PULSE_DEFAULT"
  fi

  # 3. Modyfikacja /etc/mpd.conf - tylko konkretne parametry
  if [ -f "$MPD_CONF" ]; then
    cp "$MPD_CONF" "$STAGING_DIR/mpd.conf.bak"
    # Skomentuj stare linie i dodaj nowe
    for param in "samplerate_converter" "audio_buffer_size" "replaygain" \
                 "auto_update" "auto_update_depth" "zeroconf_enabled"; do
      sed -i "s/^${param}[[:space:]].*/#OLD: &/" "$MPD_CONF"
    done
    # Dodaj nowe linie na końcu pliku
    echo "" >> "$MPD_CONF"
    echo "# Nowe ustawienia audio HQ $(date)" >> "$MPD_CONF"
    grep -v "^#" "$STAGING_DIR/mpd_changes.txt" >> "$MPD_CONF"
    echo "✅ Zmodyfikowano $MPD_CONF"
  else
    echo "⚠️  Brak pliku $MPD_CONF, tworzenie nowego..."
    cat > "$MPD_CONF" << EOF
music_directory "/var/lib/mpd/music"
playlist_directory "/var/lib/mpd/playlists"
db_file "/var/lib/mpd/tag_cache"
log_file "/var/log/mpd/mpd.log"
pid_file "/run/mpd/pid"
state_file "/var/lib/mpd/state"
user "mpd"
group "mpd"

audio_output {
    type            "pulse"
    name            "RPi4 Hi-Res Pulse"
    mixer_type      "${MIXER_TYPE}"
}

EOF
    grep -v "^#" "$STAGING_DIR/mpd_changes.txt" >> "$MPD_CONF"
  fi

  # === POPRAWIONA SEKCJA config.txt ===
  echo -e "${YELLOW}Aktualizacja $BOOT_CFG${NC}"
  
  if [ -f "$BOOT_CFG" ]; then
    BOOT_BACKUP="$BACKUP_BASE/config.txt.$(date +%Y%m%d_%H%M%S).bak"
    cp "$BOOT_CFG" "$BOOT_BACKUP"
    echo "Backup utworzony: $BOOT_BACKUP"

    # Najbezpieczniejsza metoda: zastąp całą sekcję audio
    # Usuń stare linie audio (tylko jeśli plik istnieje)
    sed -i '/^dtoverlay=.*\(dac\|audio\|hifiberry\|justboom\|iqaudio\|allo\|pcm512x\)/d' "$BOOT_CFG"
    sed -i '/^dtparam=audio=/d' "$BOOT_CFG"

    # Dodaj czysty wpis
    {
      echo ""
      echo "# === Audio HAT - dodane przez skrypt $(date '+%Y-%m-%d %H:%M') ==="
      echo "dtoverlay=${HAT_MODEL}"
      echo "dtparam=audio=off"
    } >> "$BOOT_CFG"

    echo -e "${GREEN}✅ Zapisano dtoverlay=${HAT_MODEL} (tylko jeden)${NC}"
  else
    # Plik nie istnieje - utwórz nowy z samym overlayem
    echo -e "${YELLOW}⚠️  $BOOT_CFG nie istnieje, tworzenie nowego pliku${NC}"
    {
      echo "# === Audio HAT - dodane przez skrypt $(date '+%Y-%m-%d %H:%M') ==="
      echo "dtoverlay=${HAT_MODEL}"
      echo "dtparam=audio=off"
    } > "$BOOT_CFG"
    echo -e "${GREEN}✅ Utworzono $BOOT_CFG z dtoverlay=${HAT_MODEL}${NC}"
  fi
  
  log "Zastosowano dtoverlay=${HAT_MODEL}"
  
  # Uprawnienia
  chown mpd:audio "$MPD_CONF" 2>/dev/null || true
  chmod 640 "$MPD_CONF"

  echo "Restart usług..."
  systemctl daemon-reload
  
  # Włącz i uruchom usługi jeśli nie są aktywne
  if ! systemctl is-active --quiet pulseaudio 2>/dev/null; then
    echo "Uruchamianie PulseAudio..."
    systemctl enable pulseaudio 2>/dev/null || true
    systemctl start pulseaudio 2>/dev/null || true
  else
    echo "Restart PulseAudio..."
    systemctl restart pulseaudio 2>/dev/null || true
  fi
  
  if ! systemctl is-active --quiet mpd 2>/dev/null; then
    echo "Uruchamianie MPD..."
    systemctl enable mpd 2>/dev/null || true
    systemctl start mpd 2>/dev/null || true
  else
    echo "Restart MPD..."
    systemctl restart mpd 2>/dev/null || true
  fi
  
  # Sprawdź status usług
  echo ""
  echo "Status usług:"
  systemctl is-active pulseaudio 2>/dev/null && echo "  ✅ PulseAudio: aktywna" || echo "  ⚠️  PulseAudio: nieaktywna"
  systemctl is-active mpd 2>/dev/null && echo "  ✅ MPD: aktywna" || echo "  ⚠️  MPD: nieaktywna"
  
  echo -e "${GREEN}✅ Konfiguracja zastosowana!${NC}"
  echo ""
  echo -e "${YELLOW}Wykonaj reboot: sudo reboot${NC}"
  echo ""
  echo "⚠️  WAŻNE: Aby zmiany w config.txt (HAT) zadziałały, konieczny jest RESTART Raspberry Pi."
  read -r -p "Czy chcesz teraz zrestartować system? (tak/nie): " reboot_now
  if [ "$reboot_now" = "tak" ]; then
    reboot
  fi
}
test_audio() {
  print_header
  echo -e "${CYAN}🔊 Test Dźwięku${NC}"
  echo "Upewnij się, że głośniki są podłączone."
  echo ""
  echo "1. Test ALSA (bezpośrednio do sprzętu)"
  aplay -l | grep -i dac || echo "Nie wykryto DACa przez aplay."
  read -r -p "Naciśnij Enter, aby odtworzyć dźwięk testowy (sinus)..."
  speaker-test -t sine -f 440 -l 3 || echo "Błąd speaker-test. Czy usługa audio działa?"
  
  echo ""
  echo "2. Test PulseAudio"
  if command -v paplay &> /dev/null; then
     echo "Generowanie szumu różowego przez PulseAudio..."
     # Krótki test, wymaga działającego serwera PA
     timeout 2 dd if=/dev/urandom of=/tmp/test.raw bs=4096 count=100 2>/dev/null
     paplay --raw --rate=44100 --channels=2 --format=s16le /tmp/test.raw 2>/dev/null || echo "PA nie odpowiada."
  fi
  echo ""
  read -r -p "Naciśnij Enter, aby wrócić..."
}

# ==========================================
# MENU GŁÓWNE
# ==========================================

main_menu() {
  local hat_model_selected=""
  
  while true; do
    print_header
    if [ "$MENU_LANG" = "en" ]; then
      echo -e "${CYAN}MAIN MENU:${NC}"
      if [ -n "$hat_model_selected" ]; then
        echo -e "Selected DAC model: ${GREEN}$hat_model_selected${NC}"
      else
        echo -e "Selected DAC model: ${YELLOW}None (select option 4)${NC}"
      fi
      echo ""
      echo "0) 🌐 Change language (PL/EN)"
      echo "1) 📦 Install packages (mpd, pulseaudio, sox)"
      echo "2) 💾 Backup current files"
      echo "3) 👁️ Preview system files"
      echo "4) ⚙️ Select HAT + Configure quality"
      echo "5) 🚀 Generate and Apply configuration"
      echo "6) 🔍 Compare backup with new files"
      echo "7) 🔊 Audio Test"
      echo "8) 🛑 Exit"
      echo ""
      read -r -p "Select option [0-8]: " choice
    else
      echo -e "${CYAN}MENU GŁÓWNE:${NC}"
      if [ -n "$hat_model_selected" ]; then
        echo -e "Wybrany model DAC: ${GREEN}$hat_model_selected${NC}"
      else
        echo -e "Wybrany model DAC: ${YELLOW}Brak (wybierz opcję 4)${NC}"
      fi
      echo ""
      echo "0) 🌐 Zmień język (PL/EN)"
      echo "1) 📦 Zainstaluj pakiety (mpd, pulseaudio, sox)"
      echo "2) 💾 Backup obecnych plików"
      echo "3) 👁️ Podgląd plików systemowych"
      echo "4) ⚙️ Wybierz HAT + Konfiguruj jakość"
      echo "5) 🚀 Generuj i Zastosuj konfigurację"
      echo "6) 🔍 Porównaj backup z nowymi plikami"
      echo "7) 🔊 Test Dźwięku"
      echo "8) 🛑 Wyjdź"
      echo ""
      read -r -p "Wybierz opcję [0-8]: " choice
    fi

    case $choice in
      0)
        if [ "$MENU_LANG" = "en" ]; then
          MENU_LANG="pl"
          echo "Language changed to Polish (Polski)"
        else
          MENU_LANG="en"
          echo "Zmieniono język na angielski (English)"
        fi
        read -r -p "Press Enter to continue..."
        ;;
      1) install_packages ;;
      2) backup_files ;;
      3)
        if [ "$MENU_LANG" = "en" ]; then
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
          1) preview_file "$BOOT_CFG" "Boot Config" ;;
          2) preview_file "$PULSE_DAEMON" "Pulse Daemon" ;;
          3) preview_file "$MPD_CONF" "MPD Config" ;;
        esac
        ;;
      4) 
        hat_model_selected=$(select_model)
        configure_quality "$hat_model_selected"
        ;;
      5)
        if [ -z "$hat_model_selected" ]; then
          if [ "$MENU_LANG" = "en" ]; then
            echo -e "${RED}⚠️  First select DAC model (option 4)!${NC}"
          else
            echo -e "${RED}⚠️  Najpierw wybierz model DAC (opcja 4)!${NC}"
          fi
          read -r -p "Enter..."
        else
          gen_configs "$hat_model_selected"
          apply_configs
        fi
        ;;
      6)
        LATEST=$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d -printf "%T@ %p\n" 2>/dev/null | sort -nr | head -n1 | cut -d" " -f2-)
        if [ -z "$LATEST" ]; then
          if [ "$MENU_LANG" = "en" ]; then
            echo "No backup found!"
          else
            echo "Brak backupu!"
          fi
        else
          compare_files "$LATEST/$(basename "$PULSE_DAEMON")" "$STAGING_DIR/daemon.conf"
          compare_files "$LATEST/$(basename "$PULSE_DEFAULT")" "$STAGING_DIR/default.pa"
          compare_files "$LATEST/$(basename "$MPD_CONF")" "$STAGING_DIR/mpd.conf"
          compare_files "$LATEST/$(basename "$BOOT_CFG")" "$STAGING_DIR/config.txt.preview"
        fi
        read -r -p "Enter..."
        ;;
      7) test_audio ;;
      8) exit 0 ;;
      *) 
        if [ "$MENU_LANG" = "en" ]; then
          echo "Invalid choice."
        else
          echo "Nieprawidłowy wybór."
        fi
        ;;
    esac
  done
}

# Start
main_menu
