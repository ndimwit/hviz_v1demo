#!/usr/bin/env swift

// Standalone FFT test script to isolate mirroring issues
// This script tests the FFT implementation independently of the app

import Foundation
import Accelerate

// Test parameters
let windowSize = 512
let sampleRate: Float = 44100.0
let testFrequency: Float = 1000.0  // 1kHz test tone

// Generate test signal: pure sine wave at testFrequency
func generateTestSignal(frequency: Float, sampleRate: Float, windowSize: Int) -> [Float] {
    var signal: [Float] = []
    signal.reserveCapacity(windowSize)
    
    for i in 0..<windowSize {
        let t = Float(i) / sampleRate
        let sample = sin(2.0 * Float.pi * frequency * t)
        signal.append(sample)
    }
    
    return signal
}

// Perform FFT using the same approach as AudioUnitMonitor
func performFFTTest(inputData: [Float], windowSize: Int) -> (allMagnitudes: [Float], extractedMagnitudes: [Float], realOut: [Float], imagOut: [Float]) {
    // Create FFT setup (real-to-complex)
    guard let fftSetup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(windowSize), vDSP_DFT_Direction.FORWARD) else {
        fatalError("Failed to create FFT setup")
    }
    defer {
        vDSP_DFT_DestroySetup(fftSetup)
    }
    
    // Apply windowing
    var windowedData = inputData
    var window = [Float](repeating: 0, count: windowSize)
    vDSP_hann_window(&window, vDSP_Length(windowSize), Int32(vDSP_HANN_NORM))
    vDSP_vmul(windowedData, 1, window, 1, &windowedData, 1, vDSP_Length(windowSize))
    
    // Prepare output arrays
    var realOut = [Float](repeating: 0, count: windowSize)
    var imagOut = [Float](repeating: 0, count: windowSize)
    var inputImag = [Float](repeating: 0, count: windowSize)
    
    // Execute DFT
    windowedData.withUnsafeBufferPointer { inputPtr in
        inputImag.withUnsafeBufferPointer { inputImagPtr in
            realOut.withUnsafeMutableBufferPointer { realOutPtr in
                imagOut.withUnsafeMutableBufferPointer { imagOutPtr in
                    vDSP_DFT_Execute(
                        fftSetup,
                        inputPtr.baseAddress!,
                        inputImagPtr.baseAddress!,
                        realOutPtr.baseAddress!,
                        imagOutPtr.baseAddress!
                    )
                }
            }
        }
    }
    
    // Compute magnitudes for all bins
    var complex = DSPSplitComplex(
        realp: realOut.withUnsafeMutableBufferPointer { $0.baseAddress! },
        imagp: imagOut.withUnsafeMutableBufferPointer { $0.baseAddress! }
    )
    
    var allMagnitudes = [Float](repeating: 0, count: windowSize)
    allMagnitudes.withUnsafeMutableBufferPointer { allMagPtr in
        vDSP_zvabs(&complex, 1, allMagPtr.baseAddress!, 1, vDSP_Length(windowSize))
    }
    
    // Extract first N/2 bins (as done in AudioUnitMonitor)
    let fftOutputSize = windowSize / 2
    var extractedMagnitudes = Array(allMagnitudes.prefix(fftOutputSize))
    
    // Debug: Check real/imaginary parts to understand the output structure
    print("\n🔍 Debug: Checking bins 250-255 (where mirrored values appear in extracted array):")
    for i in 250...255 {
        let mirrorIdx = windowSize - i
        let correspondingBin = windowSize / 2 - (i - windowSize / 2)
        print("  bin[\(i)]: real=\(String(format: "%.4f", realOut[i])), imag=\(String(format: "%.4f", imagOut[i])), mag=\(String(format: "%.4f", allMagnitudes[i]))")
        print("    Expected mirror bin[\(mirrorIdx)]: real=\(String(format: "%.4f", realOut[mirrorIdx])), imag=\(String(format: "%.4f", imagOut[mirrorIdx])), mag=\(String(format: "%.4f", allMagnitudes[mirrorIdx]))")
        if i < windowSize / 2 {
            print("    Corresponding bin[\(correspondingBin)]: real=\(String(format: "%.4f", realOut[correspondingBin])), imag=\(String(format: "%.4f", imagOut[correspondingBin])), mag=\(String(format: "%.4f", allMagnitudes[correspondingBin]))")
        }
    }
    
    print("\n🔍 Debug: Checking bins 1-10 (low frequency bins):")
    for i in 1...10 {
        print("  bin[\(i)]: real=\(String(format: "%.4f", realOut[i])), imag=\(String(format: "%.4f", imagOut[i])), mag=\(String(format: "%.4f", allMagnitudes[i]))")
    }
    
    return (allMagnitudes, extractedMagnitudes, realOut, imagOut)
}

// Helper to repeat string
func repeatString(_ str: String, count: Int) -> String {
    return String(repeating: str, count: count)
}

