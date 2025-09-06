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

//using namespace std;

Point Gn[CPU_GRP_SIZE / 2];
Point _2Gn;

// ====================================================================================
// <<< ANFANG: NEUE HELFERFUNKTION FÜR DAS REGELWERK >>>
// ====================================================================================
/**
 * @brief Überprüft einen Schlüssel anhand des benutzerdefinierten Regelwerks.
 * @param key Der zu überprüfende private Schlüssel als Int-Objekt.
 * @return true, wenn der Schlüssel übersprungen werden soll, ansonsten false.
 */
bool KeyHunt::isKeyFiltered(Int& key)
{
    // Konvertiere den Schlüssel in einen Hex-String für die Analyse
    std::string hexStr = key.GetBase16();

    // Fülle mit führenden Nullen auf, um eine feste Länge von 64 zu gewährleisten
    if (hexStr.length() < 64) {
        hexStr.insert(0, 64 - hexStr.length(), '0');
    }

    // Finde die erste Ziffer, die nicht '0' ist
    size_t first_digit_pos = hexStr.find_first_not_of('0');
    if (first_digit_pos == std::string::npos) {
        return false; // Schlüssel ist 0
    }

    // Wende die Filterregeln nur auf den relevanten Teil des Schlüssels an
    // Wir prüfen ab der ersten signifikanten Ziffer
    if (first_digit_pos < 62) { // Sicherstellen, dass wir nicht über das Ende hinauslesen
        size_t i = first_digit_pos;
        while (i < hexStr.length() - 2) {
            // Regel 1: Keine drei aufeinanderfolgenden gleichen Zeichen (xxx)
            if (hexStr[i] == hexStr[i+1] && hexStr[i] == hexStr[i+2]) {
                // Optimierung: Überspringe ganze Block von identischen chars
                char skip_char = hexStr[i];
                size_t j = i + 3;
                while (j < hexStr.length() && hexStr[j] == skip_char) {
                    ++j;
                }
                i = j;
                return true; // Schlüssel überspringen
            }
            // Regel 2: Keine zwei aufeinanderfolgenden Paare (xxyy)
            if (i < hexStr.length() - 3) {
                if (hexStr[i] == hexStr[i+1] && hexStr[i+2] == hexStr[i+3] && hexStr[i] != hexStr[i+2]) {
                    return true; // Schlüssel überspringen
                }
            }
            ++i;
        }
    }

    return false; // Schlüssel ist gültig
}
// ====================================================================================
// <<< ENDE: NEUE HELFERFUNKTION FÜR DAS REGELWERK >>>
// ====================================================================================


// ----------------------------------------------------------------------------

