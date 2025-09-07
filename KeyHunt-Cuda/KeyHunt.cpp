#include "KeyHunt.h"
#include "GmpUtil.h"
#include "Base58.h"
#include "hash/sha256.h"
#include "hash/keccak160.h"
#include "IntGroup.h"
#include "Timer.h"
#include "hash/ripemd160.h"
#include <cstring>
#include <cmath>
#include <algorithm>
#include <iostream>
#include <cassert>
#ifndef WIN64
#include <pthread.h>
#endif

#define CPU_GRP_SIZE 64

// Definitionen für Kompatibilität
#define SEARCH_MODE_SA 0
#define SEARCH_MODE_SX 1
#define SEARCH_MODE_MA 2
#define SEARCH_MODE_MX 3
#define COIN_BTC 0
#define COIN_ETH 1
#define SEARCH_COMPRESSED 0
#define SEARCH_UNCOMPRESSED 1
#define SEARCH_BOTH 2

// Struktur für Thread-Parameter
typedef struct {
    KeyHunt* obj;
    int threadId;
    uint64_t rKeyCount;
    bool hasStarted;
    bool endOfSearch;
} TH_PARAM;


// Globale Variablen für CPU-Berechnung
Point Gn[CPU_GRP_SIZE / 2];
Point _2Gn;

KeyHunt::KeyHunt(const std::string& target, int mode, int coin, int range, bool useGpu,
                 const std::string& inputFile, bool useBloom, uint32_t bloomFilterSize,
                 uint64_t bloomFilterNum, const std::string& rangeStartStr,
                 const std::string& rangeEndStr, bool& success)
{
    this->searchMode = mode;
    this->coinType = coin;
    this->compression = range;
    this->useGpu = useGpu;
    this->useBloomFilter = useBloom;
    this->rangeStart.SetBase16(rangeStartStr.c_str());
    this->rangeEnd.SetBase16(rangeEndStr.c_str());
    this->totalKeys = 0;
    this->totalChecks = 0;
    this->startTime = time(NULL);

    secp = new Secp256K1();
    secp->Init();

    bloom = new Bloom(bloomFilterSize, bloomFilterNum, 0);
    mlFilter = new MLFilter();

    FILE* wfd = fopen(inputFile.c_str(), "rb");
    if (!wfd) {
        printf("Error, can't open the input file: %s\n", inputFile.c_str());
        success = false;
        return;
    }

    fseek(wfd, 0, SEEK_END);
    uint64_t fileSize = ftell(wfd);
    rewind(wfd);

    if (fileSize % 20 != 0) {
        printf("Error, input file size is not a multiple of 20 bytes\n");
        success = false;
        fclose(wfd);
        return;
    }

    uint64_t N = fileSize / 20;
    this->ITEM_COUNT = N;
    this->TARGET_HASH.resize(N);
    uint8_t* buf = new uint8_t[N * 20];
    size_t readSize = fread(buf, 1, N * 20, wfd);
    if(readSize != N * 20) {
        printf("Error reading from file\n");
        success = false;
    }
    for (uint64_t i = 0; i < N; i++) {
        memcpy(this->TARGET_HASH[i].hash, buf + i * 20, 20);
    }
    delete[] buf;
    fclose(wfd);

    if (useBloomFilter) {
        bloom->Init(this->TARGET_HASH);
    }
}

KeyHunt::~KeyHunt()
{
    if (secp) delete secp;
    if (bloom) delete bloom;
    if (mlFilter) delete mlFilter;
}

void KeyHunt::Search()
{
    if (this->useGpu) {
        printf("\nGPU search not implemented in this version.\n\n");
    } else {
        int numThreads = Timer::getCoreNumber();
        SetupRanges(numThreads);
        
        TH_PARAM* params = new TH_PARAM[numThreads];
        pthread_t* threads = new pthread_t[numThreads];

        for(int i = 0; i < numThreads; i++) {
            params[i].obj = this;
            params[i].threadId = i;
            pthread_create(&threads[i], NULL, _FindKeyCPUThread, &params[i]);
        }

        for(int i = 0; i < numThreads; i++) {
            pthread_join(threads[i], NULL);
        }
        
        delete[] params;
        delete[] threads;
    }
}

