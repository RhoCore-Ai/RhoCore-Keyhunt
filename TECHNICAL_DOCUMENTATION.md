# Technische Dokumentation: Key Filtering System in KeyHunt-Cuda

## Übersicht

Dieses Dokument beschreibt die Implementierung eines benutzerdefinierten Key-Filtering-Systems in KeyHunt-Cuda, das entwickelt wurde, um den Suchprozess durch das proaktive Verwerfen von privaten Schlüsseln zu optimieren, die statistisch unwahrscheinlichen Mustern folgen.

## Filterregeln

Das System implementiert zwei primäre Filterregeln, die auf der Hexadezimalrepräsentation der privaten Schlüssel basieren:

1. **Keine drei aufeinanderfolgenden, identischen Hexadezimalziffern** (...xxx...)
2. **Keine zwei direkt aufeinanderfolgenden Paare identischer Hexadezimalziffern** (...xxyy...)

## Implementierungsdetails

### 1. Zentrale Filterfunktion

Die Filterlogik ist in der `isKeyFiltered()`-Funktion der `KeyHunt`-Klasse gekapselt:

```cpp
bool KeyHunt::isKeyFiltered(Int& key);
```

Diese Funktion führt folgende Schritte aus:

1. **Hex-Konvertierung**: Konvertiert den 256-Bit-Schlüssel in einen Hex-String
2. **Normalisierung**: Füllt den String mit führenden Nullen auf eine feste Länge von 64 Zeichen auf
3. **Mustererkennung**: Sucht nach den beiden definierten Mustern in der Hexadezimalrepräsentation
4. **Rückgabewert**: Gibt `true` zurück, wenn der Schlüssel einem Muster entspricht, ansonsten `false`

### 2. CPU-Integration

Die Filterung wurde in die CPU-Worker-Schleife integriert, um eine optimale Leistung zu gewährleisten:

#### Block-Skipping-Optimierung
Anstatt jeden einzelnen Schlüssel zu überprüfen, wird eine Block-Skipping-Optimierung implementiert:

```cpp
// Skip entire blocks if the starting key is filtered
while (isKeyFiltered(key) && key.IsLower(&rangeEnd)) {
    // Skip the entire block by incrementing by CPU_GRP_SIZE
    key.Add((uint64_t)CPU_GRP_SIZE);
    count += CPU_GRP_SIZE;
    rkeyCount += CPU_GRP_SIZE;
}
```

Diese Optimierung ermöglicht es, ganze Blöcke von Schlüsseln zu überspringen, wenn der Startschlüssel eines Blocks gefiltert wird, was potenziell tausende unnötiger kryptografischer Operationen vermeidet.

### 3. GPU-Integration

Die vollständige GPU-Integration umfasst:

#### GPU-seitige Filterfunktion
Eine Gerätefunktion wurde implementiert, um die Filterung direkt auf der GPU durchzuführen:

```cpp
__device__ __forceinline__ bool isKeyFiltered(uint64_t* key);
```

Diese Funktion:
1. Konvertiert den 256-Bit-Schlüssel in eine Hexadezimalrepräsentation
2. Wendet die gleichen Filterregeln an wie die CPU-Version
3. Gibt `true` zurück, wenn der Schlüssel gefiltert werden soll

#### Integration in GPU-Kernel
Die Filterfunktion wurde in alle ComputeKeys-Funktionen integriert:

```cpp
// Check if the starting key should be filtered
if (isKeyFiltered(sx)) {
    // If key is filtered, skip the entire computation
    return;
}
```

Dies wurde für alle Suchmodi implementiert:
- SEARCH_MODE_MA (Multiple Addresses)
- SEARCH_MODE_SA (Single Address)
- SEARCH_MODE_MX (Multiple XPoints)
- SEARCH_MODE_SX (Single XPoint)
- ETH-Modi für Ethereum-Adressen

#### Vorteile der GPU-Integration
1. **Frühzeitiges Überspringen**: Schlüssel werden bereits vor teuren kryptografischen Berechnungen gefiltert
2. **Keine Datenübertragung**: Gefilterte Schlüssel werden nicht vom Host zum Gerät übertragen
3. **Volle Parallelität**: Jeder GPU-Thread filtert unabhängig seine Schlüssel

## Leistungsoptimierung

Die Implementierung wurde mit folgenden Optimierungen durchgeführt:

1. **Frühzeitige Filterung**: Die Filterung erfolgt vor teuren kryptografischen Operationen
2. **Block-Skipping**: Ganze Blöcke werden übersprungen, wenn der Startschlüssel gefiltert ist
3. **String-basierte Prüfung**: Die Filterung erfolgt auf der CPU, wo die Schlüssel generiert werden
4. **GPU-seitige Filterung**: Direkte Filterung in den GPU-Kernels vermeidet unnötige Berechnungen

## Zukünftige Verbesserungen

1. **Erweiterte Filterregeln**: Hinzufügen zusätzlicher Filterregeln basierend auf statistischen Analysen
2. **Konfigurierbare Regeln**: Ermöglichen der Konfiguration der Filterregeln zur Laufzeit
3. **Optimierte Hex-Konvertierung**: Verbesserung der GPU-seitigen Hex-Konvertierung für bessere Leistung