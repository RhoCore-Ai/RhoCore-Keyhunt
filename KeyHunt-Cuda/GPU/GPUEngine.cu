#include "GPUEngine.h"
#include <cuda.h>
#include <cuda_runtime.h>
#include <device_launch_parameters.h>
#include <cooperative_groups.h>
#include <cooperative_groups/reduce.h>

#include <stdint.h>
#include <math.h>
#include "../hash/sha256.h"
#include "../hash/ripemd160.h"
#include "../Timer.h"

#include "GPUMath.h"
#include "GPUHash.h"
#include "GPUBase58.h"
#include "GPUCompute.h"

// GLV constants for GPU
__device__ uint64_t d_lambda[4];
__device__ uint64_t d_beta[4];

// ---------------------------------------------------------------------------------------
#define CudaSafeCall( err ) __cudaSafeCall( err, __FILE__, __LINE__ )

inline void __cudaSafeCall(cudaError err, const char* file, const int line)
{
	if (cudaSuccess != err)
	{
		fprintf(stderr, "cudaSafeCall() failed at %s:%i : %s\n", file, line, cudaGetErrorString(err));
		exit(-1);
	}
	return;
}

// ---------------------------------------------------------------------------------------

// mode multiple addresses
__global__ void compute_keys_mode_ma(uint32_t mode, uint8_t* bloomLookUp, int BLOOM_BITS, uint8_t BLOOM_HASHES,
	uint64_t* keys, uint32_t maxFound, uint32_t* found)
{

	int xPtr = (blockIdx.x * blockDim.x) * 8;
	int yPtr = xPtr + 4 * blockDim.x;
	ComputeKeysSEARCH_MODE_MA(mode, keys + xPtr, keys + yPtr, bloomLookUp, BLOOM_BITS, BLOOM_HASHES, maxFound, found);

}

__global__ void compute_keys_comp_mode_ma(uint32_t mode, uint8_t* bloomLookUp, int BLOOM_BITS, uint8_t BLOOM_HASHES, uint64_t* keys,
	uint32_t maxFound, uint32_t* found)
{
	// Create thread block group
	namespace cg = cooperative_groups;
	cg::thread_block block = cg::this_thread_block();

	// Calculate thread and block indices
	int tid = blockIdx.x * blockDim.x + threadIdx.x;
	int xPtr = (blockIdx.x * blockDim.x) * 8;
	// Create thread block group and warp group
	namespace cg = cooperative_groups;
	cg::thread_block block = cg::this_thread_block();
	cg::thread_block_tile<32> warp = cg::tiled_partition<32>(block);

	// Calculate thread and block indices
	int tid = blockIdx.x * blockDim.x + threadIdx.x;
	int xPtr = (blockIdx.x * blockDim.x) * 8;
	int yPtr = xPtr + 4 * blockDim.x;

	// Perform computation
	ComputeKeysSEARCH_MODE_SA(mode, keys + xPtr, keys + yPtr, hash160, maxFound, found);

	// Use warp-level primitive to find maximum found value across the warp
	uint32_t local_found = found[0];
	uint32_t warp_max_found = cg::reduce(warp, local_found, cg::greater<uint32_t>());

	// Only the first thread in the warp updates the global maximum
	if (warp.thread_rank() == 0 && warp_max_found > found[0]) {
		atomicMax((int*)found, (int)warp_max_found);
	}

	// Synchronize threads in block using Cooperative Groups
	block.sync();
}

// mode single address
__global__ void compute_keys_mode_sa(uint32_t mode, uint32_t* hash160, uint64_t* keys, uint32_t maxFound, uint32_t* found)
{

	int xPtr = (blockIdx.x * blockDim.x) * 8;
	int yPtr = xPtr + 4 * blockDim.x;
	ComputeKeysSEARCH_MODE_SA(mode, keys + xPtr, keys + yPtr, hash160, maxFound, found);

}

__global__ void compute_keys_comp_mode_sa(uint32_t mode, uint32_t* hash160, uint64_t* keys, uint32_t maxFound, uint32_t* found)
{

	int xPtr = (blockIdx.x * blockDim.x) * 8;
	int yPtr = xPtr + 4 * blockDim.x;
	ComputeKeysSEARCH_MODE_SA(mode, keys + xPtr, keys + yPtr, hash160, maxFound, found);

}

// mode multiple x points
__global__ void compute_keys_comp_mode_mx(uint32_t mode, uint8_t* bloomLookUp, int BLOOM_BITS, uint8_t BLOOM_HASHES, uint64_t* keys,
	uint32_t maxFound, uint32_t* found)
{

	int xPtr = (blockIdx.x * blockDim.x) * 8;
	int yPtr = xPtr + 4 * blockDim.x;
	ComputeKeysSEARCH_MODE_MX(mode, keys + xPtr, keys + yPtr, bloomLookUp, BLOOM_BITS, BLOOM_HASHES, maxFound, found);

}

// mode single x point
__global__ void compute_keys_comp_mode_sx(uint32_t mode, uint32_t* xpoint, uint64_t* keys, uint32_t maxFound, uint32_t* found)
{

	int xPtr = (blockIdx.x * blockDim.x) * 8;
	int yPtr = xPtr + 4 * blockDim.x;
	ComputeKeysSEARCH_MODE_SX(mode, keys + xPtr, keys + yPtr, xpoint, maxFound, found);

}

// ---------------------------------------------------------------------------------------
// ethereum

__global__ void compute_keys_mode_eth_ma(uint8_t* bloomLookUp, int BLOOM_BITS, uint8_t BLOOM_HASHES, uint64_t* keys,
	uint32_t maxFound, uint32_t* found)
{

	int xPtr = (blockIdx.x * blockDim.x) * 8;
	int yPtr = xPtr + 4 * blockDim.x;
	ComputeKeysSEARCH_ETH_MODE_MA(keys + xPtr, keys + yPtr, bloomLookUp, BLOOM_BITS, BLOOM_HASHES, maxFound, found);

}

__global__ void compute_keys_mode_eth_sa(uint32_t* hash, uint64_t* keys, uint32_t maxFound, uint32_t* found)
{

	int xPtr = (blockIdx.x * blockDim.x) * 8;
	int yPtr = xPtr + 4 * blockDim.x;
	ComputeKeysSEARCH_ETH_MODE_SA(keys + xPtr, keys + yPtr, hash, maxFound, found);

}

// ---------------------------------------------------------------------------------------

using namespace std;

