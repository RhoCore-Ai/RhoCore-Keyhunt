#!/bin/bash

# Stellt sicher, dass das Skript bei einem Fehler sofort beendet wird.
set -e

# --- GLOBALE VARIABLEN ---
# Definieren der Variablen hier, damit sie in allen Funktionen verf�gbar sind
VENV_DIR="keyhunt_env"
HASH_FILE_SORTED="hash160.bin"
GPU_COUNT=0
CCAP=0
KEY_RANGE=""


# --- HAUPTFUNKTION ---
main() {
    check_dependencies
    detect_hardware
    select_search_range
    compile_keyhunt
    prepare_address_file
    start_search
}


# --- HILFSFUNKTIONEN ---

check_dependencies() {
    echo "--- 1. �berpr�fe und installiere Abh�ngigkeiten ---"
    NEEDS_INSTALL=0
    
    install_package() {
        if ! dpkg -s "$1" >/dev/null 2>&1; then
            echo "Paket '$1' wird ben�tigt."
            NEEDS_INSTALL=1
        fi
    }
    
    check_command() {
        if ! command -v "$1" >/dev/null 2>&1; then
            echo "Befehl '$1' wird ben�tigt (normalerweise in 'build-essential' oder 'nvidia-driver')."
            NEEDS_INSTALL=1
        fi
    }
    
    install_package build-essential
    install_package wget
    install_package gzip
    install_package libgmp-dev
    install_package python3
    install_package python3-pip
    install_package python3-venv
    check_command nvidia-smi

    if [ "$NEEDS_INSTALL" -eq 1 ]; then
        echo "Einige Abh�ngigkeiten fehlen. F�hre Installation aus..."
        sudo apt-get update
        sudo apt-get install -y build-essential wget gzip libgmp-dev python3 python3-pip python3-venv
    else
        echo "Alle Abh�ngigkeiten sind vorhanden."
    fi
    
    if [ ! -d "$VENV_DIR" ]; then
        echo "Erstelle Python Virtual Environment..."
        python3 -m venv "$VENV_DIR"
        ./${VENV_DIR}/bin/pip install -q base58
    fi
}

detect_hardware() {
    echo -e "\n--- 2. Erkenne Hardware automatisch ---"
    GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader | head -n 1)
    local COMPUTE_CAP=$(nvidia-smi -i 0 --query-gpu=compute_cap --format=csv,noheader)
    CCAP=$(echo "$COMPUTE_CAP" | tr -d '.')
    echo "Erkannt: ${GPU_COUNT} NVIDIA GPU(s) mit Compute Capability ${COMPUTE_CAP} (CCAP=${CCAP})"
}

select_search_range() {
    echo -e "\n--- 3. Konfiguration des Suchbereichs ---"
    select_bit() {
        local PROMPT_MESSAGE=$1; local SELECTED_BIT; PS3="$PROMPT_MESSAGE"
        options=("Bit 1-32" "Bit 33-64" "Bit 65-96" "Bit 97-128" "Bit 129-160" "Bit 161-192" "Bit 193-224" "Bit 225-256" "Manuelle Eingabe")
        select opt in "${options[@]}"; do
            case $opt in
                "Bit 1-32") read -p "Geben Sie eine Bit-Zahl zwischen 1 und 32 ein: " SELECTED_BIT; break;;
                "Bit 33-64") read -p "Geben Sie eine Bit-Zahl zwischen 33 und 64 ein: " SELECTED_BIT; break;;
                "Bit 65-96") read -p "Geben Sie eine Bit-Zahl zwischen 65 und 96 ein: " SELECTED_BIT; break;;
                "Bit 97-128") read -p "Geben Sie eine Bit-Zahl zwischen 97 und 128 ein: " SELECTED_BIT; break;;
                "Bit 129-160") read -p "Geben Sie eine Bit-Zahl zwischen 129 und 160 ein: " SELECTED_BIT; break;;
                "Bit 161-192") read -p "Geben Sie eine Bit-Zahl zwischen 161 und 192 ein: " SELECTED_BIT; break;;
                "Bit 193-224") read -p "Geben Sie eine Bit-Zahl zwischen 193 und 224 ein: " SELECTED_BIT; break;;
                "Bit 225-256") read -p "Geben Sie eine Bit-Zahl zwischen 225 und 256 ein: " SELECTED_BIT; break;;
                "Manuelle Eingabe") read -p "Geben Sie die gew�nschte Bit-Zahl (1-256) ein: " SELECTED_BIT; break;;
                *) echo "Ung�ltige Auswahl.";;
            esac
        done
        echo "$SELECTED_BIT"
    }
    local START_BIT=$(select_bit "W�hlen Sie den START-Bereich f�r die Bit-Zahl: ")
    local END_BIT=$(select_bit "W�hlen Sie den END-Bereich f�r die Bit-Zahl: ")
    if ! [[ "$START_BIT" =~ ^[0-9]+$ && "$END_BIT" =~ ^[0-9]+$ && "$START_BIT" -lt "$END_BIT" ]]; then
        echo "Fehler: Ung�ltige Bit-Bereiche."
        exit 1
    fi
    KEY_RANGE=$(./${VENV_DIR}/bin/python3 -c "print(f'{2**(${START_BIT}-1):x}:{2**${END_BIT}-1:x}')")
    echo "Der berechnete Suchbereich ist: $KEY_RANGE"
}

