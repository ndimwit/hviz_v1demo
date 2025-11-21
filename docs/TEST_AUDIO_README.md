# Test Audio Generator

This script generates test WAV files for debugging the audio visualizer FFT implementation.

## Setup

1. Install Python dependencies:
```bash
pip install -r test_audio_requirements.txt
```

Or install directly:
```bash
pip install numpy scipy
```

## Usage

Run the script:
```bash
python generate_test_audio.py
```

This will create a `test_audio/` directory with various test files.

## Generated Test Files

### 1. Pure Sine Waves
- `50hz_pure_tone.wav` - 50 Hz pure tone
- `100hz_pure_tone.wav` - 100 Hz pure tone
- `200hz_pure_tone.wav` - 200 Hz pure tone
- `440hz_pure_tone.wav` - 440 Hz (A4 note)
- `1000hz_pure_tone.wav` - 1000 Hz pure tone
- `5000hz_pure_tone.wav` - 5000 Hz pure tone

**Expected FFT result**: Sharp peak at the corresponding frequency bin.

### 2. Low-Pass Filtered Noise
- `lowpass_50hz_noise.wav` - Noise filtered below 50 Hz
- `lowpass_100hz_noise.wav` - Noise filtered below 100 Hz (matches your use case)
- `lowpass_200hz_noise.wav` - Noise filtered below 200 Hz
- `lowpass_500hz_noise.wav` - Noise filtered below 500 Hz

**Expected FFT result**: Energy only below the cutoff frequency, minimal energy above.

### 3. Multi-Tone Signals
- `multi_tone_100_200_300hz.wav` - Three frequencies simultaneously
- `multi_tone_50_100_500_1000hz.wav` - Four frequencies
- `multi_tone_harmonic_440hz.wav` - Harmonic series (440, 880, 1320 Hz)

**Expected FFT result**: Peaks at all component frequencies.

### 4. Frequency Sweeps
- `sweep_20_to_200hz.wav` - Sweep from 20 Hz to 200 Hz
- `sweep_100_to_5000hz.wav` - Sweep from 100 Hz to 5 kHz
- `sweep_5k_to_20khz.wav` - Sweep from 5 kHz to 20 kHz

**Expected FFT result**: Energy distributed across the swept frequency range.

### 5. Very Low Frequencies
- `20hz_pure_tone.wav` through `90hz_pure_tone.wav` - Low frequency tones

**Expected FFT result**: Peaks at the corresponding low frequency bins.

### 6. Baseline
- `silence.wav` - Complete silence

**Expected FFT result**: Minimal/no energy across all frequencies.

## Testing with Your Visualizer

1. Play each test file through your audio visualizer
2. Check the console output for FFT analysis
3. Verify that:
   - Pure tones show peaks at the correct frequency bins
   - Low-pass filtered noise shows energy only below the cutoff
   - Multi-tone signals show peaks at all component frequencies
   - High frequencies show minimal energy for low-pass filtered signals
   - No mirroring artifacts appear

## Frequency Bin Calculation

For a 512-point FFT at 44.1 kHz sample rate:
- Frequency resolution: 44100 / 512 = 86.13 Hz per bin
- Bin 0 = DC (0 Hz)
- Bin 1 = 86.1 Hz
- Bin 2 = 172.3 Hz
- Bin 3 = 258.4 Hz
- ...
- Bin 256 = Nyquist (22050 Hz)

So a 100 Hz tone should appear primarily in bin 1 (86.1 Hz), with some energy in bin 2 (172.3 Hz) due to spectral leakage.

