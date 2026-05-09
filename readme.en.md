# 🎧 RPi4 Audio HQ Setup - Installation and Configuration Guide

Script automating high-quality audio configuration on Raspberry Pi 4 with external DAC HAT (including R38) on Debian Trixie/Bookworm systems.

## ✨ Features

- **Multiple HAT Support**: R38, HiFiBerry, JustBoom, IQaudio, Allo, Pimoroni and others
- **Quality Configuration**: Sample rate selection (44.1kHz - 768kHz)
- **Highest Quality Resampling**: soxr highest, speex-float-10 and other options
- **PulseAudio + MPD Optimization**: Ready profiles for Hi-Res Audio
- **Safety**: Automatic backup before changes
- **Audio Testing**: Built-in diagnostic tools

---

## 📋 Requirements

- Raspberry Pi 4 (or compatible model with GPIO)
- DAC HAT (e.g., R38, HiFiBerry DAC+, JustBoom)
- System: **Debian Trixie** or **Bookworm** (Raspberry Pi OS)
- Internet access (package installation)
- Root privileges (sudo)

---

## 🚀 Quick Start

### 1. Download the script

```bash
cd ~
wget https://raw.githubusercontent.com/bartoszruta26-droid/Hifi/main/rpi4_audio_setup.sh
chmod +x rpi4_audio_setup.sh
```

### 2. Run the script

```bash
sudo bash rpi4_audio_setup.sh
```

### 3. Recommended Operation Order

1. **Option 1** - Install packages (`mpd`, `pulseaudio`, `sox`)
2. **Option 2** - Create backup of current files
3. **Option 4** - Generate configuration:
   - Select HAT model (for R38: option 1 "Justboom DAC")
   - Select quality (recommended: 384 kHz + soxr highest)
4. **Option 5** - Apply configuration and restart

---

## ⚙️ Menu Options

| No | Function | Description |
|----|----------|-------------|
| 1 | 📦 Package Installation | mpd, pulseaudio, alsa-utils, sox, libsoxr-dev |
| 2 | 💾 Backup | Backup copies of configuration files |
| 3 | 👁️ Preview | View current system files |
| 4 | ⚙️ Generate Configuration | **Key**: HAT selection + quality parameters |
| 5 | 🚀 Apply and Restart | Overwrite files + reboot (required for HAT) |
| 6 | 🔍 Compare | Differences between backup and new files |
| 7 | 🔊 Sound Test | speaker-test + paplay diagnostics |
| 8 | 🛑 Exit | End script execution |

---

## 🎛️ Quality Configuration (Option 4)

### Sample Rate

| Selection | Value | Use Case |
|-----------|-------|----------|
| 1 | 44.1 kHz | CD Standard |
| 2 | 48 kHz | Video, Studio |
| 3 | 96 kHz | Hi-Res |
| 4 | 192 kHz | High End |
| 5 | **384 kHz** | **Ultra Hi-Res (recommended)** |
| 6 | 768 kHz | Maximum (experimental) |

### Resampling Method (PulseAudio)

| Selection | Method | Quality | CPU Load |
|-----------|--------|---------|----------|
| 1 | speex-float-1 | Low | Minimal |
| 2 | speex-float-5 | Good | Moderate |
| 3 | speex-float-10 | Very Good | Medium |
| 4 | soxr | High | Higher |
| 5 | soxr very high | Studio | Large |
| 6 | **soxr highest** | **Maximum** | **Highest** |

> **Recommendation**: For RPi4, select **384 kHz + soxr highest**. The RPi4 processor handles this configuration without issues.

---

## 🔧 Supported HATs

The script includes predefined profiles for:

1. **R38 / Generic I2S DAC** (uses `justboom-dac`)
2. HiFiBerry DAC+ / Pro / Zero
3. HiFiBerry DAC+ HD
4. JustBoom DAC HAT
5. IQaudio DAC Pro / DAC+
6. Pimoroni DACSHIM
7. Allo Boss DAC
8. Allo Katana DAC
9. Google Voice HAT
10. Audioinjector WM8804
11. Custom (manual dtoverlay entry)

---

## 📁 File Locations

| File | Path | Description |
|------|------|-------------|
| Boot Config | `/boot/firmware/config.txt` | HAT dtoverlay |
| Pulse Daemon | `/etc/pulse/daemon.conf` | Sample rate, resampler |
| Pulse Default | `/etc/pulse/default.pa` | PulseAudio modules |
| MPD Config | `/etc/mpd.conf` | soxr converter, buffer |
| Backup | `~/.rpi_audio_backup/` | Dated backup copies |
| Logs | `~/.rpi_audio_script.log` | Operation log |

---

## 🛠️ Troubleshooting

### No sound after restart
1. Check if HAT is detected: `aplay -l`
2. Ensure `dtoverlay` is correct in `/boot/firmware/config.txt`
3. Check service status: `systemctl status mpd pulseaudio`

### Crackling / sound interruptions
- Increase buffer in MPD: edit `audio_buffer_size` in `/etc/mpd.conf`
- Change resampler to a lighter one (e.g., `speex-float-5`)
- Disable other applications using audio

### PipeWire conflict
The script automatically disables `pipewire-pulse`. If problems persist:
```bash
systemctl --user mask pipewire-pulse.service
systemctl --user stop pipewire-pulse.service
```

### Restoring backup
```bash
cp ~/.rpi_audio_backup/YYYYMMDD_HHMMSS/daemon.conf /etc/pulse/
cp ~/.rpi_audio_backup/YYYYMMDD_HHMMSS/mpd.conf /etc/mpd.conf
sudo systemctl restart pulseaudio mpd
```

---

## 📊 Example Configuration (Max Quality)

After selecting **384 kHz + soxr highest**, files will contain:

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

## 📝 Notes

- **Restart required** after first applying configuration (dtoverlay loading)
- Script creates logs in `~/.rpi_audio_script.log`
- All backups are dated and stored in `~/.rpi_audio_backup/`
- For R38 HAT, `justboom-dac` or `generic` overlay most commonly works

---

## 📄 License

Script released under MIT license. You can modify and distribute.

---

## 🤝 Support

If you encounter problems:
1. Check logs: `cat ~/.rpi_audio_script.log`
2. Verify HAT model in manufacturer documentation
3. Ensure you have updated system: `sudo apt update && sudo apt upgrade`

---

**Author**: AI Assistant  
**Version**: 2.0  
**Date**: 2024