KeyHunt::KeyHunt(const std::string& inputFile, int compMode, int searchMode, int coinType, bool useGpu,
	const std::string& outputFile, bool useSSE, uint32_t maxFound, uint64_t rKey,
	const std::string& rangeStart, const std::string& rangeEnd, bool& should_exit)
{
	this->compMode = compMode;
	this->useGpu = useGpu;
	this->outputFile = outputFile;
	this->useSSE = useSSE;
	this->nbGPUThread = 0;
	this->inputFile = inputFile;
	this->maxFound = maxFound;
	this->rKey = rKey;
	this->searchMode = searchMode;
	this->coinType = coinType;
	this->rangeStart.SetBase16(rangeStart.c_str());
	this->rangeEnd.SetBase16(rangeEnd.c_str());
	this->rangeDiff2.Set(&this->rangeEnd);
	this->rangeDiff2.Sub(&this->rangeStart);
	this->lastrKey = 0;

	secp = new Secp256K1();
	secp->Init();

	// load file
	FILE* wfd;
	uint64_t N = 0;

	wfd = fopen(this->inputFile.c_str(), "rb");
	if (!wfd) {
		printf("Error, can't open the input file: %s\n", this->inputFile.c_str());
		should_exit = true;
		return;
	}

	fseek(wfd, 0, SEEK_END);
	uint64_t fileSize = ftell(wfd);
	rewind(wfd);

	if (this->searchMode == SEARCH_MODE_MA || this->searchMode == SEARCH_MODE_MX) {
		// For addresses and xpoints, we know the input size
		if (this->coinType == COIN_BTC) {
			if (fileSize % 20 != 0) {
				printf("Error, input file size is not a multiple of 20 bytes (Bitcoin P2PKH address size)\n");
				should_exit = true;
				fclose(wfd);
				return;
			}
			N = fileSize / 20;
		}
		else if (this->coinType == COIN_ETH) {
			if (fileSize % 20 != 0) {
				printf("Error, input file size is not a multiple of 20 bytes (Ethereum address size)\n");
				should_exit = true;
				fclose(wfd);
				return;
			}
			N = fileSize / 20;
		}
		else {
			printf("Error, unknow coin type\n");
			should_exit = true;
			fclose(wfd);
			return;
		}
	}
	else if (this->searchMode == SEARCH_MODE_SA || this->searchMode == SEARCH_MODE_SX) {
		// For single address or xpoint, we only need one item
		N = 1;
		if (this->coinType == COIN_BTC) {
			if (fileSize != 20) {
				printf("Error, input file size is not 20 bytes (Bitcoin P2PKH address size) for single address search\n");
				should_exit = true;
				fclose(wfd);
				return;
			}
		}
		else if (this->coinType == COIN_ETH) {
			if (fileSize != 20) {
				printf("Error, input file size is not 20 bytes (Ethereum address size) for single address search\n");
				should_exit = true;
				fclose(wfd);
				return;
			}
		}
		else {
			printf("Error, unknow coin type\n");
			should_exit = true;
			fclose(wfd);
			return;
		}
	}
	else {
		printf("Error, unknown search mode\n");
		should_exit = true;
		fclose(wfd);
		return;
	}

	if (N == 0) {
		printf("Error, the input file is empty\n");
		should_exit = true;
		fclose(wfd);
		return;
	}

	ITEM_COUNT = N;

	if (this->searchMode == SEARCH_MODE_MA || this->searchMode == SEARCH_MODE_MX) {
		// For multiple addresses or xpoints, we need to load all items
		if (this->coinType == COIN_BTC) {
			this->TARGET_HASH.resize(N);
			uint8_t* buf = new uint8_t[N * 20];
			fread(buf, 1, N * 20, wfd);
			for (uint64_t i = 0; i < N; i++) {
				memcpy(this->TARGET_HASH[i].hash, buf + i * 20, 20);
			}
			delete[] buf;
		}
		else if (this->coinType == COIN_ETH) {
			this->TARGET_HASH.resize(N);
			uint8_t* buf = new uint8_t[N * 20];
			fread(buf, 1, N * 20, wfd);
			for (uint64_t i = 0; i < N; i++) {
				memcpy(this->TARGET_HASH[i].hash, buf + i * 20, 20);
			}
			delete[] buf;
		}
	}
	else if (this->searchMode == SEARCH_MODE_SA || this->searchMode == SEARCH_MODE_SX) {
		// For single address or xpoint, we only need to load one item
		if (this->coinType == COIN_BTC) {
			this->TARGET_HASH.resize(1);
			fread(this->TARGET_HASH[0].hash, 1, 20, wfd);
		}
		else if (this->coinType == COIN_ETH) {
			this->TARGET_HASH.resize(1);
			fread(this->TARGET_HASH[0].hash, 1, 20, wfd);
		}
	}

	fclose(wfd);

	// Init bloom
	if (this->searchMode == SEARCH_MODE_MA || this->searchMode == SEARCH_MODE_MX) {
		bloom.Init(this->TARGET_HASH);
	}

	// Display info
	if (this->coinType == COIN_BTC) {
		if (this->searchMode == SEARCH_MODE_MA) {
			printf("Loaded %llu Bitcoin addresses\n", (unsigned long long int)N);
		}
		else if (this->searchMode == SEARCH_MODE_SA) {
			printf("Loaded 1 Bitcoin address\n");
			printf("Target address: ");
			for (int i = 0; i < 20; i++) {
				printf("%02x", this->TARGET_HASH[0].hash[i]);
			}
			printf("\n");
		}
		else if (this->searchMode == SEARCH_MODE_MX) {
			printf("Loaded %llu Bitcoin xpoints\n", (unsigned long long int)N);
		}
		else if (this->searchMode == SEARCH_MODE_SX) {
			printf("Loaded 1 Bitcoin xpoint\n");
			printf("Target xpoint: ");
			for (int i = 0; i < 20; i++) {
				printf("%02x", this->TARGET_HASH[0].hash[i]);
			}
			printf("\n");
		}
	}
	else if (this->coinType == COIN_ETH) {
		if (this->searchMode == SEARCH_MODE_MA) {
			printf("Loaded %llu Ethereum addresses\n", (unsigned long long int)N);
		}
		else if (this->searchMode == SEARCH_MODE_SA) {
			printf("Loaded 1 Ethereum address\n");
			printf("Target address: ");
			for (int i = 0; i < 20; i++) {
				printf("%02x", this->TARGET_HASH[0].hash[i]);
			}
			printf("\n");
		}
		else if (this->searchMode == SEARCH_MODE_MX) {
			printf("Loaded %llu Ethereum xpoints\n", (unsigned long long int)N);
		}
		else if (this->searchMode == SEARCH_MODE_SX) {
			printf("Loaded 1 Ethereum xpoint\n");
			printf("Target xpoint: ");
			for (int i = 0; i < 20; i++) {
				printf("%02x", this->TARGET_HASH[0].hash[i]);
			}
			printf("\n");
		}
	}

	// Compute generator table
	if (!useGpu) {
		// CPU mode
		if (this->compMode) {
			// Compute compressed table
			Gn[0] = secp->ComputePublicKey(Int((uint64_t)1));
			_2Gn = secp->DoubleDirect(Gn[0]);
			for (int i = 1; i < CPU_GRP_SIZE / 2; i++) {
				Gn[i] = secp->AddDirect(Gn[i - 1], _2Gn);
			}
		}
		else {
			// Compute uncompressed table
			Gn[0] = secp->ComputePublicKey(Int((uint64_t)1));
			_2Gn = secp->DoubleDirect(Gn[0]);
			for (int i = 1; i < CPU_GRP_SIZE / 2; i++) {
				Gn[i] = secp->AddDirect(Gn[i - 1], _2Gn);
			}
		}
	}
}

