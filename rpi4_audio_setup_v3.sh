#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

# ==========================================
# RPi4 Audio HQ Setup + Streaming + Multiroom
# Autor: AI Assistant | Wersja: 3.1
# Przeznaczenie: Debian Trixie/Bookworm, PulseAudio + MPD + Snapcast
# Funkcje: Auto-Detect HAT, Streaming, Monitoring, Multiroom
# ==========================================

# Ścieżki systemowe
BOOT_CFG="/boot/firmware/config.txt"
if [ ! -d "/boot/firmware" ]; then
  BOOT_CFG="/boot/config.txt"
fi

PULSE_DAEMON="/etc/pulse/daemon.conf"
PULSE_DEFAULT="/etc/pulse/default.pa"
MPD_CONF="/etc/mpd.conf"
MPD_MPD_CONF="/etc/mpd.conf.d/50-snapcast.conf"
SNAPCAST_SERVER_CONF="/etc/snapserver.conf"
SPOTIFY_CONF="/etc/spotifyd.conf"
SHAIRPORT_CONF="/etc/shairport-sync.conf"
MINIDLNA_CONF="/etc/minidlna.conf"

STAGING_DIR="/tmp/rpi_audio_staging"
BACKUP_BASE="$HOME/.rpi_audio_backup"
LOG_FILE="$HOME/.rpi_audio_script.log"

# Domyślne wartości najwyższej jakości audio
SAMPLE_RATE="384000"
BIT_DEPTH="32"
RESAMPLE_METHOD="soxr highest"
MPD_CONVERTER="soxr highest"
MIXER_TYPE="hardware"
VOLUME_CURVE="logarithmic"
DITHER_ENABLED="yes"
BUFFER_SIZE="40960"
CLOCK_SOURCE="internal"
OUTPUT_FORMAT="float32le"
ZERO_CROSSING="yes"
SOFT_CLIP="yes"
HAT_MODEL=""
AUTO_DETECTED="false"

# Język menu (domyślnie polski)
MENU_LANG="pl"

# Kolory
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Sprawdzenie uprawnień
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}⚠️  BŁĄD: Skrypt wymaga uprawnień roota.${NC}"
  echo -e "Uruchom komendą: ${CYAN}sudo bash $0${NC}"
  exit 1
fi

# Logowanie
log() { 
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
  echo -e "${BLUE}[LOG]${NC} $1"
}

# Tworzenie katalogów
mkdir -p "$STAGING_DIR" "$BACKUP_BASE"

# ==========================================
# BAZA DANYCH DAC HAT
# ==========================================

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
# AUTOMATYCZNE WYKRYWANIE HAT
# ==========================================