int _ConvertSMVer2Cores(int major, int minor)
{

	// Defines for GPU Architecture types (using the SM version to determine
	// the # of cores per SM
	typedef struct {
		int SM;  // 0xMm (hexidecimal notation), M = SM Major version,
		// and m = SM minor version
		int Cores;
	} sSMtoCores;

	sSMtoCores nGpuArchCoresPerSM[] = {
		{0x20, 32}, // Fermi Generation (SM 2.0) GF100 class
		{0x21, 48}, // Fermi Generation (SM 2.1) GF10x class
		{0x30, 192},
		{0x32, 192},
		{0x35, 192},
		{0x37, 192},
		{0x50, 128},
		{0x52, 128},
		{0x53, 128},
		{0x60,  64},
		{0x61, 128},
		{0x62, 128},
		{0x70,  64},
		{0x72,  64},
		{0x75,  64},
		{0x80,  64},
		{0x86, 128},
		{0x89, 128}, // Added for compute capability 8.9 (RTX 40XX series)
		{0xC0, 128}, // Added for compute capability 12.0 (RTX 50XX series) - preliminary
		{-1, -1}
	};

	int index = 0;

	while (nGpuArchCoresPerSM[index].SM != -1) {
		if (nGpuArchCoresPerSM[index].SM == ((major << 4) + minor)) {
			return nGpuArchCoresPerSM[index].Cores;
		}

		index++;
	}

	return 0;

}

// ----------------------------------------------------------------------------

GPUEngine::GPUEngine(Secp256K1* secp, int nbThreadGroup, int nbThreadPerGroup, int gpuId, uint32_t maxFound,
	int searchMode, int compMode, int coinType, int64_t BLOOM_SIZE, uint64_t BLOOM_BITS,
	uint8_t BLOOM_HASHES, const uint8_t* BLOOM_DATA, uint8_t* DATA, uint64_t TOTAL_COUNT, bool rKey)
{

	// Initialise CUDA
	this->searchMode = searchMode;
	this->compMode = compMode;
	this->coinType = coinType;
	this->rKey = rKey;

	this->BLOOM_SIZE = BLOOM_SIZE;
	this->BLOOM_BITS = BLOOM_BITS;
	this->BLOOM_HASHES = BLOOM_HASHES;
	this->DATA = DATA;
	this->TOTAL_COUNT = TOTAL_COUNT;

	initialised = false;

	int deviceCount = 0;
	CudaSafeCall(cudaGetDeviceCount(&deviceCount));

	// This function call returns 0 if there are no CUDA capable devices.
	if (deviceCount == 0) {
		printf("GPUEngine: There are no available device(s) that support CUDA\n");
		return;
	}

	if (gpuId >= deviceCount) {
		printf("GPUEngine: GPU id out of range\n");
		return;
	}

	// Set the GPU device
	CudaSafeCall(cudaSetDevice(gpuId));

	// Get device properties for adaptive sizing
	cudaDeviceProp deviceProp;
	CudaSafeCall(cudaGetDeviceProperties(&deviceProp, gpuId));

	// Print GPU information
	printf("GPU #%d: %s (%dx%d cores) Grid(%dx%d)\n", gpuId, deviceProp.name, deviceProp.multiProcessorCount,
		_ConvertSMVer2Cores(deviceProp.major, deviceProp.minor), nbThreadGroup, nbThreadPerGroup);

	// Adaptive block sizing based on GPU architecture
	// Determine optimal block size based on compute capability
	if (deviceProp.major >= 8) {
		// RTX 30XX, 40XX series - more cores, larger block size
		if (nbThreadPerGroup > 512) {
			nbThreadPerGroup = 512; // Max 512 threads per block for newer architectures
		}
	} else if (deviceProp.major >= 7) {
		// RTX 20XX series - keep default
		if (nbThreadPerGroup > 256) {
			nbThreadPerGroup = 256;
		}
	} else {
		// Older GPUs - smaller block size
		if (nbThreadPerGroup > 128) {
			nbThreadPerGroup = 128;
		}
	}

	// Ensure nbThreadPerGroup is a multiple of 32 (warp size)
	nbThreadPerGroup = (nbThreadPerGroup / 32) * 32;

	// Store the adjusted values
	this->nbThreadPerGroup = nbThreadPerGroup;
	this->nbThreadGroup = nbThreadGroup;
	this->nbThread = nbThreadGroup * nbThreadPerGroup;

	// Adjust shared memory usage based on GPU capabilities
	size_t sharedMemPerBlock = deviceProp.sharedMemPerBlock;
	if (sharedMemPerBlock >= 48 * 1024) {
		// 48KB or more shared memory - use more aggressive optimization
		this->maxFound = min(maxFound, 1024U); // Increase max found for GPUs with more shared memory
	} else {
		// Limited shared memory - be more conservative
		this->maxFound = min(maxFound, 256U);
	}

	// Initialize GLV support
	hasGLV = false;

	// Check if GPU supports GLV operations
	if (deviceProp.major >= 7) { // GLV requires compute capability 7.0+
		hasGLV = true;
	}

	// Set GLV constants if supported
	if (hasGLV) {
		SetGLVConstants(secp->Lambda, secp->Beta);
	}

	char tmp[512];
	sprintf(tmp, "GPU #%d %s (%dx%d cores) Grid(%dx%d)",
		gpuId, deviceProp.name, deviceProp.multiProcessorCount,
		_ConvertSMVer2Cores(deviceProp.major, deviceProp.minor),
		nbThreadGroup,  // Verwende die aktualisierte Variable
		nbThreadPerGroup);
	deviceName = std::string(tmp);

	// Prefer L1 (We do not use __shared__ at all)
	CudaSafeCall(cudaDeviceSetCacheConfig(cudaFuncCachePreferL1));

	size_t stackSize = 49152;
	CudaSafeCall(cudaDeviceSetLimit(cudaLimitStackSize, stackSize));

	// Allocate memory
	size_t memSize = (size_t)nbThreadGroup * (size_t)nbThreadPerGroup * 8 * sizeof(uint64_t); // 8*64 bit per thread
	CudaSafeCall(cudaMalloc((void**)&inputKeyBuffer, memSize));
	CudaSafeCall(cudaHostAlloc((void**)&inputKeyBufferPinned, memSize, cudaHostAllocDefault));

	// Initialize memory to zero
	CudaSafeCall(cudaMemset(inputKeyBuffer, 0, memSize));

	// Output buffer for found keys
	outputSize = (size_t)maxFound * (size_t)ITEM_SIZE_A + 4;  // Use the adjusted maxFound
	CudaSafeCall(cudaMalloc((void**)&outputBuffer, outputSize));
	CudaSafeCall(cudaHostAlloc((void**)&outputBufferPinned, outputSize, cudaHostAllocDefault));

	// Initialize output buffer
	CudaSafeCall(cudaMemset(outputBuffer, 0, outputSize));

	// Bloom filter or hash data
	if (searchMode == SEARCH_MODE_MA || searchMode == SEARCH_MODE_MX) {
		// Allocate bloom filter
		CudaSafeCall(cudaMalloc((void**)&bloomFilter, BLOOM_SIZE));
		CudaSafeCall(cudaMemcpy(bloomFilter, BLOOM_DATA, BLOOM_SIZE, cudaMemcpyHostToDevice));
	} else {
		// Allocate hash data
		CudaSafeCall(cudaMalloc((void**)&hashData, 20)); // 20 bytes for hash160
		CudaSafeCall(cudaMemcpy(hashData, BLOOM_DATA, 20, cudaMemcpyHostToDevice));
	}

	// Generator points
	CudaSafeCall(cudaMalloc((void**)&_2Gnx, 256 * 32 * sizeof(uint64_t)));
	CudaSafeCall(cudaMalloc((void**)&_2Gny, 256 * 32 * sizeof(uint64_t)));
	CudaSafeCall(cudaMemcpy(_2Gnx, secp->GTable, 256 * 32 * sizeof(uint64_t), cudaMemcpyHostToDevice));
	CudaSafeCall(cudaMemcpy(_2Gny, ((uint64_t*)secp->GTable) + 256 * 32, 256 * 32 * sizeof(uint64_t), cudaMemcpyHostToDevice));

	// Set up device constants
	CudaSafeCall(cudaMemcpyToSymbol(_2Gnx, &_2Gnx, sizeof(uint64_t*)));
	CudaSafeCall(cudaMemcpyToSymbol(_2Gny, &_2Gny, sizeof(uint64_t*)));

	// Generator point
	uint64_t gx[4], gy[4];
	gx[0] = secp->G.x.bits64[0];
	gx[1] = secp->G.x.bits64[1];
	gx[2] = secp->G.x.bits64[2];
	gx[3] = secp->G.x.bits64[3];
	gy[0] = secp->G.y.bits64[0];
	gy[1] = secp->G.y.bits64[1];
	gy[2] = secp->G.y.bits64[2];
	gy[3] = secp->G.y.bits64[3];

	CudaSafeCall(cudaMalloc((void**)&Gx, 4 * sizeof(uint64_t)));
	CudaSafeCall(cudaMalloc((void**)&Gy, 4 * sizeof(uint64_t)));
	CudaSafeCall(cudaMemcpy(Gx, gx, 4 * sizeof(uint64_t), cudaMemcpyHostToDevice));
	CudaSafeCall(cudaMemcpy(Gy, gy, 4 * sizeof(uint64_t), cudaMemcpyHostToDevice));
	CudaSafeCall(cudaMemcpyToSymbol(::Gx, &Gx, sizeof(uint64_t*)));
	CudaSafeCall(cudaMemcpyToSymbol(::Gy, &Gy, sizeof(uint64_t*)));

	initialised = true;


	CudaSafeCall(cudaGetLastError());

	compMode = SEARCH_COMPRESSED;
	initialised = true;

}

