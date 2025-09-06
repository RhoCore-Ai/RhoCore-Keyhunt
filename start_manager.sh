#!/bin/bash

# Stellt sicher, dass das Skript bei einem Fehler sofort beendet wird.
set -e

# --- GLOBALE VARIABLEN ---
VENV_DIR="keyhunt_env"
HASH_FILE_SORTED="hash160.bin"
KEYHUNT_EXECUTABLE_NAME="KeyHunt"
KEYHUNT_DIR="KeyHunt-Cuda"
PYTHON_MANAGER_SCRIPT="keyhunt_manager.py"
GPU_COUNT=0
CCAP=0


# --- HAUPTFUNKTION ---
main() {
    check_dependencies
    detect_hardware
    compile_keyhunt
    # Die Adressdatei-Vorbereitung ist optional, falls Sie eine eigene hash160.bin verwenden.
    # prepare_address_file 
    start_python_manager
}


# --- HILFSFUNKTIONEN ---

check_dependencies() {
    echo "--- 1. Überprüfe und installiere Abhängigkeiten ---"
    NEEDS_INSTALL=0
    
    # Funktion zur Überprüfung von Paketen
    install_package() {
        if ! dpkg -s "$1" >/dev/null 2>&1; then
            echo "Paket '$1' wird benötigt."
            NEEDS_INSTALL=1
        fi
    }
    
    # Funktion zur Überprüfung von Befehlen
    check_command() {
        if ! command -v "$1" >/dev/null 2>&1; then
            echo "Befehl '$1' wird benötigt (normalerweise in 'build-essential' oder 'nvidia-driver')."
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
        echo "Einige Abhängigkeiten fehlen. Führe Installation aus..."
        sudo apt-get update
        sudo apt-get install -y build-essential wget gzip libgmp-dev python3 python3-pip python3-venv
    else
        echo "Alle System-Abhängigkeiten sind vorhanden."
    fi
    
    if [ ! -d "$VENV_DIR" ]; then
        echo "Erstelle Python Virtual Environment..."
        python3 -m venv "$VENV_DIR"
    fi

    echo "Installiere/Aktualisiere Python-Pakete (requests)..."
    # Stellt sicher, dass die Pakete bei jedem Lauf aktuell sind
    ./${VENV_DIR}/bin/pip install --upgrade -q requests
}

detect_hardware() {
    echo -e "\n--- 2. Erkenne Hardware automatisch ---"
    GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader | head -n 1)
    local COMPUTE_CAP=$(nvidia-smi -i 0 --query-gpu=compute_cap --format=csv,noheader)
    CCAP=$(echo "$COMPUTE_CAP" | tr -d '.')
    echo "Erkannt: ${GPU_COUNT} NVIDIA GPU(s) mit Compute Capability ${COMPUTE_CAP} (CCAP=${CCAP})"
}

compile_keyhunt() {
    echo -e "\n--- 3. Prüfe KeyHunt-Kompilierung ---"
    if [ ! -f "${KEYHUNT_DIR}/${KEYHUNT_EXECUTABLE_NAME}" ]; then
        echo "KeyHunt wird kompiliert (mit CCAP=${CCAP})..."
        (cd ${KEYHUNT_DIR} && make clean && make ${KEYHUNT_EXECUTABLE_NAME} gpu=1 CCAP=${CCAP})
        if [ ! -f "${KEYHUNT_DIR}/${KEYHUNT_EXECUTABLE_NAME}" ]; then 
            echo "Fehler: Kompilierung fehlgeschlagen."
            exit 1
        fi
        echo "Kompilierung erfolgreich."
    else
        echo "KeyHunt ist bereits kompiliert."
    fi
}

prepare_address_file() {
    echo -e "\n--- 4. Prüfe Adressdatei ---"
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
        
        echo "Sortiere die Binärdatei (kann dauern)..."
        (cd BinSort && make)
        ./BinSort/BinSort 20 "$HASH_FILE_RAW" "$HASH_FILE_SORTED"
        rm "$HASH_FILE_RAW"
        echo "Vorbereitung der Adressdatei abgeschlossen."
    else
        echo "Sortierte Adressdatei '${HASH_FILE_SORTED}' ist bereits vorhanden."
    fi
}

start_python_manager() {
    echo -e "\n--- 5. Starte den KeyHunt Python Manager ---"
    echo "Der Python-Manager wird nun die Suche in optimierten, zufälligen Paketen steuern."
    echo "Alle Konfigurationen (Telegram, Suchbereiche) werden in '${PYTHON_MANAGER_SCRIPT}' vorgenommen."
    echo "Drücken Sie STRG+C, um den Manager zu beenden."
    
    # Python Virtual Environment aktivieren und das Manager-Skript ausführen
    source "${VENV_DIR}/bin/activate"
    python3 "${PYTHON_MANAGER_SCRIPT}"
    deactivate
    
    echo "Manager-Skript beendet."
}

# --- Skript starten ---
main
