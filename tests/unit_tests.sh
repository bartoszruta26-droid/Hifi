#!/usr/bin/env bash
# shellcheck shell=bash
# ==========================================
# RPi4 Audio Setup - Testy jednostkowe
# Uruchomienie: bash tests/unit_tests.sh
# ==========================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"

# Kolory dla outputu testów
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Statystyki testów
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Funkcje pomocnicze testów
assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="${3:-Test}"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    if [[ "$expected" == "$actual" ]]; then
        echo -e "${GREEN}✅ PASS${NC}: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}❌ FAIL${NC}: $test_name"
        echo "  Expected: '$expected'"
        echo "  Actual:   '$actual'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 0  # Nie przerywaj testów
    fi
}

assert_file_exists() {
    local file="$1"
    local test_name="${2:-File exists}"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    if [[ -f "$file" ]]; then
        echo -e "${GREEN}✅ PASS${NC}: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}❌ FAIL${NC}: $test_name ($file)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 0
    fi
}

assert_function_exists() {
    local func_name="$1"
    local test_name="${2:-Function exists}"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    if declare -f "$func_name" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ PASS${NC}: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}❌ FAIL${NC}: $test_name ($func_name)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 0
    fi
}

# ==========================================
# TESTY MODUŁU CORE
# ==========================================

test_core_module() {
    echo ""
    echo -e "${YELLOW}=== Testy modułu core.sh ===${NC}"
    
    source "$LIB_DIR/core.sh"
    
    # Test 1: Sprawdzenie czy stałe są zdefiniowane
    assert_equals "/boot/firmware/config.txt" "$BOOT_CFG_DEFAULT" "BOOT_CFG_DEFAULT path"
    assert_equals "/etc/pulse/daemon.conf" "$PULSE_DAEMON" "PULSE_DAEMON path"
    assert_equals "768000" "$DEFAULT_SAMPLE_RATE" "DEFAULT_SAMPLE_RATE value"
    assert_equals "32" "$DEFAULT_BIT_DEPTH" "DEFAULT_BIT_DEPTH value"
    
    # Test 2: Sprawdzenie czy funkcje istnieją
    assert_function_exists "log" "log function"
    assert_function_exists "check_root" "check_root function"
    assert_function_exists "init_dirs" "init_dirs function"
    assert_function_exists "validate_hat_model" "validate_hat_model function"
    assert_function_exists "get_dac_capabilities" "get_dac_capabilities function"
    
    # Test 3: Walidacja modeli DAC
    if validate_hat_model "hifiberry-dacplus" 2>/dev/null; then
        echo -e "${GREEN}✅ PASS${NC}: validate hifiberry-dacplus"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}❌ FAIL${NC}: validate hifiberry-dacplus"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    # Test 4: Pobranie możliwości DAC
    local caps
    caps=$(get_dac_capabilities "hifiberry-dacplushd")
    if [[ "$caps" == *"768000"* ]]; then
        echo -e "${GREEN}✅ PASS${NC}: get capabilities for hifiberry-dacplushd"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}❌ FAIL${NC}: get capabilities for hifiberry-dacplushd"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

# ==========================================
# TESTY MODUŁU BACKUP
# ==========================================

test_backup_module() {
    echo ""
    echo -e "${YELLOW}=== Testy modułu backup.sh ===${NC}"
    
    source "$LIB_DIR/core.sh"
    source "$LIB_DIR/backup.sh"
    
    # Test 1: Sprawdzenie funkcji
    assert_function_exists "backup_files" "backup_files function"
    assert_function_exists "restore_from_backup" "restore_from_backup function"
    assert_function_exists "compare_files" "compare_files function"
    assert_function_exists "preview_file" "preview_file function"
    assert_function_exists "cleanup_old_backups" "cleanup_old_backups function"
}

# ==========================================
# TESTY MODUŁU CONFIG GENERATOR
# ==========================================

