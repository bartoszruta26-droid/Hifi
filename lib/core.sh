#!/usr/bin/env bash
# shellcheck shell=bash
# ==========================================
# RPi4 Audio Setup - Core Library
# Moduł rdzeniowy: stałe, konfiguracja globalna, utils
# ==========================================

set -euo pipefail

# Guard przed wielokrotnym sourcingiem
[[ -n "${_CORE_SH_LOADED:-}" ]] && return 0
readonly _CORE_SH_LOADED=1

# ==========================================
# WERYFIKACJA WERSJI BASH
# ==========================================
if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 2) )); then
    echo "BŁĄD: Wymagany bash 4.2+. Zainstalowana wersja: ${BASH_VERSION}" >&2
    exit 1
fi

# ==========================================
# ŚCIEŻKI SYSTEMOWE (readonly)
# ==========================================
readonly BOOT_FW="/boot/firmware"
readonly BOOT_CFG_DEFAULT="/boot/firmware/config.txt"
readonly BOOT_CFG_LEGACY="/boot/config.txt"
readonly PULSE_DAEMON="/etc/pulse/daemon.conf"
readonly PULSE_DEFAULT="/etc/pulse/default.pa"
readonly MPD_CONF="/etc/mpd.conf"

# ==========================================
# KATALOGI ROBOCZE
# ==========================================
readonly STAGING_DIR="/tmp/rpi_audio_staging"
readonly BACKUP_BASE="$HOME/.rpi_audio_backup"
readonly LOG_FILE="$HOME/.rpi_audio_script.log"

# ==========================================
# WARTOŚCI DOMYŚLNE
# ==========================================
readonly DEFAULT_SAMPLE_RATE="768000"
readonly DEFAULT_BIT_DEPTH="32"
readonly DEFAULT_RESAMPLE_METHOD="soxr-vhq"
readonly DEFAULT_MPD_CONVERTER="soxr"
readonly DEFAULT_MIXER_TYPE="hardware"
readonly DEFAULT_VOLUME_CURVE="logarithmic"
readonly DEFAULT_DITHER_ENABLED="no"
readonly DEFAULT_BUFFER_SIZE="40960"
readonly DEFAULT_CLOCK_SOURCE="internal"
readonly DEFAULT_OUTPUT_FORMAT="float64le"
readonly DEFAULT_ZERO_CROSSING="no"
readonly DEFAULT_SOFT_CLIP="no"
readonly DEFAULT_HAT_MODEL="hifiberry-dacplus"
readonly DEFAULT_CLOCK_MODE="master"
readonly DEFAULT_OUTPUT_DELAY="0"
readonly DEFAULT_AUTO_MUTE="no"
readonly DEFAULT_VOLUME_GAIN="0"
readonly DEFAULT_DEEMPHASIS="auto"
readonly DEFAULT_CHANNEL_MODE="stereo"
readonly DEFAULT_MENU_LANG="pl"

# ==========================================
# KOLORY ANSI
# ==========================================
declare -gA COLORS=(
    [RED]=$(tput setaf 1 2>/dev/null || printf '\033[0;31m')
    [GREEN]=$(tput setaf 2 2>/dev/null || printf '\033[0;32m')
    [YELLOW]=$(tput setaf 3 2>/dev/null || printf '\033[1;33m')
    [BLUE]=$(tput setaf 4 2>/dev/null || printf '\033[0;34m')
    [CYAN]=$(tput setaf 6 2>/dev/null || printf '\033[0;36m')
    [NC]=$(tput sgr0 2>/dev/null || printf '\033[0m')
)

# ==========================================
# BAZA DANYCH MOŻLIWOŚCI DAC HAT
# Format: MAX_SAMPLE_RATE:MAX_BIT_DEPTH:SUPPORTED_RATES
# ==========================================
declare -gA DAC_CAPABILITIES=(
    ["justboom-dac"]="384000:32:44100,48000,88200,96000,176400,192000,352800,384000"
    ["hifiberry-dac"]="384000:32:44100,48000,88200,96000,176400,192000,352800,384000"
    ["hifiberry-dacplus"]="384000:32:44100,48000,88200,96000,176400,192000,352800,384000"
    ["hifiberry-dacplushd"]="768000:32:44100,48000,88200,96000,176400,192000,352800,384000,705600,768000"
    ["iqaudio-dacplus"]="384000:32:44100,48000,88200,96000,176400,192000,352800,384000"
    ["i2s-dac"]="384000:32:44100,48000,88200,96000,176400,192000,352800,384000"
    ["allo-boss-dac-pcm512x-audio"]="384000:32:44100,48000,88200,96000,176400,192000,352800,384000"
    ["allo-katana-dac-audio"]="768000:32:44100,48000,88200,96000,176400,192000,352800,384000,705600,768000"
    ["googlevoicehat-soundcard"]="48000:16:8000,16000,22050,24000,32000,44100,48000"
    ["audioinjector-wm8731-audio"]="96000:24:8000,16000,22050,24000,32000,44100,48000,88200,96000"
)

