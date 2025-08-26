#!/bin/bash

# Stellt sicher, dass das Skript bei einem Fehler sofort beendet wird.
set -e

# --- STATUSDATEI FÜR FORTSCHRITT ---
# In dieser Datei wird der letzte abgeschlossene Schritt gespeichert.
STATUS_FILE=".script_status"

# Funktion zum Lesen des Status
get_status() {
    if [ -f "$STATUS_FILE" ]; then
        cat "$STATUS_FILE"
    else
        echo "0"
    fi
}

# Funktion zum Schreiben des Status
update_status() {
    echo "$1" > "$STATUS_FILE"
}

# --- ABHÄNGIGKEITEN PRÜFEN (immer ausführen) ---
echo -e "--- 1. Überprüfe und installiere Abhängigkeiten ---"
install_package() {
    PACKAGE=$1
    if ! dpkg -s $PACKAGE >/dev/null 2>&1; then
        echo "Installiere $PACKAGE..."
        apt-get install -y $PACKAGE
    fi
}
apt-get update -qq
install_package build-essential
install_package wget
install_package gzip
install_package libgmp-dev
install_package python3
install_package python3-pip
install_package python3-venv

command -v nvidia-smi >/dev/null 2>&1 || { echo >&2 "Fehler: 'nvidia-smi' wurde nicht gefunden. Bitte stellen Sie sicher, dass die NVIDIA-Treiber korrekt installiert sind."; exit 1; }
echo "Abhängigkeiten sind auf dem neuesten Stand."

# --- HARDWARE AUTOMATISCH ERKENNEN ---
echo -e "\n--- 2. Erkenne Hardware automatisch ---"
GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader | head -n 1)
COMPUTE_CAP=$(nvidia-smi -i 0 --query-gpu=compute_cap --format=csv,noheader)
CCAP=$(echo $COMPUTE_CAP | tr -d '.')
echo "Erkannt: ${GPU_COUNT} NVIDIA GPU(s) mit Compute Capability ${COMPUTE_CAP} (CCAP=${CCAP})"

# --- AUSWAHL DES BIT-BEREICHS ---
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
            "Manuelle Eingabe") read -p "Geben Sie die gewünschte Bit-Zahl (1-256) ein: " SELECTED_BIT; break;;
            *) echo "Ungültige Auswahl.";;
        esac
    done
    echo $SELECTED_BIT
}
START_BIT=$(select_bit "Wählen Sie den START-Bereich für die Bit-Zahl: ")
END_BIT=$(select_bit "Wählen Sie den END-Bereich für die Bit-Zahl: ")
if ! [[ "$START_BIT" =~ ^[0-9]+$ && "$END_BIT" =~ ^[0-9]+$ && "$START_BIT" -lt "$END_BIT" ]]; then
    echo "Fehler: Ungültige Bit-Bereiche."
    exit 1
fi

# --- PYTHON-UMGEBUNG & BEREICH BERECHNEN ---
VENV_DIR="keyhunt_env"
if [ ! -d "$VENV_DIR" ]; then
    echo "Erstelle Python Virtual Environment..."
    python3 -m venv $VENV_DIR
    ./${VENV_DIR}/bin/pip install -q base58
fi
KEY_RANGE=$(./${VENV_DIR}/bin/python3 -c "print(f'{2**(${START_BIT}-1):x}:{2**${END_BIT}-1:x}')")
echo "Der berechnete Suchbereich ist: $KEY_RANGE"

# --- KOMPILIERUNG ---
echo -e "\n--- 4. Kompiliere KeyHunt ---"
if [ ! -f KeyHunt-Cuda/KeyHunt ]; then
    echo "KeyHunt wird kompiliert (mit CCAP=${CCAP})..."
    (cd KeyHunt-Cuda && make clean && make KeyHunt gpu=1 CCAP=${CCAP})
    if [ ! -f KeyHunt-Cuda/KeyHunt ]; then echo "Fehler: Kompilierung fehlgeschlagen."; exit 1; fi
    echo "Kompilierung erfolgreich."
else
    echo "KeyHunt existiert bereits. Kompilierung wird übersprungen."
fi

# --- DATEN HERUNTERLADEN UND VORBEREITEN ---
echo -e "\n--- 5. Lade Adressliste herunter und bereite sie vor ---"
HASH_FILE_SORTED="hash160.bin"
if [ ! -f "${HASH_FILE_SORTED}" ]; then
    ADDRESS_FILE="Bitcoin_addresses_LATEST.txt"
    if [ ! -f "${ADDRESS_FILE}" ]; then
        echo "Lade ${ADDRESS_FILE}.gz herunter..."
        wget http://addresses.loyce.club/Bitcoin_addresses_LATEST.txt.gz
        gunzip Bitcoin_addresses_LATEST.txt.gz
    fi
    
    HASH_FILE_RAW="hash160_raw.bin"
    echo "Konvertiere Adressen zu hash160 (dies kann einige Minuten dauern)..."
    ./${VENV_DIR}/bin/python3 addresses_to_hash160.py ${ADDRESS_FILE} ${HASH_FILE_RAW}
    
    echo "Sortiere die Binärdatei (dies kann ebenfalls dauern)..."
    (cd BinSort && make)
    ./BinSort/BinSort 20 ${HASH_FILE_RAW} ${HASH_FILE_SORTED}
    rm ${HASH_FILE_RAW}
    echo "Vorbereitung der Adressdatei abgeschlossen."
else
    echo "Sortierte Adressdatei '${HASH_FILE_SORTED}' existiert bereits. Vorbereitung wird übersprungen."
fi

# --- SUCHE STARTEN ---
echo -e "\n--- 6. Starte KeyHunt auf ${GPU_COUNT} GPU(s) ---"
GPU_IDS=$(seq -s, 0 $((GPU_COUNT - 1)))
echo "Verwendete GPU-IDs: ${GPU_IDS}"
echo "Verwendete Zieldatei: ${HASH_FILE_SORTED}"
echo "Verwendeter Suchbereich: --range ${KEY_RANGE}"
echo "Der Suchprozess wird jetzt gestartet. Drücken Sie STRG+C, um ihn zu beenden."

./KeyHunt-Cuda/KeyHunt --gpu --mode ADDRESSES --coin BTC -i ${HASH_FILE_SORTED} --gpui ${GPU_IDS} --range ${KEY_RANGE}

echo "Suche beendet."