// ----------------------------------------------------------------------------

KeyHunt::~KeyHunt()
{
	if (secp) delete secp;
}

// ----------------------------------------------------------------------------

void KeyHunt::GetFinalResult(std::vector<KEYSEARCHRESULT>& result)
{
	result.insert(result.end(), this->lastFound.begin(), this->lastFound.end());
	this->lastFound.clear();
}

// ----------------------------------------------------------------------------

void KeyHunt::OutputFound(const KEYSEARCHRESULT& result)
{
	// Convert key to base16
	std::string keyStr = result.key.GetBase16();

	// Compute public key
	Point pub = secp->ComputePublicKey(result.key);

	// Convert public key to address
	std::string addrStr;
	if (this->coinType == COIN_BTC) {
		if (this->compMode) {
			addrStr = secp->GetAddress(true, pub);
		}
		else {
			addrStr = secp->GetAddress(false, pub);
		}
	}
	else if (this->coinType == COIN_ETH) {
		addrStr = secp->GetAddressETH(pub);
	}

	// Output
	if (this->coinType == COIN_BTC) {
		if (this->compMode) {
			printf("[+] Private key found: %s (compressed)\n", keyStr.c_str());
			printf("[+] Public key: %s (compressed)\n", secp->GetPublicKeyHex(true, pub).c_str());
		}
		else {
			printf("[+] Private key found: %s (uncompressed)\n", keyStr.c_str());
			printf("[+] Public key: %s (uncompressed)\n", secp->GetPublicKeyHex(false, pub).c_str());
		}
		printf("[+] Address: %s\n", addrStr.c_str());
	}
	else if (this->coinType == COIN_ETH) {
		printf("[+] Private key found: %s\n", keyStr.c_str());
		printf("[+] Public key: %s\n", secp->GetPublicKeyHex(true, pub).c_str());
		printf("[+] Address: %s\n", addrStr.c_str());
	}

	// Write to file
	if (!this->outputFile.empty()) {
		FILE* f = fopen(this->outputFile.c_str(), "a");
		if (f) {
			if (this->coinType == COIN_BTC) {
				if (this->compMode) {
					fprintf(f, "Private key: %s (compressed)\n", keyStr.c_str());
					fprintf(f, "Public key: %s (compressed)\n", secp->GetPublicKeyHex(true, pub).c_str());
				}
				else {
					fprintf(f, "Private key: %s (uncompressed)\n", keyStr.c_str());
					fprintf(f, "Public key: %s (uncompressed)\n", secp->GetPublicKeyHex(false, pub).c_str());
				}
				fprintf(f, "Address: %s\n\n", addrStr.c_str());
			}
			else if (this->coinType == COIN_ETH) {
				fprintf(f, "Private key: %s\n", keyStr.c_str());
				fprintf(f, "Public key: %s\n", secp->GetPublicKeyHex(true, pub).c_str());
				fprintf(f, "Address: %s\n\n", addrStr.c_str());
			}
			fclose(f);
		}
	}

	// Add to last found
	this->lastFound.push_back(result);
}

// ----------------------------------------------------------------------------

