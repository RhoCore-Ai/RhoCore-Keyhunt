# KeyHunt-Cuda 
_Hunt for Bitcoin private keys._

This is a modified version of VanitySearch by [JeanLucPons](https://github.com/JeanLucPons/VanitySearch/).

Renamed from VanitySearch to KeyHunt (inspired from [keyhunt](https://github.com/albertobsd/keyhunt) by albertobsd).

A lot of gratitude to all the developers whose codes has been used here.

## Features
- For Bitcoin use ```--coin BTC``` and for Ethereum use ```--coin ETH```
- Single address(rmd160 hash) for BTC or ETH address searching with mode ```-m ADDREES```
- Multiple addresses(rmd160 hashes) or ETH addresses searching with mode ```-m ADDREESES```
- XPoint[s] mode is applicable for ```--coin BTC``` only
- Single xpoint searching with mode ```-m XPOINT```
- Multiple xpoint searching with mode ```-m XPOINTS```
- For XPoint[s] mode use x point of the public key, without 02 or 03 prefix(64 chars).
- Cuda only.

## Updates for RTX 30XX and 40XX Support

This version has been updated to support:
- RTX 30XX series GPUs (compute capability 8.6)
- RTX 40XX series GPUs (compute capability 8.9)
- CUDA 12.X compatibility

### Windows Build
- Updated project files for CUDA 12.0
- Added support for compute capabilities 8.0, 8.6, and 8.9
- Updated platform toolset to v143 (Visual Studio 2022)

### Linux Build
- Updated Makefile for CUDA 12.X compatibility
- Added support for compute capabilities 8.0, 8.6, and 8.9
- Made CUDA path more flexible

## Usage
- For multiple addresses or xpoints, file format must be binary with sorted data.
- To convert Bitcoin addresses to rmd160 hashes, use the provided Python scripts.
- For Ethereum addresses, use the eth_addresses_to_bin.py script.

## Building

### Windows
Open KeyHunt-Cuda.sln in Visual Studio 2022 and build with CUDA 12.0 installed.

### Linux
```bash
# For CPU only build
make

# For GPU enabled build
make gpu=1

# For GPU enabled build with specific compute capability
make gpu=1 CCAP=86  # For RTX 30XX
make gpu=1 CCAP=89  # For RTX 40XX
```

## Requirements
- CUDA 12.X toolkit
- For Windows: Visual Studio 2022
- GMP library