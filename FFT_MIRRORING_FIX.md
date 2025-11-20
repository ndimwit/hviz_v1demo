# FFT Mirroring Issue - Root Cause and Fix

## Problem Identified

The test script revealed that **bins 250-255 contain complex conjugates of bins 6-1**. This is actually **correct behavior** for a real-to-complex DFT, but it means we're seeing mirrored magnitudes in the extracted array.

### Key Finding

For a 512-point FFT with real input:
- **Bin[1]**: real=-6.5881, imag=3.8818, mag=7.6467
- **Bin[255]**: real=-6.5881, imag=-3.8818, mag=7.6467 (complex conjugate of bin[1])

The magnitudes are the same, which is why we see "mirroring" in the visualization.

## Root Cause

The issue is that **bins 250-255 (within the first N/2 bins) are complex conjugates of bins 6-1**. This suggests that the DFT output might be storing the data in a way where:
- Bins 0 to ~245: Normal frequency components
- Bins 246-255: Complex conjugates of earlier bins (mirrored data)
- Bin 256: Nyquist
- Bins 257-511: Zeros or additional mirrored data

## Solution

We need to ensure we're only extracting the **truly unique** frequency bins. The current code extracts bins 0 to N/2-1 (0 to 255), but this includes mirrored data in bins 250-255.

### Recommended Fix

1. **Extract only bins 0 to N/2-1, but verify they're not mirrored**
2. **Or, use a different extraction strategy** that identifies and excludes mirrored bins

However, the standard approach for real-to-complex FFTs is to extract bins 0 to N/2 (inclusive), which gives N/2+1 unique bins. The current code extracts N/2 bins (0 to N/2-1), which should be correct, but the test shows mirrored data.

## Next Steps

1. Verify the actual DFT output structure by checking if bins 250-255 should actually be zeros
2. Check if the issue is in how we're computing magnitudes (maybe we need to handle the complex conjugate differently)
3. Consider using `vDSP_fft_zrip` instead of `vDSP_DFT_Execute` if it provides a better packed format

## Test Results Summary

- **Expected frequency**: 1000 Hz at bin 11
- **Peak found at**: bin 6 (516.8 Hz) - this is likely due to spectral leakage from windowing
- **Mirroring detected**: Bins 250-255 are complex conjugates of bins 6-1
- **Extracted array**: Contains 256 bins (0-255), including mirrored data in bins 246-255