bool KeyHunt::CheckAddress(const uint8_t* hash160, bool compressed, Int& key, uint32_t* found)
{
	// Check bloom filter first
	if (this->searchMode == SEARCH_MODE_MA || this->searchMode == SEARCH_MODE_MX) {
		if (!bloom.Check(hash160)) {
			return false;
		}
	}
	else if (this->searchMode == SEARCH_MODE_SA || this->searchMode == SEARCH_MODE_SX) {
		if (memcmp(hash160, this->TARGET_HASH[0].hash, 20) != 0) {
			return false;
		}
	}

	// Found!
	KEYSEARCHRESULT result;
	result.key = key;
	result.compressed = compressed;
	result.hash160 = hash160;
	*found = *found + 1;
	OutputFound(result);

	return true;
}

// ----------------------------------------------------------------------------

void KeyHunt::CheckAddresses(bool compressed, Int key, uint32_t* found)
{
	// Check if key is filtered by rules
	if (isKeyFiltered(key)) {
		return;
	}

	// Compute public key
	Point pub = secp->ComputePublicKey(key);

	// Compute address
	uint8_t hash160[20];
	if (this->coinType == COIN_BTC) {
		if (compressed) {
			secp->GetHash160(true, pub, hash160);
		}
		else {
			secp->GetHash160(false, pub, hash160);
		}
	}
	else if (this->coinType == COIN_ETH) {
		secp->GetHash160ETH(pub, hash160);
	}

	// Check address
	CheckAddress(hash160, compressed, key, found);
}

// ----------------------------------------------------------------------------

void KeyHunt::SetupRanges(uint32_t totalThreads)
{
	// Compute range division
	Int rangeTotal(&this->rangeDiff2);
	rangeTotal.AddOne();

	Int rangeDiv = rangeTotal.Div(totalThreads);
	Int rangeMod = rangeTotal.Mod(totalThreads);

	// Setup ranges
	this->threadRanges.resize(totalThreads);
	for (uint32_t i = 0; i < totalThreads; i++) {
		this->threadRanges[i].start.Set(&this->rangeStart);
		this->threadRanges[i].start.Add(&rangeDiv.Mult(i));
		if (i < (uint32_t)rangeMod.GetInt32()) {
			this->threadRanges[i].start.Add((uint64_t)(i + 1));
		}
		else {
			this->threadRanges[i].start.Add((uint64_t)rangeMod.GetInt32());
		}

		this->threadRanges[i].end.Set(&this->threadRanges[i].start);
		this->threadRanges[i].end.Add(&rangeDiv);
		if (i < (uint32_t)rangeMod.GetInt32()) {
			this->threadRanges[i].end.AddOne();
		}

		// Make sure we don't exceed the range
		if (this->threadRanges[i].end.IsGreater(&this->rangeEnd)) {
			this->threadRanges[i].end.Set(&this->rangeEnd);
		}
	}
}

// ----------------------------------------------------------------------------

#ifdef WIN64
DWORD WINAPI KeyHunt::_FindKeyCPUThread(LPVOID lpParam)
{
	TH_PARAM* p = (TH_PARAM*)lpParam;
	KeyHunt* obj = (KeyHunt*)p->obj;
	obj->FindKeyCPUThread(p);
	return 0;
}
#else
void* KeyHunt::_FindKeyCPUThread(void* lpParam)
{
	TH_PARAM* p = (TH_PARAM*)lpParam;
	KeyHunt* obj = (KeyHunt*)p->obj;
	obj->FindKeyCPUThread(p);
	return 0;
}
#endif

// ----------------------------------------------------------------------------

