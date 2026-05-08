#!/usr/bin/env bash
set -euo pipefail

# ==========================================
# Konfiguracja Audio RPi4 + HAT (Max Quality)
# Autor: AI Assistant | Wersja: 2.0 (CLI + Menu)
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

# Domyślne wartości wysokiej jakości
SAMPLE_RATE="384000"
BIT_DEPTH="32"
RESAMPLE_METHOD="soxr highest"
MPD_CONVERTER="soxr highest"
MIXER_TYPE="hardware"
VOLUME_CURVE="logarithmic"
DITHER_ENABLED="yes"
BUFFER_SIZE="20480"
CLOCK_SOURCE="internal"
OUTPUT_FORMAT="float32le"
ZERO_CROSSING="yes"
SOFT_CLIP="no"
HAT_MODEL="justboom-dac"

# Kolory dla CLI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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

# Tworzenie katalogu tymczasowego
mkdir -p "$STAGING_DIR" "$BACKUP_BASE"

# ==========================================
# FUNKCJE POMOCNICZE
# ==========================================

print_header() {
  clear
  echo -e "${CYAN}=========================================="
  echo -e "🎧 RPi4 Audio HQ Setup (Trixie/Bookworm)"
  echo -e "Wersja: 2.0 | Obsługa R38 i innych HAT"
  echo -e "==========================================${NC}"
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
    read -p "Naciśnij Enter, aby kontynuować..."
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
  read -p "Twój wybór [1-$default_choice] (domyślnie $default_choice): " sr_choice
  
  if [[ -v rate_map[$sr_choice] ]]; then
    SAMPLE_RATE="${rate_map[$sr_choice]}"
  else
    SAMPLE_RATE="${RATES_ARRAY[-1]}"
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
  read -p "Twój wybór [1-$bit_max] (domyślnie $bit_max): " bit_choice
  
  case $bit_choice in
    1) BIT_DEPTH="16" ;;
    2) BIT_DEPTH="24" ;;
    3) BIT_DEPTH="32" ;;
    *) BIT_DEPTH="$max_bit" ;;
  esac
  
  echo "Ustawiono Bit Depth: ${BIT_DEPTH} bit"
  echo ""

  # Wybór formatu wyjściowego PulseAudio
  echo "Wybierz format wyjściowy (Output Format):"
  echo "1) s16le (16-bit Integer)"
  echo "2) s24le (24-bit Integer)"
  echo "3) s32le (32-bit Integer)"
  echo "4) float32le (32-bit Float - Zalecane)"
  echo "5) float64le (64-bit Float - Najwyższa precyzja)"
  echo ""
  read -p "Twój wybór [1-5] (domyślnie 4): " fmt_choice
  case $fmt_choice in
    1) OUTPUT_FORMAT="s16le" ;;
    2) OUTPUT_FORMAT="s24le" ;;
    3) OUTPUT_FORMAT="s32le" ;;
    4) OUTPUT_FORMAT="float32le" ;;
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
  read -p "Twój wybór [1-3] (domyślnie 1): " mixer_choice
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
  read -p "Twój wybór [1-2] (domyślnie 1): " curve_choice
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
  read -p "Twój wybór [1-2] (domyślnie 1): " dither_choice
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
  read -p "Twój wybór [1-4] (domyślnie 2): " buffer_choice
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
  read -p "Twój wybór [1-3] (domyślnie 1): " clock_choice
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
  read -p "Twój wybór [1-2] (domyślnie 1): " zc_choice
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
  read -p "Twój wybór [1-2] (domyślnie 2): " sc_choice
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
  echo "4) soxr (Najwyższa jakość, większe CPU)"
  echo "5) soxr very high (Jakość studyjna)"
  echo "6) soxr highest (Maksymalna wierność)"
  echo ""
  read -p "Twój wybór [1-6] (domyślnie 6): " rs_choice
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

  # Automatyczne dopasowanie MPD
  if [[ "$RESAMPLE_METHOD" == soxr* ]]; then
    MPD_CONVERTER="soxr highest"
  else
    MPD_CONVERTER="soxr very high"
  fi
  echo "Dostosowano konwerter MPD: ${MPD_CONVERTER}"
  echo ""
  read -p "Naciśnij Enter, aby powrócić do menu..."
}