// ----------------------------------------------------------------------------

GPUEngine::GPUEngine(Secp256K1* secp, int nbThreadGroup, int nbThreadPerGroup, int gpuId, uint32_t maxFound,
	int searchMode, int compMode, int coinType, int64_t BLOOM_SIZE, uint64_t BLOOM_BITS,
	uint8_t BLOOM_HASHES, const uint8_t* BLOOM_DATA, uint8_t* DATA, uint64_t TOTAL_COUNT, bool rKey)
{

	// Initialise CUDA
	this->searchMode = searchMode;
	this->compMode = compMode;
	this->coinType = coinType;
	this->rKey = rKey;

	this->BLOOM_SIZE = BLOOM_SIZE;
	this->BLOOM_BITS = BLOOM_BITS;
	this->BLOOM_HASHES = BLOOM_HASHES;
	this->DATA = DATA;
	this->TOTAL_COUNT = TOTAL_COUNT;

	initialised = false;

	// Initialize asynchronous processing
	asyncEnabled = false;
	numStreams = 0;
	streams = nullptr;
	currentStream = 0;

	int deviceCount = 0;
	CudaSafeCall(cudaGetDeviceCount(&deviceCount));

	// This function call returns 0 if there are no CUDA capable devices.
	if (deviceCount == 0) {
		printf("GPUEngine: There are no available device(s) that support CUDA\n");
		return;
	}

	CudaSafeCall(cudaSetDevice(gpuId));

	cudaDeviceProp deviceProp;
	CudaSafeCall(cudaGetDeviceProperties(&deviceProp, gpuId));

	if (nbThreadGroup == -1)
		nbThreadGroup = deviceProp.multiProcessorCount * 8;

	this->nbThread = nbThreadGroup * nbThreadPerGroup;
	this->maxFound = maxFound;
	this->outputSize = (maxFound * ITEM_SIZE_A + 4);
	if (this->searchMode == (int)SEARCH_MODE_SX)
		this->outputSize = (maxFound * ITEM_SIZE_X + 4);

	// Initialize CUDA streams for double buffering
	for (int i = 0; i < 2; i++) {
		CudaSafeCall(cudaStreamCreate(&stream_ma[i]));
		CudaSafeCall(cudaStreamCreate(&stream_sa[i]));
		CudaSafeCall(cudaStreamCreate(&stream_mx[i]));
		CudaSafeCall(cudaStreamCreate(&stream_sx[i]));
	}

	// Initialize asynchronous processing
	asyncEnabled = false;
	numStreams = 0;
	streams = nullptr;
	currentStream = 0;

	char tmp[512];
	sprintf(tmp, "GPU #%d %s (%dx%d cores) Grid(%dx%d)",
		gpuId, deviceProp.name, deviceProp.multiProcessorCount,
		_ConvertSMVer2Cores(deviceProp.major, deviceProp.minor),
		nbThread / nbThreadPerGroup,
		nbThreadPerGroup);
	deviceName = std::string(tmp);

	// Prefer L1 (We do not use __shared__ at all)
	CudaSafeCall(cudaDeviceSetCacheConfig(cudaFuncCachePreferL1));

	// Initialize GLV support
	hasGLV = false;

	// Check if GPU supports GLV operations
	if (deviceProp.major >= 7) { // GLV requires compute capability 7.0+
		hasGLV = true;
	}

	// Set GLV constants if supported
	if (hasGLV) {
		SetGLVConstants(secp->Lambda, secp->Beta);
	}

	// Search mode
	switch (searchMode) {
	case SEARCH_MODE_MA:
	case SEARCH_MODE_SA:
	case SEARCH_MODE_MX:
	case SEARCH_MODE_SX:
		break;
	default:
		printf("GPUEngine: Invalid search mode\n");
		return;
	}

	// Compression mode
	switch (compMode) {
	case SEARCH_COMPRESSED:
	case SEARCH_UNCOMPRESSED:
	case SEARCH_BOTH:
		break;
	default:
		printf("GPUEngine: Invalid compression mode\n");
		return;
	}

	size_t stackSize = 49152;
	CudaSafeCall(cudaDeviceSetLimit(cudaLimitStackSize, stackSize));

	// Allocate memory
	CudaSafeCall(cudaMalloc((void**)&inputKey, nbThread * 32 * 2));
	CudaSafeCall(cudaHostAlloc(&inputKeyPinned, nbThread * 32 * 2, cudaHostAllocWriteCombined | cudaHostAllocMapped));

	CudaSafeCall(cudaMalloc((void**)&outputBuffer, outputSize));
	CudaSafeCall(cudaHostAlloc(&outputBufferPinned, outputSize, cudaHostAllocWriteCombined | cudaHostAllocMapped));

	int K_SIZE = 5;
	if (this->searchMode == (int)SEARCH_MODE_SX)
		K_SIZE = 8;

	CudaSafeCall(cudaMalloc((void**)&inputHashORxpoint, K_SIZE * sizeof(uint32_t)));
	CudaSafeCall(cudaHostAlloc(&inputHashORxpointPinned, K_SIZE * sizeof(uint32_t), cudaHostAllocWriteCombined | cudaHostAllocMapped));

	memcpy(inputHashORxpointPinned, hashORxpoint, K_SIZE * sizeof(uint32_t));

	CudaSafeCall(cudaMemcpy(inputHashORxpoint, inputHashORxpointPinned, K_SIZE * sizeof(uint32_t), cudaMemcpyHostToDevice));
	CudaSafeCall(cudaFreeHost(inputHashORxpointPinned));
	inputHashORxpointPinned = NULL;

	// generator table
	InitGenratorTable(secp);


	CudaSafeCall(cudaGetLastError());

	compMode = SEARCH_COMPRESSED;
	initialised = true;

}

