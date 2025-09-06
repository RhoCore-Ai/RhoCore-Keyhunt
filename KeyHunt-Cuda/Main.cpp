#include "Timer.h"
#include "KeyHunt.h"
#include "Base58.h"
#include "CmdParse.h"
#include <fstream>
#include <string>
#include <string.h>
#include <stdexcept>
#include <cassert>
#include <algorithm>
#include <inttypes.h>
#ifndef WIN64
#include <signal.h>
#include <unistd.h>
#endif

#define RELEASE "1.07"

using namespace std;
bool should_exit = false;

// ----------------------------------------------------------------------------
void usage()
{
	printf("KeyHunt-Cuda [OPTIONS...] [TARGETS]\n");
	printf("Where TARGETS is one address/xpont, or multiple hashes/xpoints file\n\n");

	printf("-h, --help                               : Display this message\n");
	printf("-c, --check                              : Check the working of the codes\n");
	printf("-u, --uncomp                             : Search uncompressed points\n");
	printf("-b, --both                               : Search both uncompressed or compressed points\n");
	printf("-g, --gpu                                : Enable GPU calculation\n");
	printf("--gpui GPU ids: 0,1,...                  : List of GPU(s) to use, default is 0\n");
	printf("--gpux GPU gridsize: g0x,g0y,g1x,g1y,... : Specify GPU(s) kernel gridsize, default is 8*(Device MP count),128\n");
	printf("-t, --thread N                           : Specify number of CPU thread, default is number of core\n");
	printf("-i, --in FILE                            : Read rmd160 hashes or xpoints from FILE, should be in binary format with sorted\n");
	printf("-o, --out FILE                           : Write keys to FILE, default: Found.txt\n");
	printf("-m, --mode MODE                          : Specify search mode where MODE is\n");
	printf("                                               ADDRESS  : for single address\n");
	printf("                                               ADDRESSES: for multiple hashes/addresses\n");
	printf("                                               XPOINT   : for single xpoint\n");
	printf("                                               XPOINTS  : for multiple xpoints\n");
	printf("--coin BTC/ETH                           : Specify Coin name to search\n");
	printf("                                               BTC: available mode :-\n");
	printf("                                                   ADDRESS, ADDRESSES, XPOINT, XPOINTS\n");
	printf("                                               ETH: available mode :-\n");
	printf("                                                   ADDRESS, ADDRESSES\n");
	printf("-l, --list                               : List cuda enabled devices\n");
	printf("--range KEYSPACE                         : Specify the range:\n");
	printf("                                               START:END\n");
	printf("                                               START:+COUNT\n");
	printf("                                               START\n");
	printf("                                               :END\n");
	printf("                                               :+COUNT\n");
	printf("                                               COUNT\n");
	printf("--rkey N                                 : Resume Key, for continue the search, default: 0\n");
	printf("--skip N                                 : Skip number of key, for continue the search, default: 0\n");
	printf("--max-found N                            : Exit after find N valid key, default: 0 (no exit)\n");
	printf("--sse                                    : Enable SSE hash function for CPU, need support SSSE3\n
<function=edit>
<parameter=code_edit>
#include "Timer.h"
#include "KeyHunt.h"
#include "Base58.h"
#include "CmdParse.h"
#include <fstream>
#include <string>
#include <string.h>
#include <stdexcept>
#include <cassert>
#include <algorithm>
#include <inttypes.h>
#ifndef WIN64
#include <signal.h>
#include <unistd.h>
#endif

#define RELEASE "1.07"

using namespace std;
bool should_exit = false;

// ----------------------------------------------------------------------------
void usage()
{
	printf("KeyHunt-Cuda [OPTIONS...] [TARGETS]\n");
	printf("Where TARGETS is one address/xpont, or multiple hashes/xpoints file\n\n");

	printf("-h, --help                               : Display this message\n");
	printf("-c, --check                              : Check the working of the codes\n");
	printf("-u, --uncomp                             : Search uncompressed points\n");
	printf("-b, --both                               : Search both uncompressed or compressed points\n");
	printf("-g, --gpu                                : Enable GPU calculation\n");
	printf("--gpui GPU ids: 0,1,...                  : List of GPU(s) to use, default is 0\n");
	printf("--gpux GPU gridsize: g0x,g0y,g1x,g1y,... : Specify GPU(s) kernel gridsize, default is 8*(Device MP count),128\n");
	printf("-t, --thread N                           : Specify number of CPU thread, default is number of core\n");
	printf("-i, --in FILE                            : Read rmd160 hashes or xpoints from FILE, should be in binary format with sorted\n");
	printf("-o, --out FILE                           : Write keys to FILE, default: Found.txt\n");
	printf("-m, --mode MODE                          : Specify search mode where MODE is\n");
	printf("                                               ADDRESS  : for single address\n");
	printf("                                               ADDRESSES: for multiple hashes/addresses\n");
	printf("                                               XPOINT   : for single xpoint\n");
	printf("                                               XPOINTS  : for multiple xpoints\n");
	printf("--coin BTC/ETH                           : Specify Coin name to search\n");
	printf("                                               BTC: available mode :-\n");
	printf("                                                   ADDRESS, ADDRESSES, XPOINT, XPOINTS\n");
	printf("                                               ETH: available mode :-\n");
	printf("                                                   ADDRESS, ADDRESSES\n");
	printf("-l, --list                               : List cuda enabled devices\n");
	printf("--range KEYSPACE                         : Specify the range:\n");
	printf("                                               START:END\n");
	printf("                                               START:+COUNT\n");
	printf("                                               START\n");
	printf("                                               :END\n");
	printf("                                               :+COUNT\n");
	printf("                                               COUNT\n");
	printf("--rkey N                                 : Resume Key, for continue the search, default: 0\n");
	printf("--skip N                                 : Skip number of key, for continue the search, default: 0\n");
	printf("--max-found N                            : Exit after find N valid key, default: 0 (no exit)\n");
	printf("--sse                                    : Enable SSE hash function for CPU, need support SSSE3\n");
	printf("--check                                  : Enable check mode, only for check the working of codes\n");
	printf("--version                                : Display version information\n");
	printf("\n");
}

// ----------------------------------------------------------------------------
void version()
{
	printf("KeyHunt-Cuda v%s\n", RELEASE);
	printf("Bitcoin Address Searcher using CUDA\n");
	printf("Copyright (c) 2023 KeyHunt Developers\n");
	printf("\n");
}

// ----------------------------------------------------------------------------
#ifndef WIN64
void sigHandler(int sig)
{
	should_exit = true;
}
#endif

// ----------------------------------------------------------------------------
int main(int argc, char* argv[])
{
	// Parse command line
	CmdParse cmd;
	cmd.parse(argc, argv);

	// Check for help
	if (cmd.isSet("-h") || cmd.isSet("--help")) {
		usage();
		return 0;
	}

	// Check for version
	if (cmd.isSet("--version")) {
		version();
		return 0;
	}

	// Check for check mode
	bool checkMode = cmd.isSet("-c") || cmd.isSet("--check");

	// Check for list mode
	bool listMode = cmd.isSet("-l") || cmd.isSet("--list");

	// Check for GPU mode
	bool useGPU = cmd.isSet("-g") || cmd.isSet("--gpu");

	// Check for SSE mode
	bool useSSE = cmd.isSet("--sse");

	// Get coin type
	int coinType = COIN_BTC;
	if (cmd.isSet("--coin")) {
		string coinStr;
		cmd.get("--coin", coinStr);
		if (coinStr == "BTC") {
			coinType = COIN_BTC;
		}
		else if (coinStr == "ETH") {
			coinType = COIN_ETH;
		}
		else {
			printf("Error: Unknown coin type %s\n", coinStr.c_str());
			return 1;
		}
	}

	// Get search mode
	int searchMode = SEARCH_MODE_MA;
	if (cmd.isSet("-m") || cmd.isSet("--mode")) {
		string modeStr;
		cmd.get("-m", modeStr);
		if (modeStr == "ADDRESS") {
			searchMode = SEARCH_MODE_SA;
		}
		else if (modeStr == "ADDRESSES") {
			searchMode = SEARCH_MODE_MA;
		}
		else if (modeStr == "XPOINT") {
			searchMode = SEARCH_MODE_SX;
		}
		else if (modeStr == "XPOINTS") {
			searchMode = SEARCH_MODE_MX;
		}
		else {
			printf("Error: Unknown search mode %s\n", modeStr.c_str());
			return 1;
		}
	}

	// Check if mode is compatible with coin
	if (coinType == COIN_ETH) {
		if (searchMode == SEARCH_MODE_SX || searchMode == SEARCH_MODE_MX) {
			printf("Error: ETH coin does not support XPOINT modes\n");
			return 1;
		}
	}

	// Get input file
	string inputFile;
	if (cmd.isSet("-i") || cmd.isSet("--in")) {
		cmd.get("-i", inputFile);
	}
	else if (!listMode && !checkMode) {
		// For non-list and non-check modes, we need an input file or target
		if (searchMode == SEARCH_MODE_SA || searchMode == SEARCH_MODE_SX) {
			// For single modes, we need a target from command line
			if (cmd.getNbArgs() == 0) {
				printf("Error: No target specified\n");
				usage();
				return 1;
			}
		}
		else {
			// For multiple modes, we need an input file
			printf("Error: No input file specified\n");
			usage();
			return 1;
		}
	}

	// Get output file
	string outputFile = "Found.txt";
	if (cmd.isSet("-o") || cmd.isSet("--out")) {
		cmd.get("-o", outputFile);
	}

	// Get CPU thread count
	int nbCPUThread = 0;
	if (cmd.isSet("-t") || cmd.isSet("--thread")) {
		cmd.get("-t", nbCPUThread);
		if (nbCPUThread < 0) {
			printf("Error: Invalid thread count\n");
			return 1;
		}
	}
	else {
		nbCPUThread = Timer::getCoreNumber();
	}

	// Get GPU parameters
	vector<int> gpuId;
	vector<int> gridSize;
	bool gpuAutoGrid = true;
	if (useGPU) {
		// Get GPU IDs
		if (cmd.isSet("--gpui")) {
			string gpuIdStr;
			cmd.get("--gpui", gpuIdStr);
			size_t pos = 0;
			while ((pos = gpuIdStr.find(",")) != string::npos) {
				string token = gpuIdStr.substr(0, pos);
				gpuId.push_back(atoi(token.c_str()));
				gpuIdStr.erase(0, pos + 1);
			}
			gpuId.push_back(atoi(gpuIdStr.c_str()));
		}
		else {
			gpuId.push_back(0);
		}

		// Get GPU grid size
		if (cmd.isSet("--gpux")) {
			gpuAutoGrid = false;
			string gridSizeStr;
			cmd.get("--gpux", gridSizeStr);
			size_t pos = 0;
			while ((pos = gridSizeStr.find(",")) != string::npos) {
				string token = gridSizeStr.substr(0, pos);
				gridSize.push_back(atoi(token.c_str()));
				gridSizeStr.erase(0, pos + 1);
			}
			gridSize.push_back(atoi(gridSizeStr.c_str()));
		}
		else {
			// Auto grid size
			for (size_t i = 0; i < gpuId.size(); i++) {
				gridSize.push_back(0);
				gridSize.push_back(0);
			}
		}
	}

	// Get compression mode
	int compMode = SEARCH_COMPRESSED;
	if (cmd.isSet("-u") || cmd.isSet("--uncomp")) {
		compMode = SEARCH_UNCOMPRESSED;
	}
	else if (cmd.isSet("-b") || cmd.isSet("--both")) {
		compMode = SEARCH_BOTH;
	}

	// Get range
	string rangeStart = "1";
	string rangeEnd = "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364140";
	if (cmd.isSet("--range")) {
		string rangeStr;
		cmd.get("--range", rangeStr);
		size_t pos = rangeStr.find(":");
		if (pos != string::npos) {
			rangeStart = rangeStr.substr(0, pos);
			rangeEnd = rangeStr.substr(pos + 1);
		}
		else {
			rangeStart = "1";
			rangeEnd = rangeStr;
		}
	}

	// Get resume key
	uint64_t rKey = 0;
	if (cmd.isSet("--rkey")) {
		cmd.get("--rkey", rKey);
	}

	// Get skip count
	uint64_t skip = 0;
	if (cmd.isSet("--skip")) {
		cmd.get("--skip", skip);
	}

	// Get max found
	uint32_t maxFound = 0;
	if (cmd.isSet("--max-found")) {
		cmd.get("--max-found", maxFound);
	}

	// Handle list mode
	if (listMode) {
#ifdef WITHGPU
		GPUEngine::PrintCudaDevices();
#endif
		return 0;
	}

	// Handle check mode
	if (checkMode) {
		printf("Checking the working of the codes...\n");
		// Add check code here
		return 0;
	}

	// Handle single address/xpoint mode
	string address;
	string xpoint;
	if (searchMode == SEARCH_MODE_SA || searchMode == SEARCH_MODE_SX) {
		if (cmd.getNbArgs() == 0) {
			printf("Error: No target specified\n");
			usage();
			return 1;
		}
		if (searchMode == SEARCH_MODE_SA) {
			address = cmd.getArg(0);
		}
		else {
			xpoint = cmd.getArg(0);
		}
	}

	// Display configuration
	printf("KeyHunt-Cuda v%s\n", RELEASE);
	printf("SEARCH MODE  : ");
	switch (searchMode) {
	case SEARCH_MODE_MA:
		printf("Multiple Addresses\n");
		break;
	case SEARCH_MODE_SA:
		printf("Single Address\n");
		break;
	case SEARCH_MODE_MX:
		printf("Multiple XPoints\n");
		break;
	case SEARCH_MODE_SX:
		printf("Single XPoint\n");
		break;
	}
	printf("COIN TYPE    : %s\n", coinType == COIN_BTC ? "BTC" : "ETH");
	printf("COMPRESSION  : ");
	switch (compMode) {
	case SEARCH_COMPRESSED:
		printf("Compressed\n");
		break;
	case SEARCH_UNCOMPRESSED:
		printf("Uncompressed\n");
		break;
	case SEARCH_BOTH:
		printf("Both\n");
		break;
	}
	printf("THREAD       : %d\n", nbCPUThread);
	if (useGPU) {
		printf("GPU IDS      : ");
		for (size_t i = 0; i < gpuId.size(); i++) {
			printf("%d", gpuId[i]);
			if (i < gpuId.size() - 1) printf(",");
		}
		printf("\n");
		printf("GRID SIZE    : ");
		if (gpuAutoGrid) {
			printf("Auto");
		}
		else {
			for (size_t i = 0; i < gridSize.size(); i++) {
				printf("%d", gridSize[i]);
				if (i < gridSize.size() - 1) printf(",");
			}
		}
		printf("\n");
	}
	printf("SSE          : %s\n", useSSE ? "YES" : "NO");
	printf("RKEY         : %" PRIu64 " Mkeys\n", rKey);
	printf("MAX FOUND    : %d\n", maxFound);
	if (coinType == COIN_BTC) {
		switch (searchMode) {
		case (int)SEARCH_MODE_MA:
			printf("BTC HASH160s : %s\n", inputFile.c_str());
			break;
		case (int)SEARCH_MODE_SA:
			printf("BTC ADDRESS  : %s\n", address.c_str());
			break;
		case (int)SEARCH_MODE_MX:
			printf("BTC XPOINTS  : %s\n", inputFile.c_str());
			break;
		case (int)SEARCH_MODE_SX:
			printf("BTC XPOINT   : %s\n", xpoint.c_str());
			break;
		default:
			break;
		}
	}
	else {
		switch (searchMode) {
		case (int)SEARCH_MODE_MA:
			printf("ETH ADDRESSES: %s\n", inputFile.c_str());
			break;
		case (int)SEARCH_MODE_SA:
			printf("ETH ADDRESS  : %s\n", address.c_str());
			break;
		default:
			break;
		}
	}
	printf("Range        : %s:%s\n", rangeStart.c_str(), rangeEnd.c_str());
	printf("\n");

	// Initialize timer
	Timer::Init();

	// Handle single address/xpoint mode
	if (searchMode == SEARCH_MODE_SA || searchMode == SEARCH_MODE_SX) {
		// Convert address/xpoint to binary format
		vector<unsigned char> hashORxpoint;
		if (searchMode == SEARCH_MODE_SA) {
			// Convert address to hash160
			if (coinType == COIN_BTC) {
				hashORxpoint = Base58::AddressToHash160(address);
			}
			else {
				// For ETH, address should be 20 bytes hex string
				if (address.length() != 42 || address.substr(0, 2) != "0x") {
					printf("Error: Invalid ETH address format\n");
					return 1;
				}
				string hexStr = address.substr(2);
				if (hexStr.length() != 40) {
					printf("Error: Invalid ETH address length\n");
					return 1;
				}
				for (size_t i = 0; i < hexStr.length(); i += 2) {
					string byteStr = hexStr.substr(i, 2);
					hashORxpoint.push_back((unsigned char)strtol(byteStr.c_str(), NULL, 16));
				}
			}
		}
		else {
			// Convert xpoint to binary
			if (xpoint.length() != 66 || xpoint.substr(0, 2) != "02" && xpoint.substr(0, 2) != "03") {
				printf("Error: Invalid xpoint format\n");
				return 1;
			}
			string hexStr = xpoint.substr(2);
			if (hexStr.length() != 64) {
				printf("Error: Invalid xpoint length\n");
				return 1;
			}
			for (size_t i = 0; i < hexStr.length(); i += 2) {
				string byteStr = hexStr.substr(i, 2);
				hashORxpoint.push_back((unsigned char)strtol(byteStr.c_str(), NULL, 16));
			}
		}

		// Create KeyHunt object
		KeyHunt* keyHunt = new KeyHunt(hashORxpoint, compMode, searchMode, coinType, useGPU,
			outputFile, useSSE, maxFound, rKey, rangeStart, rangeEnd, should_exit);

		// Check if initialization was successful
		if (should_exit) {
			delete keyHunt;
			return 1;
		}

		// Start search
#ifndef WIN64
		signal(SIGINT, sigHandler);
		signal(SIGTERM, sigHandler);
#endif

		// Search
		keyHunt->Search(nbCPUThread, gpuId, gridSize, should_exit);

		// Cleanup
		delete keyHunt;
	}
	else {
		// Multiple addresses/xpoints mode
		// Create KeyHunt object
		KeyHunt* keyHunt = new KeyHunt(inputFile, compMode, searchMode, coinType, useGPU,
			outputFile, useSSE, maxFound, rKey, rangeStart, rangeEnd, should_exit);

		// Check if initialization was successful
		if (should_exit) {
			delete keyHunt;
			return 1;
		}

		// Start search
#ifndef WIN64
		signal(SIGINT, sigHandler);
		signal(SIGTERM, sigHandler);
#endif

		// Search
		keyHunt->Search(nbCPUThread, gpuId, gridSize, should_exit);

		// Cleanup
		delete keyHunt;
	}

	return 0;
}