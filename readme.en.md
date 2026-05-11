# 🎧 RPi4 Audio HQ Setup - Installation and Configuration Guide

Script automating high-quality audio configuration on Raspberry Pi 4 with external DAC HAT (including R38) on Debian Trixie/Bookworm systems.

**Version 3.0** - Modular, safe architecture with advanced audio quality configuration.

## ✨ Features

- **Multiple HAT Support**: R38, HiFiBerry, JustBoom, IQaudio, Allo, Pimoroni and others
- **Quality Configuration**: Sample rate selection (44.1kHz - 768kHz) and bit depth (16/24/32 bit)
- **Highest Quality Resampling**: soxr-vhq, soxr, speex-float-10 and other options
- **PulseAudio + MPD Optimization**: Ready profiles for Hi-Res Audio
- **Safety**: Automatic backup before changes, configuration restore
- **Audio Testing**: Built-in diagnostic tools (speaker-test, paplay)
- **Bilingual Interface**: Polish / English
- **Modular Design**: Easy code expansion and maintenance

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
wget https://raw.githubusercontent.com/bartoszruta26-droid/Hifi/main/rpi4_audio_setup_v3.sh
chmod +x rpi4_audio_setup_v3.sh
```

### 2. Run the script

```bash
sudo bash rpi4_audio_setup_v3.sh
```

### 3. Recommended Operation Order

1. **Option 1** - Install packages (`mpd`, `pulseaudio`, `sox`, `alsa-utils`)
2. **Option 2** - Create backup of current files
3. **Option 4** - Select HAT model + configure quality:
   - Select HAT model (for R38: option 1-2 "R38 / Generic I2S DAC")
   - Select Sample Rate (recommended: highest available for your DAC)
   - Select Bit Depth (recommended: 32 bit)
   - Select resampling method (recommended: soxr-vhq)
   - Select mixer type (recommended: hardware)
4. **Option 5** - Generate configuration
5. **Option 6** - Apply configuration and restart

---

## ⚙️ Menu Options

| No | Function | Description |
|----|----------|-------------|
| 0 | 🌐 Change language | Switch between Polish and English |
| 1 | 📦 Package Installation | mpd, pulseaudio, alsa-utils, sox, libsoxr-dev |
| 2 | 💾 Backup | Backup copies of configuration files |
| 3 | 👁️ Preview | View current system files |
| 4 | ⚙️ Select HAT + Configure Quality | **Key**: DAC model selection + quality parameters |
| 5 | 🚀 Generate Configuration | Prepare files in staging directory |
| 6 | 🔧 Apply Configuration | Overwrite system files + restart services |
| 7 | 🔍 Compare | Differences between backup and new files |
| 8 | 🔊 Sound Test | speaker-test + paplay diagnostics |
| 9 | 🔄 Restore from Backup | Restore previous configurations |
| 10 | 🛑 Exit | End script execution |

---

## 🎛️ Quality Configuration (Option 4)

The script automatically adjusts available options to the capabilities of the selected DAC HAT.

### Sample Rate

Available values depend on the DAC model:

| Value | Use Case |
|-------|----------|
| 44.1 kHz | CD Standard |
| 48 kHz | Video, Studio |
| 88.2 / 96 kHz | Hi-Res |
| 176.4 / 192 kHz | High End |
| 352.8 / 384 kHz | Ultra Hi-Res |
| 705.6 / 768 kHz | Maximum (HD DAC only) |

> **Note**: The script displays only sample rates supported by the selected DAC model.

### Bit Depth

| Selection | Value | Use Case |
|-----------|-------|----------|
| 1 | 16 bit | CD Standard |
| 2 | 24 bit | Hi-Res Audio |
| 3 | 32 bit | Maximum Quality (Recommended) |

### Resampling Method (PulseAudio)

| Selection | Method | Quality | CPU Load |
|-----------|--------|---------|----------|
| 1 | speex-float-1 | Low | Minimal |
| 2 | speex-float-5 | Good | Moderate |
| 3 | speex-float-10 | Very Good | Medium |
| 4 | soxr | High | Higher |
| 5 | soxr-lq | Low | Lower |
| 6 | **soxr-vhq** | **Very High** (Recommended) | Large |

### Mixer Type

| Selection | Type | Description |
|-----------|------|-------------|
| 1 | hardware | Direct hardware control (Recommended) |
| 2 | software | PulseAudio software mixer |
| 3 | none | No mixer - direct access |

> **Recommendation**: For RPi4 with DAC HAT select **highest available frequency + 32 bit + soxr-vhq + hardware mixer**.

---

## 🔧 Supported HATs

The script includes predefined profiles for:

| No | DAC Model | Overlay | Max Sample Rate | Max Bit Depth |
|----|-----------|---------|-----------------|---------------|
| 1-2 | R38 / Generic I2S DAC | `hifiberry-dacplus` | 384 kHz | 32 bit |
| 3 | HiFiBerry DAC+ HD | `hifiberry-dacplushd` | 768 kHz | 32 bit |
| 4 | JustBoom DAC HAT | `justboom-dac` | 384 kHz | 32 bit |
| 5 | IQaudio DAC Pro / DAC+ | `iqaudio-dacplus` | 384 kHz | 32 bit |
| 6 | Pimoroni DAC Shim | `i2s-dac` | 384 kHz | 32 bit |
| 7 | Allo Boss DAC | `allo-boss-dac-pcm512x-audio` | 384 kHz | 32 bit |
| 8 | Allo Katana DAC | `allo-katana-dac-audio` | 768 kHz | 32 bit |
| 9 | Google Voice HAT | `googlevoicehat-soundcard` | 48 kHz | 16 bit |
| 10 | AudioInjector (WM8731) | `audioinjector-wm8731-audio` | 96 kHz | 24 bit |
| 11 | Other / Custom | manual entry | depends on model | depends on model |

> **Note**: For R38 and similar HATs, the default overlay is **`hifiberry-dacplus`** as the main/generic DAC.

---

## 📁 File Locations

| File | Path | Description |
|------|------|-------------|
| Boot Config | `/boot/firmware/config.txt` or `/boot/config.txt` | HAT dtoverlay |
| Pulse Daemon | `/etc/pulse/daemon.conf` | Sample rate, resampler, output format |
| Pulse Default | `/etc/pulse/default.pa` | PulseAudio modules |
| MPD Config | `/etc/mpd.conf` | soxr converter, buffer, replaygain |
| Backup | `~/.rpi_audio_backup/` | Dated backup copies |
| Logs | `~/.rpi_audio_script.log` | Operation log |
| Staging | `/tmp/rpi_audio_staging/` | Temporary configuration files |

---

## 🛠️ Troubleshooting

### No sound after restart
1. Check if HAT is detected: `aplay -l`
2. Ensure `dtoverlay` is correct in `/boot/firmware/config.txt`
3. Check service status: `systemctl --user status pulseaudio` or `systemctl status mpd`
4. Verify correct mixer type is selected (try `hardware` or `software`)

### Crackling / sound interruptions
- Increase buffer in MPD: edit `audio_buffer_size` in `/etc/mpd.conf` (e.g., to 40960)
- Change resampler to a lighter one (e.g., `speex-float-5` or `soxr-lq`)
- Disable other applications using audio
- Check CPU load: `top` or `htop`

### PipeWire conflict
The script offers an option to disable `pipewire-pulse`. If problems persist:
```bash
systemctl --user mask pipewire-pulse.service
systemctl --user stop pipewire-pulse.service
```

### Restoring backup
Use option 9 in the script menu or manually:
```bash
# Find latest backup
ls -la ~/.rpi_audio_backup/

