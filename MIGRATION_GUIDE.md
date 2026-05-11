# RPi4 Audio Setup v3.0 - Dokumentacja

## Przegląd zmian i poprawek

### Architektura modularna

Skrypt został całkowicie przepisany w oparciu o moduły:

```
/workspace/
├── rpi4_audio_setup_v3.sh      # Główny punkt wejścia
├── lib/
│   ├── core.sh                 # Rdzeń: stałe, utils, walidacje
│   ├── backup.sh               # Moduł backupu i przywracania
│   ├── config_generator.sh     # Generator konfiguracji
│   ├── applier.sh              # Aplikowanie konfiguracji
│   └── ui.sh                   # Interfejs użytkownika (menu)
└── tests/                      # Testy (do dodania)
```

---

## Naprawione błędy krytyczne

### 1. Dodano `set -euo pipefail`
Wszystkie moduły mają na początku:
```bash
set -euo pipefail
```
Co zapewnia:
- `set -e`: natychmiastowe wyjście przy błędzie
- `set -u`: błąd przy użyciu niezdefiniowanych zmiennych
- `set -o pipefail`: błędy w pipe'ach nie są ignorowane

### 2. Sprawdzenie uprawnień root
```bash
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR: Script requires root privileges" "ERROR"
        return 1
    fi
}
```

### 3. Bezpieczne operacje na plikach systemowych

**Stary kod (niebezpieczny):**
```bash
sed -i '/^dtoverlay=.*\(dac\|audio\|...\)/d' "$BOOT_CFG"
```

**Nowy kod (bezpieczny):**
```bash
# Tylko konkretne, znane overlaye
sed -i '/^dtoverlay[[:space:]]*=[[:space:]]*\(hifiberry\|justboom\|iqaudio\|allo-boss\)/d' "$output_file"
```

### 4. Walidacja modelu DAC
```bash
validate_hat_model() {
    local model="$1"
    
    # Whitelist poprawnych modeli
    for valid in "${VALID_OVERLAYS[@]}"; do
        if [[ "$model" == "$valid" ]]; then
            return 0
        fi
    done
    
    # Dozwolone prefixy
    if [[ "$model" =~ ^(hifiberry|justboom|iqaudio|allo|audioinjector) ]]; then
        return 0
    fi
    
    log "Invalid DAC model: $model" "WARN"
    return 1
}
```

### 5. Naprawiony błąd logiczny z MPD_CONVERTER

**Stary kod:**
```bash
if [[ "$RESAMPLE_METHOD" == soxr* ]]; then
    MPD_CONVERTER="soxr"
else
    MPD_CONVERTER="soxr"  # To samo!
fi
```

**Nowy kod:**
```bash
# soxr jest zawsze najlepszym wyborem
MPD_CONVERTER="soxr"
```

### 6. Bezpieczne appendowanie do plików

Zamiast bezwarunkowego `>>`, najpierw sprawdzamy czy plik istnieje i usuwamy stare wpisy:
```bash
if [[ -f "$MPD_CONF" ]]; then
    # Usuń stare parametry
    sed -i '/^samplerate_converter/d' "$MPD_CONF"
    # Dodaj nowe
    grep -E "^samplerate_converter" "$new_file" >> "$MPD_CONF"
fi
```

### 7. Obsługa PipeWire z ostrzeżeniem

Zamiast agresywnego maskowania:
```bash
if systemctl is-active --quiet pipewire-pulse; then
    echo "⚠️ Wykryto PipeWire-Pulse. Czy chcesz go wyłączyć?"
    read -r -p "Wyłączyć? (tak/nie): " answer
    if [[ "$answer" == "tak" ]]; then
        systemctl mask pipewire-pulse.service || true
    fi
fi
```

### 8. Walidacja konfiguracji MPD przed restartem
```bash
validate_mpd_config() {
    if command -v mpd &>/dev/null; then
        if mpd --test "$MPD_CONF" &>/dev/null; then
            echo "✅ Konfiguracja MPD poprawna"
            return 0
        else
            echo "⚠️ Błąd walidacji konfiguracji MPD"
            return 1
        fi
    fi
}
```

---

## Poprawki bezpieczeństwa

### Quoting zmiennych
Wszystkie zmienne są properly quoted:
```bash
local file="$1"           # ✅
if [[ -f "$file" ]]; then # ✅
```

### Walidacja inputu użytkownika
```bash
safe_read() {
    local prompt="$1"
    local default="$2"
    local validation_pattern="${3:-}"
    local result
    
    read -r -p "$prompt" result
    
    if [[ -n "$validation_pattern" ]] && [[ ! "$result" =~ $validation_pattern ]]; then
        log "Invalid input" "WARN"
        return 1
    fi
    
    echo "$result"
}
```