compile_keyhunt() {
    echo -e "\n--- 4. Pr�fe KeyHunt-Kompilierung ---"
    if [ ! -f "KeyHunt-Cuda/KeyHunt" ]; then
        echo "KeyHunt wird kompiliert (mit CCAP=${CCAP})..."
        (cd KeyHunt-Cuda && make clean && make KeyHunt gpu=1 CCAP=${CCAP})
        if [ ! -f "KeyHunt-Cuda/KeyHunt" ]; then echo "Fehler: Kompilierung fehlgeschlagen."; exit 1; fi
        echo "Kompilierung erfolgreich."
    else
        echo "KeyHunt ist bereits kompiliert."
    fi
}

prepare_address_file() {
    echo -e "\n--- 5. Pr�fe Adressdatei ---"
    if [ ! -f "$HASH_FILE_SORTED" ]; then
        echo "Sortierte Adressdatei '${HASH_FILE_SORTED}' nicht gefunden. Starte Vorbereitung..."
        local ADDRESS_FILE="Bitcoin_addresses_LATEST.txt"
        if [ ! -f "$ADDRESS_FILE" ]; then
            echo "Lade ${ADDRESS_FILE}.gz herunter..."
            wget -q --show-progress http://addresses.loyce.club/Bitcoin_addresses_LATEST.txt.gz
            gunzip Bitcoin_addresses_LATEST.txt.gz
        fi
        
        local HASH_FILE_RAW="hash160_raw.bin"
        echo "Konvertiere Adressen zu hash160 (kann dauern)..."
        ./${VENV_DIR}/bin/python3 addresses_to_hash160.py "$ADDRESS_FILE" "$HASH_FILE_RAW"
        
        echo "Sortiere die Bin�rdatei (kann dauern)..."
        (cd BinSort && make)
        ./BinSort/BinSort 20 "$HASH_FILE_RAW" "$HASH_FILE_SORTED"
        rm "$HASH_FILE_RAW"
        echo "Vorbereitung der Adressdatei abgeschlossen."
    else
        echo "Sortierte Adressdatei '${HASH_FILE_SORTED}' ist bereits vorhanden."
    fi
}

start_search() {
    echo -e "\n--- 6. Starte KeyHunt auf ${GPU_COUNT} GPU(s) ---"
    local GPU_IDS=$(seq -s, 0 $((GPU_COUNT - 1)))
    echo "Verwendete GPU-IDs: ${GPU_IDS}"
    echo "Verwendete Zieldatei: ${HASH_FILE_SORTED}"
    echo "Verwendeter Suchbereich: --range ${KEY_RANGE}"
    echo "Der Suchprozess wird jetzt gestartet. Dr�cken Sie STRG+C, um ihn zu beenden."
    
    ./KeyHunt-Cuda/KeyHunt --gpu --mode ADDRESSES --coin BTC -i "$HASH_FILE_SORTED" --gpui "$GPU_IDS" --range "$KEY_RANGE"
    
    echo "Suche beendet."
}

# --- Skript starten ---
main