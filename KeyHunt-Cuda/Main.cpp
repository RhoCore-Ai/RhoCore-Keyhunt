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
#ifndef WIN64
#include <signal.h>
#include <unistd.h>
#endif

// Definitionen, damit der Compiler die Modi erkennt
#define SEARCH_MODE_SA 0      // Single Address
#define SEARCH_MODE_SX 1      // Single XPoint
#define SEARCH_MODE_MA 2      // Multi Address
#define SEARCH_MODE_MX 3      // Multi XPoint
#define COIN_BTC 0
#define COIN_ETH 1
#define SEARCH_COMPRESSED 0
#define SEARCH_UNCOMPRESSED 1
#define SEARCH_BOTH 2
#define RELEASE "1.07"


using namespace std;
bool should_exit = false;

// ----------------------------------------------------------------------------
void usage()
{
    printf("KeyHunt-Cuda [OPTIONS...] [TARGETS]\n");
    printf("Where TARGETS is one address/xpont, or multiple hashes/xpoints file\n\n");

    printf("-h, --help                            : Display this message\n");
    printf("-u, --uncomp                          : Search uncompressed points\n");
    printf("-b, --both                            : Search both uncompressed or compressed points\n");
    printf("-g, --gpu                             : Enable GPU calculation\n");
    printf("--gpui GPU ids: 0,1,...             : List of GPU(s) to use, default is 0\n");
    printf("-t, --thread N                        : Specify number of CPU thread, default is number of core\n");
    printf("-i, --in FILE                         : Read rmd160 hashes or xpoints from FILE, should be in binary format with sorted\n");
    printf("-o, --out FILE                        : Write keys to FILE, default: Found.txt\n");
    printf("-m, --mode MODE                       : Specify search mode where MODE is\n");
    printf("                                          ADDRESS  : for single address\n");
    printf("                                          ADDRESSES: for multiple hashes/addresses\n");
    printf("                                          XPOINT   : for single xpoint\n");
    printf("                                          XPOINTS  : for multiple xpoints\n");
    printf("--coin BTC/ETH                      : Specify Coin name to search\n");
    printf("--range KEYSPACE                    : Specify the range:\n");
    printf("                                          START:END\n");
}


int parseSearchMode(const std::string& s)
{
    std::string stype = s;
    std::transform(stype.begin(), stype.end(), stype.begin(), ::tolower);

    if (stype == "address") {
        return SEARCH_MODE_SA;
    }
    if (stype == "xpoint") {
        return SEARCH_MODE_SX;
    }
    if (stype == "addresses") {
        return SEARCH_MODE_MA;
    }
    if (stype == "xpoints") {
        return SEARCH_MODE_MX;
    }

    printf("Invalid search mode format: %s", stype.c_str());
    usage();
    exit(-1);
}

int parseCoinType(const std::string& s)
{
    std::string stype = s;
    std::transform(stype.begin(), stype.end(), stype.begin(), ::tolower);
    if (stype == "btc") {
        return COIN_BTC;
    }
    if (stype == "eth") {
        return COIN_ETH;
    }
    printf("Invalid coin name: %s", stype.c_str());
    usage();
    exit(-1);
}

bool parseRange(const std::string& s, Int& start, Int& end)
{
    size_t pos = s.find(':');
    if (pos == std::string::npos) {
        start.SetBase16(s.c_str());
        end.Set(&start);
        end.Add(0xFFFFFFFFFFFFULL);
    } else {
        std::string left = s.substr(0, pos);
        if (left.length() == 0) {
            start.SetInt32(1);
        } else {
            start.SetBase16(left.c_str());
        }
        std::string right = s.substr(pos + 1);
        if (right[0] == '+') {
            Int t;
            t.SetBase16(right.substr(1).c_str());
            end.Set(&start);
            end.Add(&t);
        } else {
            end.SetBase16(right.c_str());
        }
    }
    return true;
}


#ifndef WIN64
void CtrlHandler(int signum) {
    printf("\n\nBYE\n");
    exit(signum);
}
#endif

int main(int intc, char** argv)
{
    Timer::Init();
    rseed(Timer::getSeed32());

    bool gpuEnable = false;
    int compMode = SEARCH_COMPRESSED;
    
    string outputFile = "Found.txt";
    string inputFile = ""; 
    
    Int rangeStart;
    Int rangeEnd;
    rangeStart.SetInt32(0);
    rangeEnd.SetInt32(0);

    int searchMode = SEARCH_MODE_SA;
    int coinType = COIN_BTC;

    CmdParse parser;
    parser.add("-h", "--help", false);
    parser.add("-u", "--uncomp", false);
    parser.add("-b", "--both", false);
    parser.add("-g", "--gpu", false);
    parser.add("-i", "--in", true);
    parser.add("-o", "--out", true);
    parser.add("-m", "--mode", true);
    parser.add("--coin", true);
    parser.add("--range", true);
    
    if (intc == 1) {
        usage();
        return 0;
    }

    parser.parse(intc, argv);
    std::vector<OptArg> args = parser.getArgs();

    for (unsigned int i = 0; i < args.size(); i++) {
        OptArg optArg = args[i];
        if (optArg.equals("-h", "--help")) {
            usage();
            return 0;
        } else if (optArg.equals("-u", "--uncomp")) {
            compMode = SEARCH_UNCOMPRESSED;
        } else if (optArg.equals("-b", "--both")) {
            compMode = SEARCH_BOTH;
        } else if (optArg.equals("-g", "--gpu")) {
            gpuEnable = true;
        } else if (optArg.equals("-i", "--in")) {
            inputFile = optArg.arg;
        } else if (optArg.equals("-o", "--out")) {
            outputFile = optArg.arg;
        } else if (optArg.equals("-m", "--mode")) {
            searchMode = parseSearchMode(optArg.arg);
        } else if (optArg.equals("--coin")) {
            coinType = parseCoinType(optArg.arg);
        } else if (optArg.equals("--range")) {
            parseRange(optArg.arg, rangeStart, rangeEnd);
        }
    }

    if(inputFile.empty()) {
        std::vector<std::string> ops = parser.getOperands();
        if(ops.size() > 0) {
            inputFile = ops[0];
        } else {
            printf("Error: Missing input file or target\n");
            usage();
            return -1;
        }
    }

#ifndef WIN64
    signal(SIGINT, CtrlHandler);
#endif

    bool success = true;
    KeyHunt* v = new KeyHunt(inputFile, searchMode, coinType, compMode, gpuEnable, inputFile, false, 0, 0, rangeStart.GetBase16(), rangeEnd.GetBase16(), success);

    if(!success) {
        delete v;
        return 1;
    }
    
    v->Search();

    delete v;
    return 0;
}