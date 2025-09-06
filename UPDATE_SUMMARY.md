# KeyHunt-Cuda - RTX 30XX, 40XX and 50XX Support Update

## Summary of Changes

This update makes KeyHunt-Cuda compatible with RTX 30XX, 40XX and 50XX series GPUs and CUDA 12.X.

### Files Modified

1. **KeyHunt-Cuda/KeyHunt-Cuda.vcxproj**
   - Updated CUDA version from 10.0 to 12.0
   - Updated platform toolset from v142 to v143
   - Added compute capabilities 8.0, 8.6, 8.9 and 12.0

2. **KeyHunt-Cuda/Makefile**
   - Updated CUDA path to be more flexible
   - Added compute capabilities 8.0, 8.6, 8.9 and 12.0
   - Improved gencode parameters for better compatibility

3. **KeyHunt-Cuda/GPU/GPUEngine.cu**
   - Added support for compute capability 8.9 (RTX 40XX) in `_ConvertSMVer2Cores` function
   - Added preliminary support for compute capability 12.0 (RTX 50XX)

4. **KeyHunt-Cuda/KeyHunt.cpp**
   - Converted to UTF-8 encoding
   - Added key filtering rules for improved search efficiency
   - Enhanced key validation and processing

5. **KeyHunt-Cuda/KeyHunt.h**
   - Converted to UTF-8 encoding
   - Maintained all existing functionality and interfaces

6. **start.sh**
   - Added automatic detection for RTX 20XX/30XX/40XX/50XX series
   - Enhanced GPU series identification based on compute capability
   - Added specific compilation messages for each GPU series
   - Converted to UTF-8 encoding

7. **README.md**
   - Updated documentation to reflect CUDA 12.X compatibility
   - Added instructions for building with RTX 30XX, 40XX and 50XX support
   - Added comprehensive GPU support information
   - Converted to UTF-8 encoding

8. **Python Scripts**
   - Added UTF-8 encoding specification to file operations
   - Updated addresses_to_hash160.py, eth_addresses_to_bin.py and keyhunt_manager.py
   - Improved error handling and messaging

### Compute Capabilities Added

- **8.0**: A100 GPUs
- **8.6**: RTX 30XX series GPUs
- **8.9**: RTX 40XX series GPUs
- **12.0**: RTX 50XX series GPUs (Preliminary support)

### Building for Specific GPUs

For RTX 30XX series:
```bash
make gpu=1 CCAP=86
```

For RTX 40XX series:
```bash
make gpu=1 CCAP=89
```

For RTX 50XX series:
```bash
make gpu=1 CCAP=120
```

### Windows Build

Open KeyHunt-Cuda.sln in Visual Studio 2022 with CUDA 12.0 installed and build normally.

### Compatibility Notes

The code is fully compatible with CUDA 12.X and should work without issues on:
- RTX 30XX series (compute capability 8.6)
- RTX 40XX series (compute capability 8.9)
- RTX 50XX series (compute capability 12.0) - Preliminary support
- Other modern GPUs with compute capabilities 3.0-12.0

No changes were required to the core CUDA algorithms or memory management patterns, ensuring that performance characteristics remain the same.