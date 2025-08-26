#!/bin/bash

# Stellt sicher, dass das Skript bei einem Fehler sofort beendet wird.
set -e

# --- BENUTZEREINGABEN ---
echo "--- Hardware-Konfiguration ---"
# Abfrage für GPU-Anzahl und Compute Capability
if [ -z "$GPU_COUNT" ]; then
    read -p "Wie viele NVIDIA-GPUs möchten Sie verwenden?: " GPU_COUNT
fi
if [ -z "$CCAP" ]; then
    read -p "Geben Sie die Compute Capability Ihrer GPUs an (z.B. 86 für RTX 3070): " CCAP
fi

# Überprüft, ob die Eingaben gültig sind
if ! [[ "$GPU_COUNT" =~ ^[0-9]+$ ]] || ! [[ "$CCAP" =~ ^[0-9]+$ ]]; then
    echo "Fehler: GPU-Anzahl und CCAP müssen Zahlen sein."
    exit 1
fi

# --- ABHÄNGIGKEITEN INSTALLIEREN ---
echo -e "\n--- Überprüfe und installiere Abhängigkeiten ---"

# Funktion zur Installation von Paketen
install_package() {
    PACKAGE=$1
    if ! dpkg -s $PACKAGE >/dev/null 2>&1; then
        echo "Installiere $PACKAGE..."
        apt-get install -y $PACKAGE
    else
        echo "$PACKAGE ist bereits installiert."
    fi
}

# Update der Paketlisten und Installation der System-Abhängigkeiten
apt-get update
install_package build-essential
install_package wget
install_package gzip
install_package libgmp-dev
install_package python3
install_package python3-pip
install_package python3-venv

echo "Alle System-Abhängigkeiten sind vorhanden."

# --- PYTHON-UMGEBUNG EINRICHTEN ---
VENV_DIR="keyhunt_env"
if [ ! -d "$VENV_DIR" ]; then
    echo "Erstelle Python Virtual Environment in '$VENV_DIR'..."
    python3 -m venv $VENV_DIR
fi

echo "Aktiviere Python Virtual Environment und installiere 'base58'..."
# Führe pip im venv aus, um base58 zu installieren
./${VENV_DIR}/bin/pip install -q base58

echo "Python-Abhängigkeiten sind bereit."

# --- KOMPILIERUNG ---
echo -e "\n--- Kompiliere KeyHunt (mit CCAP=${CCAP}) ---"
make clean
make KeyHunt gpu=1 CCAP=${CCAP}
if [ ! -f KeyHunt ]; then
    echo "Fehler: Kompilierung von KeyHunt fehlgeschlagen."
    exit 1
fi
echo "KeyHunt erfolgreich kompiliert."

# --- DATEN HERUNTERLADEN UND VORBEREITEN ---
echo -e "\n--- Lade Adressliste herunter und bereite sie vor ---"
ADDRESS_FILE="Bitcoin_addresses_LATEST.txt"
HASH_FILE_RAW="hash160_raw.bin"
HASH_FILE_SORTED="hash160.bin"

if [ ! -f "${ADDRESS_FILE}" ]; then
    echo "Lade ${ADDRESS_FILE}.gz herunter..."
    wget http://addresses.loyce.club/Bitcoin_addresses_LATEST.txt.gz
    echo "Entpacke die Datei..."
    gunzip Bitcoin_addresses_LATEST.txt.gz
else
    echo "Adressdatei '${ADDRESS_FILE}' bereits vorhanden. Download wird übersprungen."
fi

echo "Konvertiere Adressen zu hash160 (dies kann einige Minuten dauern)..."
# Stelle sicher, dass das Python-Skript aus dem venv ausgeführt wird
./${VENV_DIR}/bin/python3 addresses_to_hash160.py ${ADDRESS_FILE} ${HASH_FILE_RAW}

echo "Sortiere die Binärdatei (dies kann ebenfalls dauern)..."
# BinSort kompilieren, falls noch nicht geschehen
(cd BinSort && make)
./BinSort/BinSort ${HASH_FILE_RAW} ${HASH_FILE_SORTED}

echo "Bereinige temporäre Dateien..."
rm ${HASH_FILE_RAW}

echo "Vorbereitung der Adressdatei abgeschlossen. Die sortierte Datei ist '${HASH_FILE_SORTED}'."

# --- SUCHE STARTEN ---
echo -e "\n--- Starte KeyHunt auf ${GPU_COUNT} GPU(s) ---"

# Erstellt die GPU-ID-Liste (z.B. "0,1,2,3")
GPU_IDS=$(seq -s, 0 $((GPU_COUNT - 1)))

echo "Verwendete GPU-IDs: ${GPU_IDS}"
echo "Verwendete Zieldatei: ${HASH_FILE_SORTED}"
echo "Der Suchprozess wird jetzt gestartet. Drücken Sie STRG+C, um ihn zu beenden."

# Der finale Befehl zum Starten der Suche
./KeyHunt --gpu --mode ADDRESSES --coin BTC -i ${HASH_FILE_SORTED} --gpui ${GPU_IDS}

echo "Suche beendet."