### Readonly constants
```bash
readonly BOOT_CFG_DEFAULT="/boot/firmware/config.txt"
readonly PULSE_DAEMON="/etc/pulse/daemon.conf"
readonly DEFAULT_SAMPLE_RATE="768000"
```

### Local variables
Wszystkie zmienne w funkcjach są `local`:
```bash
my_function() {
    local var1="$1"
    local var2="default"
    # ...
}
```

---

## Ulepszenia UX

### 1. Fallback kolorów ANSI
```bash
declare -gR COLORS=(
    [RED]=$(tput setaf 1 2>/dev/null || echo '\033[0;31m')
    [GREEN]=$(tput setaf 2 2>/dev/null || echo '\033[0;32m')
    # ...
)
```

### 2. Komunikaty w dwóch językach (PL/EN)
Każda funkcja UI obsługuje oba języki przez zmienną `MENU_LANG`.

### 3. Confirm before destructive actions
```bash
read -r -p "Czy na pewno chcesz kontynuować? (tak/nie): " confirm
if [[ "$confirm" != "tak" ]]; then
    echo "Anulowano."
    return 0
fi
```

### 4. Status usług po zastosowaniu konfiguracji
```bash
case "$pa_status" in
    aktywna)  echo "✅ PulseAudio: aktywna" ;;
    błąd)     echo "⚠️ PulseAudio: błąd uruchomienia" ;;
    *)        echo "⚠️ PulseAudio: nieaktywna" ;;
esac
```

---

## Nowe funkcje

### 1. Przywracanie z backupu
```bash
restore_from_backup() {
    local backup_dir="${1:-}"
    # Znajdź najnowszy backup jeśli nie podano
    if [[ -z "$backup_dir" ]]; then
        backup_dir=$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d \
                     -printf "%T@ %p\n" | sort -nr | head -n1 | cut -d" " -f2-)
    fi
    # Przywróć pliki...
}
```

### 2. Czyszczenie starych backupów
```bash
cleanup_old_backups() {
    local keep_count="${1:-5}"
    # Zachowaj tylko N najnowszych backupów
}
```

### 3. Podgląd plików
```bash
preview_file() {
    local file="$1"
    local title="${2:-File}"
    local lines="${3:-50}"
    
    if [[ ! -f "$file" ]]; then
        echo "⚠️ Plik nie istnieje: $file"
        return 1
    fi
    
    head -n "$lines" "$file"
}
```

---

## Uruchamianie

```bash
# Wymagane uprawnienia root
sudo bash /workspace/rpi4_audio_setup_v3.sh
```

---

## Struktura menu

```
MENU GŁÓWNE:
Wybrany model DAC: Brak (wybierz opcję 4)

0) 🌐 Zmień język (PL/EN)
1) 📦 Zainstaluj pakiety
2) 💾 Backup obecnych plików
3) 👁️ Podgląd plików systemowych
4) ⚙️ Wybierz HAT + Konfiguruj jakość
5) 🚀 Generuj konfigurację
6) 🔧 Zastosuj konfigurację
7) 🔍 Porównaj backup z nowymi plikami
8) 🔊 Test Dźwięku
9) 🔄 Przywróć z backupu
10) 🛑 Wyjdź
```

---

## Testowanie

Sprawdzenie składni wszystkich modułów:
```bash
bash -n /workspace/rpi4_audio_setup_v3.sh
for f in /workspace/lib/*.sh; do bash -n "$f"; done
```

---

## Co dalej? (TODO)

1. **Testy jednostkowe** - dodać testy dla każdej funkcji
2. **Tryb dry-run** - podgląd zmian bez wprowadzania
3. **Ansible playbook** - alternatywa dla Bash
4. **Python CLI** - pełniejsza walidacja i obsługa błędów
5. **Log rotation** - rotacja pliku logów
6. **Web UI** - opcjonalny interfejs WWW

---

## Porównanie wersji

| Funkcja | v2.x (stary) | v3.0 (nowy) |
|---------|-------------|-------------|
| Architektura | Monolit | Modularna |
| `set -euo pipefail` | ❌ | ✅ |
| Sprawdzenie root | ❌ | ✅ |
| Walidacja inputu | ❌ | ✅ |
| Whitelist overlayów | ❌ | ✅ |
| Bezpieczny sed | ❌ | ✅ |
| Walidacja MPD config | ❌ | ✅ |
| Przywracanie backupu | ❌ | ✅ |
| Fallback kolorów | ❌ | ✅ |
| Local variables | Częściowo | ✅ |
| Readonly constants | ❌ | ✅ |