// ----------------------------------------------------------------------------

void GPUEngine::InitGenratorTable(Secp256K1* secp)
{

	// generator table
	uint64_t* _2GnxPinned;
	uint64_t* _2GnyPinned;

	uint64_t* GxPinned;
	uint64_t* GyPinned;

	uint64_t size = (uint64_t)GRP_SIZE;

	CudaSafeCall(cudaMalloc((void**)&__2Gnx, 4 * sizeof(uint64_t)));
	CudaSafeCall(cudaHostAlloc(&_2GnxPinned, 4 * sizeof(uint64_t), cudaHostAllocWriteCombined | cudaHostAllocMapped));

	CudaSafeCall(cudaMalloc((void**)&__2Gny, 4 * sizeof(uint64_t)));
	CudaSafeCall(cudaHostAlloc(&_2GnyPinned, 4 * sizeof(uint64_t), cudaHostAllocWriteCombined | cudaHostAllocMapped));

	size_t TSIZE = (size / 2) * 4 * sizeof(uint64_t);
	CudaSafeCall(cudaMalloc((void**)&_Gx, TSIZE));
	CudaSafeCall(cudaHostAlloc(&GxPinned, TSIZE, cudaHostAllocWriteCombined | cudaHostAllocMapped));

	CudaSafeCall(cudaMalloc((void**)&_Gy, TSIZE));
	CudaSafeCall(cudaHostAlloc(&GyPinned, TSIZE, cudaHostAllocWriteCombined | cudaHostAllocMapped));


	Point* Gn = new Point[size];
	Point g = secp->G;
	Gn[0] = g;
	g = secp->DoubleDirect(g);
	Gn[1] = g;
	for (int i = 2; i < size; i++) {
		g = secp->AddDirect(g, secp->G);
		Gn[i] = g;
	}
	// _2Gn = CPU_GRP_SIZE*G
	Point _2Gn = secp->DoubleDirect(Gn[size / 2 - 1]);

	int nbDigit = 4;
	for (int i = 0; i < nbDigit; i++) {
		_2GnxPinned[i] = _2Gn.x.bits64[i];
		_2GnyPinned[i] = _2Gn.y.bits64[i];
	}
	for (int i = 0; i < size / 2; i++) {
		for (int j = 0; j < nbDigit; j++) {
			GxPinned[i * nbDigit + j] = Gn[i].x.bits64[j];
			GyPinned[i * nbDigit + j] = Gn[i].y.bits64[j];
		}
	}

	delete[] Gn;

	CudaSafeCall(cudaMemcpy(__2Gnx, _2GnxPinned, 4 * sizeof(uint64_t), cudaMemcpyHostToDevice));
	CudaSafeCall(cudaFreeHost(_2GnxPinned));
	_2GnxPinned = NULL;

	CudaSafeCall(cudaMemcpy(__2Gny, _2GnyPinned, 4 * sizeof(uint64_t), cudaMemcpyHostToDevice));
	CudaSafeCall(cudaFreeHost(_2GnyPinned));
	_2GnyPinned = NULL;

	CudaSafeCall(cudaMemcpy(_Gx, GxPinned, TSIZE, cudaMemcpyHostToDevice));
	CudaSafeCall(cudaFreeHost(GxPinned));
	GxPinned = NULL;

	CudaSafeCall(cudaMemcpy(_Gy, GyPinned, TSIZE, cudaMemcpyHostToDevice));
	CudaSafeCall(cudaFreeHost(GyPinned));
	GyPinned = NULL;

	CudaSafeCall(cudaMemcpyToSymbol(_2Gnx, &__2Gnx, sizeof(uint64_t*)));
	CudaSafeCall(cudaMemcpyToSymbol(_2Gny, &__2Gny, sizeof(uint64_t*)));
	CudaSafeCall(cudaMemcpyToSymbol(Gx, &_Gx, sizeof(uint64_t*)));
	CudaSafeCall(cudaMemcpyToSymbol(Gy, &_Gy, sizeof(uint64_t*)));

	// Create texture objects for lookup tables
	cudaResourceDesc resDescGx = {};
	resDescGx.resType = cudaResourceTypeLinear;
	resDescGx.res.linear.devPtr = _Gx;
	resDescGx.res.linear.sizeInBytes = TSIZE;
	resDescGx.res.linear.desc.f = cudaChannelFormatKindUnsigned;
	resDescGx.res.linear.desc.x = 32; // 32-bit unsigned int
	resDescGx.res.linear.desc.y = 32; // 32-bit unsigned int for 64-bit total

	cudaTextureDesc texDescGx = {};
	texDescGx.readMode = cudaReadModeElementType;
	texDescGx.addressMode[0] = cudaAddressModeClamp;
	texDescGx.filterMode = cudaFilterModePoint;

	CudaSafeCall(cudaCreateTextureObject(&texGx, &resDescGx, &texDescGx, NULL));

	cudaResourceDesc resDescGy = {};
	resDescGy.resType = cudaResourceTypeLinear;
	resDescGy.res.linear.devPtr = _Gy;
	resDescGy.res.linear.sizeInBytes = TSIZE;
	resDescGy.res.linear.desc.f = cudaChannelFormatKindUnsigned;
	resDescGy.res.linear.desc.x = 32;
	resDescGy.res.linear.desc.y = 32;

	cudaTextureDesc texDescGy = {};
	texDescGy.readMode = cudaReadModeElementType;
	texDescGy.addressMode[0] = cudaAddressModeClamp;
	texDescGy.filterMode = cudaFilterModePoint;

	CudaSafeCall(cudaCreateTextureObject(&texGy, &resDescGy, &texDescGy, NULL));

	cudaResourceDesc resDesc2Gnx = {};
	resDesc2Gnx.resType = cudaResourceTypeLinear;
	resDesc2Gnx.res.linear.devPtr = __2Gnx;
	resDesc2Gnx.res.linear.sizeInBytes = 4 * sizeof(uint64_t);
	resDesc2Gnx.res.linear.desc.f = cudaChannelFormatKindUnsigned;
	resDesc2Gnx.res.linear.desc.x = 32;
	resDesc2Gnx.res.linear.desc.y = 32;

	cudaTextureDesc texDesc2Gnx = {};
	texDesc2Gnx.readMode = cudaReadModeElementType;
	texDesc2Gnx.addressMode[0] = cudaAddressModeClamp;
	texDesc2Gnx.filterMode = cudaFilterModePoint;

	CudaSafeCall(cudaCreateTextureObject(&tex2Gnx, &resDesc2Gnx, &texDesc2Gnx, NULL));

	cudaResourceDesc resDesc2Gny = {};
	resDesc2Gny.resType = cudaResourceTypeLinear;
	resDesc2Gny.res.linear.devPtr = __2Gny;
	resDesc2Gny.res.linear.sizeInBytes = 4 * sizeof(uint64_t);
	resDesc2Gny.res.linear.desc.f = cudaChannelFormatKindUnsigned;
	resDesc2Gny.res.linear.desc.x = 32;
	resDesc2Gny.res.linear.desc.y = 32;

	cudaTextureDesc texDesc2Gny = {};
	texDesc2Gny.readMode = cudaReadModeElementType;
	texDesc2Gny.addressMode[0] = cudaAddressModeClamp;
	texDesc2Gny.filterMode = cudaFilterModePoint;

	CudaSafeCall(cudaCreateTextureObject(&tex2Gny, &resDesc2Gny, &texDesc2Gny, NULL));

}

