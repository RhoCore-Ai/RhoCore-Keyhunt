#!/bin/bash

# Stellt sicher, dass das Skript bei einem Fehler sofort beendet wird.
set -e

# --- ABH�NGIGKEITEN PR�FEN ---
echo -e "--- �berpr�fe und installiere Abh�ngigkeiten ---"
install_package() {
    PACKAGE=$1
    if ! dpkg -s $PACKAGE >/dev/null 2>&1; then
        echo "Installiere $PACKAGE..."
        apt-get install -y $PACKAGE
    else
        echo "$PACKAGE ist bereits installiert."
    fi
}
apt-get update
install_package build-essential
install_package wget
install_package gzip
install_package libgmp-dev
install_package python3
install_package python3-pip
install_package python3-venv

# Pr�fe auf nvidia-smi
command -v nvidia-smi >/dev/null 2>&1 || { echo >&2 "Fehler: 'nvidia-smi' wurde nicht gefunden. Bitte stellen Sie sicher, dass die NVIDIA-Treiber korrekt installiert sind."; exit 1; }
echo "Alle System-Abh�ngigkeiten sind vorhanden."


# --- HARDWARE AUTOMATISCH ERKENNEN ---
echo -e "\n--- Erkenne Hardware automatisch ---"
GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader)
COMPUTE_CAP=$(nvidia-smi -i 0 --query-gpu=compute_cap --format=csv,noheader) # Liest CCAP von der ersten GPU
CCAP=$(echo $COMPUTE_CAP | tr -d '.')

echo "Erkannt: ${GPU_COUNT} NVIDIA GPU(s)"
echo "Erkannt: Compute Capability ${COMPUTE_CAP} (wird als CCAP=${CCAP} f�r die Kompilierung verwendet)"


# --- AUSWAHL DES BIT-BEREICHS ---
echo -e "\n--- Konfiguration des Suchbereichs ---"
select_bit() {
    local PROMPT_MESSAGE=$1
    local SELECTED_BIT
    PS3="$PROMPT_MESSAGE"
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
            *) echo "Ung�ltige Auswahl. Bitte versuchen Sie es erneut.";;
        esac
    done
    echo $SELECTED_BIT
}

START_BIT=$(select_bit "W�hlen Sie den START-Bereich f�r die Bit-Zahl: ")
END_BIT=$(select_bit "W�hlen Sie den END-Bereich f�r die Bit-Zahl: ")

if ! [[ "$START_BIT" =~ ^[0-9]+$ ]] || ! [[ "$END_BIT" =~ ^[0-9]+$ ]]; then
    echo "Fehler: Die Bit-Bereiche m�ssen Zahlen sein."
    exit 1
fi

if [ "$START_BIT" -ge "$END_BIT" ]; then
    echo "Fehler: Der START-Bitbereich muss kleiner als der END-Bitbereich sein."
    exit 1
fi

# --- PYTHON-UMGEBUNG EINRICHTEN & BEREICH BERECHNEN ---
VENV_DIR="keyhunt_env"
if [ ! -d "$VENV_DIR" ]; then
    echo "Erstelle Python Virtual Environment in '$VENV_DIR'..."
    python3 -m venv $VENV_DIR
fi
echo "Aktiviere Python Virtual Environment und installiere 'base58'..."
./${VENV_DIR}/bin/pip install -q base58

echo "Berechne den Hexadezimal-Bereich mit Python..."
KEY_RANGE=$(./${VENV_DIR}/bin/python3 -c "print(f'{2**(${START_BIT}-1):x}:{2**${END_BIT}-1:x}')")
echo "Der berechnete Suchbereich ist: $KEY_RANGE"
echo "Python-Abh�ngigkeiten sind bereit."


# --- KOMPILIERUNG ---
echo -e "\n--- Kompiliere KeyHunt (mit CCAP=${CCAP}) ---"
(cd KeyHunt-Cuda && make clean && make KeyHunt gpu=1 CCAP=${CCAP})
if [ ! -f KeyHunt-Cuda/KeyHunt ]; then
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
    echo "Adressdatei '${ADDRESS_FILE}' bereits vorhanden. Download wird �bersprungen."
fi

echo "Konvertiere Adressen zu hash160 (dies kann einige Minuten dauern)..."
./${VENV_DIR}/bin/python3 addresses_to_hash160.py ${ADDRESS_FILE} ${HASH_FILE_RAW}

echo "Sortiere die Bin�rdatei (dies kann ebenfalls dauern)..."
(cd BinSort && make)
./BinSort/BinSort 20 ${HASH_FILE_RAW} ${HASH_FILE_SORTED}
rm ${HASH_FILE_RAW}
echo "Vorbereitung der Adressdatei abgeschlossen. Die sortierte Datei ist '${HASH_FILE_SORTED}'."

# --- SUCHE STARTEN ---
echo -e "\n--- Starte KeyHunt auf ${GPU_COUNT} GPU(s) ---"
GPU_IDS=$(seq -s, 0 $((GPU_COUNT - 1)))
echo "Verwendete GPU-IDs: ${GPU_IDS}"
echo "Verwendete Zieldatei: ${HASH_FILE_SORTED}"
echo "Verwendeter Suchbereich: --range ${KEY_RANGE}"
echo "Der Suchprozess wird jetzt gestartet. Dr�cken Sie STRG+C, um ihn zu beenden."

# KeyHunt aus dem richtigen Verzeichnis starten
./KeyHunt-Cuda/KeyHunt --gpu --mode ADDRESSES --coin BTC -i ${HASH_FILE_SORTED} --gpui ${GPU_IDS} --range ${KEY_RANGE}

echo "Suche beendet."