void KeyHunt::GetFinalResult(std::vector<KEYSEARCHRESULT>& results)
{
    results = this->finalResult;
}

bool KeyHunt::isKeyFiltered(Int& key)
{
    std::string hexStr = key.GetBase16();
    if (hexStr.length() < 64) {
        hexStr.insert(0, 64 - hexStr.length(), '0');
    }
    return mlFilter->isKeyFiltered(hexStr);
}

void KeyHunt::SetupRanges(uint32_t numThreads)
{
    threadRanges.resize(numThreads);
    Int rangeTotal = rangeEnd;
    rangeTotal.Sub(&rangeStart);
    rangeTotal.AddOne();

    Int itemsPerThread = rangeTotal;
    Int divInt(numThreads);
    itemsPerThread.Div(&divInt, NULL);

    for(uint32_t i = 0; i < numThreads; i++) {
        threadRanges[i].start = rangeStart;
        Int offset = itemsPerThread;
        offset.Mult(i);
        threadRanges[i].start.Add(&offset);

        threadRanges[i].end = threadRanges[i].start;
        threadRanges[i].end.Add(&itemsPerThread);
        
        if (i == numThreads - 1) {
            threadRanges[i].end = rangeEnd;
        }
    }
}

void* KeyHunt::_FindKeyCPUThread(void* lpParam)
{
    TH_PARAM* p = (TH_PARAM*)lpParam;
    p->obj->FindKeyCPUThread(p);
    return NULL;
}

void KeyHunt::FindKeyCPUThread(void* param)
{
    TH_PARAM* p = (TH_PARAM*)param;
    Int key = threadRanges[p->threadId].start;
    Int end = threadRanges[p->threadId].end;
    uint32_t found = 0;

    while(key.IsLower(&end)) {
        if(!isKeyFiltered(key)) {
            if(compression == SEARCH_COMPRESSED || compression == SEARCH_BOTH) {
                CheckAddresses(true, key, &found);
            }
            if(compression == SEARCH_UNCOMPRESSED || compression == SEARCH_BOTH) {
                CheckAddresses(false, key, &found);
            }
        }
        key.AddOne();
    }
}

void KeyHunt::CheckAddresses(bool compressed, Int key, uint32_t* found)
{
    Point p = secp->ComputePublicKey(key);
    uint8_t hash[20];
    secp->GetHash160(compressed, p, hash);
    if(CheckAddress(hash, compressed, key, found)) {
        // Optional: early exit if needed
    }
}

bool KeyHunt::CheckAddress(const uint8_t* hash160, bool compressed, Int& key, uint32_t* found)
{
    if(useBloomFilter) {
        if(!bloom->Check(hash160)) {
            return false;
        }
    }
    
    for(uint64_t i = 0; i < ITEM_COUNT; i++) {
        if(memcmp(hash160, TARGET_HASH[i].hash, 20) == 0) {
            KEYSEARCHRESULT res;
            res.privateKey = key;
            res.publicKey = secp->ComputePublicKey(key);
            res.compressed = compressed;
            OutputFound(res);
            (*found)++;
            return true;
        }
    }
    return false;
}

void KeyHunt::OutputFound(const KEYSEARCHRESULT& result)
{
    std::string keyHex = result.privateKey.GetBase16();
    std::string addr = secp->GetAddress(result.compressed, result.publicKey);
    printf("\n--- Match Found ---\n");
    printf("PrivateKey: %s\n", keyHex.c_str());
    printf("Address:    %s\n", addr.c_str());
    printf("-------------------\n");
    finalResult.push_back(result);
}