// Print results
func printResults(allMagnitudes: [Float], extractedMagnitudes: [Float], realOut: [Float], imagOut: [Float], windowSize: Int, sampleRate: Float, testFrequency: Float) {
    let frequencyResolution = sampleRate / Float(windowSize)
    let expectedBin = Int(testFrequency / frequencyResolution)
    
    print(repeatString("=", count: 80))
    print("FFT Test Results")
    print(repeatString("=", count: 80))
    print("Window Size: \(windowSize)")
    print("Sample Rate: \(sampleRate) Hz")
    print("Test Frequency: \(testFrequency) Hz")
    print("Frequency Resolution: \(frequencyResolution) Hz/bin")
    print("Expected Bin: \(expectedBin) (frequency: \(Float(expectedBin) * frequencyResolution) Hz)")
    print()
    
    // Check for mirroring in allMagnitudes
    print("Mirroring Check (comparing bin k with bin N-k):")
    print(repeatString("-", count: 80))
    var mirroringFound = false
    for k in 1..<min(50, windowSize / 2) {
        let mirrorIdx = windowSize - k
        let diff = abs(allMagnitudes[k] - allMagnitudes[mirrorIdx])
        if diff > 0.001 {
            print("  bin[\(k)]=\(String(format: "%.4f", allMagnitudes[k])) vs bin[\(mirrorIdx)]=\(String(format: "%.4f", allMagnitudes[mirrorIdx])): diff=\(String(format: "%.4f", diff))")
            mirroringFound = true
        }
    }
    if !mirroringFound {
        print("  No significant differences found (mirroring is correct for real input)")
    }
    print()
    
    // Show bins around expected frequency
    print("Bins around expected frequency (\(testFrequency) Hz):")
    print(repeatString("-", count: 80))
    let startBin = max(0, expectedBin - 5)
    let endBin = min(windowSize, expectedBin + 6)
    for i in startBin..<endBin {
        let freq = Float(i) * frequencyResolution
        let magnitude = allMagnitudes[i]
        let marker = (i == expectedBin) ? " <-- EXPECTED" : ""
        print("  bin[\(i)]: \(String(format: "%6.1f", freq)) Hz, magnitude: \(String(format: "%.4f", magnitude))\(marker)")
    }
    print()
    
    // Show extracted magnitudes (first N/2 bins)
    print("Extracted Magnitudes (first N/2 = \(windowSize/2) bins):")
    print(repeatString("-", count: 80))
    let extractedStartBin = max(0, expectedBin - 5)
    let extractedEndBin = min(extractedMagnitudes.count, expectedBin + 6)
    for i in extractedStartBin..<extractedEndBin {
        let freq = Float(i) * frequencyResolution
        let magnitude = extractedMagnitudes[i]
        let marker = (i == expectedBin) ? " <-- EXPECTED" : ""
        print("  bin[\(i)]: \(String(format: "%6.1f", freq)) Hz, magnitude: \(String(format: "%.4f", magnitude))\(marker)")
    }
    print()
    
    // Check if peak is at expected bin
    if let maxIndex = allMagnitudes.enumerated().max(by: { $0.element < $1.element })?.offset {
        let maxFreq = Float(maxIndex) * frequencyResolution
        print("Peak magnitude found at:")
        print("  bin[\(maxIndex)]: \(String(format: "%6.1f", maxFreq)) Hz, magnitude: \(String(format: "%.4f", allMagnitudes[maxIndex]))")
        if abs(maxIndex - expectedBin) <= 1 {
            print("  ✅ Peak is at expected bin (within 1 bin tolerance)")
        } else {
            print("  ⚠️ Peak is NOT at expected bin (expected: \(expectedBin), found: \(maxIndex))")
        }
    }
    print()
    
    // Show first and last 10 bins of extracted magnitudes
    print("First 10 extracted bins (low frequencies):")
    print(repeatString("-", count: 80))
    for i in 0..<min(10, extractedMagnitudes.count) {
        let freq = Float(i) * frequencyResolution
        print("  bin[\(i)]: \(String(format: "%6.1f", freq)) Hz, magnitude: \(String(format: "%.4f", extractedMagnitudes[i]))")
    }
    print()
    
    print("Last 10 extracted bins (high frequencies):")
    print(repeatString("-", count: 80))
    let lastStart = max(0, extractedMagnitudes.count - 10)
    for i in lastStart..<extractedMagnitudes.count {
        let freq = Float(i) * frequencyResolution
        print("  bin[\(i)]: \(String(format: "%6.1f", freq)) Hz, magnitude: \(String(format: "%.4f", extractedMagnitudes[i]))")
    }
    print()
    
    // Save to file for analysis
    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let allMagFile = documentsPath.appendingPathComponent("test_fft_allMagnitudes.txt")
    let extractedFile = documentsPath.appendingPathComponent("test_fft_extractedMagnitudes.txt")
    
    var allMagContent = "Index\tFrequency(Hz)\tMagnitude\n"
    for (index, value) in allMagnitudes.enumerated() {
        let freq = Float(index) * frequencyResolution
        allMagContent += "\(index)\t\(String(format: "%.2f", freq))\t\(String(format: "%.6f", value))\n"
    }
    
    var extractedContent = "Index\tFrequency(Hz)\tMagnitude\n"
    for (index, value) in extractedMagnitudes.enumerated() {
        let freq = Float(index) * frequencyResolution
        extractedContent += "\(index)\t\(String(format: "%.2f", freq))\t\(String(format: "%.6f", value))\n"
    }
    
    do {
        try allMagContent.write(to: allMagFile, atomically: true, encoding: .utf8)
        try extractedContent.write(to: extractedFile, atomically: true, encoding: .utf8)
        print("Results saved to:")
        print("  \(allMagFile.path)")
        print("  \(extractedFile.path)")
    } catch {
        print("Failed to save results: \(error)")
    }
    
    print(repeatString("=", count: 80))
}

// Main test
print("Generating test signal...")
let testSignal = generateTestSignal(frequency: testFrequency, sampleRate: sampleRate, windowSize: windowSize)

print("Performing FFT...")
let results = performFFTTest(inputData: testSignal, windowSize: windowSize)

print("Analyzing results...")
printResults(
    allMagnitudes: results.allMagnitudes,
    extractedMagnitudes: results.extractedMagnitudes,
    realOut: results.realOut,
    imagOut: results.imagOut,
    windowSize: windowSize,
    sampleRate: sampleRate,
    testFrequency: testFrequency
)

