#!/usr/bin/env bash
# shellcheck shell=bash
# ==========================================
# RPi4 Audio Setup - Config Generator Module
# Moduł generowania konfiguracji: PulseAudio, MPD, config.txt
# ==========================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/core.sh"

# Zmienne konfiguracyjne (globalne dla sesji)
declare -g SAMPLE_RATE="$DEFAULT_SAMPLE_RATE"
declare -g BIT_DEPTH="$DEFAULT_BIT_DEPTH"
declare -g RESAMPLE_METHOD="$DEFAULT_RESAMPLE_METHOD"
declare -g MPD_CONVERTER="$DEFAULT_MPD_CONVERTER"
declare -g MIXER_TYPE="$DEFAULT_MIXER_TYPE"
declare -g VOLUME_CURVE="$DEFAULT_VOLUME_CURVE"
declare -g DITHER_ENABLED="$DEFAULT_DITHER_ENABLED"
declare -g BUFFER_SIZE="$DEFAULT_BUFFER_SIZE"
declare -g CLOCK_SOURCE="$DEFAULT_CLOCK_SOURCE"
declare -g OUTPUT_FORMAT="$DEFAULT_OUTPUT_FORMAT"
declare -g ZERO_CROSSING="$DEFAULT_ZERO_CROSSING"
declare -g SOFT_CLIP="$DEFAULT_SOFT_CLIP"
declare -g HAT_MODEL="$DEFAULT_HAT_MODEL"
declare -g CLOCK_MODE="$DEFAULT_CLOCK_MODE"
declare -g OUTPUT_DELAY="$DEFAULT_OUTPUT_DELAY"
declare -g AUTO_MUTE="$DEFAULT_AUTO_MUTE"
declare -g VOLUME_GAIN="$DEFAULT_VOLUME_GAIN"
declare -g DEEMPHASIS="$DEFAULT_DEEMPHASIS"
declare -g CHANNEL_MODE="$DEFAULT_CHANNEL_MODE"

# ==========================================
# GENEROWANIE KONFIGURACJI
# ==========================================

# Generowanie pliku daemon.conf dla PulseAudio
generate_daemon_conf() {
    local output_file="$STAGING_DIR/daemon.conf.new"
    
    cat > "$output_file" << EOF
# === RPi4 Audio HQ Configuration ===
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
# Sample Rate: ${SAMPLE_RATE} Hz | Bit Depth: ${BIT_DEPTH} bit
# Output Format: ${OUTPUT_FORMAT} | Resample: ${RESAMPLE_METHOD}
# Mixer: ${MIXER_TYPE} | Volume Curve: ${VOLUME_CURVE}
# Dither: ${DITHER_ENABLED} | Buffer: ${BUFFER_SIZE} kB
# Clock: ${CLOCK_SOURCE} | Zero Crossing: ${ZERO_CROSSING} | Soft Clip: ${SOFT_CLIP}

default-sample-format = ${OUTPUT_FORMAT}
default-sample-rate = ${SAMPLE_RATE}
alternate-sample-rate = 96000
resample-method = ${RESAMPLE_METHOD}
flat-volumes = no
realtime-scheduling = yes
rlimit-rtprio = 20
exit-idle-time = -1
log-level = error
EOF
    
    log "Generated daemon.conf: $output_file"
    echo "$output_file"
}

# Generowanie pliku default.pa dla PulseAudio
generate_default_pa() {
    local output_file="$STAGING_DIR/default.pa.new"
    
    cat > "$output_file" << 'EOF'
#!/usr/bin/pulseaudio -nF
# === RPi4 Audio HQ Modules ===
# Generated: 
EOF
    echo "# Generated: $(date '+%Y-%m-%d %H:%M:%S')" >> "$output_file"
    
    # Dodaj tylko niezbędne moduły
    cat >> "$output_file" << 'EOF'

# Podstawowe moduły systemowe
load-module module-device-restore
load-module module-stream-restore
load-module module-card-restore

# Protokół lokalny
load-module module-native-protocol-unix

# Detekcja sprzętu (tsched=0 dla lepszej synchronizacji)
load-module module-udev-detect tsched=0

# ALSA jako fallback
load-module module-alsa-sink

# Always sink dla stabilności
load-module module-always-sink

# Intended roles dla lepszego routingu
load-module module-intended-roles

# Combine sink (opcjonalnie, jeśli potrzebne)
# load-module module-combine-sink

# Console kit i systemd integration
.ifexists module-systemd-login.so
load-module module-systemd-login
.endif

# Polkit authentication
.ifexists module-polkit.so
load-module module-polkit
.endif

# Extend volume range
set-default-sink alsa_output.platform-analog-stereo
EOF
    
    log "Generated default.pa: $output_file"
    echo "$output_file"
}