// ----------------------------------------------------------------------------

int GPUEngine::GetGroupSize()
{
	return GRP_SIZE;
}

// ----------------------------------------------------------------------------
// Asynchronous processing methods
void GPUEngine::EnableAsyncProcessing(int numStreams)
{
	if (!initialised) return;

	// Clean up existing streams if any
	if (asyncEnabled && streams) {
		for (int i = 0; i < this->numStreams; i++) {
			cudaStreamDestroy(streams[i]);
		}
		delete[] streams;
	}

	// Create new streams
	this->numStreams = numStreams;
	streams = new cudaStream_t[numStreams];

	for (int i = 0; i < numStreams; i++) {
		CudaSafeCall(cudaStreamCreate(&streams[i]));
	}

	asyncEnabled = true;
	currentStream = 0;
}

bool GPUEngine::callKernelSEARCH_MODE_MA_Async()
{
	if (!asyncEnabled || !streams) return false;

	// Reset nbFound for current stream
	CudaSafeCall(cudaMemsetAsync(outputBuffer, 0, 4, streams[currentStream]));

	// Call the kernel (Perform STEP_SIZE keys per thread)
	if (coinType == COIN_BTC) {
		if (compMode == SEARCH_COMPRESSED) {
			compute_keys_comp_mode_ma << < nbThread / nbThreadPerGroup, nbThreadPerGroup, 0, streams[currentStream] >> >
				(compMode, inputBloomLookUp, BLOOM_BITS, BLOOM_HASHES, inputKey, maxFound, outputBuffer);
		}
		else {
			compute_keys_mode_ma << < nbThread / nbThreadPerGroup, nbThreadPerGroup, 0, streams[currentStream] >> >
				(compMode, inputBloomLookUp, BLOOM_BITS, BLOOM_HASHES, inputKey, maxFound, outputBuffer);
		}
	}
	else {
		compute_keys_mode_eth_ma << < nbThread / nbThreadPerGroup, nbThreadPerGroup, 0, streams[currentStream] >> >
			(inputBloomLookUp, BLOOM_BITS, BLOOM_HASHES, inputKey, maxFound, outputBuffer);
	}

	// Check for kernel launch errors
	cudaError_t err = cudaGetLastError();
	if (err != cudaSuccess) {
		printf("Kernel launch error: %s\n", cudaGetErrorString(err));
		return false;
	}

	// Move to next stream for round-robin scheduling
	currentStream = (currentStream + 1) % numStreams;
	return true;
}

void GPUEngine::PrintCudaInfo()
{
	const char* sComputeMode[] = {
		"Multiple host threads",
		"Only one host thread",
		"No host thread",
		"Multiple process threads",
		"Unknown",
		NULL
	};

	int deviceCount = 0;
	CudaSafeCall(cudaGetDeviceCount(&deviceCount));

	// This function call returns 0 if there are no CUDA capable devices.
	if (deviceCount == 0) {
		printf("GPUEngine: There are no available device(s) that support CUDA\n");
		return;
	}

	for (int i = 0; i < deviceCount; i++) {
		CudaSafeCall(cudaSetDevice(i));
		cudaDeviceProp deviceProp;
		CudaSafeCall(cudaGetDeviceProperties(&deviceProp, i));
		printf("GPU #%d %s (%dx%d cores) (Cap %d.%d) (%.1f MB) (%s)\n",
			i, deviceProp.name, deviceProp.multiProcessorCount,
			_ConvertSMVer2Cores(deviceProp.major, deviceProp.minor),
			deviceProp.major, deviceProp.minor, (double)deviceProp.totalGlobalMem / 1048576.0,
			sComputeMode[deviceProp.computeMode]);
	}
}