# Wartości domyślne dla nieznanego DAC
readonly DEFAULT_MAX_RATE="384000"
readonly DEFAULT_MAX_BIT="32"
readonly DEFAULT_RATES="44100,48000,88200,96000,176400,192000,352800,384000"

# Lista poprawnych overlayów (whitelist bezpieczeństwa)
declare -ga VALID_OVERLAYS=(
    "justboom-dac"
    "hifiberry-dac"
    "hifiberry-dacplus"
    "hifiberry-dacplushd"
    "iqaudio-dacplus"
    "i2s-dac"
    "allo-boss-dac-pcm512x-audio"
    "allo-katana-dac-audio"
    "googlevoicehat-soundcard"
    "audioinjector-wm8731-audio"
)

# ==========================================
# FUNKCJE UTILITY
# ==========================================

# Logowanie do pliku i stderr (NIE stdout — nie zatruwa podstawień $(...))
log() {
    local msg="$1"
    local level="${2:-INFO}"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "$timestamp [$level] $msg" >> "$LOG_FILE"

    local color="${COLORS[BLUE]}"
    case "$level" in
        ERROR)   color="${COLORS[RED]}" ;;
        WARN)    color="${COLORS[YELLOW]}" ;;
        SUCCESS) color="${COLORS[GREEN]}" ;;
        DEBUG)   color="${COLORS[CYAN]}" ;;
    esac

    # ← stderr, nie stdout: bezpieczne przy daemon_file=$(generate_daemon_conf)
    echo -e "${color}[$level]${COLORS[NC]} $msg" >&2
}

# Sprawdzenie uprawnień root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "Script requires root privileges. Run with: sudo bash $0" "ERROR"
        return 1
    fi
    return 0
}

# Weryfikacja wymaganych narzędzi
check_dependencies() {
    local missing=()
    local required=(sed diff find date systemctl aplay)
    for cmd in "${required[@]}"; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log "Brak wymaganych narzędzi: ${missing[*]}" "ERROR"
        return 1
    fi
    return 0
}

# Inicjalizacja katalogów roboczych
init_dirs() {
    mkdir -p "$STAGING_DIR" "$BACKUP_BASE"
    chmod 700 "$STAGING_DIR"
    log "Initialized working directories"
}

# Walidacja modelu DAC
validate_hat_model() {
    local model="$1"

    for valid in "${VALID_OVERLAYS[@]}"; do
        [[ "$model" == "$valid" ]] && return 0
    done

    # Dozwolone też modele z zaufanymi prefixami
    if [[ "$model" =~ ^(hifiberry|justboom|iqaudio|allo|audioinjector|googlevoicehat|i2s) ]]; then
        return 0
    fi

    log "Invalid DAC model: $model" "WARN"
    return 1
}

# Pobranie możliwości DAC
get_dac_capabilities() {
    local hat_model="$1"

    if [[ -v DAC_CAPABILITIES["$hat_model"] ]]; then
        echo "${DAC_CAPABILITIES[$hat_model]}"
    else
        echo "$DEFAULT_MAX_RATE:$DEFAULT_MAX_BIT:$DEFAULT_RATES"
    fi
}

# Sprawdza czy dany DAC wymaga I2C
hat_requires_i2c() {
    local hat_model="$1"
    case "$hat_model" in
        hifiberry-dacplus|hifiberry-dacplushd|iqaudio-dacplus|\
        allo-boss-dac-pcm512x-audio|allo-katana-dac-audio|\
        audioinjector-wm8731-audio)
            return 0 ;;
        *)
            return 1 ;;
    esac
}

# Bezpieczne czytanie inputu z walidacją
safe_read() {
    local prompt="$1"
    local default="$2"
    local validation_pattern="${3:-}"
    local result

    read -r -p "$prompt" result

    if [[ -z "$result" ]] && [[ -n "$default" ]]; then
        echo "$default"
        return 0
    fi

    if [[ -n "$validation_pattern" ]] && [[ ! "$result" =~ $validation_pattern ]]; then
        log "Invalid input: $result does not match pattern" "WARN"
        return 1
    fi

    echo "$result"
    return 0
}

# Eksport funkcji dla innych modułów
export -f log check_root check_dependencies init_dirs validate_hat_model \
           get_dac_capabilities hat_requires_i2c safe_read
