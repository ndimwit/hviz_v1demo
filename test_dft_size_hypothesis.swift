#!/usr/bin/env swift

// Test to verify if vDSP_DFT_zrop_CreateSetup expects N or N/2 as the length parameter

import Foundation
import Accelerate

let testWindowSize = 512
let testFrequency: Float = 1000.0
let sampleRate: Float = 44100.0

// Generate test signal
func generateTestSignal(frequency: Float, sampleRate: Float, windowSize: Int) -> [Float] {
    var signal: [Float] = []
    signal.reserveCapacity(windowSize)
    for i in 0..<windowSize {
        let t = Float(i) / sampleRate
        signal.append(sin(2.0 * Float.pi * frequency * t))
    }
    return signal
}

func repeatString(_ str: String, count: Int) -> String {
    return String(repeating: str, count: count)
}

print("Testing DFT setup with different size parameters...")
print(repeatString("=", count: 80))

let testSignal = generateTestSignal(frequency: testFrequency, sampleRate: sampleRate, windowSize: testWindowSize)

// Test 1: Create setup with N (512)
print("\nTest 1: Creating setup with N = \(testWindowSize)")
if let setup1 = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(testWindowSize), vDSP_DFT_Direction.FORWARD) {
    defer { vDSP_DFT_DestroySetup(setup1) }
    
    var realOut = [Float](repeating: 0, count: testWindowSize)
    var imagOut = [Float](repeating: 0, count: testWindowSize)
    var inputImag = [Float](repeating: 0, count: testWindowSize)
    
    testSignal.withUnsafeBufferPointer { inputPtr in
        inputImag.withUnsafeBufferPointer { inputImagPtr in
            realOut.withUnsafeMutableBufferPointer { realOutPtr in
                imagOut.withUnsafeMutableBufferPointer { imagOutPtr in
                    vDSP_DFT_Execute(setup1, inputPtr.baseAddress!, inputImagPtr.baseAddress!, realOutPtr.baseAddress!, imagOutPtr.baseAddress!)
                }
            }
        }
    }
    
    var complex = DSPSplitComplex(realp: realOut.withUnsafeMutableBufferPointer { $0.baseAddress! }, imagp: imagOut.withUnsafeMutableBufferPointer { $0.baseAddress! })
    var magnitudes = [Float](repeating: 0, count: testWindowSize)
    magnitudes.withUnsafeMutableBufferPointer { magPtr in
        vDSP_zvabs(&complex, 1, magPtr.baseAddress!, 1, vDSP_Length(testWindowSize))
    }
    
    let expectedBin = Int(testFrequency / (sampleRate / Float(testWindowSize)))
    print("  Setup created successfully with N=\(testWindowSize)")
    print("  Output array size: \(magnitudes.count)")
    print("  Expected peak at bin: \(expectedBin)")
    if let maxIndex = magnitudes.enumerated().max(by: { $0.element < $1.element })?.offset {
        let maxFreq = Float(maxIndex) * sampleRate / Float(testWindowSize)
        print("  Actual peak at bin: \(maxIndex) (frequency: \(maxFreq) Hz)")
    }
    print("  First 5 bins: \(Array(magnitudes.prefix(5)))")
    print("  Bins around expected: \(Array(magnitudes[max(0, expectedBin-2)...min(testWindowSize-1, expectedBin+2)]))")
} else {
    print("  ❌ Failed to create setup with N=\(testWindowSize)")
}

// Test 2: Create setup with N/2 (256)
print("\nTest 2: Creating setup with N/2 = \(testWindowSize/2)")
if let setup2 = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(testWindowSize/2), vDSP_DFT_Direction.FORWARD) {
    defer { vDSP_DFT_DestroySetup(setup2) }
    
    // Use only first N/2 samples
    let halfSignal = Array(testSignal.prefix(testWindowSize/2))
    
    var realOut = [Float](repeating: 0, count: testWindowSize/2)
    var imagOut = [Float](repeating: 0, count: testWindowSize/2)
    var inputImag = [Float](repeating: 0, count: testWindowSize/2)
    
    halfSignal.withUnsafeBufferPointer { inputPtr in
        inputImag.withUnsafeBufferPointer { inputImagPtr in
            realOut.withUnsafeMutableBufferPointer { realOutPtr in
                imagOut.withUnsafeMutableBufferPointer { imagOutPtr in
                    vDSP_DFT_Execute(setup2, inputPtr.baseAddress!, inputImagPtr.baseAddress!, realOutPtr.baseAddress!, imagOutPtr.baseAddress!)
                }
            }
        }
    }
    
    var complex = DSPSplitComplex(realp: realOut.withUnsafeMutableBufferPointer { $0.baseAddress! }, imagp: imagOut.withUnsafeMutableBufferPointer { $0.baseAddress! })
    var magnitudes = [Float](repeating: 0, count: testWindowSize/2)
    magnitudes.withUnsafeMutableBufferPointer { magPtr in
        vDSP_zvabs(&complex, 1, magPtr.baseAddress!, 1, vDSP_Length(testWindowSize/2))
    }
    
    let expectedBin = Int(testFrequency / (sampleRate / Float(testWindowSize/2)))
    print("  Setup created successfully with N/2=\(testWindowSize/2)")
    print("  Output array size: \(magnitudes.count)")
    print("  Expected peak at bin: \(expectedBin)")
    if let maxIndex = magnitudes.enumerated().max(by: { $0.element < $1.element })?.offset {
        let maxFreq = Float(maxIndex) * sampleRate / Float(testWindowSize/2)
        print("  Actual peak at bin: \(maxIndex) (frequency: \(maxFreq) Hz)")
    }
    print("  First 5 bins: \(Array(magnitudes.prefix(5)))")
    print("  Bins around expected: \(Array(magnitudes[max(0, expectedBin-2)...min(testWindowSize/2-1, expectedBin+2)]))")
} else {
    print("  ❌ Failed to create setup with N/2=\(testWindowSize/2)")
}

print("\n" + repeatString("=", count: 80))

