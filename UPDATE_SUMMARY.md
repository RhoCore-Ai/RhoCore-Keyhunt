# KeyHunt-Cuda - RTX 30XX and 40XX Support Update

## Summary of Changes

This update makes KeyHunt-Cuda compatible with RTX 30XX and 40XX series GPUs and CUDA 12.X.

### Files Modified

1. **KeyHunt-Cuda/KeyHunt-Cuda.vcxproj**
   - Updated CUDA version from 10.0 to 12.0
   - Updated platform toolset from v142 to v143
   - Added compute capabilities 8.0, 8.6, and 8.9

2. **KeyHunt-Cuda/Makefile**
   - Updated CUDA path to be more flexible
   - Added compute capabilities 8.0, 8.6, and 8.9
   - Improved gencode parameters for better compatibility

3. **KeyHunt-Cuda/GPU/GPUEngine.cu**
   - Added support for compute capability 8.9 (RTX 40XX) in `_ConvertSMVer2Cores` function

4. **README.md**
   - Updated documentation to reflect CUDA 12.X compatibility
   - Added instructions for building with RTX 30XX and 40XX support

### Compute Capabilities Added

- **8.0**: A100 GPUs
- **8.6**: RTX 30XX series GPUs
- **8.9**: RTX 40XX series GPUs

### Building for Specific GPUs

For RTX 30XX series:
```bash
make gpu=1 CCAP=86
```

For RTX 40XX series:
```bash
make gpu=1 CCAP=89
```

### Windows Build

Open KeyHunt-Cuda.sln in Visual Studio 2022 with CUDA 12.0 installed and build normally.

### Compatibility Notes

The code is fully compatible with CUDA 12.X and should work without issues on:
- RTX 30XX series (compute capability 8.6)
- RTX 40XX series (compute capability 8.9)
- Other modern GPUs with compute capabilities 3.0-8.9

No changes were required to the core CUDA algorithms or memory management patterns, ensuring that performance characteristics remain the same.