# Restore files
cp ~/.rpi_audio_backup/YYYYMMDD_HHMMSS/daemon.conf /etc/pulse/
cp ~/.rpi_audio_backup/YYYYMMDD_HHMMSS/default.pa /etc/pulse/
cp ~/.rpi_audio_backup/YYYYMMDD_HHMMSS/mpd.conf /etc/mpd.conf
cp ~/.rpi_audio_backup/YYYYMMDD_HHMMSS/config.txt* /boot/firmware/

sudo systemctl restart pulseaudio mpd
```

---

## 📊 Example Configuration (Max Quality)

After selecting **768 kHz + 32 bit + soxr-vhq** (for HD DAC), files will contain:

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
dtoverlay=hifiberry-dacplus
dtparam=audio=off
```

> **Note**: For HiFiBerry DAC+ HD use `hifiberry-dacplushd`, for other models use appropriate overlay from the table above.

---

## 📝 Notes

- **Restart required** after first applying configuration (dtoverlay loading from config.txt)
- Script creates logs in `~/.rpi_audio_script.log`
- All backups are dated and stored in `~/.rpi_audio_backup/`
- Configuration is generated to `/tmp/rpi_audio_staging/` before applying
- **Main DAC**: For R38 and similar HATs use overlay **`hifiberry-dacplus`** (option 1-2 in menu)
- For HiFiBerry DAC+ HD use `hifiberry-dacplushd` (option 3)
- PulseAudio may require restart as user service: `systemctl --user restart pulseaudio`
- MPD uses `soxr` converter regardless of selected PulseAudio resampling method

---

## 📄 License

Script released under MIT license. You can modify and distribute.

---

## 🤝 Support

If you encounter problems:
1. Check logs: `cat ~/.rpi_audio_script.log`
2. Verify HAT model in manufacturer documentation
3. Ensure you have updated system: `sudo apt update && sudo apt upgrade`
4. Use option 9 (Restore from backup) to revert changes

---

**Author**: AI Assistant  
**Version**: 3.0 (Modular)  
**Date**: 2024  
**Structure**: 
- `rpi4_audio_setup_v3.sh` - main entry point
- `lib/core.sh` - core: constants, utils, validation
- `lib/backup.sh` - backup and restore
- `lib/config_generator.sh` - configuration file generation
- `lib/applier.sh` - safe configuration application
- `lib/ui.sh` - user interface (menu, options selection)
