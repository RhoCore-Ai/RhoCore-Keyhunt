#!/bin/bash

# Stellt sicher, dass das Skript bei einem Fehler sofort beendet wird.
set -e

# --- BENUTZEREINGABEN ---
echo "--- Hardware-Konfiguration ---"
if [ -z "$GPU_COUNT" ]; then
    read -p "Wie viele NVIDIA-GPUs möchten Sie verwenden?: " GPU_COUNT
fi
if [ -z "$CCAP" ]; then
    read -p "Geben Sie die Compute Capability Ihrer GPUs an (z.B. 86 für RTX 3070): " CCAP
fi

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
            "Manuelle Eingabe") read -p "Geben Sie die gewünschte Bit-Zahl (1-256) ein: " SELECTED_BIT; break;;
            *) echo "Ungültige Auswahl. Bitte versuchen Sie es erneut.";;
        esac
    done
    echo $SELECTED_BIT
}

START_BIT=$(select_bit "Wählen Sie den START-Bereich für die Bit-Zahl: ")
END_BIT=$(select_bit "Wählen Sie den END-Bereich für die Bit-Zahl: ")

if ! [[ "$GPU_COUNT" =~ ^[0-9]+$ ]] || ! [[ "$CCAP" =~ ^[0-9]+$ ]] || ! [[ "$START_BIT" =~ ^[0-9]+$ ]] || ! [[ "$END_BIT" =~ ^[0-9]+$ ]]; then
    echo "Fehler: GPU-Anzahl, CCAP und Bit-Bereiche müssen Zahlen sein."
    exit 1
fi

if [ "$START_BIT" -ge "$END_BIT" ]; then
    echo "Fehler: Der START-Bitbereich muss kleiner als der END-Bitbereich sein."
    exit 1
fi

# --- ABHÄNGIGKEITEN INSTALLIEREN ---
echo -e "\n--- Überprüfe und installiere Abhängigkeiten ---"
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
echo "Alle System-Abhängigkeiten sind vorhanden."

# --- PYTHON-UMGEBUNG EINRICHTEN & BEREICH BERECHNEN ---
VENV_DIR="keyhunt_env"
if [ ! -d "$VENV_DIR" ]; then
    echo "Erstelle Python Virtual Environment in '$VENV_DIR'..."
    python3 -m venv $VENV_DIR
fi
echo "Aktiviere Python Virtual Environment und installiere 'base58'..."
./${VENV_DIR}/bin/pip install -q base58

echo "Berechne den Hexadezimal-Bereich mit Python..."
# Python zur Berechnung großer Zahlen verwenden
KEY_RANGE=$(./${VENV_DIR}/bin/python3 -c "print(f'{2**(${START_BIT}-1):x}:{2**${END_BIT}-1:x}')")
echo "Der berechnete Suchbereich ist: $KEY_RANGE"
echo "Python-Abhängigkeiten sind bereit."


# --- KOMPILIERUNG ---
# In das richtige Verzeichnis wechseln, kompilieren, und zurück wechseln
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
    echo "Adressdatei '${ADDRESS_FILE}' bereits vorhanden. Download wird übersprungen."
fi

echo "Konvertiere Adressen zu hash160 (dies kann einige Minuten dauern)..."
./${VENV_DIR}/bin/python3 addresses_to_hash160.py ${ADDRESS_FILE} ${HASH_FILE_RAW}

echo "Sortiere die Binärdatei (dies kann ebenfalls dauern)..."
(cd BinSort && make)
./BinSort/BinSort ${HASH_FILE_RAW} ${HASH_FILE_SORTED}
rm ${HASH_FILE_RAW}
echo "Vorbereitung der Adressdatei abgeschlossen. Die sortierte Datei ist '${HASH_FILE_SORTED}'."

# --- SUCHE STARTEN ---
echo -e "\n--- Starte KeyHunt auf ${GPU_COUNT} GPU(s) ---"
GPU_IDS=$(seq -s, 0 $((GPU_COUNT - 1)))
echo "Verwendete GPU-IDs: ${GPU_IDS}"
echo "Verwendete Zieldatei: ${HASH_FILE_SORTED}"
echo "Verwendeter Suchbereich: --range ${KEY_RANGE}"
echo "Der Suchprozess wird jetzt gestartet. Drücken Sie STRG+C, um ihn zu beenden."

# KeyHunt aus dem richtigen Verzeichnis starten
./KeyHunt-Cuda/KeyHunt --gpu --mode ADDRESSES --coin BTC -i ${HASH_FILE_SORTED} --gpui ${GPU_IDS} --range ${KEY_RANGE}

echo "Suche beendet."