detect_hat_auto() {
  print_header
  echo -e "${CYAN}🔍 Automatyczne wykrywanie DAC HAT...${NC}"
  echo ""
  
  local detected=""
  local aplay_output
  local dtb_overlays
  local sound_cards
  
  # Metoda 1: Sprawdzenie overlay w device-tree
  if [ -f "/proc/device-tree/chosen/bootloader" ]; then
    dtb_overlays=$(cat /proc/device-tree/chosen/bootloader 2>/dev/null | grep -o "dtoverlay.*" || true)
  fi
  
  # Metoda 2: Sprawdzenie config.txt
  if [ -f "$BOOT_CFG" ]; then
    local config_overlay
    config_overlay=$(grep -E "^dtoverlay=.*(dac|audio)" "$BOOT_CFG" 2>/dev/null | tail -1 | cut -d'=' -f2 | cut -d',' -f1 || true)
    if [ -n "$config_overlay" ]; then
      detected="$config_overlay"
    fi
  fi
  
  # Metoda 3: Sprawdzenie kart dźwiękowych przez aplay
  if command -v aplay &>/dev/null; then
    aplay_output=$(aplay -l 2>/dev/null || true)
    
    # Sprawdzanie znanych nazw DAC
    if echo "$aplay_output" | grep -qi "justboom"; then
      detected="justboom-dac"
    elif echo "$aplay_output" | grep -qi "hifiberry.*dac.*hd"; then
      detected="hifiberry-dacplushd"
    elif echo "$aplay_output" | grep -qi "hifiberry.*dac.*plus"; then
      detected="hifiberry-dacplus"
    elif echo "$aplay_output" | grep -qi "hifiberry-dac"; then
      detected="hifiberry-dacplus"
    elif echo "$aplay_output" | grep -qi "iqaudio"; then
      detected="iqaudio-dacplus"
    elif echo "$aplay_output" | grep -qi "allo.*boss"; then
      detected="allo-boss-dac-pcm512x-audio"
    elif echo "$aplay_output" | grep -qi "allo.*katana"; then
      detected="allo-katana-dac-audio"
    elif echo "$aplay_output" | grep -qi "google.*voice"; then
      detected="googlevoicehat-soundcard"
    elif echo "$aplay_output" | grep -qi "audioinjector\|wm8731"; then
      detected="audioinjector-wm8731-audio"
    elif echo "$aplay_output" | grep -qi "i2s\|pcm512x"; then
      detected="i2s-dac"
    fi
  fi
  
  # Metoda 4: Sprawdzenie modułów kernel
  if [ -z "$detected" ]; then
    local loaded_modules
    loaded_modules=$(lsmod 2>/dev/null || true)
    
    if echo "$loaded_modules" | grep -q "snd_soc_pcm512x"; then
      detected="justboom-dac"
    elif echo "$loaded_modules" | grep -q "snd_soc_pcm1792a"; then
      detected="hifiberry-dacplushd"
    elif echo "$loaded_modules" | grep -q "snd_soc_wm8731"; then
      detected="audioinjector-wm8731-audio"
    fi
  fi
  
  # Metoda 5: Sprawdzenie I2C dla DAC z EEPROM
  if [ -z "$detected" ] && [ -d "/sys/bus/i2c/devices" ]; then
    for dev in /sys/bus/i2c/devices/*/name; do
      if [ -f "$dev" ]; then
        local i2c_name
        i2c_name=$(cat "$dev" 2>/dev/null || true)
        if echo "$i2c_name" | grep -qi "dac\|audio"; then
          log "Wykryto urządzenie I2C: $i2c_name"
        fi
      fi
    done
  fi
  
  echo ""
  if [ -n "$detected" ]; then
    echo -e "${GREEN}✅ Wykryto DAC: ${detected}${NC}"
    
    # Walidacja czy model istnieje w bazie
    if [[ -v DAC_CAPABILITIES["$detected"] ]]; then
      echo -e "${GREEN}   Model znany w bazie danych.${NC}"
      HAT_MODEL="$detected"
      AUTO_DETECTED="true"
    else
      echo -e "${YELLOW}   ⚠️  Model nieznany, użyto domyślnego: justboom-dac${NC}"
      HAT_MODEL="justboom-dac"
      AUTO_DETECTED="true"
    fi
    
    # Wyświetlenie możliwości
    local dac_caps max_rate max_bit supported_rates
    dac_caps=$(get_dac_capabilities "$HAT_MODEL")
    IFS=':' read -r max_rate max_bit supported_rates <<< "$dac_caps"
    echo ""
    echo -e "   Maksymalna częstotliwość: ${GREEN}${max_rate} Hz${NC}"
    echo -e "   Maksymalna głębia bitowa: ${GREEN}${max_bit} bit${NC}"
  else
    echo -e "${YELLOW}⚠️  Nie wykryto automatycznie żadnego DAC HAT.${NC}"
    echo ""
    echo "Możliwe przyczyny:"
    echo "  - HAT nie jest podłączony"
    echo "  - Brak sterowników w kernelu"
    echo "  - Konieczność ręcznej konfiguracji dtoverlay"
    echo ""
    read -r -p "Czy chcesz wybrać model ręcznie? (tak/nie): " manual_choice
    if [ "$manual_choice" = "tak" ]; then
      select_model_interactive
    else
      HAT_MODEL="justboom-dac"
      AUTO_DETECTED="false"
    fi
  fi
  
  echo ""
  read -r -p "Naciśnij Enter, aby kontynuować..."
}

# ==========================================
# RĘCZNY WYBÓR MODELU DAC HAT
# ==========================================

select_model_interactive() {
  print_header
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
  echo "0) Powrót"
  echo ""
  read -r -p "Twój wybór [0-11] (domyślnie 1): " hat_choice
  
  case $hat_choice in
    0) return 1 ;;
    1) HAT_MODEL="justboom-dac" ;;
    2) HAT_MODEL="hifiberry-dacplus" ;;
    3) HAT_MODEL="hifiberry-dacplushd" ;;
    4) HAT_MODEL="justboom-dac" ;;
    5) HAT_MODEL="iqaudio-dacplus" ;;
    6) HAT_MODEL="i2s-dac" ;;
    7) HAT_MODEL="allo-boss-dac-pcm512x-audio" ;;
    8) HAT_MODEL="allo-katana-dac-audio" ;;
    9) HAT_MODEL="googlevoicehat-soundcard" ;;
    10) HAT_MODEL="audioinjector-wm8731-audio" ;;
    11) 
      read -r -p "Wpisz nazwę dtoverlay (np. hifiberry-dac): " CUSTOM_HAT
      HAT_MODEL="${CUSTOM_HAT:-justboom-dac}"
      ;;
    *) HAT_MODEL="justboom-dac" ;;
  esac
  
  AUTO_DETECTED="false"
  echo "Wybrano overlay: ${HAT_MODEL}"
  return 0
}

# ==========================================
# KONFIGURACJA PARAMETRÓW JAKOŚCI
# ==========================================

configure_quality() {
  local hat_model="${1:-$HAT_MODEL}"
  
  if [ -z "$hat_model" ]; then
    hat_model="justboom-dac"
  fi
  
  local dac_caps max_rate max_bit supported_rates
  dac_caps=$(get_dac_capabilities "$hat_model")
  IFS=':' read -r max_rate max_bit supported_rates <<< "$dac_caps"
  
  print_header
  echo -e "${CYAN}⚙️  Konfiguracja Jakości Dźwięku${NC}"
  echo -e "Model DAC: ${GREEN}$hat_model${NC}"
  echo -e "Maksymalna częstotliwość: ${GREEN}${max_rate} Hz${NC}"
  echo -e "Maksymalna głębia bitowa: ${GREEN}${max_bit} bit${NC}"
  echo ""
  
  IFS=',' read -ra RATES_ARRAY <<< "$supported_rates"
  
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

  echo "Wybierz metodę resamplingu dla PulseAudio:"
  echo "1) speex-float-1 (Szybka, niska jakość)"
  echo "2) speex-float-5 (Dobra jakość, zbalansowana)"
  echo "3) speex-float-10 (Bardzo dobra jakość)"
  echo "4) soxr (Najwyższa jakość, większe CPU)"
  echo "5) soxr very high (Jakość studyjna)"
  echo "6) soxr highest (Maksymalna wierność)"
  echo ""
  read -r -p "Twój wybór [1-6] (domyślnie 6): " rs_choice
  case $rs_choice in
    1) RESAMPLE_METHOD="speex-float-1" ;;
    2) RESAMPLE_METHOD="speex-float-5" ;;
    3) RESAMPLE_METHOD="speex-float-10" ;;
    4) RESAMPLE_METHOD="soxr" ;;
    5) RESAMPLE_METHOD="soxr very high" ;;
    6) RESAMPLE_METHOD="soxr highest" ;;
    *) RESAMPLE_METHOD="soxr highest" ;;
  esac
  echo "Ustawiono Resample Method: ${RESAMPLE_METHOD}"
  echo ""
  
  read -r -p "Naciśnij Enter, aby zapisać ustawienia..."
}

# ==========================================
# GENEROWANIE KONFIGURACJI
# ==========================================

gen_configs() {
  local hat_model="${1:-$HAT_MODEL}"
  
  if [ -z "$hat_model" ]; then
    hat_model="justboom-dac"
  fi
  
  print_header
  echo -e "${YELLOW}⏳ Generowanie plików konfiguracyjnych...${NC}"
  
  HAT_MODEL="$hat_model"
  echo "Używam modelu: ${HAT_MODEL}"

  # 1. PulseAudio daemon.conf
  cat > "$STAGING_DIR/daemon.conf" << EOF
# Optymalizacja: Max Quality
# Sample Rate: ${SAMPLE_RATE} Hz | Bit Depth: ${BIT_DEPTH} bit
# Output Format: ${OUTPUT_FORMAT} | Resample: ${RESAMPLE_METHOD}
# Mixer: ${MIXER_TYPE} | Volume Curve: ${VOLUME_CURVE}
# Dither: ${DITHER_ENABLED} | Buffer: ${BUFFER_SIZE} kB
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

  # 2. PulseAudio default.pa
  cat > "$STAGING_DIR/default.pa" << 'EOF'
#!/usr/bin/pulseaudio -nF
load-module module-native-protocol-unix
load-module module-udev-detect tsched=0
load-module module-combine-sink
load-module module-intended-roles
load-module module-always-sink
EOF

  # 3. MPD mpd.conf
  cat > "$STAGING_DIR/mpd.conf" << EOF
# MPD - Wysoka jakość + PulseAudio
music_directory "/var/lib/mpd/music"
playlist_directory "/var/lib/mpd/playlists"
db_file "/var/lib/mpd/tag_cache"
log_file "/var/log/mpd/mpd.log"
pid_file "/run/mpd/pid"
state_file "/var/lib/mpd/state"
user "mpd"
group "audio"

audio_output {
    type            "pulse"
    name            "RPi4 Hi-Res Pulse"
    mixer_type      "${MIXER_TYPE}"
}

samplerate_converter "${MPD_CONVERTER}"
audio_buffer_size "${BUFFER_SIZE}"
buffer_before_play "10%"
gapless_mp3_playback "yes"
replaygain "album"
auto_update "yes"
auto_update_depth "3"
zeroconf_enabled "no"
EOF

  # 4. Boot config
  if [ -f "$BOOT_CFG" ]; then
    cp "$BOOT_CFG" "$STAGING_DIR/config.txt"
    sed -i 's/^\(dtoverlay=.*dac\)/#DEPRECATED: \1/' "$STAGING_DIR/config.txt"
    sed -i 's/^\(dtoverlay=.*audio\)/#DEPRECATED: \1/' "$STAGING_DIR/config.txt"
    sed -i 's/^\(dtparam=audio=on\)/#DEPRECATED: \1/' "$STAGING_DIR/config.txt"
  else
    touch "$STAGING_DIR/config.txt"
  fi
  
  {
    echo ""
    echo "# Dodane przez skrypt audio HQ $(date)"
    echo "dtoverlay=${HAT_MODEL}"
    echo "dtparam=audio=off"
  } >> "$STAGING_DIR/config.txt"

  echo -e "${GREEN}✅ Pliki wygenerowane w: $STAGING_DIR${NC}"
  log "Wygenerowano konfiguracje."
}

# ==========================================
# INSTALACJA PAKIETÓW
# ==========================================

install_packages() {
  print_header
  echo -e "${YELLOW}📦 Instalacja pakietów...${NC}"
  
  apt-get update -qq
  
  DEPS="mpd pulseaudio pulseaudio-utils alsa-utils sox libsoxr-dev avahi-daemon"
  
  echo "Instalowanie podstawowych pakietów: $DEPS"
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
  echo -e "${RED}⚠️  UWAGA: Ta operacja nadpisze pliki systemowe!${NC}"
  read -r -p "Czy na pewno chcesz kontynuować? (tak/nie): " confirm
  if [ "$confirm" != "tak" ]; then
    echo "Anulowano."
    return 0
  fi
  
  if [ ! -f "$STAGING_DIR/daemon.conf" ]; then
    echo -e "${RED}⚠️  Najpierw wygeneruj konfigurację!${NC}"
    return 1
  fi

  echo "Zatrzymywanie usług..."
  systemctl stop mpd pulseaudio 2>/dev/null || true

  echo "Kopiowanie plików..."
  cp -f "$STAGING_DIR/daemon.conf" "$PULSE_DAEMON"
  cp -f "$STAGING_DIR/default.pa" "$PULSE_DEFAULT"
  cp -f "$STAGING_DIR/mpd.conf" "$MPD_CONF"
  cp -f "$STAGING_DIR/config.txt" "$BOOT_CFG"
  
  chown mpd:audio "$MPD_CONF" 2>/dev/null || true
  chmod 640 "$MPD_CONF"

  echo "Restart usług..."
  systemctl daemon-reload
  systemctl restart mpd pulseaudio 2>/dev/null || true
  
  echo -e "${GREEN}✅ Konfiguracja zastosowana!${NC}"
  echo ""
  echo "⚠️  WAŻNE: Aby zmiany w config.txt (HAT) zadziałały, konieczny jest RESTART."
  read -r -p "Czy chcesz teraz zrestartować system? (tak/nie): " reboot_now
  if [ "$reboot_now" = "tak" ]; then
    reboot
  fi
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
      echo "  ⚠️  $f (nie istnieje)"
    fi
  done
  echo -e "${GREEN}✅ Backup utworzony w: $DIR${NC}"
}

# ==========================================
# STREAMING SERVICES
# ==========================================

install_spotify_connect() {
  print_header
  echo -e "${CYAN}🎵 Instalacja Spotify Connect (spotifyd)...${NC}"
  echo ""
  
  # Sprawdzenie czy już zainstalowany
  if command -v spotifyd &>/dev/null; then
    echo "Spotifyd jest już zainstalowany."
    read -r -p "Czy chcesz przekonfigurować? (tak/nie): " reconfig
    if [ "$reconfig" != "tak" ]; then
      return 0
    fi
  fi
  
  echo "Pobieranie spotifyd..."
  cd /tmp
  
  # Pobranie najnowszej wersji dla ARM
  local arch
  arch=$(uname -m)
  if [ "$arch" = "armv7l" ] || [ "$arch" = "armhf" ]; then
    local SPOTIFYD_URL="https://github.com/Spotifyd/spotifyd/releases/latest/download/spotifyd-armv7-unknown-linux-gnueabihf.tar.gz"
  elif [ "$arch" = "aarch64" ]; then
    local SPOTIFYD_URL="https://github.com/Spotifyd/spotifyd/releases/latest/download/spotifyd-aarch64-unknown-linux-musl.tar.gz"
  else
    echo -e "${RED}Nieobsługiwana architektura: $arch${NC}"
    return 1
  fi
  
  if curl -sL "$SPOTIFYD_URL" -o spotifyd.tar.gz; then
    tar xzf spotifyd.tar.gz
    mv spotifyd /usr/local/bin/
    chmod +x /usr/local/bin/spotifyd
    
    # Tworzenie użytkownika
    if ! id -u spotifyd &>/dev/null; then
      useradd -r -s /bin/false spotifyd
    fi
    
    # Konfiguracja
    cat > "$SPOTIFY_CONF" << EOF
[GLOBAL]
# Nazwa urządzenia w sieci
device_name = "RPi4 Spotify"
# Typ backendu audio
backend = pulseaudio
# Normalizacja głośności
volume_normalisation = true
# Poziom normalizacji (dB)
normalisation_pregain = -3
# Bitrate (90, 160, 320)
bitrate = 320
# Katalog na cache
cache_path = /var/cache/spotifyd
# Plik PID
pidfile = /var/run/spotifyd.pid
# Interwał ładowania playlist
autoplay_playlist = true
# Tryb shuffle
shuffle = false
EOF
    
    # Usługa systemd
    cat > /etc/systemd/system/spotifyd.service << 'EOF'
[Unit]
Description=Spotifyd
After=network.target pulseaudio.service

[Service]
Type=simple
User=spotifyd
Group=audio
ExecStart=/usr/local/bin/spotifyd --no-daemon
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    mkdir -p /var/cache/spotifyd
    chown spotifyd:audio /var/cache/spotifyd
    
    systemctl daemon-reload
    systemctl enable spotifyd
    systemctl start spotifyd
    
    echo -e "${GREEN}✅ Spotify Connect zainstalowany i uruchomiony!${NC}"
    echo ""
    echo "Twoje urządzenie powinno być widoczne w aplikacji Spotify jako 'RPi4 Spotify'"
  else
    echo -e "${RED}❌ Nie udało się pobrać spotifyd${NC}"
    return 1
  fi
}

install_airplay() {
  print_header
  echo -e "${CYAN}🍎 Instalacja AirPlay (shairport-sync)...${NC}"
  echo ""
  
  if dpkg -l | grep -q shairport-sync; then
    echo "Shairport-sync jest już zainstalowany."
    read -r -p "Czy chcesz przekonfigurować? (tak/nie): " reconfig
    if [ "$reconfig" != "tak" ]; then
      return 0
    fi
  fi
  
  echo "Instalowanie shairport-sync..."
  apt-get install -y shairport-sync avahi-daemon
  
  # Konfiguracja
  cat > "$SHAIRPORT_CONF" << EOF
// Konfiguracja Shairport Sync
general = {
  name = "RPi4 AirPlay";
  output_backend = "pulse";
};

alsa = {
  output_device = "default";
  mixer_control_name = "";
};

sessioncontrol = {
  run_this_before_play_begins = "/usr/bin/pactl set-sink-mute @DEFAULT_SINK@ 0";
};

metadata = {
  enabled = "yes";
  include_cover_art = "yes";
};
EOF
  
  # Restart usług
  systemctl restart avahi-daemon
  systemctl restart shairport-sync
  systemctl enable shairport-sync
  
  echo -e "${GREEN}✅ AirPlay zainstalowany i uruchomiony!${NC}"
  echo ""
  echo "Twoje urządzenie powinno być widoczne jako 'RPi4 AirPlay' w iOS/macOS"
}

install_upnp_dlna() {
  print_header
  echo -e "${CYAN}📺 Instalacja UPnP/DLNA (MiniDLNA)...${NC}"
  echo ""
  
  if dpkg -l | grep -q minidlna; then
    echo "MiniDLNA jest już zainstalowana."
    read -r -p "Czy chcesz przekonfigurować? (tak/nie): " reconfig
    if [ "$reconfig" != "tak" ]; then
      return 0
    fi
  fi
  
  echo "Instalowanie MiniDLNA..."
  apt-get install -y minidlna
  
  # Tworzenie katalogu na media
  mkdir -p /var/media/{music,videos,pictures}
  
  # Konfiguracja
  cat > "$MINIDLNA_CONF" << EOF
# Konfiguracja MiniDLNA
friendly_name=RPi4 Media Server
media_dir=A,/var/media/pictures
media_dir=P,/var/media/pictures
media_dir=V,/var/media/videos
media_dir=M,/var/media/music
port=8200
inotify=yes
enable_tivo=no
strict_dlna=no
notify_interval=90
EOF
  
  systemctl restart minidlna
  systemctl enable minidlna
  
  echo -e "${GREEN}✅ UPnP/DLNA zainstalowany!${NC}"
  echo ""
  echo "Serwer mediów dostępny na porcie 8200"
  echo "Dodaj pliki do /var/media/music aby były widoczne"
}

streaming_menu() {
  while true; do
    print_header
    echo -e "${CYAN}📡 MENU STREAMING:${NC}"
    echo ""
    echo "1) 🎵 Zainstaluj/Konfiguruj Spotify Connect"
    echo "2) 🍎 Zainstaluj/Konfiguruj AirPlay"
    echo "3) 📺 Zainstaluj/Konfiguruj UPnP/DLNA"
    echo "4) 🔍 Sprawdź status usług streaming"
    echo "0) Powrót do menu głównego"
    echo ""
    read -r -p "Wybierz opcję [0-4]: " choice
    
    case $choice in
      1) install_spotify_connect ;;
      2) install_airplay ;;
      3) install_upnp_dlna ;;
      4)
        echo ""
        echo "Status usług streaming:"
        echo "========================"
        if systemctl is-active --quiet spotifyd 2>/dev/null; then
          echo -e "Spotify Connect: ${GREEN}● Aktywny${NC}"
        else
          echo -e "Spotify Connect: ${RED}○ Nieaktywny${NC}"
        fi
        
        if systemctl is-active --quiet shairport-sync 2>/dev/null; then
          echo -e "AirPlay: ${GREEN}● Aktywny${NC}"
        else
          echo -e "AirPlay: ${RED}○ Nieaktywny${NC}"
        fi
        
        if systemctl is-active --quiet minidlna 2>/dev/null; then
          echo -e "UPnP/DLNA: ${GREEN}● Aktywny${NC}"
        else
          echo -e "UPnP/DLNA: ${RED}○ Nieaktywny${NC}"
        fi
        echo ""
        read -r -p "Naciśnij Enter..."
        ;;
      0) return ;;
      *) echo "Nieprawidłowy wybór." ;;
    esac
  done
}

# ==========================================
# MONITORING I DIAGNOSTYKA
# ==========================================

show_audio_status() {
  print_header
  echo -e "${CYAN}📊 Status Audio - Live${NC}"
  echo ""
  
  echo "=== Karty dźwiękowe ==="
  if command -v aplay &>/dev/null; then
    aplay -l 2>/dev/null || echo "Brak kart dźwiękowych"
  else
    echo "aplay niedostępne"
  fi
  echo ""
  
  echo "=== Urządzenia PulseAudio ==="
  if command -v pactl &>/dev/null; then
    echo "Domyślne źródło:"
    pactl get-default-source 2>/dev/null || echo "Niedostępne"
    echo "Domyślny sink:"
    pactl get-default-sink 2>/dev/null || echo "Niedostępne"
    echo ""
    echo "Aktywne streamy:"
    pactl list short sink-inputs 2>/dev/null || echo "Brak aktywnych streamów"
  else
    echo "pactl niedostępne"
  fi
  echo ""
  
  echo "=== Głośność ==="
  if command -v amixer &>/dev/null; then
    amixer get Master 2>/dev/null | head -5 || echo "amixer niedostępne"
  fi
  echo ""
}

show_system_monitor() {
  print_header
  echo -e "${CYAN}💻 Monitor Systemu - Live${NC}"
  echo ""
  
  echo "=== Temperatury ==="
  if [ -f "/sys/class/thermal/thermal_zone0/temp" ]; then
    local temp
    temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo "0")
    echo "CPU: $((temp / 1000))°C"
  else
    echo "Czujnik temperatury niedostępny"
  fi
  echo ""
  
  echo "=== Obciążenie CPU ==="
  if command -v top &>/dev/null; then
    top -bn1 | head -5
  fi
  echo ""
  
  echo "=== Pamięć RAM ==="
  free -h 2>/dev/null || echo "free niedostępne"
  echo ""
  
  echo "=== Procesy audio ==="
  ps aux | grep -E "(pulse|mpd|snap|spotify|airplay)" | grep -v grep || echo "Brak procesów audio"
  echo ""
}

monitoring_loop() {
  print_header
  echo -e "${CYAN}📈 Monitoring Na Żywo (Ctrl+C aby wyjść)${NC}"
  echo ""
  
  trap 'echo ""; echo "Monitoring zatrzymany."; return 0' INT
  
  while true; do
    clear
    echo -e "${CYAN}=== MONITORING AUDIO - $(date) ===${NC}"
    echo ""
    
    # Temperatura
    if [ -f "/sys/class/thermal/thermal_zone0/temp" ]; then
      local temp
      temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo "0")
      printf "Temperatura CPU: %3d°C  " "$((temp / 1000))"
    fi
    
    # Obciążenie CPU
    local load
    load=$(uptime | awk -F'load average:' '{print $2}' | cut -d',' -f1 | tr -d ' ')
    printf "Load: %s  " "$load"
    
    # Głośność
    if command -v amixer &>/dev/null; then
      local vol
      vol=$(amixer get Master 2>/dev/null | grep -o '[0-9]*%' | head -1 || echo "N/A")
      printf "Głośność: %s  " "$vol"
    fi
    
    # Aktywne streamy
    if command -v pactl &>/dev/null; then
      local streams
      streams=$(pactl list short sink-inputs 2>/dev/null | wc -l || echo "0")
      printf "Streamy: %s\n" "$streams"
    fi
    
    echo ""
    echo "=== Ostatnie procesy audio ==="
    ps aux --sort=-%cpu | grep -E "(pulse|mpd|snap)" | grep -v grep | head -3 || echo "Brak"
    
    echo ""
    echo "Odświeżanie co 2 sekundy... (Ctrl+C aby wyjść)"
    sleep 2
  done
}

diagnostics_menu() {
  while true; do
    print_header
    echo -e "${CYAN}🔧 MENU DIAGNOSTYKI:${NC}"
    echo ""
    echo "1) 📊 Pokaż status audio"
    echo "2) 💻 Pokaż monitor systemu"
    echo "3) 📈 Monitoring na żywo (real-time)"
    echo "4) 🧪 Test dźwięku"
    echo "5) 📋 Raport systemowy"
    echo "0) Powrót"
    echo ""
    read -r -p "Wybierz opcję [0-5]: " choice
    
    case $choice in
      1) show_audio_status; read -r -p "Enter..." ;;
      2) show_system_monitor; read -r -p "Enter..." ;;
      3) monitoring_loop ;;
      4) test_audio ;;
      5)
        print_header
        echo "=== RAPORT SYSTEMOWY ==="
        echo "Data: $(date)"
        echo "Host: $(hostname)"
        echo "Kernel: $(uname -r)"
        echo "Architektura: $(uname -m)"
        echo ""
        echo "=== Sieć ==="
        ip addr show | grep -E "inet |^[0-9]+:" | head -20
        echo ""
        echo "=== USB Devices ==="
        lsusb 2>/dev/null | head -10 || echo "lsusb niedostępne"
        echo ""
        read -r -p "Enter..."
        ;;
      0) return ;;
      *) echo "Nieprawidłowy wybór." ;;
    esac
  done
}

test_audio() {
  print_header
  echo -e "${CYAN}🔊 Test Dźwięku${NC}"
  echo ""
  
  if ! command -v speaker-test &>/dev/null; then
    echo -e "${RED}Brak speaker-test. Zainstaluj alsa-utils.${NC}"
    return 1
  fi
  
  echo "Test będzie trwał 10 sekund..."
  echo "Powinieneś usłyszeć szum z lewego i prawego kanału."
  echo ""
  read -r -p "Naciśnij Enter aby rozpocząć test..."
  
  speaker-test -t wav -c 2 -l 3 -r 44100 2>/dev/null
  
  echo ""
  echo -e "${GREEN}Test zakończony.${NC}"
}

# ==========================================
# SNAPCAST MULTIROOM
# ==========================================

discover_snapcast_clients() {
  echo -e "${CYAN}🔍 Skanowanie sieci w poszukiwaniu klientów Snapcast...${NC}"
  echo ""
  
  # Pobranie własnego IP
  local my_ip
  my_ip=$(hostname -I | awk '{print $1}')
  local network_prefix
  network_prefix=$(echo "$my_ip" | cut -d'.' -f1-3)
  
  echo "Skanowanie sieci ${network_prefix}.0/24..."
  echo ""
  
  declare -a found_clients
  
  # Skanowanie portu 1705 (Snapcast server)
  for i in $(seq 1 254); do
    local host="${network_prefix}.${i}"
    if ping -c 1 -W 1 "$host" &>/dev/null; then
      # Sprawdzenie czy port 1705 lub 1780 jest otwarty
      if timeout 1 bash -c "echo >/dev/tcp/$host/1705" 2>/dev/null || \
         timeout 1 bash -c "echo >/dev/tcp/$host/1780" 2>/dev/null; then
        found_clients+=("$host")
        echo -e "  ${GREEN}✓ Znaleziono: $host${NC}"
      fi
    fi
  done
  
  echo ""
  if [ ${#found_clients[@]} -gt 0 ]; then
    echo -e "${GREEN}Znaleziono ${#found_clients[@]} potencjalnych klientów Snapcast${NC}"
  else
    echo -e "${YELLOW}Nie znaleziono żadnych klientów Snapcast${NC}"
  fi
  
  # Zapis do pliku
  if [ ${#found_clients[@]} -gt 0 ]; then
    printf '%s\n' "${found_clients[@]}" > "$STAGING_DIR/snapcast_clients.txt"
    echo "Lista zapisana do: $STAGING_DIR/snapcast_clients.txt"
  fi
  
  return 0
}

install_snapcast_server() {
  print_header
  echo -e "${CYAN}🏠 Instalacja Snapcast Server...${NC}"
  echo ""
  
  if dpkg -l | grep -q snapserver; then
    echo "Snapserver jest już zainstalowany."
    read -r -p "Czy chcesz przekonfigurować? (tak/nie): " reconfig
    if [ "$reconfig" != "tak" ]; then
      return 0
    fi
  fi
  
  echo "Dodawanie repozytorium Snapcast..."
  
  # Instalacja z repozytorium
  apt-get install -y snapserver || {
    # Fallback - pobranie z GitHub
    echo "Próba instalacji z GitHub..."
    cd /tmp
    local version="0.27.0"
    local arch
    arch=$(uname -m)
    
    if [ "$arch" = "armv7l" ]; then
      wget -q "https://github.com/badaix/snapcast/releases/download/v${version}/snapserver_${version}_armhf.deb" || return 1
    elif [ "$arch" = "aarch64" ]; then
      wget -q "https://github.com/badaix/snapcast/releases/download/v${version}/snapserver_${version}_arm64.deb" || return 1
    else
      echo "Nieobsługiwana architektura"
      return 1
    fi
    
    dpkg -i snapserver_${version}_*.deb || apt-get install -f -y
  }
  
  # Konfiguracja
  cat > "$SNAPCAST_SERVER_CONF" << EOF
# Konfiguracja Snapcast Server
[stream]
source = pipe:///tmp/snapfifo?name=default
codec = flac
sample_rate = 48000
sample_fmt = s16le
channels = 2
fragment_ms = 20
buffer_ms = 1000

[server]
datadir = /var/lib/snapserver
ssl_cert = 
hosts_file = 

[broadcast]
host = 0.0.0.0
port = 1704
bind_to_address = 

[http]
enabled = true
port = 1780
doc_root = /usr/share/snapserver/www

[tcp]
enabled = true
port = 1705

[unix]
enabled = false

[logging]
filter = *:info
targets = syslog
EOF
  
  # Konfiguracja MPD dla Snapcast
  mkdir -p /etc/mpd.conf.d
  cat > "$MPD_MPD_CONF" << EOF
audio_output {
  type    "pipe"
  name    \"Snapcast\"
  command \"/bin/sh -c 'cat > /tmp/snapfifo'\"
  format  \"44100:16:2\"
  auto_resample \"no\"
}
EOF
  
  # Tworzenie FIFO
  rm -f /tmp/snapfifo
  mkfifo /tmp/snapfifo
  chown snapserver:snapserver /tmp/snapfifo
  
  systemctl daemon-reload
  systemctl enable snapserver
  systemctl restart snapserver
  
  echo -e "${GREEN}✅ Snapcast Server zainstalowany!${NC}"
  echo ""
  echo "Interfejs webowy: http://$(hostname -I | awk '{print $1}'):1780"
}

install_snapcast_client() {
  print_header
  echo -e "${CYAN}📱 Instalacja Snapcast Client...${NC}"
  echo ""
  
  if dpkg -l | grep -q snapclient; then
    echo "Snapclient jest już zainstalowany."
    read -r -p "Czy chcesz przekonfigurować? (tak/nie): " reconfig
    if [ "$reconfig" != "tak" ]; then
      return 0
    fi
  fi
  
  # Pobranie adresu serwera
  read -r -p "Podaj adres IP serwera Snapcast: " server_ip
  
  if dpkg -l | grep -q snapclient; then
    apt-get install -y snapclient || {
      cd /tmp
      local version="0.27.0"
      local arch
      arch=$(uname -m)
      
      if [ "$arch" = "armv7l" ]; then
        wget -q "https://github.com/badaix/snapcast/releases/download/v${version}/snapclient_${version}_armhf.deb"
      elif [ "$arch" = "aarch64" ]; then
        wget -q "https://github.com/badaix/snapcast/releases/download/v${version}/snapclient_${version}_arm64.deb"
      fi
      
      dpkg -i snapclient_${version}_*.deb || apt-get install -f -y
    }
  else
    apt-get install -y snapclient || {
      cd /tmp
      local version="0.27.0"
      local arch
      arch=$(uname -m)
      
      if [ "$arch" = "armv7l" ]; then
        wget -q "https://github.com/badaix/snapcast/releases/download/v${version}/snapclient_${version}_armhf.deb"
      elif [ "$arch" = "aarch64" ]; then
        wget -q "https://github.com/badaix/snapcast/releases/download/v${version}/snapclient_${version}_arm64.deb"
      fi
      
      dpkg -i snapclient_${version}_*.deb || apt-get install -f -y
    }
  fi
  
  # Konfiguracja klienta
  sed -i "s/SERVER_IP/${server_ip}/g" /etc/default/snapclient 2>/dev/null || true
  echo "SERVER=\"${server_ip}\"" > /etc/default/snapclient
  
  systemctl daemon-reload
  systemctl enable snapclient
  systemctl restart snapclient
  
  echo -e "${GREEN}✅ Snapcast Client skonfigurowany!${NC}"
  echo "Połączono z serwerem: $server_ip"
}

snapcast_menu() {
  while true; do
    print_header
    echo -e "${CYAN}🏠 MENU SNAPCAST (Multiroom):${NC}"
    echo ""
    echo "1) 🔍 Skanuj sieć w poszukiwaniu klientów"
    echo "2) 🏠 Zainstaluj Snapcast Server (główny)"
    echo "3) 📱 Zainstaluj Snapcast Client (satelita)"
    echo "4) 📊 Status Snapcast"
    echo "5) 🌐 Otwórz interfejs webowy"
    echo "0) Powrót"
    echo ""
    read -r -p "Wybierz opcję [0-5]: " choice
    
    case $choice in
      1) discover_snapcast_clients; read -r -p "Enter..." ;;
      2) install_snapcast_server; read -r -p "Enter..." ;;
      3) install_snapcast_client; read -r -p "Enter..." ;;
      4)
        echo ""
        echo "Status Snapcast:"
        if systemctl is-active --quiet snapserver 2>/dev/null; then
          echo -e "  Server: ${GREEN}● Aktywny${NC}"
        else
          echo -e "  Server: ${RED}○ Nieaktywny${NC}"
        fi
        if systemctl is-active --quiet snapclient 2>/dev/null; then
          echo -e "  Client: ${GREEN}● Aktywny${NC}"
        else
          echo -e "  Client: ${RED}○ Nieaktywny${NC}"
        fi
        echo ""
        echo "Połączeni klienci:"
        if command -v curl &>/dev/null; then
          curl -s "http://localhost:1780/jsonrpc" -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"Server.GetStatus","id":1}' 2>/dev/null | head -5 || echo "Brak danych"
        fi
        read -r -p "Enter..."
        ;;
      5)
        local ip
        ip=$(hostname -I | awk '{print $1}')
        echo -e "${GREEN}Otwórz w przeglądarce: http://${ip}:1780${NC}"
        read -r -p "Enter..."
        ;;
      0) return ;;
      *) echo "Nieprawidłowy wybór." ;;
    esac
  done
}

# ==========================================
# MENU GŁÓWNE
# ==========================================

print_header() {
  clear
  echo -e "${CYAN}=========================================="
  echo -e "🎧 RPi4 Audio HQ + Streaming + Multiroom"
  echo -e "Wersja: 3.0 | Auto-Detect | Snapcast"
  echo -e "==========================================${NC}"
  echo ""
}

main_menu() {
  while true; do
    print_header
    
    if [ -n "$HAT_MODEL" ]; then
      if [ "$AUTO_DETECTED" = "true" ]; then
        echo -e "Wybrany DAC: ${GREEN}$HAT_MODEL (Auto)${NC}"
      else
        echo -e "Wybrany DAC: ${GREEN}$HAT_MODEL (Manual)${NC}"
      fi
    else
      echo -e "Wybrany DAC: ${YELLOW}Brak (wybierz opcję 1 lub 2)${NC}"
    fi
    echo ""
    echo "=== KONFIGURACJA AUDIO ==="
    echo "1) 🔍 Automatycznie wykryj DAC HAT"
    echo "2) ⚙️  Ręczny wybór DAC HAT + Jakość"
    echo "3) 📦 Zainstaluj pakiety"
    echo "4) 💾 Backup"
    echo "5) 🚀 Generuj i Zastosuj konfigurację"
    echo ""
    echo "=== STREAMING ==="
    echo "6) 📡 Spotify Connect / AirPlay / UPnP"
    echo ""
    echo "=== MULTIROOM ==="
    echo "7) 🏠 Snapcast (Multiroom Audio)"
    echo ""
    echo "=== DIAGNOSTYKA ==="
    echo "8) 🔧 Monitoring i Diagnostyka"
    echo "9) 🔊 Test Dźwięku"
    echo ""
    echo "0) 🛑 Wyjdź"
    echo ""
    read -r -p "Wybierz opcję [0-9]: " choice
    
    case $choice in
      1) detect_hat_auto ;;
      2) 
        if select_model_interactive; then
          configure_quality "$HAT_MODEL"
        fi
        ;;
      3) install_packages ;;
      4) backup_files ;;
      5)
        if [ -z "$HAT_MODEL" ]; then
          echo -e "${RED}⚠️  Najpierw wybierz model DAC!${NC}"
          read -r -p "Enter..."
        else
          gen_configs "$HAT_MODEL"
          apply_configs
        fi
        ;;
      6) streaming_menu ;;
      7) snapcast_menu ;;
      8) diagnostics_menu ;;
      9) test_audio ;;
      0) exit 0 ;;
      *) echo "Nieprawidłowy wybór." ;;
    esac
  done
}

# Start
main_menu