# ==========================================
# GENEROWANIE KONFIGURACJI
# ==========================================

gen_configs() {
  print_header
  echo -e "${YELLOW}⏳ Generowanie plików konfiguracyjnych...${NC}"
  
  # Wybór modelu HAT
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
  read -p "Twój wybór [1-11] (domyślnie 1): " hat_choice
  
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
      read -p "Wpisz nazwę dtoverlay (np. hifiberry-dac): " CUSTOM_HAT
      HAT_MODEL="${CUSTOM_HAT:-justboom-dac}"
      ;;
    *) HAT_MODEL="justboom-dac" ;;
  esac
  
  echo "Wybrano overlay: ${HAT_MODEL}"

  # 1. PulseAudio daemon.conf
  cat > "$STAGING_DIR/daemon.conf" << EOF
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

  # 2. PulseAudio default.pa
  cat > "$STAGING_DIR/default.pa" << 'EOF'
#!/usr/bin/pulseaudio -nF
# Core
load-module module-native-protocol-unix
# Udev + TSched=0 (redukuje opóźnienia i zakłócenia)
load-module module-udev-detect tsched=0
# Always combine / remap off dla jakości
load-module module-combine-sink
load-module module-intended-roles
load-module module-always-sink
# Exit - don't force auto_null, let PulseAudio auto-select the hardware sink
# set-default-sink auto_null
EOF

  # 3. MPD mpd.conf
  cat > "$STAGING_DIR/mpd.conf" << EOF
# MPD - Wysoka jakość + PulseAudio
# Konwerter: ${MPD_CONVERTER} | Mixer: ${MIXER_TYPE}
# Buffer: ${BUFFER_SIZE} kB | Zero Crossing: ${ZERO_CROSSING}
music_directory "/var/lib/mpd/music"
playlist_directory "/var/lib/mpd/playlists"
db_file "/var/lib/mpd/tag_cache"
log_file "/var/log/mpd/mpd.log"
pid_file "/run/mpd/pid"
state_file "/var/lib/mpd/state"
user "mpd"
group "audio"

# Audio Output (PulseAudio)
audio_output {
    type            "pulse"
    name            "RPi4 Hi-Res Pulse"
    mixer_type      "${MIXER_TYPE}"
}

# Konwersja próbkowania (SOX High Quality)
samplerate_converter "${MPD_CONVERTER}"

# Buforowanie i odtwarzanie
audio_buffer_size "${BUFFER_SIZE}"
buffer_before_play "10%"
gapless_mp3_playback "yes"
replaygain "album"
auto_update "yes"
auto_update_depth "3"

# Optymalizacje sieciowe / systemowe
zeroconf_enabled "no"
EOF

  # 4. Boot config
  if [ -f "$BOOT_CFG" ]; then
    cp "$BOOT_CFG" "$STAGING_DIR/config.txt"
    # Usuń stare dtoverlay audio
    sed -i '/^dtoverlay=.*dac\|^dtoverlay=.*audio\|^dtparam=audio/d' "$STAGING_DIR/config.txt"
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
  log "Wygenerowano konfiguracje (SR: $SAMPLE_RATE, RS: $RESAMPLE_METHOD)."
}

# ==========================================
# INSTALACJA I APLIKACJA
# ==========================================

