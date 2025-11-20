import SwiftUI

/// Stereo field analyzer preset (shows stereo imaging/panning)
public struct StereoFieldPreset: VisualizerPreset {
    public let id = "stereo_field"
    public let displayName = "Stereo Field"
    
    @ViewBuilder
    public func makeView(
        magnitudes: [Float],
        rawAudioSamples: [Float],
        maxMagnitude: Float,
        renderingMode: RenderingMode,
        scrollingData: [[Float]]?,
        continuousWaveformData: [Float]?,
        isRegularWidth: Bool,
        chartHeight: CGFloat,
        availableWidth: CGFloat,
        horizontalPadding: CGFloat,
        leftChannelSamples: [Float]?,
        rightChannelSamples: [Float]?
    ) -> any View {
        GeometryReader { geometry in
            let chartWidth = geometry.size.width - (horizontalPadding * 2)
            let centerX = chartWidth / 2.0
            let centerY = chartHeight / 2.0
            
            if renderingMode == .scrolling, let scrollingFrames = scrollingData, !scrollingFrames.isEmpty {
                // Scrolling mode: display as horizontal scrolling stereo field
                let frameWidth = chartWidth / CGFloat(max(scrollingFrames.count, 1))
                
                ZStack {
                    HStack(spacing: 0) {
                        ForEach(scrollingFrames.indices, id: \.self) { frameIndex in
                            let frame = scrollingFrames[frameIndex]
                            let downsampledFrame = downsampleMagnitudes(frame, to: Int(chartHeight))
                            
                            // Draw vertical slice showing stereo field
                            VStack(spacing: 0) {
                                ForEach(downsampledFrame.indices, id: \.self) { bandIndex in
                                    let magnitude = downsampledFrame[bandIndex]
                                    let normalizedMagnitude = CGFloat(magnitude / maxMagnitude)
                                    
                                    // Simulate stereo width based on frequency
                                    let frequencyIndex = Double(bandIndex) / Double(max(downsampledFrame.count - 1, 1))
                                    let width = frameWidth * (0.3 + 0.7 * (1.0 - frequencyIndex))
                                    
                                    // Color based on frequency
                                    let color = Color(
                                        hue: Double(bandIndex) / Double(downsampledFrame.count) * 0.7,
                                        saturation: 0.8,
                                        brightness: 0.8
                                    )
                                    
                                    Rectangle()
                                        .fill(color.opacity(0.6))
                                        .frame(width: width * normalizedMagnitude, height: chartHeight / CGFloat(downsampledFrame.count))
                                }
                            }
                            .frame(width: frameWidth)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, horizontalPadding)
                    
                    // Labels
                    VStack {
                        HStack {
                            Text("L")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("C")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("R")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, horizontalPadding)
                        Spacer()
                    }
                }
            } else {
                // Chunk mode: stereo field display using actual left/right channels
                makeStereoFieldChunkView(
                    chartWidth: chartWidth,
                    centerX: centerX,
                    centerY: centerY,
                    chartHeight: chartHeight,
                    horizontalPadding: horizontalPadding,
                    maxMagnitude: maxMagnitude,
                    magnitudes: magnitudes,
                    leftChannelSamples: leftChannelSamples,
                    rightChannelSamples: rightChannelSamples
                )
            }
        }
        .frame(height: chartHeight)
    }
    
    /// Calculate stereo field data from left and right channels
    private func calculateStereoFieldData(
        leftSamples: [Float],
        rightSamples: [Float],
        chartWidth: CGFloat,
        maxMagnitude: Float
    ) -> [(pan: CGFloat, width: CGFloat, magnitude: CGFloat)] {
        let targetPointCount = max(Int(chartWidth), min(leftSamples.count, 512))
        let downsampledLeft = downsampleMagnitudes(leftSamples, to: targetPointCount)
        let downsampledRight = downsampleMagnitudes(rightSamples, to: targetPointCount)
        
        return zip(downsampledLeft, downsampledRight).map { left, right in
            let leftMag = abs(left)
            let rightMag = abs(right)
            let sum = leftMag + rightMag
            // Calculate pan: rightMag - leftMag so that:
            // - Positive pan (rightMag > leftMag) = panned RIGHT
            // - Negative pan (leftMag > rightMag) = panned LEFT
            let diff = rightMag - leftMag
            
            // Panning: -1.0 (fully left) to 1.0 (fully right), 0.0 = center
            let pan = sum > 0.001 ? CGFloat(diff / sum) : 0.0
            
            // Stereo width: 0.0 (mono) to 1.0 (wide stereo)
            let correlation = sum > 0.001 ? 1.0 - abs(diff / sum) : 0.0
            let width = CGFloat(correlation)
            
            // Overall magnitude for visualization
            let magnitude = CGFloat(max(leftMag, rightMag))
            
            return (pan: pan, width: width, magnitude: magnitude)
        }
    }
    
    /// Create stereo field chunk view
    private func makeStereoFieldChunkView(
        chartWidth: CGFloat,
        centerX: CGFloat,
        centerY: CGFloat,
        chartHeight: CGFloat,
        horizontalPadding: CGFloat,
        maxMagnitude: Float,
        magnitudes: [Float],
        leftChannelSamples: [Float]?,
        rightChannelSamples: [Float]?
    ) -> some View {
        // Calculate stereo field information from left and right channels
        let stereoData: [(pan: CGFloat, width: CGFloat, magnitude: CGFloat)]
        let effectiveMaxMagnitude: CGFloat
        
        if let leftSamples = leftChannelSamples, let rightSamples = rightChannelSamples,
           !leftSamples.isEmpty && !rightSamples.isEmpty && leftSamples.count == rightSamples.count {
            let data = calculateStereoFieldData(
                leftSamples: leftSamples,
                rightSamples: rightSamples,
                chartWidth: chartWidth,
                maxMagnitude: maxMagnitude
            )
            // Calculate max magnitude from the stereo data itself for proper normalization
            let maxMag = data.map { $0.magnitude }.max() ?? 1.0
            stereoData = data
            effectiveMaxMagnitude = max(maxMag, 0.001)
        } else {
            // Fallback: use magnitudes if stereo data not available
            // Create a simple visualization showing magnitude distribution
            let targetPointCount = max(Int(chartWidth / 4), min(magnitudes.count, 128))
            let downsampledMagnitudes = downsampleMagnitudes(magnitudes, to: targetPointCount)
            let maxMag = max(downsampledMagnitudes.max() ?? 1.0, maxMagnitude, 0.001)
            stereoData = downsampledMagnitudes.map { mag in
                let normalizedMag = CGFloat(mag / maxMag)
                // Center all bars when no stereo data available
                return (pan: 0.0, width: 0.5, magnitude: normalizedMag)
            }
            effectiveMaxMagnitude = CGFloat(maxMag)
        }
        
        return ZStack {
            // Center line
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 1)
                .position(x: centerX + horizontalPadding, y: centerY)
            
            if !stereoData.isEmpty {
                ForEach(0..<stereoData.count, id: \.self) { index in
                    let data = stereoData[index]
                    // Normalize using the max magnitude from stereo data itself
                    let normalizedMagnitude = min(data.magnitude / effectiveMaxMagnitude, 1.0)
                    
                    // Calculate bar dimensions
                    // Each frequency band gets a horizontal row
                    let barRowHeight = chartHeight / CGFloat(stereoData.count)
                    let yPosition = centerY - chartHeight / 2 + CGFloat(index) * barRowHeight + barRowHeight / 2
                    let centerXPos = centerX + horizontalPadding
                    
                    // Maximum bar length (half the chart width, leaving some margin)
                    let maxBarLength = chartWidth / 2.0 * 0.95
                    
                    // Bar length should be primarily based on magnitude
                    // Pan amount determines how far from center, but we always show something if there's magnitude
                    let panAmount = abs(data.pan)
                    
                    // Base bar length on magnitude (this ensures bars are visible)
                    // Pan amount scales how far it extends, but we ensure minimum visibility
                    let baseLength = maxBarLength * normalizedMagnitude
                    
                    // Scale by pan amount, but ensure minimum length even for centered audio
                    // If pan is 0 (mono), show a small centered bar
                    // If pan is non-zero, extend proportionally
                    let barLength: CGFloat = {
                        if panAmount < 0.01 {
                            // Center/mono - show small centered bar
                            return max(baseLength * 0.3, 5.0)
                        } else {
                            // Panned - extend based on pan amount
                            return max(baseLength * (0.5 + panAmount * 0.5), baseLength * 0.2, 3.0)
                        }
                    }()
                    
                    let finalBarLength = barLength
                    
                    // Bar height (vertical thickness) - represents the frequency band row
                    // Use most of the row height, with small gaps between bands
                    let barHeight = barRowHeight * 0.85
                    
                    // Color based on panning: blue for left, red for right, purple for center
                    let hue = 0.7 + (data.pan * 0.3) // 0.7 (blue) to 1.0 (red)
                    let color = Color(hue: Double(hue), saturation: 0.8, brightness: 0.8)
                    
                    // Draw bar extending from center line if there's any magnitude
                    // Lower threshold to ensure more bars are visible
                    if normalizedMagnitude > 0.0001 || data.magnitude > 0.0001 {
                        if data.pan < -0.001 {
                            // Bar extends LEFT from center line
                            // Position: start at center, extend leftward
                            Rectangle()
                                .fill(color.opacity(0.8))
                                .frame(width: finalBarLength, height: barHeight)
                                .position(
                                    x: centerXPos - finalBarLength / 2.0, // Center of bar is left of center line
                                    y: yPosition
                                )
                        } else if data.pan > 0.001 {
                            // Bar extends RIGHT from center line
                            // Position: start at center, extend rightward
                            Rectangle()
                                .fill(color.opacity(0.8))
                                .frame(width: finalBarLength, height: barHeight)
                                .position(
                                    x: centerXPos + finalBarLength / 2.0, // Center of bar is right of center line
                                    y: yPosition
                                )
                        } else {
                            // Center (mono) - draw small centered bar
                            let centerBarWidth = max(finalBarLength * 0.5, 3.0)
                            Rectangle()
                                .fill(color.opacity(0.8))
                                .frame(width: centerBarWidth, height: barHeight)
                                .position(x: centerXPos, y: yPosition)
                        }
                    }
                }
            }
            
            // Labels
            VStack {
                HStack {
                    Text("L")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("C")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("R")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, horizontalPadding)
                Spacer()
            }
        }
    }
    
    /// Downsample magnitudes to fit the target number of points
    private func downsampleMagnitudes(_ magnitudes: [Float], to targetCount: Int) -> [Float] {
        guard !magnitudes.isEmpty && targetCount > 0 else {
            return magnitudes
        }
        
        if magnitudes.count <= targetCount {
            return magnitudes
        }
        
        // Use linear interpolation to downsample
        var result = [Float]()
        let step = Double(magnitudes.count - 1) / Double(targetCount - 1)
        
        for i in 0..<targetCount {
            let position = Double(i) * step
            let lowerIndex = Int(position)
            let upperIndex = min(lowerIndex + 1, magnitudes.count - 1)
            let fraction = position - Double(lowerIndex)
            
            let interpolated = Float(Double(magnitudes[lowerIndex]) * (1.0 - fraction) + Double(magnitudes[upperIndex]) * fraction)
            result.append(interpolated)
        }
        
        return result
    }
}

