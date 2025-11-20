#!/usr/bin/env python3
"""
Generate test WAV files for audio visualizer debugging.

This script creates various test signals to verify FFT functionality:
- Pure sine waves at specific frequencies
- Low-pass filtered noise (matching your use case)
- Multiple frequency components
- Frequency sweeps
- Silence (baseline)

Usage:
    python generate_test_audio.py
"""

import numpy as np
import scipy.io.wavfile as wavfile
from scipy import signal
import os

# Audio parameters
SAMPLE_RATE = 44100  # 44.1 kHz (matching your app)
DURATION = 5.0  # 5 seconds per file
OUTPUT_DIR = "test_audio"

def ensure_output_dir():
    """Create output directory if it doesn't exist."""
    if not os.path.exists(OUTPUT_DIR):
        os.makedirs(OUTPUT_DIR)
        print(f"Created directory: {OUTPUT_DIR}")

def generate_sine_wave(frequency, sample_rate, duration, amplitude=0.5):
    """Generate a pure sine wave at the specified frequency."""
    t = np.linspace(0, duration, int(sample_rate * duration), False)
    wave = amplitude * np.sin(2 * np.pi * frequency * t)
    return wave.astype(np.float32)

def generate_lowpass_noise(cutoff_freq, sample_rate, duration, amplitude=0.3):
    """Generate white noise filtered with a low-pass filter."""
    # Generate white noise
    noise = np.random.normal(0, amplitude, int(sample_rate * duration))
    
    # Design a Butterworth low-pass filter
    nyquist = sample_rate / 2
    normal_cutoff = cutoff_freq / nyquist
    b, a = signal.butter(4, normal_cutoff, btype='low', analog=False)
    
    # Apply the filter
    filtered_noise = signal.filtfilt(b, a, noise)
    
    return filtered_noise.astype(np.float32)

def generate_multi_tone(frequencies, amplitudes, sample_rate, duration):
    """Generate a signal with multiple frequency components."""
    t = np.linspace(0, duration, int(sample_rate * duration), False)
    wave = np.zeros_like(t)
    
    for freq, amp in zip(frequencies, amplitudes):
        wave += amp * np.sin(2 * np.pi * freq * t)
    
    # Normalize to prevent clipping
    max_val = np.max(np.abs(wave))
    if max_val > 1.0:
        wave = wave / max_val * 0.9
    
    return wave.astype(np.float32)

def generate_sweep(start_freq, end_freq, sample_rate, duration, amplitude=0.5):
    """Generate a frequency sweep (chirp) from start_freq to end_freq."""
    t = np.linspace(0, duration, int(sample_rate * duration), False)
    
    # Linear frequency sweep
    phase = 2 * np.pi * (start_freq * t + (end_freq - start_freq) * t**2 / (2 * duration))
    wave = amplitude * np.sin(phase)
    
    return wave.astype(np.float32)

def save_wav(filename, data, sample_rate):
    """Save audio data as a WAV file."""
    # Normalize to 16-bit integer range
    data_int16 = (data * 32767).astype(np.int16)
    filepath = os.path.join(OUTPUT_DIR, filename)
    wavfile.write(filepath, sample_rate, data_int16)
    print(f"Generated: {filepath}")

def main():
    """Generate all test audio files."""
    ensure_output_dir()
    
    print("Generating test audio files...")
    print(f"Sample rate: {SAMPLE_RATE} Hz")
    print(f"Duration: {DURATION} seconds")
    print(f"Output directory: {OUTPUT_DIR}\n")
    
    # 1. Pure sine waves at specific frequencies
    print("1. Generating pure sine waves...")
    test_frequencies = [
        (50, "50hz_pure_tone.wav"),
        (100, "100hz_pure_tone.wav"),
        (200, "200hz_pure_tone.wav"),
        (440, "440hz_pure_tone.wav"),  # A4 note
        (1000, "1000hz_pure_tone.wav"),
        (5000, "5000hz_pure_tone.wav"),
    ]
    
    for freq, filename in test_frequencies:
        wave = generate_sine_wave(freq, SAMPLE_RATE, DURATION, amplitude=0.5)
        save_wav(filename, wave, SAMPLE_RATE)
    
    # 2. Low-pass filtered noise (matching your use case)
    print("\n2. Generating low-pass filtered noise...")
    cutoff_frequencies = [
        (50, "lowpass_50hz_noise.wav"),
        (100, "lowpass_100hz_noise.wav"),
        (200, "lowpass_200hz_noise.wav"),
        (500, "lowpass_500hz_noise.wav"),
    ]
    
    for cutoff, filename in cutoff_frequencies:
        noise = generate_lowpass_noise(cutoff, SAMPLE_RATE, DURATION, amplitude=0.3)
        save_wav(filename, noise, SAMPLE_RATE)
    
    # 3. Multiple frequency components
    print("\n3. Generating multi-tone signals...")
    multi_tones = [
        ([100, 200, 300], [0.3, 0.2, 0.1], "multi_tone_100_200_300hz.wav"),
        ([50, 100, 500, 1000], [0.25, 0.25, 0.15, 0.1], "multi_tone_50_100_500_1000hz.wav"),
        ([440, 880, 1320], [0.3, 0.2, 0.15], "multi_tone_harmonic_440hz.wav"),  # Harmonic series
    ]
    
    for freqs, amps, filename in multi_tones:
        wave = generate_multi_tone(freqs, amps, SAMPLE_RATE, DURATION)
        save_wav(filename, wave, SAMPLE_RATE)
    
    # 4. Frequency sweeps
    print("\n4. Generating frequency sweeps...")
    sweeps = [
        (20, 200, "sweep_20_to_200hz.wav"),
        (100, 5000, "sweep_100_to_5000hz.wav"),
        (5000, 20000, "sweep_5k_to_20khz.wav"),
    ]
    
    for start, end, filename in sweeps:
        wave = generate_sweep(start, end, SAMPLE_RATE, DURATION, amplitude=0.5)
        save_wav(filename, wave, SAMPLE_RATE)
    
    # 5. Silence (baseline)
    print("\n5. Generating silence (baseline)...")
    silence = np.zeros(int(SAMPLE_RATE * DURATION), dtype=np.float32)
    save_wav("silence.wav", silence, SAMPLE_RATE)
    
    # 6. Very low frequency (below 100Hz) - matching your use case
    print("\n6. Generating very low frequency signals...")
    low_freqs = [
        (20, "20hz_pure_tone.wav"),
        (30, "30hz_pure_tone.wav"),
        (40, "40hz_pure_tone.wav"),
        (60, "60hz_pure_tone.wav"),
        (80, "80hz_pure_tone.wav"),
        (90, "90hz_pure_tone.wav"),
    ]
    
    for freq, filename in low_freqs:
        wave = generate_sine_wave(freq, SAMPLE_RATE, DURATION, amplitude=0.5)
        save_wav(filename, wave, SAMPLE_RATE)
    
    print(f"\n✅ All test files generated in '{OUTPUT_DIR}' directory!")
    print("\nExpected FFT results:")
    print("  - Pure tones: Should show peak at corresponding frequency bin")
    print("  - Low-pass noise: Should show energy only below cutoff frequency")
    print("  - Multi-tone: Should show peaks at all component frequencies")
    print("  - Sweeps: Should show energy across the swept frequency range")
    print("  - Silence: Should show minimal/no energy across all frequencies")

if __name__ == "__main__":
    main()