// ----------------------------------------------------------------------------

GPUEngine::~GPUEngine()
{
	CudaSafeCall(cudaFree(inputKey));
	if (searchMode == (int)SEARCH_MODE_MA || searchMode == (int)SEARCH_MODE_MX)
		CudaSafeCall(cudaFree(inputBloomLookUp));
	else
		CudaSafeCall(cudaFree(inputHashORxpoint));

	CudaSafeCall(cudaFreeHost(outputBufferPinned));
	CudaSafeCall(cudaFree(outputBuffer));

	CudaSafeCall(cudaFree(__2Gnx));
	CudaSafeCall(cudaFree(__2Gny));
	CudaSafeCall(cudaFree(_Gx));
	CudaSafeCall(cudaFree(_Gy));

	// Destroy texture objects
	cudaDestroyTextureObject(texGx);
	cudaDestroyTextureObject(texGy);
	cudaDestroyTextureObject(tex2Gnx);
	cudaDestroyTextureObject(tex2Gny);

	// Destroy CUDA streams for double buffering
	for (int i = 0; i < 2; i++) {
		cudaStreamDestroy(stream_ma[i]);
		cudaStreamDestroy(stream_sa[i]);
		cudaStreamDestroy(stream_mx[i]);
		cudaStreamDestroy(stream_sx[i]);
	}

	// Destroy async streams if enabled
	if (asyncEnabled && streams) {
		for (int i = 0; i < numStreams; i++) {
			cudaStreamDestroy(streams[i]);
		}
		delete[] streams;
	}

	if (rKey)
		CudaSafeCall(cudaFreeHost(inputKeyPinned));
}

// ----------------------------------------------------------------------------

int GPUEngine::GetNbThread()
{
	return nbThread;
}

// ----------------------------------------------------------------------------

bool GPUEngine::callKernelSEARCH_MODE_MA()
{

	// Reset nbFound
	CudaSafeCall(cudaMemset(outputBuffer, 0, 4));

	// Call the kernel (Perform STEP_SIZE keys per thread)
	if (coinType == COIN_BTC) {
		if (compMode == SEARCH_COMPRESSED) {
			compute_keys_comp_mode_ma << < nbThread / nbThreadPerGroup, nbThreadPerGroup >> >
				(compMode, inputBloomLookUp, BLOOM_BITS, BLOOM_HASHES, inputKey, maxFound, outputBuffer);
		}
		else {
			compute_keys_mode_ma << < nbThread / nbThreadPerGroup, nbThreadPerGroup >> >
				(compMode, inputBloomLookUp, BLOOM_BITS, BLOOM_HASHES, inputKey, maxFound, outputBuffer);
		}
	}
	else {
		compute_keys_mode_eth_ma << < nbThread / nbThreadPerGroup, nbThreadPerGroup >> >
			(inputBloomLookUp, BLOOM_BITS, BLOOM_HASHES, inputKey, maxFound, outputBuffer);
	}

	cudaError_t err = cudaGetLastError();
	if (err != cudaSuccess) {
		printf("GPUEngine: Kernel: %s\n", cudaGetErrorString(err));
		return false;
	}
	return true;

}

// ----------------------------------------------------------------------------

bool GPUEngine::callKernelSEARCH_MODE_MX()
{

	// Reset nbFound
	CudaSafeCall(cudaMemset(outputBuffer, 0, 4));

	// Call the kernel (Perform STEP_SIZE keys per thread)
	if (compMode == SEARCH_COMPRESSED) {
		compute_keys_comp_mode_mx << < nbThread / nbThreadPerGroup, nbThreadPerGroup >> >
			(compMode, inputBloomLookUp, BLOOM_BITS, BLOOM_HASHES, inputKey, maxFound, outputBuffer);
	}
	else {
		printf("GPUEngine: PubKeys search doesn't support uncompressed\n");
		return false;
	}

	cudaError_t err = cudaGetLastError();
	if (err != cudaSuccess) {
		printf("GPUEngine: Kernel: %s\n", cudaGetErrorString(err));
		return false;
	}
	return true;
}

// ----------------------------------------------------------------------------

bool GPUEngine::callKernelSEARCH_MODE_SA()
{

	// Reset nbFound
	CudaSafeCall(cudaMemset(outputBuffer, 0, 4));

	// Call the kernel (Perform STEP_SIZE keys per thread)
	if (coinType == COIN_BTC) {
		if (compMode == SEARCH_COMPRESSED) {
			compute_keys_comp_mode_sa << < nbThread / nbThreadPerGroup, nbThreadPerGroup, 0, stream_sa[0] >> >
				(compMode, inputHashORxpoint, inputKey, maxFound, outputBuffer);
		}
		else {
			compute_keys_mode_sa << < nbThread / nbThreadPerGroup, nbThreadPerGroup, 0, stream_sa[0] >> >
				(compMode, inputHashORxpoint, inputKey, maxFound, outputBuffer);
		}
	}
	else {
		compute_keys_mode_eth_sa << < nbThread / nbThreadPerGroup, nbThreadPerGroup, 0, stream_sa[0] >> >
			(inputHashORxpoint, inputKey, maxFound, outputBuffer);
	}

	cudaError_t err = cudaGetLastError();
	if (err != cudaSuccess) {
		printf("GPUEngine: Kernel: %s\n", cudaGetErrorString(err));
		return false;
	}
	return true;

}

// ----------------------------------------------------------------------------

bool GPUEngine::callKernelSEARCH_MODE_SX()
{

	// Reset nbFound
	CudaSafeCall(cudaMemset(outputBuffer, 0, 4));

	// Call the kernel (Perform STEP_SIZE keys per thread)
	if (compMode == SEARCH_COMPRESSED) {
		compute_keys_comp_mode_sx << < nbThread / nbThreadPerGroup, nbThreadPerGroup >> >
			(compMode, inputHashORxpoint, inputKey, maxFound, outputBuffer);
	}
	else {
		printf("GPUEngine: PubKeys search doesn't support uncompressed\n");
		return false;
	}

	cudaError_t err = cudaGetLastError();
	if (err != cudaSuccess) {
		printf("GPUEngine: Kernel: %s\n", cudaGetErrorString(err));
		return false;
	}
	return true;
}

// ----------------------------------------------------------------------------