# Generowanie konfiguracji MPD
generate_mpd_conf() {
    local output_file="$STAGING_DIR/mpd.conf.new"
    
    # Sprawdź czy istnieje oryginalny plik MPD
    if [[ -f "$MPD_CONF" ]]; then
        # Kopiujemy istniejący i modyfikujemy tylko nasze sekcje
        cp "$MPD_CONF" "$output_file"
        
        # Usuń stare linie naszych parametrów
        sed -i '/^samplerate_converter/d' "$output_file"
        sed -i '/^audio_buffer_size/d' "$output_file"
        sed -i '/^replaygain/d' "$output_file"
        sed -i '/^auto_update/d' "$output_file"
        sed -i '/^zeroconf_enabled/d' "$output_file"
        
        # Dodaj nowe parametry na końcu
        cat >> "$output_file" << EOF

# === RPi4 Audio HQ Settings ===
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
# Konwerter: ${MPD_CONVERTER} | Mixer: ${MIXER_TYPE}
# Buffer: ${BUFFER_SIZE} kB | Zero Crossing: ${ZERO_CROSSING}

samplerate_converter "${MPD_CONVERTER}"
audio_buffer_size "${BUFFER_SIZE}"
replaygain "album"
auto_update "yes"
auto_update_depth "3"
zeroconf_enabled "no"
EOF
    else
        # Utwórz nowy plik od podstaw
        cat > "$output_file" << EOF
# === MPD Configuration for RPi4 Audio HQ ===
# Generated: $(date '+%Y-%m-%d %H:%M:%S')

music_directory "/var/lib/mpd/music"
playlist_directory "/var/lib/mpd/playlists"
db_file "/var/lib/mpd/tag_cache"
log_file "/var/log/mpd/mpd.log"
pid_file "/run/mpd/pid"
state_file "/var/lib/mpd/state"
user "mpd"
group "mpd"

# Audio output - PulseAudio
audio_output {
    type            "pulse"
    name            "RPi4 Hi-Res Pulse"
    mixer_type      "${MIXER_TYPE}"
}

# === RPi4 Audio HQ Settings ===
samplerate_converter "${MPD_CONVERTER}"
audio_buffer_size "${BUFFER_SIZE}"
replaygain "album"
auto_update "yes"
auto_update_depth "3"
zeroconf_enabled "no"
EOF
    fi
    
    log "Generated mpd.conf: $output_file"
    echo "$output_file"
}

