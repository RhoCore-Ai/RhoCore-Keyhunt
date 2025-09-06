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

Die aktuelle GPU-Implementierung verwendet die bestehenden Suchmechanismen. Zukünftige Verbesserungen könnten die Filterung direkt in die GPU-Kernel integrieren, um noch bessere Leistung zu erzielen.

## Leistungsoptimierung

Die Implementierung wurde mit folgenden Optimierungen durchgeführt:

1. **Frühzeitige Filterung**: Die Filterung erfolgt vor teuren kryptografischen Operationen
2. **Block-Skipping**: Ganze Blöcke werden übersprungen, wenn der Startschlüssel gefiltert ist
3. **String-basierte Prüfung**: Die Filterung erfolgt auf der CPU, wo die Schlüssel generiert werden

## Zukünftige Verbesserungen

1. **GPU-Kernel-Integration**: Implementierung der Filterlogik direkt in den GPU-Kernels
2. **Erweiterte Filterregeln**: Hinzufügen zusätzlicher Filterregeln basierend auf statistischen Analysen
3. **Konfigurierbare Regeln**: Ermöglichen der Konfiguration der Filterregeln zur Laufzeit