bool GPUEngine::SetKeys(Point* p)
{
	// Sets the starting keys for each thread
	// p must contains nbThread public keys
	for (int i = 0; i < nbThread; i += nbThreadPerGroup) {
		for (int j = 0; j < nbThreadPerGroup; j++) {

			inputKeyPinned[8 * i + j + 0 * nbThreadPerGroup] = p[i + j].x.bits64[0];
			inputKeyPinned[8 * i + j + 1 * nbThreadPerGroup] = p[i + j].x.bits64[1];
			inputKeyPinned[8 * i + j + 2 * nbThreadPerGroup] = p[i + j].x.bits64[2];
			inputKeyPinned[8 * i + j + 3 * nbThreadPerGroup] = p[i + j].x.bits64[3];

			inputKeyPinned[8 * i + j + 4 * nbThreadPerGroup] = p[i + j].y.bits64[0];
			inputKeyPinned[8 * i + j + 5 * nbThreadPerGroup] = p[i + j].y.bits64[1];
			inputKeyPinned[8 * i + j + 6 * nbThreadPerGroup] = p[i + j].y.bits64[2];
			inputKeyPinned[8 * i + j + 7 * nbThreadPerGroup] = p[i + j].y.bits64[3];

		}
	}

	// Fill device memory
	CudaSafeCall(cudaMemcpy(inputKey, inputKeyPinned, nbThread * 32 * 2, cudaMemcpyHostToDevice));

	if (!rKey) {
		// We do not need the input pinned memory anymore
		CudaSafeCall(cudaFreeHost(inputKeyPinned));
		inputKeyPinned = NULL;
	}

	switch (searchMode) {
	case (int)SEARCH_MODE_MA:
		return callKernelSEARCH_MODE_MA();
		break;
	case (int)SEARCH_MODE_SA:
		return callKernelSEARCH_MODE_SA();
		break;
	case (int)SEARCH_MODE_MX:
		return callKernelSEARCH_MODE_MX();
		break;
	case (int)SEARCH_MODE_SX:
		return callKernelSEARCH_MODE_SX();
		break;
	default:
		return false;
		break;
	}
}

// ----------------------------------------------------------------------------

bool GPUEngine::LaunchSEARCH_MODE_MA(std::vector<ITEM>& dataFound, bool spinWait)
{

	dataFound.clear();

	// Get the result
	if (spinWait) {
		CudaSafeCall(cudaMemcpy(outputBufferPinned, outputBuffer, outputSize, cudaMemcpyDeviceToHost));
	}
	else {
		// Use cudaMemcpyAsync to avoid default spin wait of cudaMemcpy wich takes 100% CPU
		cudaEvent_t evt;
		CudaSafeCall(cudaEventCreate(&evt));
		CudaSafeCall(cudaMemcpyAsync(outputBufferPinned, outputBuffer, 4, cudaMemcpyDeviceToHost, 0));
		CudaSafeCall(cudaEventRecord(evt, 0));
		while (cudaEventQuery(evt) == cudaErrorNotReady) {
			// Sleep 1 ms to free the CPU
			Timer::SleepMillis(1);
		}
		CudaSafeCall(cudaEventDestroy(evt));
	}

	// Look for data found
	uint32_t nbFound = outputBufferPinned[0];
	if (nbFound > maxFound) {
		nbFound = maxFound;
	}

	// When can perform a standard copy, the kernel is eneded
	CudaSafeCall(cudaMemcpy(outputBufferPinned, outputBuffer, nbFound * ITEM_SIZE_A + 4, cudaMemcpyDeviceToHost));

	for (uint32_t i = 0; i < nbFound; i++) {

		uint32_t* itemPtr = outputBufferPinned + (i * ITEM_SIZE_A32 + 1);
		uint8_t* hash = (uint8_t*)(itemPtr + 2);
		if (CheckBinary(hash, 20) > 0) {

			ITEM it;
			it.thId = itemPtr[0];
			int16_t* ptr = (int16_t*)&(itemPtr[1]);
			//it.endo = ptr[0] & 0x7FFF;
			it.mode = (ptr[0] & 0x8000) != 0;
			it.incr = ptr[1];
			it.hash = (uint8_t*)(itemPtr + 2);
			dataFound.push_back(it);
		}
	}
	return callKernelSEARCH_MODE_MA();
}

// ----------------------------------------------------------------------------

bool GPUEngine::LaunchSEARCH_MODE_SA(std::vector<ITEM>& dataFound, bool spinWait)
{

	dataFound.clear();

	// Get the result
	if (spinWait) {
		CudaSafeCall(cudaMemcpy(outputBufferPinned, outputBuffer, outputSize, cudaMemcpyDeviceToHost));
	}
	else {
		// Use cudaMemcpyAsync to avoid default spin wait of cudaMemcpy wich takes 100% CPU
		cudaEvent_t evt;
		CudaSafeCall(cudaEventCreate(&evt));
		CudaSafeCall(cudaMemcpyAsync(outputBufferPinned, outputBuffer, 4, cudaMemcpyDeviceToHost, 0));
		CudaSafeCall(cudaEventRecord(evt, 0));
		while (cudaEventQuery(evt) == cudaErrorNotReady) {
			// Sleep 1 ms to free the CPU
			Timer::SleepMillis(1);
		}
		CudaSafeCall(cudaEventDestroy(evt));
	}

	// Look for data found
	uint32_t nbFound = outputBufferPinned[0];
	if (nbFound > maxFound) {
		nbFound = maxFound;
	}

	// When can perform a standard copy, the kernel is eneded
	CudaSafeCall(cudaMemcpy(outputBufferPinned, outputBuffer, nbFound * ITEM_SIZE_A + 4, cudaMemcpyDeviceToHost));

	for (uint32_t i = 0; i < nbFound; i++) {
		uint32_t* itemPtr = outputBufferPinned + (i * ITEM_SIZE_A32 + 1);
		ITEM it;
		it.thId = itemPtr[0];
		int16_t* ptr = (int16_t*)&(itemPtr[1]);
		//it.endo = ptr[0] & 0x7FFF;
		it.mode = (ptr[0] & 0x8000) != 0;
		it.incr = ptr[1];
		it.hash = (uint8_t*)(itemPtr + 2);
		dataFound.push_back(it);
	}
	return callKernelSEARCH_MODE_SA();
}

// ----------------------------------------------------------------------------