# Generowanie config.txt z overlayem DAC
generate_config_txt() {
    local output_file="$STAGING_DIR/config.txt.new"
    local source_cfg=""
    
    # Określ źródłowy plik config.txt
    if [[ -d "/boot/firmware" ]] && [[ -f "$BOOT_CFG_DEFAULT" ]]; then
        source_cfg="$BOOT_CFG_DEFAULT"
    elif [[ -f "$BOOT_CFG_LEGACY" ]]; then
        source_cfg="$BOOT_CFG_LEGACY"
    else
        log "No existing config.txt found, creating new one" "WARN"
        source_cfg=""
    fi
    
    if [[ -n "$source_cfg" ]] && [[ -f "$source_cfg" ]]; then
        # Kopiuj oryginał
        cp "$source_cfg" "$output_file"
        
        # Bezpieczne usuwanie starych wpisów audio
        # Używamy bardziej precyzyjnych regexów
        sed -i '/^dtoverlay[[:space:]]*=[[:space:]]*\(hifiberry\|justboom\|iqaudio\|allo-boss\|allo-katana\|googlevoicehat\|audioinjector\|i2s-dac\)/d' "$output_file"
        sed -i '/^dtparam[[:space:]]*=[[:space:]]*audio=/d' "$output_file"
        
        # Dodaj nowy wpis na końcu
        {
            echo ""
            echo "# === Audio HAT Configuration ==="
            echo "# Added by RPi4 Audio Setup on $(date '+%Y-%m-%d %H:%M')"
            echo "dtoverlay=${HAT_MODEL}"
            echo "dtparam=audio=off"
        } >> "$output_file"
        
        log "Modified config.txt from $source_cfg"
    else
        # Utwórz nowy plik
        cat > "$output_file" << EOF
# === RPi4 Audio HAT Configuration ===
# Generated: $(date '+%Y-%m-%d %H:%M:%S')

dtoverlay=${HAT_MODEL}
dtparam=audio=off
EOF
        log "Created new config.txt"
    fi
    
    echo "$output_file"
}

# Główna funkcja generująca wszystkie konfiguracje
gen_configs() {
    local hat_model="${1:-$HAT_MODEL}"
    
    if [[ -n "$hat_model" ]]; then
        HAT_MODEL="$hat_model"
    fi
    
    log "Generating configurations for HAT model: $HAT_MODEL"
    echo -e "${COLORS[YELLOW]}⏳ Generowanie plików konfiguracyjnych...${COLORS[NC]}"
    
    # Walidacja modelu HAT
    if ! validate_hat_model "$HAT_MODEL"; then
        echo -e "${COLORS[RED]}⚠️  Ostrzeżenie: Model '$HAT_MODEL' może być niepoprawny${COLORS[NC]}"
    fi
    
    # Generuj wszystkie pliki
    local daemon_file pa_file mpd_file boot_file
    
    daemon_file=$(generate_daemon_conf)
    pa_file=$(generate_default_pa)
    mpd_file=$(generate_mpd_conf)
    boot_file=$(generate_config_txt)
    
    echo -e "${COLORS[GREEN]}✅ Przygotowano pliki:${COLORS[NC]}"
    echo "  • daemon.conf: $daemon_file"
    echo "  • default.pa: $pa_file"
    echo "  • mpd.conf: $mpd_file"
    echo "  • config.txt: $boot_file"
    echo ""
    echo -e "${COLORS[CYAN]}📋 Podsumowanie konfiguracji:${COLORS[NC]}"
    echo "  • Sample Rate: ${SAMPLE_RATE} Hz"
    echo "  • Bit Depth: ${BIT_DEPTH} bit"
    echo "  • Output Format: ${OUTPUT_FORMAT}"
    echo "  • Resample Method: ${RESAMPLE_METHOD}"
    echo "  • DAC Overlay: ${HAT_MODEL}"
    echo ""
    
    log "Configuration generation completed" "SUCCESS"
    
    # Zwróć ścieżkę do katalogu staging
    echo "$STAGING_DIR"
}

# Podgląd wygenerowanych plików
preview_configs() {
    echo -e "${COLORS[CYAN]}=== Podgląd wygenerowanych konfiguracji ===${COLORS[NC]}"
    echo ""
    
    for file in "$STAGING_DIR"/*.new "$STAGING_DIR"/*.txt.new; do
        if [[ -f "$file" ]]; then
            preview_file "$file" "$(basename "$file")" 30
            echo ""
        fi
    done
}

# Eksport funkcji i zmiennych
export -f generate_daemon_conf generate_default_pa generate_mpd_conf generate_config_txt gen_configs preview_configs
export SAMPLE_RATE BIT_DEPTH RESAMPLE_METHOD MPD_CONVERTER MIXER_TYPE VOLUME_CURVE
export DITHER_ENABLED BUFFER_SIZE CLOCK_SOURCE OUTPUT_FORMAT ZERO_CROSSING SOFT_CLIP
export HAT_MODEL CLOCK_MODE OUTPUT_DELAY AUTO_MUTE VOLUME_GAIN DEEMPHASIS CHANNEL_MODE
