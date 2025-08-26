#!/bin/bash

# Stellt sicher, dass das Skript bei einem Fehler sofort beendet wird.
set -e

# --- BENUTZEREINGABEN ---
echo "--- Hardware-Konfiguration ---"
# Abfrage f�r GPU-Anzahl und Compute Capability
if [ -z "$GPU_COUNT" ]; then
    read -p "Wie viele NVIDIA-GPUs m�chten Sie verwenden?: " GPU_COUNT
fi
if [ -z "$CCAP" ]; then
    read -p "Geben Sie die Compute Capability Ihrer GPUs an (z.B. 86 f�r RTX 3070): " CCAP
fi

# --- AUSWAHL DES BIT-BEREICHS ---
echo -e "\n--- Konfiguration des Suchbereichs ---"

# Funktion f�r das Auswahlmen�
select_bit() {
    local PROMPT_MESSAGE=$1
    local SELECTED_BIT
    PS3="$PROMPT_MESSAGE" # Setzt die Eingabeaufforderung f�r das Men�
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
    # Gibt den ausgew�hlten Wert zur�ck
    echo $SELECTED_BIT
}

START_BIT=$(select_bit "W�hlen Sie den START-Bereich f�r die Bit-Zahl: ")
END_BIT=$(select_bit "W�hlen Sie den END-Bereich f�r die Bit-Zahl: ")


# �berpr�ft, ob die Eingaben g�ltig sind
if ! [[ "$GPU_COUNT" =~ ^[0-9]+$ ]] || ! [[ "$CCAP" =~ ^[0-9]+$ ]] || ! [[ "$START_BIT" =~ ^[0-9]+$ ]] || ! [[ "$END_BIT" =~ ^[0-9]+$ ]]; then
    echo "Fehler: GPU-Anzahl, CCAP und Bit-Bereiche m�ssen Zahlen sein."
    exit 1
fi

if [ "$START_BIT" -ge "$END_BIT" ]; then
    echo "Fehler: Der START-Bitbereich muss kleiner als der END-Bitbereich sein."
    exit 1
fi

# --- BERECHNUNG DES HEX-BEREICHS ---
echo "Berechne den Hexadezimal-Bereich..."
# bc wird f�r die Berechnung mit gro�en Zahlen ben�tigt
START_RANGE_DEC=$(echo "2^($START_BIT - 1)" | bc)
END_RANGE_DEC=$(echo "(2^$END_BIT) - 1" | bc)

# Konvertiere die Dezimalzahlen in Hexadezimal
START_RANGE_HEX=$(printf '%x\n' $START_RANGE_DEC)
END_RANGE_HEX=$(printf '%x\n' $END_RANGE_DEC)
KEY_RANGE="${START_RANGE_HEX}:${END_RANGE_HEX}"
echo "Der berechnete Suchbereich ist: $KEY_RANGE"


# --- ABH�NGIGKEITEN INSTALLIEREN ---
echo -e "\n--- �berpr�fe und installiere Abh�ngigkeiten ---"

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

# Update der Paketlisten und Installation der System-Abh�ngigkeiten
apt-get update
install_package build-essential
install_package wget
install_package gzip
install_package libgmp-dev
install_package python3
install_package python3-pip
install_package python3-venv
install_package bc # Notwendig f�r die Bereichsberechnung

echo "Alle System-Abh�ngigkeiten sind vorhanden."


# --- PYTHON-UMGEBUNG EINRICHTEN ---
VENV_DIR="keyhunt_env"
if [ ! -d "$VENV_DIR" ]; then
    echo "Erstelle Python Virtual Environment in '$VENV_DIR'..."
    python3 -m venv $VENV_DIR
fi

echo "Aktiviere Python Virtual Environment und installiere 'base58'..."
# F�hre pip im venv aus, um base58 zu installieren
./${VENV_DIR}/bin/pip install -q base58
echo "Python-Abh�ngigkeiten sind bereit."


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
    echo "Adressdatei '${ADDRESS_FILE}' bereits vorhanden. Download wird �bersprungen."
fi

echo "Konvertiere Adressen zu hash160 (dies kann einige Minuten dauern)..."
# Stelle sicher, dass das Python-Skript aus dem venv ausgef�hrt wird
./${VENV_DIR}/bin/python3 addresses_to_hash160.py ${ADDRESS_FILE} ${HASH_FILE_RAW}

echo "Sortiere die Bin�rdatei (dies kann ebenfalls dauern)..."
# BinSort kompilieren, falls noch nicht geschehen
(cd BinSort && make)
./BinSort/BinSort ${HASH_FILE_RAW} ${HASH_FILE_SORTED}

echo "Bereinige tempor�re Dateien..."
rm ${HASH_FILE_RAW}
echo "Vorbereitung der Adressdatei abgeschlossen. Die sortierte Datei ist '${HASH_FILE_SORTED}'."


# --- SUCHE STARTEN ---
echo -e "\n--- Starte KeyHunt auf ${GPU_COUNT} GPU(s) ---"

# Erstellt die GPU-ID-Liste (z.B. "0,1,2,3")
GPU_IDS=$(seq -s, 0 $((GPU_COUNT - 1)))

echo "Verwendete GPU-IDs: ${GPU_IDS}"
echo "Verwendete Zieldatei: ${HASH_FILE_SORTED}"
echo "Verwendeter Suchbereich: --range ${KEY_RANGE}"
echo "Der Suchprozess wird jetzt gestartet. Dr�cken Sie STRG+C, um ihn zu beenden."

# Der finale Befehl zum Starten der Suche
./KeyHunt --gpu --mode ADDRESSES --coin BTC -i ${HASH_FILE_SORTED} --gpui ${GPU_IDS} --range ${KEY_RANGE}

echo "Suche beendet."