install_packages() {
  print_header
  echo -e "${YELLOW}📦 Instalacja pakietów...${NC}"
  
  apt-get update -qq
  
  DEPS="mpd pulseaudio pulseaudio-utils alsa-utils sox libsoxr-dev"
  # Sprawdź czy dialog jest potrzebny (używamy tylko CLI w tej wersji, ale zostawiamy jako opcję)
  # Jeśli użytkownik chce TUI, można dopisać 'dialog'
  
  echo "Instalowanie: $DEPS"
  apt-get install -y $DEPS
  
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
  read -p "Czy na pewno chcesz kontynuować? (tak/nie): " confirm
  if [ "$confirm" != "tak" ]; then
    echo "Anulowano."
    return 0
  fi
  
  # Sprawdź czy pliki staging istnieją
  if [ ! -f "$STAGING_DIR/daemon.conf" ]; then
    echo -e "${RED}⚠️  Najpierw wygeneruj konfigurację (Opcja 4)!${NC}"
    return 1
  fi

  echo "Zatrzymywanie usług..."
  systemctl stop mpd pulseaudio 2>/dev/null || true

  echo "Kopiowanie plików..."
  cp -f "$STAGING_DIR/daemon.conf" "$PULSE_DAEMON"
  cp -f "$STAGING_DIR/default.pa" "$PULSE_DEFAULT"
  cp -f "$STAGING_DIR/mpd.conf" "$MPD_CONF"
  cp -f "$STAGING_DIR/config.txt" "$BOOT_CFG"
  
  # Uprawnienia
  chown mpd:audio "$MPD_CONF" 2>/dev/null || true
  chmod 640 "$MPD_CONF"

  echo "Restart usług..."
  systemctl daemon-reload
  systemctl restart mpd pulseaudio 2>/dev/null || true
  
  echo -e "${GREEN}✅ Konfiguracja zastosowana!${NC}"
  echo ""
  echo "⚠️  WAŻNE: Aby zmiany w config.txt (HAT) zadziałały, konieczny jest RESTART Raspberry Pi."
  read -p "Czy chcesz teraz zrestartować system? (tak/nie): " reboot_now
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
  read -p "Naciśnij Enter, aby odtworzyć dźwięk testowy (sinus)..."
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
  read -p "Naciśnij Enter, aby wrócić..."
}

# ==========================================
# MENU GŁÓWNE
# ==========================================

main_menu() {
  while true; do
    print_header
    echo -e "${CYAN}MENU GŁÓWNE:${NC}"
    echo "1) 📦 Zainstaluj pakiety (mpd, pulseaudio, sox)"
    echo "2) 💾 Backup obecnych plików"
    echo "3) 👁️ Podgląd plików systemowych"
    echo "4) ⚙️ Generuj konfigurację (Wybór HAT + Jakość)"
    echo "5) 🚀 Zastosuj konfigurację i Restart"
    echo "6) 🔍 Porównaj backup z nowymi plikami"
    echo "7) 🔊 Test Dźwięku"
    echo "8) 🛑 Wyjdź"
    echo ""
    read -p "Wybierz opcję [1-8]: " choice

    case $choice in
      1) install_packages ;;
      2) backup_files ;;
      3)
        echo "Podgląd:"
        echo "1) Boot Config"
        echo "2) Pulse Daemon"
        echo "3) MPD Config"
        read -p "Wybierz [1-3]: " sub
        case $sub in
          1) preview_file "$BOOT_CFG" "Boot Config" ;;
          2) preview_file "$PULSE_DAEMON" "Pulse Daemon" ;;
          3) preview_file "$MPD_CONF" "MPD Config" ;;
        esac
        ;;
      4) 
        configure_quality
        gen_configs
        ;;
      5) apply_configs ;;
      6)
        LATEST=$(ls -td "$BACKUP_BASE"/*/ 2>/dev/null | head -n1)
        if [ -z "$LATEST" ]; then
          echo "Brak backupu!"
        else
          compare_files "$LATEST/daemon.conf" "$PULSE_DAEMON"
        fi
        read -p "Enter..."
        ;;
      7) test_audio ;;
      8) exit 0 ;;
      *) echo "Nieprawidłowy wybór." ;;
    esac
  done
}

# Start
main_menu
