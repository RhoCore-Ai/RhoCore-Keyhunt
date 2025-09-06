import subprocess
import os
import random
import time
import requests
import csv
import sys

# ==============================================================================
# BENUTZERKONFIGURATION
# ==============================================================================

# Pfad zur KeyHunt-Executable (wird für Linux/Windows angepasst)
KEYHUNT_EXECUTABLE = "./KeyHunt-Cuda/KeyHunt" if os.name != 'nt' else ".\\KeyHunt-Cuda\\x64\\Release\\KeyHunt-Cuda.exe"

# Pfad zur Zieldatei (hash160.bin)
HASH_FILE = "hash160.bin"

# GPUs, die verwendet werden sollen (wird automatisch erkannt)
GPU_IDS = ",".join([str(i) for i in range(int(os.getenv('GPU_COUNT', '1')))])

# --- SICHERHEITSUPDATE: Lese sensible Daten aus Umgebungsvariablen ---
# Lesen des Bot-Tokens und der Chat-ID aus der Umgebung.
# Anweisungen zum Setzen dieser Variablen finden Sie in der SETUP_GUIDE.md.
TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN")
TELEGRAM_CHAT_ID = os.getenv("TELEGRAM_CHAT_ID")

# Pfad zur Puzzle-Datenbank
PUZZLE_CSV_FILE = "bitcoin-puzzle-all-20250906.csv"

# Größe eines Arbeitspakets (Work Unit) in Hex.
WORK_UNIT_SIZE_HEX = "10000000000000000000000000"  # 2^168

# Anzahl der Durchläufe, bevor der Zufallsmodus aktiviert wird
RUNS_BEFORE_RANDOM = 5

# Maximale Laufzeit pro Durchlauf in Sekunden (24 Stunden)
MAX_RUN_TIME = 24 * 60 * 60

# ==============================================================================
# HILFSFUNKTIONEN
# ==============================================================================

def send_telegram_message(message):
    """Sendet eine Nachricht über Telegram, falls Token und Chat-ID gesetzt sind."""
    if TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID:
        try:
            url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
            data = {"chat_id": TELEGRAM_CHAT_ID, "text": message}
            requests.post(url, data=data)
        except Exception as e:
            print(f"Konnte keine Telegram-Nachricht senden: {e}")


def get_puzzle_data():
    """Liest die Puzzle-Daten aus der CSV-Datei."""
    puzzles = []
    try:
        with open(PUZZLE_CSV_FILE, 'r', encoding='utf-8') as csvfile:
            reader = csv.DictReader(csvfile)
            for row in reader:
                puzzles.append({
                    'key': row['key'],
                    'address': row['address'],
                    'hex': row['hex'],
                    'private_key': row['private_key'],
                    'bits': int(row['bits'])
                })
    except FileNotFoundError:
        print(f"Fehler: {PUZZLE_CSV_FILE} nicht gefunden.")
        send_telegram_message(f"Fehler: {PUZZLE_CSV_FILE} nicht gefunden.")
        return []
    except Exception as e:
        print(f"Fehler beim Lesen der Puzzle-Daten: {e}")
        send_telegram_message(f"Fehler beim Lesen der Puzzle-Daten: {e}")
        return []
    return puzzles


def find_puzzles_in_range(start_hex, end_hex):
    """Findet alle Puzzles, die im gegebenen Bereich liegen."""
    puzzles = get_puzzle_data()
    if not puzzles:
        return []

    # Konvertiere Hex-Werte in Ganzzahlen für den Vergleich
    try:
        start_int = int(start_hex, 16)
        end_int = int(end_hex, 16)
    except ValueError:
        print("Ungültige Hex-Werte für den Bereich.")
        return []

    # Finde Puzzles im Bereich
    matching_puzzles = []
    for puzzle in puzzles:
        try:
            puzzle_key_int = int(puzzle['key'], 16)
            if start_int <= puzzle_key_int <= end_int:
                matching_puzzles.append(puzzle)
        except ValueError:
            continue  # Überspringe ungültige Puzzle-Schlüssel

    return matching_puzzles


def format_hex_range(start, end):
    """Formatiert den Hex-Bereich für die Ausgabe."""
    return f"{start}:{end}"


def generate_random_range():
    """Generiert einen zufälligen Bereich basierend auf der Work Unit Größe."""
    # Generiere eine zufällige Startzahl
    max_start = int("FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364140", 16) - int(WORK_UNIT_SIZE_HEX, 16)
    start_int = random.randint(1, max_start)
    end_int = start_int + int(WORK_UNIT_SIZE_HEX, 16)

    start_hex = format(start_int, 'x')
    end_hex = format(end_int, 'x')

    return start_hex, end_hex


def generate_sequential_range(last_end_hex=None):
    """Generiert einen sequenziellen Bereich basierend auf dem letzten Endwert."""
    if last_end_hex is None:
        # Starte am Anfang, wenn kein letzter Wert vorhanden ist
        start_int = 1
    else:
        # Starte direkt nach dem letzten Endwert
        start_int = int(last_end_hex, 16) + 1

    end_int = start_int + int(WORK_UNIT_SIZE_HEX, 16) - 1

    start_hex = format(start_int, 'x')
    end_hex = format(end_int, 'x')

    return start_hex, end_hex


