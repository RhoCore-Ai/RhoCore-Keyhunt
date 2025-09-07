#ifndef KEYHUNT_H
#define KEYHUNT_H

#include <string>
#include <vector>
#include <stdint.h>
#include "Int.h"
#include "Point.h"
#include "SECP256k1.h"
#include "Bloom.h"
#include "MLFilter.h"

// Struktur zur Speicherung von Hash-Werten
typedef struct {
    unsigned char hash[20];
} HASH160;

// Struktur zur Speicherung von Suchergebnissen
typedef struct {
    bool compressed;
    Point publicKey;
    Int privateKey;
} KEYSEARCHRESULT;

// Struktur zur Definition von Suchbereichen für Threads
typedef struct {
    Int start;
    Int end;
    double speed;
    uint64_t total;
    int threadId;
    int deviceId;
} THREADRANGE;

class KeyHunt {
public:
    KeyHunt(const std::string& target, int mode, int coin, int range, bool useGpu, const std::string& inputFile, bool useBloom, uint32_t bloomFilterSize, uint64_t bloomFilterNum, const std::string& rangeStart, const std::string& rangeEnd, bool& success);
    ~KeyHunt();

    void Search();
    void GetFinalResult(std::vector<KEYSEARCHRESULT>& results);

private:
    // Klassenvariablen
    int searchMode;
    int coinType;
    int compression;
    bool useGpu;
    bool useBloomFilter;
    bool useMLFilter;
    Int rangeStart;
    Int rangeEnd;
    Secp256K1* secp;
    Bloom* bloom;
    MLFilter* mlFilter;
    uint64_t totalKeys;
    uint64_t totalChecks;
    time_t startTime;
    time_t endTime;
    std::vector<KEYSEARCHRESULT> finalResult;
    std::vector<THREADRANGE> threadRanges;
    std::vector<HASH160> TARGET_HASH;
    uint64_t ITEM_COUNT;

    // Methoden
    bool isKeyFiltered(Int& key);
    void SetupRanges(uint32_t numThreads);
    void FindKeyCPUThread(void* param);
    static void* _FindKeyCPUThread(void* lpParam);
    void CheckAddresses(bool compressed, Int key, uint32_t* found);
    bool CheckAddress(const uint8_t* hash160, bool compressed, Int& key, uint32_t* found);
    void OutputFound(const KEYSEARCHRESULT& result);
};

#endif // KEYHUNT_H