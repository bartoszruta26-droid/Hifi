#!/usr/bin/env bash
# shellcheck shell=bash
# ==========================================
# RPi4 Audio Setup - Backup Module
# Moduł backupu: tworzenie kopii zapasowych plików systemowych
# ==========================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/core.sh"

# ==========================================
# FUNKCJE BACKUPU
# ==========================================

backup_files() {
    local ts dir files_to_backup=()
    ts=$(date +%Y%m%d_%H%M%S)
    dir="$BACKUP_BASE/$ts"
    
    mkdir -p "$dir"
    chmod 700 "$dir"
    
    log "Creating backup in $dir"
    echo -e "${COLORS[YELLOW]}📦 Tworzenie kopii zapasowej...${COLORS[NC]}"
    
    # Lista plików do backupu
    files_to_backup=(
        "$BOOT_CFG_DEFAULT"
        "$BOOT_CFG_LEGACY"
        "$PULSE_DAEMON"
        "$PULSE_DEFAULT"
        "$MPD_CONF"
    )
    
    local backed_up=0
    local skipped=0
    
    for f in "${files_to_backup[@]}"; do
        if [ -f "$f" ]; then
            cp -a "$f" "$dir/"
            log "Backup: $f -> $dir/"
            echo -e "  ${COLORS[GREEN]}✅${COLORS[NC]} $f"
            ((backed_up++))
        else
            echo -e "  ${COLORS[YELLOW]}⚠️${COLORS[NC]} $f (nie istnieje, pominięto)"
            ((skipped++))
        fi
    done
    
    if [[ $backed_up -eq 0 ]]; then
        log "No files were backed up" "WARN"
        echo -e "${COLORS[YELLOW]}⚠️  Żadne pliki nie zostały zapisane w backupie${COLORS[NC]}"
    else
        echo -e "${COLORS[GREEN]}✅ Backup utworzony w: $dir ($backed_up plików)${COLORS[NC]}"
        log "Backup completed: $backed_up files, $skipped skipped" "SUCCESS"
    fi
    
    echo "$dir"
}

# Przywracanie z backupu
restore_from_backup() {
    local backup_dir="${1:-}"
    
    if [[ -z "$backup_dir" ]]; then
        # Znajdź najnowszy backup
        backup_dir=$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d -printf "%T@ %p\n" 2>/dev/null | sort -nr | head -n1 | cut -d" " -f2-)
    fi
    
    if [[ -z "$backup_dir" ]] || [[ ! -d "$backup_dir" ]]; then
        log "No backup found to restore" "ERROR"
        echo -e "${COLORS[RED]}⚠️  Nie znaleziono backupu do przywrócenia${COLORS[NC]}"
        return 1
    fi
    
    echo -e "${COLORS[YELLOW]}🔄 Przywracanie z backupu: $backup_dir${COLORS[NC]}"
    
    local restored=0
    
    for f in "$backup_dir"/*; do
        if [ -f "$f" ]; then
            local filename
            filename=$(basename "$f")
            local target=""
            
            # Określ docelową ścieżkę na podstawie nazwy pliku
            case "$filename" in
                config.txt*)
                    if [ -d "/boot/firmware" ]; then
                        target="$BOOT_CFG_DEFAULT"
                    else
                        target="$BOOT_CFG_LEGACY"
                    fi
                    ;;
                daemon.conf*) target="$PULSE_DAEMON" ;;
                default.pa*) target="$PULSE_DEFAULT" ;;
                mpd.conf*) target="$MPD_CONF" ;;
                *) 
                    log "Unknown file type: $filename" "WARN"
                    continue
                    ;;
            esac
            
            if [[ -n "$target" ]]; then
                cp -a "$f" "$target"
                log "Restored: $f -> $target"
                echo -e "  ${COLORS[GREEN]}✅${COLORS[NC]} Restored: $filename -> $target"
                ((restored++))
            fi
        fi
    done
    
    if [[ $restored -gt 0 ]]; then
        echo -e "${COLORS[GREEN]}✅ Przywrócono $restored plików${COLORS[NC]}"
        log "Restore completed: $restored files" "SUCCESS"
        
        echo -e "${COLORS[YELLOW]}⚠️  Wymagany restart systemu dla pełnego zastosowania zmian${COLORS[NC]}"
        read -r -p "Czy chcesz teraz zrestartować system? (tak/nie): " reboot_now
        if [[ "$reboot_now" == "tak" ]]; then
            systemctl reboot
        fi
    else
        log "No files were restored" "WARN"
        echo -e "${COLORS[YELLOW]}⚠️  Żadne pliki nie zostały przywrócone${COLORS[NC]}"
        return 1
    fi
    
    return 0
}

# Porównywanie plików
compare_files() {
    local orig="$1"
    local new="$2"
    local diff_file="$STAGING_DIR/diff_output.txt"
    
    if [[ ! -f "$orig" ]]; then
        echo -e "${COLORS[RED]}⚠️  Brak oryginalnego pliku: $orig${COLORS[NC]}"
        return 1
    fi
    
    if [[ ! -f "$new" ]]; then
        echo -e "${COLORS[RED]}⚠️  Brak nowego pliku: $new${COLORS[NC]}"
        return 1
    fi
    
    if diff -u "$orig" "$new" > "$diff_file" 2>&1; then
        echo -e "${COLORS[GREEN]}🟢 Brak różnic. Pliki są identyczne.${COLORS[NC]}"
        return 0
    else
        if [[ -s "$diff_file" ]]; then
            echo -e "${COLORS[YELLOW]}Różnice:${COLORS[NC]}"
            cat "$diff_file"
            return 2
        else
            echo -e "${COLORS[RED]}⚠️  Błąd podczas porównywania plików${COLORS[NC]}"
            return 1
        fi
    fi
}

# Podgląd pliku
preview_file() {
    local file="$1"
    local title="${2:-File}"
    local lines="${3:-50}"
    
    if [[ ! -f "$file" ]]; then
        echo -e "${COLORS[RED]}⚠️  Plik nie istnieje: $file${COLORS[NC]}"
        return 1
    fi
    
    echo -e "${COLORS[CYAN]}--- Podgląd: $title ($file) ---${COLORS[NC]}"
    head -n "$lines" "$file"
    echo -e "${COLORS[CYAN]}---------------------------------------${COLORS[NC]}"
    
    return 0
}

# Czyszczenie starych backupów (zachowaj ostatnie N)
cleanup_old_backups() {
    local keep_count="${1:-5}"
    local removed=0
    
    log "Cleaning up old backups, keeping last $keep_count"
    
    local count=0
    while IFS= read -r dir; do
        ((count++))
        if [[ $count -gt $keep_count ]]; then
            rm -rf "$dir"
            log "Removed old backup: $dir"
            ((removed++))
        fi
    done < <(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d -printf "%T@ %p\n" 2>/dev/null | sort -nr | cut -d" " -f2-)
    
    if [[ $removed -gt 0 ]]; then
        echo -e "${COLORS[GREEN]}✅ Usunięto $removed starych backupów${COLORS[NC]}"
        log "Cleanup completed: removed $removed backups" "SUCCESS"
    else
        echo "Brak starych backupów do usunięcia"
    fi
    
    return 0
}

# Eksport funkcji
export -f backup_files restore_from_backup compare_files preview_file cleanup_old_backups