def run_keyhunt(range_str, gpu_ids):
    """Führt KeyHunt mit den gegebenen Parametern aus."""
    cmd = [
        KEYHUNT_EXECUTABLE,
        "--gpu",
        "--mode", "ADDRESSES",
        "--coin", "BTC",
        "-i", HASH_FILE,
        "--gpui", gpu_ids,
        "--range", range_str
    ]

    print(f"Starte KeyHunt mit Befehl: {' '.join(cmd)}")
    send_telegram_message(f"Starte KeyHunt-Suche im Bereich {range_str}")

    try:
        # Führe den Befehl aus und warte auf das Ende
        process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

        start_time = time.time()
        while process.poll() is None:
            # Prüfe, ob die maximale Laufzeit überschritten wurde
            if time.time() - start_time > MAX_RUN_TIME:
                print("Maximale Laufzeit überschritten. Beende KeyHunt...")
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                break

            # Lies die Ausgabe zeilenweise
            output = process.stdout.readline()
            if output:
                print(output.strip())
                # Optional: Hier könnten bestimmte Ausgaben für Status-Updates verwendet werden

        # Hole den Rückgabewert
        return_code = process.returncode
        print(f"KeyHunt beendet mit Rückgabewert: {return_code}")
        send_telegram_message(f"KeyHunt-Suche im Bereich {range_str} beendet mit Rückgabewert: {return_code}")

        return return_code, None
    except Exception as e:
        error_msg = f"Fehler beim Ausführen von KeyHunt: {e}"
        print(error_msg)
        send_telegram_message(error_msg)
        return -1, str(e)


# ==============================================================================
# HAUPTPROGRAMM
# ==============================================================================

def main():
    """Hauptfunktion des Managers."""
    print("KeyHunt Manager gestartet")
    send_telegram_message("KeyHunt Manager gestartet")

    # Prüfe, ob die KeyHunt-Executable existiert
    if not os.path.exists(KEYHUNT_EXECUTABLE):
        error_msg = f"Fehler: KeyHunt-Executable nicht gefunden unter {KEYHUNT_EXECUTABLE}"
        print(error_msg)
        send_telegram_message(error_msg)
        return

    # Prüfe, ob die Hash-Datei existiert
    if not os.path.exists(HASH_FILE):
        error_msg = f"Fehler: Hash-Datei nicht gefunden unter {HASH_FILE}"
        print(error_msg)
        send_telegram_message(error_msg)
        return

    run_count = 0
    last_end_hex = None
    use_random_mode = False

    try:
        while True:
            run_count += 1

            # Wechsel in den Zufallsmodus nach einer bestimmten Anzahl von Durchläufen
            if run_count > RUNS_BEFORE_RANDOM:
                use_random_mode = True
                print("Wechsle in den Zufallsmodus...")
                send_telegram_message("Wechsle in den Zufallsmodus für die Bereichsgenerierung")

            # Generiere den Suchbereich
            if use_random_mode:
                start_hex, end_hex = generate_random_range()
                range_description = "zufällig"
            else:
                start_hex, end_hex = generate_sequential_range(last_end_hex)
                range_description = "sequenziell"

            range_str = format_hex_range(start_hex, end_hex)
            last_end_hex = end_hex

            print(f"\n[{run_count}] Starte Suche im {range_description}en Bereich: {range_str}")
            
            # Prüfe auf Puzzles im Bereich
            puzzles_in_range = find_puzzles_in_range(start_hex, end_hex)
            if puzzles_in_range:
                puzzle_info = f"Im Bereich befinden sich {len(puzzles_in_range)} bekannte Puzzle-Adressen:"
                for puzzle in puzzles_in_range:
                    puzzle_info += f"\n- Puzzle {puzzle['bits']} bits: {puzzle['address']}"
                print(puzzle_info)
                send_telegram_message(puzzle_info)

            # Führe KeyHunt aus
            return_code, error = run_keyhunt(range_str, GPU_IDS)

            if return_code != 0 and error:
                print(f"Fehler bei der Ausführung: {error}")
                send_telegram_message(f"Fehler bei der Ausführung: {error}")
                # Warte etwas vor dem nächsten Versuch
                time.sleep(10)
                continue

            # Warte etwas vor dem nächsten Durchlauf
            print("Warte 5 Sekunden vor dem nächsten Durchlauf...")
            time.sleep(5)

    except KeyboardInterrupt:
        print("\nManager durch Benutzer beendet.")
        send_telegram_message("KeyHunt Manager durch Benutzer beendet")
    except Exception as e:
        error_msg = f"Unerwarteter Fehler im Manager: {e}"
        print(error_msg)
        send_telegram_message(error_msg)
    finally:
        print("KeyHunt Manager beendet.")
        send_telegram_message("KeyHunt Manager beendet")


if __name__ == "__main__":
    main()