void KeyHunt::FindKeyCPUThread(TH_PARAM* param)
{
	// Get thread range
	Int rangeStart(&this->threadRanges[param->threadId].start);
	Int rangeEnd(&this->threadRanges[param->threadId].end);
	Int rangeDiff(&rangeEnd);
	rangeDiff.Sub(&rangeStart);

	// Setup initial key
	Int key(&rangeStart);
	Int one((uint64_t)1);

	// Setup counters
	uint64_t count = 0;
	uint32_t found = 0;
	uint64_t rkeyCount = 0;

	// Setup timer
	Timer timer;
	timer.Start();

	// Search loop
	while (key.IsLower(&rangeEnd) && !param->endOfSearch) {
		// Apply key filtering before expensive operations
		// Skip entire blocks if the starting key is filtered
		while (isKeyFiltered(key) && key.IsLower(&rangeEnd)) {
			// Skip the entire block by incrementing by CPU_GRP_SIZE
			key.Add((uint64_t)CPU_GRP_SIZE);
			count += CPU_GRP_SIZE;
			rkeyCount += CPU_GRP_SIZE;
		}

		// Check if we've exceeded the range after skipping
		if (!key.IsLower(&rangeEnd)) {
			break;
		}

		// Process the block - only check individual keys if the block start is valid
		for (int i = 0; i < CPU_GRP_SIZE && key.IsLower(&rangeEnd) && !param->endOfSearch; i++) {
			// Check key
			if (this->compMode) {
				CheckAddresses(true, key, &found);
			}
			else {
				CheckAddresses(false, key, &found);
			}

			// Increment key
			key.AddOne();

			// Update counters
			count++;
			rkeyCount++;

			// Check if we need to report
			if (rkeyCount >= this->rKey) {
			param->rKeyCount = rkeyCount;
			rkeyCount = 0;
		}

		// Check if we found enough
		if (found >= this->maxFound) {
			param->endOfSearch = true;
		}
	}

	// Final report
	param->rKeyCount = rkeyCount;
	param->hasStarted = true;
	param->endOfSearch = true;
}

// ----------------------------------------------------------------------------

void KeyHunt::SearchCPU(int nbThread)
{
	// Setup ranges
	SetupRanges(nbThread);

	// Setup threads
	TH_PARAM* params = new TH_PARAM[nbThread];
	std::vector<THREAD_HANDLE> threadHandles(nbThread);

	// Start threads
	for (int i = 0; i < nbThread; i++) {
		params[i].obj = this;
		params[i].threadId = i;
		params[i].rKeyCount = 0;
		params[i].hasStarted = false;
		params[i].endOfSearch = false;
#ifdef WIN64
		threadHandles[i] = CreateThread(NULL, 0, _FindKeyCPUThread, (LPVOID)&params[i], 0, NULL);
#else
		pthread_create(&threadHandles[i], NULL, _FindKeyCPUThread, (void*)&params[i]);
#endif
	}

	// Wait for threads to start
	bool allStarted = false;
	while (!allStarted) {
		allStarted = true;
		for (int i = 0; i < nbThread; i++) {
			if (!params[i].hasStarted) {
				allStarted = false;
				break;
			}
		}
		Sleep(100);
	}

	// Wait for threads to finish
#ifdef WIN64
	WaitForMultipleObjects(nbThread, &threadHandles[0], TRUE, INFINITE);
#else
	for (int i = 0; i < nbThread; i++) {
		pthread_join(threadHandles[i], NULL);
	}
#endif

	// Cleanup
	delete[] params;
}

// ----------------------------------------------------------------------------

void KeyHunt::SearchGPU(int nbGPUThread, int gpuId, int nbGpu)
{
	// Setup GPU engines
	std::vector<GPUEngine*> gpuEngines(nbGpu);
	for (int i = 0; i < nbGpu; i++) {
		gpuEngines[i] = new GPUEngine(secp, nbGPUThread, 256, i, this->maxFound,
			this->searchMode, this->compMode, this->coinType,
			this->bloom.GetSize(), this->bloom.GetBits(), this->bloom.GetHashes(),
			this->bloom.GetData(), this->TARGET_HASH, this->ITEM_COUNT, this->rKey);
		if (!gpuEngines[i]->Initialize()) {
			printf("Error, cannot initialize GPU engine %d\n", i);
			return;
		}
	}

	// Setup counters
	uint64_t count = 0;
	uint32_t found = 0;
	uint64_t rkeyCount = 0;

	// Setup timer
	Timer timer;
	timer.Start();

	// Search loop
	bool searchFinished = false;
	while (!searchFinished) {
		// Run GPU engines
		for (int i = 0; i < nbGpu; i++) {
			uint32_t f = gpuEngines[i]->Search(gpuId + i, this->rangeStart, this->rangeEnd);
			found += f;
		}

		// Update counters
		count += nbGPUThread * 256 * nbGpu;
		rkeyCount += nbGPUThread * 256 * nbGpu;

		// Check if we need to report
		if (rkeyCount >= this->rKey) {
			// Report
			double speed = (double)count / timer.GetElapsedTime();
			if (this->coinType == COIN_BTC) {
				printf("Keys/s: %.2fK, Found: %u\n", speed / 1000.0, found);
			}
			else if (this->coinType == COIN_ETH) {
				printf("Keys/s: %.2fK, Found: %u\n", speed / 1000.0, found);
			}
			count = 0;
			rkeyCount = 0;
			timer.Start();
		}

		// Check if we found enough
		if (found >= this->maxFound) {
			searchFinished = true;
		}

		// Check if we need to get results
		for (int i = 0; i < nbGpu; i++) {
			std::vector<KEYSEARCHRESULT> results = gpuEngines[i]->GetResults();
			for (size_t j = 0; j < results.size(); j++) {
				OutputFound(results[j]);
			}
		}
	}

	// Cleanup
	for (int i = 0; i < nbGpu; i++) {
		delete gpuEngines[i];
	}
}