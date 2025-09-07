/*
 * This file is part of the VanitySearch distribution (https://github.com/JeanLucPons/VanitySearch).
 * Copyright (c) 2019 Jean Luc PONS.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, version 3.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
*/

#ifndef GPUENGINEH
#define GPUENGINEH

#ifdef WITHGPU
#include <cuda_runtime.h>
#endif

#include <vector>
// Forward declaration instead of including the header to avoid circular dependency
class Secp256K1;
#include "../Point.h"
#include "../Int.h"

// For 64bits key
#define GPU_GRP_SIZE 256
#define GPU_GRP_SIZE_BIT 8
#define GPU_GRP_SIZE_MASK 0xFF

// For 32bits key
#define GPU_GRP_SIZE2 256
#define GPU_GRP_SIZE_BIT2 8
#define GPU_GRP_SIZE_MASK2 0xFF

#define ITEM_SIZE_A 80
#define ITEM_SIZE_X 40

#define SEARCH_MODE_MA 0
#define SEARCH_MODE_SA 1
#define SEARCH_MODE_MX 2
#define SEARCH_MODE_SX 3

#define SEARCH_COMPRESSED 0
#define SEARCH_UNCOMPRESSED 1
#define SEARCH_BOTH 2

typedef struct {
	uint8_t hash[20];
	bool mode;
} ITEM;

class GPUEngine
{

public:

	GPUEngine(Secp256K1* secp, int nbThreadGroup, int nbThreadPerGroup, int gpuId, uint32_t maxFound, 
		int searchMode, int compMode, int coinType, int64_t BLOOM_SIZE, uint64_t BLOOM_BITS, 
		uint8_t BLOOM_HASHES, const uint8_t* BLOOM_DATA, uint8_t* DATA, uint64_t TOTAL_COUNT, bool rKey);

	GPUEngine(Secp256K1* secp, int nbThreadGroup, int nbThreadPerGroup, int gpuId, uint32_t maxFound, 
		int searchMode, int compMode, int coinType, const uint32_t* hashORxpoint, bool rKey);


	~GPUEngine();

	bool SetKeys(Point* p);

	// Search method for key filtering support
	uint32_t Search(int gpuId, Int& startRange, Int& endRange);

	// GLV support methods
	void SetGLVConstants(const Int& lambda, const Int& beta);
	bool HasGLVSupport() { return hasGLV; }

	// Asynchronous processing methods
	void EnableAsyncProcessing(int numStreams = 4);
	bool LaunchSEARCH_MODE_MA_Async(std::vector<ITEM>& dataFound);
	bool LaunchSEARCH_MODE_SA_Async(std::vector<ITEM>& dataFound);
	bool LaunchSEARCH_MODE_MX_Async(std::vector<ITEM>& dataFound);
	bool LaunchSEARCH_MODE_SX_Async(std::vector<ITEM>& dataFound);

	bool LaunchSEARCH_MODE_MA(std::vector<ITEM>& dataFound, bool spinWait = false);
	bool LaunchSEARCH_MODE_SA(std::vector<ITEM>& dataFound, bool spinWait = false);
	bool LaunchSEARCH_MODE_MX(std::vector<ITEM>& dataFound, bool spinWait = false);
	bool LaunchSEARCH_MODE_SX(std::vector<ITEM>& dataFound, bool spinWait = false);

	int GetNbThread();
	int GetGroupSize();

	//bool Check(Secp256K1 *secp);
	std::string deviceName;

	static void PrintCudaInfo();
	static void GenerateCode(Secp256K1* secp, int size);

private:
	void InitGenratorTable(Secp256K1* secp);

	bool callKernelSEARCH_MODE_MA();
	bool callKernelSEARCH_MODE_SA();
	bool callKernelSEARCH_MODE_MX();
	bool callKernelSEARCH_MODE_SX();

	// Asynchronous kernel calls
	bool callKernelSEARCH_MODE_MA_Async();
	bool callKernelSEARCH_MODE_SA_Async();
	bool callKernelSEARCH_MODE_MX_Async();
	bool callKernelSEARCH_MODE_SX_Async();

	int CheckBinary(const uint8_t* x, int K_LENGTH);

	int nbThread;
	int nbThreadPerGroup;

	uint32_t* inputHashORxpoint;
	uint32_t* inputHashORxpointPinned;

	//uint8_t *bloomLookUp;
	uint8_t* inputBloomLookUp;
	uint8_t* inputBloomLookUpPinned;

	uint64_t* inputKey;
	uint64_t* inputKeyPinned;

	// CUDA streams for different search modes
	cudaStream_t stream_ma[2];  // Double buffering for MA mode
	cudaStream_t stream_sa[2];  // Double buffering for SA mode
	cudaStream_t stream_mx[2];  // Double buffering for MX mode
	cudaStream_t stream_sx[2];  // Double buffering for SX mode

	uint32_t* outputBuffer;
	uint32_t* outputBufferPinned;

	// Asynchronous processing support
	cudaStream_t* streams;
	int numStreams;
	bool asyncEnabled;
	int currentStream;

	uint64_t* __2Gnx;
	uint64_t* __2Gny;

	uint64_t* _Gx;
	uint64_t* _Gy;

	// Texture references for lookup tables
	cudaTextureObject_t texGx;
	cudaTextureObject_t texGy;
	cudaTextureObject_t tex2Gnx;
	cudaTextureObject_t tex2Gny;

	bool initialised;
	uint32_t compMode;
	uint32_t searchMode;
	uint32_t coinType;
	bool littleEndian;

	bool rKey;
	uint32_t maxFound;
	uint32_t outputSize;

	int64_t BLOOM_SIZE;
	uint64_t BLOOM_BITS;
	uint8_t BLOOM_HASHES;

	uint8_t* DATA;
	uint64_t TOTAL_COUNT;

	// GLV support
	bool hasGLV;
	uint64_t* d_lambda;
	uint64_t* d_beta;

};

#endif // GPUENGINEH