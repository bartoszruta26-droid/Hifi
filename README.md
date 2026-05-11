# 🎧 RPi4 Audio HQ Setup v3.0 - Instrukcja Instalacji i Konfiguracji

Skrypt automatyzujący konfigurację wysokiej jakości audio na Raspberry Pi 4 z zewnętrznym DAC HAT (w tym R38) w systemie Debian Trixie/Bookworm.

**Wersja 3.0** - Modularna, bezpieczna architektura z zaawansowaną konfiguracją jakości audio.

## ✨ Funkcje

- **Obsługa wielu HAT-ów**: R38, HiFiBerry, JustBoom, IQaudio, Allo, Pimoroni i inne
- **Konfiguracja jakości**: Wybór częstotliwości próbkowania (44.1kHz - 768kHz) i głębi bitowej (16/24/32 bit)
- **Resampling najwyższej jakości**: soxr-vhq, soxr, speex-float-10 i inne opcje
- **Optymalizacja PulseAudio + MPD**: Gotowe profile pod Hi-Res Audio
- **Bezpieczeństwo**: Automatyczny backup przed zmianami, przywracanie konfiguracji
- **Testowanie audio**: Wbudowane narzędzia diagnostyczne (speaker-test, paplay)
- **Interfejs dwujęzyczny**: Polski / English
- **Modułowa budowa**: Łatwa rozbudowa i utrzymanie kodu

---

## 📋 Wymagania

- Raspberry Pi 4 (lub kompatybilny model z GPIO)
- DAC HAT (np. R38, HiFiBerry DAC+, JustBoom)
- System: **Debian Trixie** lub **Bookworm** (Raspberry Pi OS)
- Dostęp do internetu (instalacja pakietów)
- Uprawnienia root (sudo)

---

## 🚀 Szybki Start

### 1. Pobranie skryptu

```bash
cd ~
wget https://raw.githubusercontent.com/bartoszruta26-droid/Hifi/main/rpi4_audio_setup_v3.sh
chmod +x rpi4_audio_setup_v3.sh
```

### 2. Uruchomienie

```bash
sudo bash rpi4_audio_setup_v3.sh
```

### 3. Kolejność operacji (zalecana)

1. **Opcja 1** - Zainstaluj pakiety (`mpd`, `pulseaudio`, `sox`, `alsa-utils`)
2. **Opcja 2** - Wykonaj backup obecnych plików
3. **Opcja 4** - Wybierz model HAT + skonfiguruj jakość:
   - Wybierz model HAT (dla R38: opcja 1 "R38 / Generic I2S DAC")
   - Wybierz Sample Rate (zalecane: najwyższa dostępna dla Twojego DAC)
   - Wybierz Bit Depth (zalecane: 32 bit)
   - Wybierz metodę resamplingu (zalecane: soxr-vhq)
   - Wybierz typ miksera (zalecane: hardware)
4. **Opcja 5** - Wygeneruj konfigurację
5. **Opcja 6** - Zastosuj konfigurację i uruchom ponownie

---

## ⚙️ Opcje Menu

| Nr | Funkcja | Opis |
|----|---------|------|
| 0 | 🌐 Zmień język | Przełączanie między polskim a angielskim |
| 1 | 📦 Instalacja pakietów | mpd, pulseaudio, alsa-utils, sox, libsoxr-dev |
| 2 | 💾 Backup | Kopie zapasowe plików konfiguracyjnych |
| 3 | 👁️ Podgląd | Przeglądanie obecnych plików systemowych |
| 4 | ⚙️ Wybierz HAT + Konfiguruj jakość | **Kluczowe**: wybór modelu DAC + parametrów jakości |
| 5 | 🚀 Generuj konfigurację | Przygotowanie plików w katalogu staging |
| 6 | 🔧 Zastosuj konfigurację | Nadpisanie plików systemowych + restart usług |
| 7 | 🔍 Porównaj | Różnice między backupem a nowymi plikami |
| 8 | 🔊 Test dźwięku | speaker-test + paplay diagnostyka |
| 9 | 🔄 Przywróć z backupu | Przywracanie poprzednich konfiguracji |
| 10 | 🛑 Wyjdź | Zakończenie pracy skryptu |

---

## 🎛️ Konfiguracja Jakości (Opcja 4)

Skrypt automatycznie dopasowuje dostępne opcje do możliwości wybranego DAC HAT.

### Częstotliwość próbkowania (Sample Rate)

Dostępne wartości zależą od modelu DAC:

