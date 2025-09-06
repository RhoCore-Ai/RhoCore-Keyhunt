# KeyHunt-Cuda - Modern GPU Support

## Unterstützte Grafikkarten

Dieses Projekt unterstützt alle modernen NVIDIA Grafikkarten:

- **RTX 50XX Series** (Compute Capability 12.0) - Vorläufige Unterstützung
- **RTX 40XX Series** (Compute Capability 8.9)
- **RTX 30XX Series** (Compute Capability 8.6)
- **RTX 20XX Series** (Compute Capability 7.5)
- **Andere moderne GPUs** mit Compute Capabilities 3.0-12.0

## Abhängigkeiten prüfen

Stellt sicher, dass das Skript bei einem Fehler sofort beendet wird.
```bash
set -e
```

### System-Abhängigkeiten

Das Skript überprüft und installiert automatisch folgende Abhängigkeiten:
- build-essential
- wget
- gzip
- libgmp-dev
- python3
- python3-pip
- python3-venv
- NVIDIA-Treiber (nvidia-smi)

## Hardware erkennen

Das Skript erkennt automatisch:
- Anzahl der verfügbaren NVIDIA GPUs
- Compute Capability der Haupt-GPU
- Entsprechende GPU-Serie (RTX 20XX/30XX/40XX/50XX)

## Konfiguration

### Suchbereich
Wählen Sie den Bit-Bereich für die Schlüsselsuche:
- Bit 1-32
- Bit 33-64
- Bit 65-96
- Bit 97-128
- Bit 129-160
- Bit 161-192
- Bit 193-224
- Bit 225-256
- Manuelle Eingabe

## Kompilierung

Das Projekt wird automatisch für die erkannte GPU-Serie kompiliert:

- **RTX 50XX**: `make gpu=1 CCAP=120`
- **RTX 40XX**: `make gpu=1 CCAP=89`
- **RTX 30XX**: `make gpu=1 CCAP=86`
- **RTX 20XX**: `make gpu=1 CCAP=75`

## Datenvorbereitung

Das Skript lädt automatisch die aktuellsten Bitcoin-Adressen und bereitet sie für die Suche vor:
1. Download von Bitcoin_addresses_LATEST.txt.gz
2. Entpacken der Datei
3. Konvertierung der Adressen zu hash160
4. Sortierung der Binärdatei für optimierte Suche

## Verwendung

Einfach `./start.sh` ausführen und den Anweisungen folgen.

### Manuelle Kompilierung

Wenn Sie manuell kompilieren möchten:

```bash
cd KeyHunt-Cuda
make clean
# Für RTX 50XX:
make KeyHunt gpu=1 CCAP=120
# Für RTX 40XX:
make KeyHunt gpu=1 CCAP=89
# Für RTX 30XX:
make KeyHunt gpu=1 CCAP=86
# Für RTX 20XX:
make KeyHunt gpu=1 CCAP=75
```

## Windows Build

Öffnen Sie KeyHunt-Cuda.sln in Visual Studio 2022 mit CUDA 12.0 installiert und bauen Sie das Projekt normal.

## Kompatibilität

Das Projekt ist vollständig kompatibel mit CUDA 12.X und sollte ohne Probleme auf allen modernen NVIDIA GPUs funktionieren.