test_config_generator_module() {
    echo ""
    echo -e "${YELLOW}=== Testy modułu config_generator.sh ===${NC}"
    
    source "$LIB_DIR/core.sh"
    source "$LIB_DIR/config_generator.sh"
    
    # Test 1: Sprawdzenie funkcji
    assert_function_exists "generate_daemon_conf" "generate_daemon_conf function"
    assert_function_exists "generate_default_pa" "generate_default_pa function"
    assert_function_exists "generate_mpd_conf" "generate_mpd_conf function"
    assert_function_exists "generate_config_txt" "generate_config_txt function"
    assert_function_exists "gen_configs" "gen_configs function"
    
    # Test 2: Generowanie daemon.conf
    local daemon_file
    daemon_file=$(generate_daemon_conf)
    assert_file_exists "$daemon_file" "Generated daemon.conf"
    
    # Sprawdź zawartość
    if grep -q "default-sample-rate = ${SAMPLE_RATE}" "$daemon_file"; then
        echo -e "${GREEN}✅ PASS${NC}: daemon.conf contains sample rate"
        ((TESTS_PASSED++))
        ((TESTS_TOTAL++))
    else
        echo -e "${RED}❌ FAIL${NC}: daemon.conf missing sample rate"
        ((TESTS_FAILED++))
        ((TESTS_TOTAL++))
    fi
    
    # Test 3: Generowanie config.txt
    local boot_file
    boot_file=$(generate_config_txt)
    assert_file_exists "$boot_file" "Generated config.txt"
    
    if grep -q "dtoverlay=${HAT_MODEL}" "$boot_file"; then
        echo -e "${GREEN}✅ PASS${NC}: config.txt contains dtoverlay"
        ((TESTS_PASSED++))
        ((TESTS_TOTAL++))
    else
        echo -e "${RED}❌ FAIL${NC}: config.txt missing dtoverlay"
        ((TESTS_FAILED++))
        ((TESTS_TOTAL++))
    fi
}

# ==========================================
# TESTY MODUŁU UI
# ==========================================

test_ui_module() {
    echo ""
    echo -e "${YELLOW}=== Testy modułu ui.sh ===${NC}"
    
    source "$LIB_DIR/core.sh"
    source "$LIB_DIR/config_generator.sh"
    source "$LIB_DIR/ui.sh"
    
    # Test 1: Sprawdzenie funkcji
    assert_function_exists "print_header" "print_header function"
    assert_function_exists "select_model" "select_model function"
    assert_function_exists "configure_quality" "configure_quality function"
    assert_function_exists "main_menu" "main_menu function"
    
    # Test 2: Zmienne językowe
    assert_equals "pl" "$MENU_LANG" "Default language is Polish"
}

# ==========================================
# TESTY SYNTAKTYCZNE
# ==========================================

test_syntax() {
    echo ""
    echo -e "${YELLOW}=== Testy składniowe ===${NC}"
    
    local files=(
        "$LIB_DIR/core.sh"
        "$LIB_DIR/backup.sh"
        "$LIB_DIR/config_generator.sh"
        "$LIB_DIR/applier.sh"
        "$LIB_DIR/ui.sh"
        "$SCRIPT_DIR/../rpi4_audio_setup_v3.sh"
    )
    
    for file in "${files[@]}"; do
        if bash -n "$file" 2>/dev/null; then
            echo -e "${GREEN}✅ PASS${NC}: Syntax check for $(basename "$file")"
            ((TESTS_PASSED++))
            ((TESTS_TOTAL++))
        else
            echo -e "${RED}❌ FAIL${NC}: Syntax error in $(basename "$file")"
            ((TESTS_FAILED++))
            ((TESTS_TOTAL++))
        fi
    done
}

# ==========================================
# PROGRAM GŁÓWNY TESTÓW
# ==========================================

main() {
    echo "=========================================="
    echo "RPi4 Audio Setup - Unit Tests"
    echo "=========================================="
    echo ""
    
    # Utwórz katalog staging dla testów
    mkdir -p /tmp/rpi_audio_staging
    
    # Uruchom wszystkie testy
    test_syntax
    test_core_module
    test_backup_module
    test_config_generator_module
    test_ui_module
    
    # Podsumowanie
    echo ""
    echo "=========================================="
    echo "PODSUMOWANIE TESTÓW"
    echo "=========================================="
    echo "Total:  $TESTS_TOTAL"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    echo ""
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✅ Wszystkie testy zakończone sukcesem!${NC}"
        exit 0
    else
        echo -e "${RED}❌ Niektóre testy nie powiodły się.${NC}"
        exit 1
    fi
}

main "$@"