| Wartość | Zastosowanie |
|---------|--------------|
| 44.1 kHz | Standard CD |
| 48 kHz | Wideo, studio |
| 88.2 / 96 kHz | Hi-Res |
| 176.4 / 192 kHz | High End |
| 352.8 / 384 kHz | Ultra Hi-Res |
| 705.6 / 768 kHz | Maksymalna (tylko dla HD DAC) |

> **Uwaga**: Skrypt wyświetla tylko częstotliwości obsługiwane przez wybrany model DAC.

### Głębia bitowa (Bit Depth)

| Wybór | Wartość | Zastosowanie |
|-------|---------|--------------|
| 1 | 16 bit | Standard CD |
| 2 | 24 bit | Hi-Res Audio |
| 3 | 32 bit | Maksymalna jakość (zalecane) |

### Metoda Resamplingu (PulseAudio)

| Wybór | Metoda | Jakość | Obciążenie CPU |
|-------|--------|--------|----------------|
| 1 | speex-float-1 | Niska | Minimalne |
| 2 | speex-float-5 | Dobra | Umiarkowane |
| 3 | speex-float-10 | Bardzo dobra | Średnie |
| 4 | soxr | Wysoka | Większe |
| 5 | soxr-lq | Niska | Mniejsze |
| 6 | **soxr-vhq** | **Bardzo wysoka** (zalecane) | Duże |

### Typ Miksera (Mixer Type)

| Wybór | Typ | Opis |
|-------|-----|------|
| 1 | hardware | Bezpośrednia kontrola sprzętu (zalecane) |
| 2 | software | Mikser programowy PulseAudio |
| 3 | none | Bez miksera - bezpośredni dostęp |

> **Rekomendacja**: Dla RPi4 z DAC HAT wybierz **najwyższą dostępną częstotliwość + 32 bit + soxr-vhq + hardware mixer**.

---

## 🔧 Obsługiwane HAT-y

Skrypt zawiera predefiniowane profile dla:

| Nr | Model DAC | Overlay | Maks. Sample Rate | Maks. Bit Depth |
|----|-----------|---------|-------------------|-----------------|
| 1-2 | R38 / Generic I2S DAC | `hifiberry-dac` | 384 kHz | 32 bit |
| 3 | HiFiBerry DAC+ HD | `hifiberry-dacplushd` | 768 kHz | 32 bit |
| 4 | JustBoom DAC HAT | `justboom-dac` | 384 kHz | 32 bit |
| 5 | IQaudio DAC Pro / DAC+ | `iqaudio-dacplus` | 384 kHz | 32 bit |
| 6 | Pimoroni DAC Shim | `i2s-dac` | 384 kHz | 32 bit |
| 7 | Allo Boss DAC | `allo-boss-dac-pcm512x-audio` | 384 kHz | 32 bit |
| 8 | Allo Katana DAC | `allo-katana-dac-audio` | 768 kHz | 32 bit |
| 9 | Google Voice HAT | `googlevoicehat-soundcard` | 48 kHz | 16 bit |
| 10 | AudioInjector (WM8731) | `audioinjector-wm8731-audio` | 96 kHz | 24 bit |
| 11 | Inny / Własny | ręczne wpisanie | zależne od modelu | zależne od modelu |

> **Uwaga**: Dla R38 i podobnych HAT-ów domyślnie używany jest overlay **`hifiberry-dac`** jako główny/generic DAC.

---

## 📁 Lokalizacje Plików

| Plik | Ścieżka | Opis |
|------|---------|------|
| Boot Config | `/boot/firmware/config.txt` lub `/boot/config.txt` | dtoverlay HAT-a |
| Pulse Daemon | `/etc/pulse/daemon.conf` | Sample rate, resampler, format wyjściowy |
| Pulse Default | `/etc/pulse/default.pa` | Moduły PulseAudio |
| MPD Config | `/etc/mpd.conf` | Konwerter soxr, buffer, replaygain |
| Backup | `~/.rpi_audio_backup/` | Datowane kopie zapasowe |
| Logi | `~/.rpi_audio_script.log` | Dziennik operacji |
| Staging | `/tmp/rpi_audio_staging/` | Tymczasowe pliki konfiguracyjne |

---

## 🛠️ Rozwiązywanie Problemów

### Brak dźwięku po restarcie
1. Sprawdź czy HAT jest wykrywany: `aplay -l`
2. Upewnij się że `dtoverlay` jest poprawny w `/boot/firmware/config.txt`
3. Sprawdź status usług: `systemctl --user status pulseaudio` lub `systemctl status mpd`
4. Sprawdź czy wybrano właściwy typ miksera (spróbuj `hardware` lub `software`)

