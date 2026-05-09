# 🎧 RPi4 Audio HQ Setup - Instrukcja Instalacji i Konfiguracji

Skrypt automatyzujący konfigurację wysokiej jakości audio na Raspberry Pi 4 z zewnętrznym DAC HAT (w tym R38) w systemie Debian Trixie/Bookworm.

## ✨ Funkcje

- **Obsługa wielu HAT-ów**: R38, HiFiBerry, JustBoom, IQaudio, Allo, Pimoroni i inne
- **Konfiguracja jakości**: Wybór częstotliwości próbkowania (44.1kHz - 768kHz)
- **Resampling najwyższej jakości**: soxr highest, speex-float-10 i inne opcje
- **Optymalizacja PulseAudio + MPD**: Gotowe profile podHi-Res Audio
- **Bezpieczeństwo**: Automatyczny backup przed zmianami
- **Testowanie audio**: Wbudowane narzędzia diagnostyczne

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
wget https://raw.githubusercontent.com/bartoszruta26-droid/Hifi/main/rpi4_audio_setup.sh
chmod +x rpi4_audio_setup.sh
```

### 2. Uruchomienie

```bash
sudo bash rpi4_audio_setup.sh
```

### 3. Kolejność operacji (zalecana)

1. **Opcja 1** - Zainstaluj pakiety (`mpd`, `pulseaudio`, `sox`)
2. **Opcja 2** - Wykonaj backup obecnych plików
3. **Opcja 4** - Wygeneruj konfigurację:
   - Wybierz model HAT (dla R38: opcja 1 "Justboom DAC")
   - Wybierz jakość (zalecane: 384 kHz + soxr highest)
4. **Opcja 5** - Zastosuj konfigurację i uruchom ponownie

---

## ⚙️ Opcje Menu

| Nr | Funkcja | Opis |
|----|---------|------|
| 1 | 📦 Instalacja pakietów | mpd, pulseaudio, alsa-utils, sox, libsoxr-dev |
| 2 | 💾 Backup | Kopie zapasowe plików konfiguracyjnych |
| 3 | 👁️ Podgląd | Przeglądanie obecnych plików systemowych |
| 4 | ⚙️ Generuj konfigurację | **Kluczowe**: wybór HAT + parametrów jakości |
| 5 | 🚀 Zastosuj i restart | Nadpisanie plików + reboot (wymagane dla HAT) |
| 6 | 🔍 Porównaj | Różnice między backupem a nowymi plikami |
| 7 | 🔊 Test dźwięku | speaker-test + paplay diagnostyka |
| 8 | 🛑 Wyjdź | Zakończenie pracy skryptu |

---

## 🎛️ Konfiguracja Jakości (Opcja 4)

### Częstotliwość próbkowania (Sample Rate)

| Wybór | Wartość | Zastosowanie |
|-------|---------|--------------|
| 1 | 44.1 kHz | Standard CD |
| 2 | 48 kHz | Wideo, studio |
| 3 | 96 kHz | Hi-Res |
| 4 | 192 kHz | High End |
| 5 | **384 kHz** | **Ultra Hi-Res (zalecane)** |
| 6 | 768 kHz | Maksymalna (eksperymentalne) |

### Metoda Resamplingu (PulseAudio)

| Wybór | Metoda | Jakość | Obciążenie CPU |
|-------|--------|--------|----------------|
| 1 | speex-float-1 | Niska | Minimalne |
| 2 | speex-float-5 | Dobra | Umiarkowane |
| 3 | speex-float-10 | Bardzo dobra | Średnie |
| 4 | soxr | Wysoka | Większe |
| 5 | soxr very high | Studyjna | Duże |
| 6 | **soxr highest** | **Maksymalna** | **Największe** |

> **Rekomendacja**: Dla RPi4 wybierz **384 kHz + soxr highest**. Procesor RPi4 bez problemu obsługuje tę konfigurację.

---

## 🔧 Obsługiwane HAT-y

Skrypt zawiera predefiniowane profile dla:

1. **R38 / Generic I2S DAC** (używa `justboom-dac`)
2. HiFiBerry DAC+ / Pro / Zero
3. HiFiBerry DAC+ HD
4. JustBoom DAC HAT
5. IQaudio DAC Pro / DAC+
6. Pimoroni DACSHIM
7. Allo Boss DAC
8. Allo Katana DAC
9. Google Voice HAT
10. Audioinjector WM8804
11. Własny (ręczne wpisanie dtoverlay)

---

## 📁 Lokalizacje Plików

| Plik | Ścieżka | Opis |
|------|---------|------|
| Boot Config | `/boot/firmware/config.txt` | dtoverlay HAT-a |
| Pulse Daemon | `/etc/pulse/daemon.conf` | Sample rate, resampler |
| Pulse Default | `/etc/pulse/default.pa` | Moduły PulseAudio |
| MPD Config | `/etc/mpd.conf` | Konwerter soxr, buffer |
| Backup | `~/.rpi_audio_backup/` | Datowane kopie zapasowe |
| Logi | `~/.rpi_audio_script.log` | Dziennik operacji |

---

## 🛠️ Rozwiązywanie Problemów

### Brak dźwięku po restarcie
1. Sprawdź czy HAT jest wykrywany: `aplay -l`
2. Upewnij się że `dtoverlay` jest poprawny w `/boot/firmware/config.txt`
3. Sprawdź status usług: `systemctl status mpd pulseaudio`

### Trzaski / przerywanie dźwięku
- Zwiększ bufor w MPD: edytuj `audio_buffer_size` w `/etc/mpd.conf`
- Zmień resampler na lżejszy (np. `speex-float-5`)
- Wyłącz inne aplikacje korzystające z audio

### Konflikt z PipeWire
Skrypt automatycznie wyłącza `pipewire-pulse`. Jeśli problemy persistują:
```bash
systemctl --user mask pipewire-pulse.service
systemctl --user stop pipewire-pulse.service
```

### Przywracanie backupu
```bash
cp ~/.rpi_audio_backup/YYYYMMDD_HHMMSS/daemon.conf /etc/pulse/
cp ~/.rpi_audio_backup/YYYYMMDD_HHMMSS/mpd.conf /etc/mpd.conf
sudo systemctl restart pulseaudio mpd
```

---

## 📊 Przykładowa Konfiguracja (Max Quality)

Po wybraniu opcji **384 kHz + soxr highest**, pliki będą zawierać:

**`/etc/pulse/daemon.conf`**:
```ini
default-sample-format = float32le
default-sample-rate = 384000
resample-method = soxr highest
avoid-resampling = yes
realtime-scheduling = yes
```

**`/etc/mpd.conf`**:
```ini
audio_output {
    type            "pulse"
    name            "RPi4 Hi-Res Pulse"
    mixer_type      "software"
}
samplerate_converter "soxr highest"
audio_buffer_size "20480"
```

**`/boot/firmware/config.txt`**:
```txt
dtoverlay=justboom-dac
dtparam=audio=off
```

---

## 📝 Uwagi

- **Wymagany restart** po pierwszym zastosowaniu konfiguracji (wczytanie dtoverlay)
- Skrypt tworzy logi w `~/.rpi_audio_script.log`
- Wszystkie backupy są datowane i przechowywane w `~/.rpi_audio_backup/`
- Dla R38 HAT najczęściej działa overlay `justboom-dac` lub `generic`

---

## 📄 Licencja

Skrypt udostępniony na licencji MIT. Możesz modyfikować i rozpowszechniać.

---

## 🤝 Wsparcie

Jeśli napotkasz problemy:
1. Sprawdź logi: `cat ~/.rpi_audio_script.log`
2. Zweryfikuj model HAT w dokumentacji producenta
3. Upewnij się że masz aktualny system: `sudo apt update && sudo apt upgrade`

---

**Autor**: AI Assistant  
**Wersja**: 2.0  
**Data**: 2024
