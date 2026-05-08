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
RESAMPLE_METHOD="soxr"
MPD_CONVERTER="soxr highest"

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
# KONFIGURACJA PARAMETRÓW JAKOŚCI
# ==========================================

configure_quality() {
  print_header
  echo -e "${CYAN}⚙️  Konfiguracja Jakości Dźwięku${NC}"
  echo ""
  
  # Wybór częstotliwości próbkowania
  echo "Wybierz domyślną częstotliwość próbkowania (Sample Rate):"
  echo "1) 44.1 kHz (Standard CD)"
  echo "2) 48 kHz (Standard wideo/pro)"
  echo "3) 96 kHz (Hi-Res)"
  echo "4) 192 kHz (High End)"
  echo "5) 384 kHz (Ultra Hi-Res - Zalecane)"
  echo "6) 768 kHz (Maksymalna - Eksperymentalne)"
  echo ""
  read -p "Twój wybór [1-6] (domyślnie 5): " sr_choice
  case $sr_choice in
    1) SAMPLE_RATE="44100" ;;
    2) SAMPLE_RATE="48000" ;;
    3) SAMPLE_RATE="96000" ;;
    4) SAMPLE_RATE="192000" ;;
    5) SAMPLE_RATE="384000" ;;
    6) SAMPLE_RATE="768000" ;;
    *) SAMPLE_RATE="384000" ;;
  esac
  echo "Ustawiono Sample Rate: ${SAMPLE_RATE} Hz"
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
# Sample Rate: ${SAMPLE_RATE} Hz | Resample: ${RESAMPLE_METHOD}
default-sample-format = float32le
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
# Konwerter: ${MPD_CONVERTER}
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
    mixer_type      "software"
}

# Konwersja próbkowania (SOX High Quality)
samplerate_converter "${MPD_CONVERTER}"

# Buforowanie i odtwarzanie
audio_buffer_size "20480"
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
