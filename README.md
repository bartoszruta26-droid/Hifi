# 🎧 RPi4 Audio HQ Setup v3.0

<div align="center">

![Version](https://img.shields.io/badge/version-3.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Shell](https://img.shields.io/badge/shell-bash-yellow.svg)
![Platform](https://img.shields.io/badge/platform-Raspberry%20Pi%204-orange.svg)

**Skrypt automatyzujący konfigurację wysokiej jakości audio na Raspberry Pi 4 z zewnętrznym DAC HAT**

[📋 Wymagania](#-wymagania) • [🚀 Szybki Start](#-szybki-start) • [⚙️ Opcje Menu](#️-opcje-menu) • [🎛️ Konfiguracja Jakości](#️-konfiguracja-jakości) • [🔧 Obsługiwane HAT-y](#-obsługiwane-haty) • [🛠️ Rozwiązywanie Problemów](#️-rozwiązywanie-problemów)

</div>

---

## ✨ Funkcje

<table>
<tr>
<td valign="top" width="50%">

### 🎯 Główne Możliwości

- **🔌 Obsługa wielu HAT-ów**: R38, HiFiBerry, JustBoom, IQaudio, Allo, Pimoroni i inne
- **🎚️ Konfiguracja jakości**: Częstotliwość próbkowania (44.1kHz - 768kHz) i głębia bitowa (16/24/32 bit)
- **🔄 Resampling najwyższej jakości**: soxr-vhq, soxr, speex-float-10 i inne opcje
- **⚡ Optymalizacja PulseAudio + MPD**: Gotowe profile pod Hi-Res Audio

</td>
<td valign="top" width="50%">

### 🛡️ Bezpieczeństwo i Wygoda

- **💾 Automatyczny backup**: Kopie zapasowe przed zmianami, przywracanie konfiguracji
- **🔊 Testowanie audio**: Wbudowane narzędzia diagnostyczne (speaker-test, paplay)
- **🌐 Interfejs dwujęzyczny**: Polski / English
- **🧩 Modułowa budowa**: Łatwa rozbudowa i utrzymanie kodu

</td>
</tr>
</table>

---

## 📋 Wymagania

<div align="center">

| <img src="https://www.raspberrypi.org/wp-content/uploads/2020/10/raspberry-pi-4-model-b.jpg" width="80" alt="RPi4"><br>**Raspberry Pi 4**<br>(lub kompatybilny z GPIO) | <img src="https://example.com/dac-hat-icon.png" width="80" alt="DAC HAT"><br>**DAC HAT**<br>(R38, HiFiBerry, JustBoom) | <img src="https://www.debian.org/logos/openlogo-nd-100.png" width="80" alt="Debian"><br>**Debian Trixie/Bookworm**<br>(Raspberry Pi OS) | <img src="https://example.com/root-icon.png" width="80" alt="Root"><br>**Uprawnienia root**<br>(sudo) |
|:---:|:---:|:---:|:---:|

</div>

---

## 🚀 Szybki Start

### 1️⃣ Pobranie skryptu

```bash
cd ~
wget https://raw.githubusercontent.com/bartoszruta26-droid/Hifi/main/rpi4_audio_setup_v3.sh
chmod +x rpi4_audio_setup_v3.sh
```

### 2️⃣ Uruchomienie

```bash
sudo bash rpi4_audio_setup_v3.sh
```

### 3️⃣ Kolejność operacji (zalecana)

```mermaid
graph LR
    A[Opcja 1<br>Instalacja pakietów] --> B[Opcja 2<br>Backup]
    B --> C[Opcja 4<br>Wybierz HAT + Konfiguruj]
    C --> D[Opcja 5<br>Generuj konfigurację]
    D --> E[Opcja 6<br>Zastosuj i restart]
```

---

## ⚙️ Opcje Menu

| Nr | Ikona | Funkcja | Opis |
|:--:|:-----:|---------|------|
| 0 | 🌐 | Zmień język | Przełączanie między polskim a angielskim |
| 1 | 📦 | Instalacja pakietów | mpd, pulseaudio, alsa-utils, sox, libsoxr-dev |
| 2 | 💾 | Backup | Kopie zapasowe plików konfiguracyjnych |
| 3 | 👁️ | Podgląd | Przeglądanie obecnych plików systemowych |
| 4 | ⚙️ | Wybierz HAT + Konfiguruj jakość | **Kluczowe**: wybór modelu DAC + parametrów jakości |
| 5 | 🚀 | Generuj konfigurację | Przygotowanie plików w katalogu staging |
| 6 | 🔧 | Zastosuj konfigurację | Nadpisanie plików systemowych + restart usług |
| 7 | 🔍 | Porównaj | Różnice między backupem a nowymi plikami |
| 8 | 🔊 | Test dźwięku | speaker-test + paplay diagnostyka |
| 9 | 🔄 | Przywróć z backupu | Przywracanie poprzednich konfiguracji |
| 10 | 🛑 | Wyjdź | Zakończenie pracy skryptu |

---

## 🎛️ Konfiguracja Jakości (Opcja 4)

Skrypt automatycznie dopasowuje dostępne opcje do możliwości wybranego DAC HAT.

### 📊 Częstotliwość próbkowania (Sample Rate)

| Wartość | Zastosowanie | Jakość |
|:-------:|--------------|--------|
| 44.1 kHz | Standard CD | ⭐⭐⭐ |
| 48 kHz | Wideo, studio | ⭐⭐⭐⭐ |
| 88.2 / 96 kHz | Hi-Res | ⭐⭐⭐⭐⭐ |
| 176.4 / 192 kHz | High End | ⭐⭐⭐⭐⭐⭐ |
| 352.8 / 384 kHz | Ultra Hi-Res | ⭐⭐⭐⭐⭐⭐⭐ |
| 705.6 / 768 kHz | Maksymalna (HD DAC) | ⭐⭐⭐⭐⭐⭐⭐⭐ |

> 💡 **Porada**: Skrypt wyświetla tylko częstotliwości obsługiwane przez wybrany model DAC.

### 🎚️ Głębia bitowa (Bit Depth)

| Wybór | Wartość | Zastosowanie | Jakość |
|:-----:|:-------:|--------------|--------|
| 1 | 16 bit | Standard CD | ⭐⭐⭐ |
| 2 | 24 bit | Hi-Res Audio | ⭐⭐⭐⭐⭐ |
| 3 | 32 bit | **Maksymalna jakość** ✅ | ⭐⭐⭐⭐⭐⭐⭐ |

### 🔄 Metoda Resamplingu (PulseAudio)

| Wybór | Metoda | Jakość | Obciążenie CPU | Rekomendacja |
|:-----:|--------|--------|----------------|--------------|
| 1 | speex-float-1 | Niska | Minimalne | ⚡ Słaby sprzęt |
| 2 | speex-float-5 | Dobra | Umiarkowane | ⚖️ Kompromis |
| 3 | speex-float-10 | Bardzo dobra | Średnie | 👍 Dobry wybór |
| 4 | soxr | Wysoka | Większe | 🎯 Hi-Res |
| 5 | soxr-lq | Niska | Mniejsze | ⚡ Oszczędność |
| 6 | **soxr-vhq** | **Bardzo wysoka** | Duże | 🏆 **Zalecane** |

### 🎚️ Typ Miksera (Mixer Type)

| Wybór | Typ | Opis | Rekomendacja |
|:-----:|-----|------|--------------|
| 1 | **hardware** | Bezpośrednia kontrola sprzętu | ✅ **Zalecane** |
| 2 | software | Mikser programowy PulseAudio | 🟡 Alternatywa |
| 3 | none | Bez miksera - bezpośredni dostęp | ⚠️ Zaawansowane |

> 🎯 **Rekomendacja**: Dla RPi4 z DAC HAT wybierz **najwyższą dostępną częstotliwość + 32 bit + soxr-vhq + hardware mixer**.

---

## 🔧 Obsługiwane HAT-y

| Nr | Model DAC | Overlay | Max Sample Rate | Max Bit Depth | Status |
|:--:|-----------|---------|:---------------:|:-------------:|:------:|
| 1-2 | R38 / Generic I2S DAC | `hifiberry-dac` | 384 kHz | 32 bit | ✅ |
| 3 | HiFiBerry DAC+ HD | `hifiberry-dacplushd` | 768 kHz | 32 bit | ✅ |
| 4 | JustBoom DAC HAT | `justboom-dac` | 384 kHz | 32 bit | ✅ |
| 5 | IQaudio DAC Pro / DAC+ | `iqaudio-dacplus` | 384 kHz | 32 bit | ✅ |
| 6 | Pimoroni DAC Shim | `i2s-dac` | 384 kHz | 32 bit | ✅ |
| 7 | Allo Boss DAC | `allo-boss-dac-pcm512x-audio` | 384 kHz | 32 bit | ✅ |
| 8 | Allo Katana DAC | `allo-katana-dac-audio` | 768 kHz | 32 bit | ✅ |
| 9 | Google Voice HAT | `googlevoicehat-soundcard` | 48 kHz | 16 bit | ✅ |
| 10 | AudioInjector (WM8731) | `audioinjector-wm8731-audio` | 96 kHz | 24 bit | ✅ |
| 11 | Inny / Własny | ręczne wpisanie | zależne | zależne | 🔧 |

> ℹ️ **Uwaga**: Dla R38 i podobnych HAT-ów domyślnie używany jest overlay **`hifiberry-dac`** jako główny/generic DAC.

---

## 📁 Lokalizacje Plików

| Plik | Ścieżka | Opis |
|------|---------|------|
| 🥾 Boot Config | `/boot/firmware/config.txt` lub `/boot/config.txt` | dtoverlay HAT-a |
| 🔊 Pulse Daemon | `/etc/pulse/daemon.conf` | Sample rate, resampler, format wyjściowy |
| 🔊 Pulse Default | `/etc/pulse/default.pa` | Moduły PulseAudio |
| 🎵 MPD Config | `/etc/mpd.conf` | Konwerter soxr, buffer, replaygain |
| 💾 Backup | `~/.rpi_audio_backup/` | Datowane kopie zapasowe |
| 📝 Logi | `~/.rpi_audio_script.log` | Dziennik operacji |
| 📂 Staging | `/tmp/rpi_audio_staging/` | Tymczasowe pliki konfiguracyjne |

---

## 🛠️ Rozwiązywanie Problemów

<details>
<summary><strong>🔇 Brak dźwięku po restarcie</strong></summary>

1. Sprawdź czy HAT jest wykrywany:
   ```bash
   aplay -l
   ```
2. Upewnij się że `dtoverlay` jest poprawny w `/boot/firmware/config.txt`
3. Sprawdź status usług:
   ```bash
   systemctl --user status pulseaudio
   systemctl status mpd
   ```
4. Sprawdź czy wybrano właściwy typ miksera (spróbuj `hardware` lub `software`)

</details>

<details>
<summary><strong>💥 Trzaski / przerywanie dźwięku</strong></summary>

- Zwiększ bufor w MPD: edytuj `audio_buffer_size` w `/etc/mpd.conf` (np. do 40960)
- Zmień resampler na lżejszy (np. `speex-float-5` lub `soxr-lq`)
- Wyłącz inne aplikacje korzystające z audio
- Sprawdź obciążenie CPU:
  ```bash
  top
  htop
  ```

</details>

<details>
<summary><strong>⚔️ Konflikt z PipeWire</strong></summary>

Skrypt oferuje opcję wyłączenia `pipewire-pulse`. Jeśli problemy persistują:

```bash
systemctl --user mask pipewire-pulse.service
systemctl --user stop pipewire-pulse.service
```

</details>

<details>
<summary><strong>🔄 Przywracanie backupu</strong></summary>

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

</details>

---

## 📊 Przykładowa Konfiguracja (Max Quality)

Po wybraniu opcji **768 kHz + 32 bit + soxr-vhq** (dla DAC HD), pliki będą zawierać:

<details>
<summary><strong>📄 /etc/pulse/daemon.conf</strong></summary>

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

</details>

<details>
<summary><strong>📄 /etc/mpd.conf</strong></summary>

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

</details>

<details>
<summary><strong>📄 /boot/firmware/config.txt</strong></summary>

```txt
# === Audio HAT Configuration ===
dtoverlay=hifiberry-dac
dtparam=audio=off
```

</details>

> ⚠️ **Uwaga**: Dla HiFiBerry DAC+ HD użyj `hifiberry-dacplushd`, dla innych modeli odpowiedni overlay z tabeli powyżej.

---

## 🔑 Najważniejsze Zmiany w Konfiguracji

### 🔊 PulseAudio (`/etc/pulse/daemon.conf`)

| Parametr | Domyślnie | Hi-Res | Cel Zmiany |
|----------|-----------|--------|------------|
| `default-sample-format` | `s16le` | `float64le` | Maksymalna precyzja przetwarzania |
| `default-sample-rate` | `44100` / `48000` | `768000` | Obsługa Hi-Res Audio |
| `resample-method` | `speex-float-1` | `soxr-vhq` | Najwyższa jakość resamplingu |
| `flat-volumes` | `yes` | `no` | Lepsza kontrola głośności |
| `realtime-scheduling` | `no` | `yes` | Priorytet czasu rzeczywistego |
| `exit-idle-time` | `30` | `-1` | Bez wyłączania (ciągła gotowość) |

### 🎵 MPD (`/etc/mpd.conf`)

| Parametr | Domyślnie | Hi-Res | Cel Zmiany |
|----------|-----------|--------|------------|
| `audio_output.type` | `alsa` / `pulse` | `pulse` | Integracja z PulseAudio |
| `mixer_type` | `software` | `hardware` | Bezpośrednia kontrola sprzętowa |
| `samplerate_converter` | brak / `libsamplerate` | `soxr` | Najwyższa jakość konwersji |
| `audio_buffer_size` | `8192` | `40960` | Większy bufor = mniej przerwań |
| `replaygain` | `off` | `album` | Normalizacja głośności albumów |
| `zeroconf_enabled` | `yes` | `no` | Wyłączenie auto-discovery (bezpieczeństwo) |

### 🥾 Boot Config (`/boot/firmware/config.txt`)

| Parametr | Domyślnie | Nowa Wartość | Cel Zmiany |
|----------|-----------|--------------|------------|
| `dtoverlay` | brak | `hifiberry-dac` | Aktywacja DAC HAT |
| `dtparam=audio` | `on` | `off` | Wyłączenie onboard audio |
| `dtparam=i2c_arm` | `off` | `on` | Włączenie interfejsu I2C dla komunikacji z DAC |
| `dtparam=i2c_baudrate` | - | `400000` | Prędkość magistrali I2C (400kHz) |

> 💡 **Uwaga**: Overlay `dtoverlay=hifiberry-dac` automatycznie włącza interfejs **I2S** do przesyłania dźwięku wysokiej jakości. Interfejs **I2C** jest jawnie włączany przez `dtparam=i2c_arm=on` do konfiguracji rejestrów DAC.

---

## 📝 Uwagi

- 🔄 **Wymagany restart** po pierwszym zastosowaniu konfiguracji (wczytanie dtoverlay z config.txt)
- 📝 Skrypt tworzy logi w `~/.rpi_audio_script.log`
- 💾 Wszystkie backupy są datowane i przechowywane w `~/.rpi_audio_backup/`
- 📂 Konfiguracja jest generowana do `/tmp/rpi_audio_staging/` przed zastosowaniem
- 🎯 **Główny DAC**: Dla R38 i podobnych HAT-ów użyj overlay **`hifiberry-dacplus`** (opcja 1-2 w menu)
- 🔊 Dla HiFiBerry DAC+ HD użyj `hifiberry-dacplushd` (opcja 3)
- ⚡ PulseAudio może wymagać restartu jako usługa użytkownika: `systemctl --user restart pulseaudio`
- 🎵 MPD korzysta z konwertera `soxr` niezależnie od wybranej metody resamplingu PulseAudio

---

## 🤝 Wsparcie

Jeśli napotkasz problemy:

1. 📝 Sprawdź logi: `cat ~/.rpi_audio_script.log`
2. 📖 Zweryfikuj model HAT w dokumentacji producenta
3. ⬆️ Upewnij się że masz aktualny system: `sudo apt update && sudo apt upgrade`
4. 🔄 Użyj opcji 9 (Przywróć z backupu) aby cofnąć zmiany

---

<div align="center">

### 📄 Licencja

Skrypt udostępniony na licencji **MIT**. Możesz modyfikować i rozpowszechniać.

---

**Autor**: AI Assistant  
**Wersja**: 3.0 (Modularna)  
**Data**: 2024  

### 🏗️ Struktura Projektu

```
rpi4_audio_setup_v3.sh          # Główny punkt wejścia
├── lib/
│   ├── core.sh                 # Rdzeń: stałe, utils, walidacja
│   ├── backup.sh               # Backup i przywracanie
│   ├── config_generator.sh     # Generowanie plików konfiguracyjnych
│   ├── applier.sh              # Bezpieczne aplikowanie konfiguracji
│   └── ui.sh                   # Interfejs użytkownika (menu, wybór opcji)
└── tests/
    └── unit_tests.sh           # Testy jednostkowe
```

</div>