bool GPUEngine::LaunchSEARCH_MODE_MX(std::vector<ITEM>& dataFound, bool spinWait)
{

	dataFound.clear();

	// Get the result
	if (spinWait) {
		CudaSafeCall(cudaMemcpy(outputBufferPinned, outputBuffer, outputSize, cudaMemcpyDeviceToHost));
	}
	else {
		// Use cudaMemcpyAsync to avoid default spin wait of cudaMemcpy wich takes 100% CPU
		cudaEvent_t evt;
		CudaSafeCall(cudaEventCreate(&evt));
		CudaSafeCall(cudaMemcpyAsync(outputBufferPinned, outputBuffer, 4, cudaMemcpyDeviceToHost, 0));
		CudaSafeCall(cudaEventRecord(evt, 0));
		while (cudaEventQuery(evt) == cudaErrorNotReady) {
			// Sleep 1 ms to free the CPU
			Timer::SleepMillis(1);
		}
		CudaSafeCall(cudaEventDestroy(evt));
	}

	// Look for data found
	uint32_t nbFound = outputBufferPinned[0];
	if (nbFound > maxFound) {
		nbFound = maxFound;
	}

	// When can perform a standard copy, the kernel is eneded
	CudaSafeCall(cudaMemcpy(outputBufferPinned, outputBuffer, nbFound * ITEM_SIZE_X + 4, cudaMemcpyDeviceToHost));

	for (uint32_t i = 0; i < nbFound; i++) {

		uint32_t* itemPtr = outputBufferPinned + (i * ITEM_SIZE_X32 + 1);
		uint8_t* pubkey = (uint8_t*)(itemPtr + 2);

		if (CheckBinary(pubkey, 32) > 0) {

			ITEM it;
			it.thId = itemPtr[0];
			int16_t* ptr = (int16_t*)&(itemPtr[1]);
			//it.endo = ptr[0] & 0x7FFF;
			it.mode = (ptr[0] & 0x8000) != 0;
			it.incr = ptr[1];
			it.hash = (uint8_t*)(itemPtr + 2);
			dataFound.push_back(it);
		}
	}
	return callKernelSEARCH_MODE_MX();
}

// ----------------------------------------------------------------------------

bool GPUEngine::LaunchSEARCH_MODE_SX(std::vector<ITEM>& dataFound, bool spinWait)
{

	dataFound.clear();

	// Get the result
	if (spinWait) {
		CudaSafeCall(cudaMemcpy(outputBufferPinned, outputBuffer, outputSize, cudaMemcpyDeviceToHost));
	}
	else {
		// Use cudaMemcpyAsync to avoid default spin wait of cudaMemcpy wich takes 100% CPU
		cudaEvent_t evt;
		CudaSafeCall(cudaEventCreate(&evt));
		CudaSafeCall(cudaMemcpyAsync(outputBufferPinned, outputBuffer, 4, cudaMemcpyDeviceToHost, 0));
		CudaSafeCall(cudaEventRecord(evt, 0));
		while (cudaEventQuery(evt) == cudaErrorNotReady) {
			// Sleep 1 ms to free the CPU
			Timer::SleepMillis(1);
		}
		CudaSafeCall(cudaEventDestroy(evt));
	}

	// Look for data found
	uint32_t nbFound = outputBufferPinned[0];
	if (nbFound > maxFound) {
		nbFound = maxFound;
	}

	// When can perform a standard copy, the kernel is eneded
	CudaSafeCall(cudaMemcpy(outputBufferPinned, outputBuffer, nbFound * ITEM_SIZE_X + 4, cudaMemcpyDeviceToHost));

	for (uint32_t i = 0; i < nbFound; i++) {

		uint32_t* itemPtr = outputBufferPinned + (i * ITEM_SIZE_X32 + 1);
		uint8_t* pubkey = (uint8_t*)(itemPtr + 2);

		ITEM it;
		it.thId = itemPtr[0];
		int16_t* ptr = (int16_t*)&(itemPtr[1]);
		//it.endo = ptr[0] & 0x7FFF;
		it.mode = (ptr[0] & 0x8000) != 0;
		it.incr = ptr[1];
		it.hash = (uint8_t*)(itemPtr + 2);
		dataFound.push_back(it);
	}
	return callKernelSEARCH_MODE_SX();
}

// ----------------------------------------------------------------------------

int GPUEngine::CheckBinary(const uint8_t* _x, int K_LENGTH)
{
	uint8_t* temp_read;
	uint64_t half, min, max, current; //, current_offset
	int64_t rcmp;
	int32_t r = 0;
	min = 0;
	current = 0;
	max = TOTAL_COUNT;
	half = TOTAL_COUNT;
	while (!r && half >= 1) {
		half = (max - min) / 2;
	}

// ----------------------------------------------------------------------------
// Search method with key filtering support
// ----------------------------------------------------------------------------

uint32_t GPUEngine::Search(int gpuId, Int& startRange, Int& endRange)
{
	// Generate starting keys for each thread
	Point* keys = new Point[nbThread];
	Int key(&startRange);

	for (int i = 0; i < nbThread; i++) {
		// Generate key for this thread
		keys[i] = secp->ComputePublicKey(key);
		// Advance key by STEP_SIZE for next thread
		key.Add((uint64_t)STEP_SIZE);
	}

	// Set keys and launch search
	SetKeys(keys);

	// Clean up
	delete[] keys;

	// For now, return 0 as we're not tracking found keys in this simplified implementation
	// In a full implementation, this would return the number of found keys
	return 0;
}

// ----------------------------------------------------------------------------
// GLV Support Methods
// ----------------------------------------------------------------------------

void GPUEngine::SetGLVConstants(const Int& lambda, const Int& beta)
{
	// Copy GLV constants to GPU device memory
	CudaSafeCall(cudaMemcpyToSymbol(d_lambda, lambda.bits64, sizeof(uint64_t) * 4, 0, cudaMemcpyHostToDevice));
	CudaSafeCall(cudaMemcpyToSymbol(d_beta, beta.bits64, sizeof(uint64_t) * 4, 0, cudaMemcpyHostToDevice));
}
		temp_read = DATA + ((current + half) * K_LENGTH);
		rcmp = memcmp(_x, temp_read, K_LENGTH);
		if (rcmp == 0) {
			r = 1;  //Found!!
		}
		else {
			if (rcmp < 0) { //data < temp_read
				max = (max - half);
			}
			else { // data > temp_read
				min = (min + half);
			}
			current = min;
		}
	}
	return r;
}

// ----------------------------------------------------------------------------
// Search method with key filtering support
// ----------------------------------------------------------------------------
uint32_t GPUEngine::Search(int gpuId, Int& startRange, Int& endRange) {

    // Generate starting keys for each thread
    Point* keys = new Point[nbThread];
    Int key(&startRange);

    for (int i = 0; i < nbThread; i++) {
        // Generate key for this thread
        keys[i] = secp->ComputePublicKey(key);
        // Advance key by STEP_SIZE for next thread
        key.Add((uint64_t)STEP_SIZE);
    }

    // Set keys and launch search
    SetKeys(keys);

    // Clean up
    delete[] keys;

    // For now, return 0 as we're not tracking found keys in this simplified implementation
    // In a full implementation, this would return the number of found keys
    return 0;
}