### Trzaski / przerywanie dźwięku
- Zwiększ bufor w MPD: edytuj `audio_buffer_size` w `/etc/mpd.conf` (np. do 40960)
- Zmień resampler na lżejszy (np. `speex-float-5` lub `soxr-lq`)
- Wyłącz inne aplikacje korzystające z audio
- Sprawdź obciążenie CPU: `top` lub `htop`

### Konflikt z PipeWire
Skrypt oferuje opcję wyłączenia `pipewire-pulse`. Jeśli problemy persistują:
```bash
systemctl --user mask pipewire-pulse.service
systemctl --user stop pipewire-pulse.service
```

### Przywracanie backupu
Użyj opcji 9 w menu skryptu lub ręcznie:
```bash
# Znajdź najnowszy backup
ls -la ~/.rpi_audio_backup/

# Przywróć pliki
cp ~/.rpi_audio_backup/YYYYMMDD_HHMMSS/daemon.conf /etc/pulse/
cp ~/.rpi_audio_backup/YYYYMMDD_HHMMSS/default.pa /etc/pulse/
cp ~/.rpi_audio_backup/YYYYMMDD_HHMMSS/mpd.conf /etc/mpd.conf
cp ~/.rpi_audio_backup/YYYYMMDD_HHMMSS/config.txt* /boot/firmware/

sudo systemctl restart pulseaudio mpd
```

---

## 📊 Przykładowa Konfiguracja (Max Quality)

Po wybraniu opcji **768 kHz + 32 bit + soxr-vhq** (dla DAC HD), pliki będą zawierać:

**`/etc/pulse/daemon.conf`**:
```ini
# === RPi4 Audio HQ Configuration ===
default-sample-format = float64le
default-sample-rate = 768000
alternate-sample-rate = 96000
resample-method = soxr-vhq
flat-volumes = no
realtime-scheduling = yes
rlimit-rtprio = 20
exit-idle-time = -1
log-level = error
```

**`/etc/mpd.conf`**:
```ini
audio_output {
    type            "pulse"
    name            "RPi4 Hi-Res Pulse"
    mixer_type      "hardware"
}
samplerate_converter "soxr"
audio_buffer_size "40960"
replaygain "album"
auto_update "yes"
zeroconf_enabled "no"
```

**`/boot/firmware/config.txt`**:
```txt
# === Audio HAT Configuration ===
dtoverlay=hifiberry-dac
dtparam=audio=off
```

> **Uwaga**: Dla HiFiBerry DAC+ HD użyj `hifiberry-dacplushd`, dla innych modeli odpowiedni overlay z tabeli powyżej.

---

## 📝 Uwagi

- **Wymagany restart** po pierwszym zastosowaniu konfiguracji (wczytanie dtoverlay z config.txt)
- Skrypt tworzy logi w `~/.rpi_audio_script.log`
- Wszystkie backupy są datowane i przechowywane w `~/.rpi_audio_backup/`
- Konfiguracja jest generowana do `/tmp/rpi_audio_staging/` przed zastosowaniem
- **Główny DAC**: Dla R38 i podobnych HAT-ów użyj overlay **`hifiberry-dacplus`** (opcja 1-2 w menu)
- Dla HiFiBerry DAC+ HD użyj `hifiberry-dacplushd` (opcja 3)
- PulseAudio może wymagać restartu jako usługa użytkownika: `systemctl --user restart pulseaudio`
- MPD korzysta z konwertera `soxr` niezależnie od wybranej metody resamplingu PulseAudio

---

## 📄 Licencja

Skrypt udostępniony na licencji MIT. Możesz modyfikować i rozpowszechniać.

---

## 🤝 Wsparcie

Jeśli napotkasz problemy:
1. Sprawdź logi: `cat ~/.rpi_audio_script.log`
2. Zweryfikuj model HAT w dokumentacji producenta
3. Upewnij się że masz aktualny system: `sudo apt update && sudo apt upgrade`
4. Użyj opcji 9 (Przywróć z backupu) aby cofnąć zmiany

---

**Autor**: AI Assistant  
**Wersja**: 3.0 (Modularna)  
**Data**: 2024  
**Struktura**: 
- `rpi4_audio_setup_v3.sh` - główny punkt wejścia
- `lib/core.sh` - rdzeń: stałe, utils, walidacja
- `lib/backup.sh` - backup i przywracanie
- `lib/config_generator.sh` - generowanie plików konfiguracyjnych
- `lib/applier.sh` - bezpieczne aplikowanie konfiguracji
- `lib/ui.sh` - interfejs użytkownika (menu, wybór opcji)
