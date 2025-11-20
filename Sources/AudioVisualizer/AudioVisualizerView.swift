import SwiftUI
import Charts
import ComposableArchitecture

/// Main view for the Audio Visualizer feature
public struct AudioVisualizerView: View {
    public let store: StoreOf<AudioVisualizerFeature>
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    
    public init(store: StoreOf<AudioVisualizerFeature>) {
        self.store = store
    }
    
    /// Determines if the device is an iPad or Mac
    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }
    
    /// Determines if the device is in landscape orientation (iPad/Mac)
    private var isRegularHeight: Bool {
        verticalSizeClass == .regular
    }
    
    /// Adaptive chart height based on available space
    private func chartHeight(for geometry: GeometryProxy) -> CGFloat {
        let availableHeight = geometry.size.height
        let isLandscape = geometry.size.width > geometry.size.height
        
        #if targetEnvironment(macCatalyst)
        // Mac Catalyst: No maximum constraints, scale freely with window size
        if isLandscape {
            return availableHeight * 0.8
        } else {
            return availableHeight * 0.75
        }
        #else
        // iOS/iPad: Keep maximum constraints for device-specific layouts
        if isRegularWidth && isRegularHeight {
            // iPad portrait - use most of the screen
            return min(availableHeight * 0.7, 600)
        } else if isRegularWidth {
            // iPad landscape - use most of the screen
            return min(availableHeight * 0.75, 500)
        } else if isLandscape {
            // iPhone landscape - use most of the screen
            return min(availableHeight * 0.7, 350)
        } else {
            // iPhone portrait - use most of the screen
            return min(availableHeight * 0.65, 500)
        }
        #endif
    }
    
    /// Adaptive spacing between elements
    private var verticalSpacing: CGFloat {
        if isRegularWidth {
            return 30
        } else {
            return 20
        }
    }
    
    /// Adaptive horizontal padding
    private var horizontalPadding: CGFloat {
        if isRegularWidth {
            return 40
        } else {
            return 20
        }
    }
    
    /// Format buffer size for display
    private func formatBufferSize(_ size: Int) -> String {
        return "\(size)"
    }
    
    public var body: some View {
        GeometryReader { geometry in
            WithViewStore(self.store, observe: { $0 }) { viewStore in
                VStack(spacing: verticalSpacing) {
                    // Error message
                    if let errorMessage = viewStore.errorMessage {
                        Text(errorMessage)
                            .font(isRegularWidth ? .body : .caption)
                            .foregroundColor(.red)
                            .padding(.horizontal, horizontalPadding)
                            .multilineTextAlignment(.center)
                            .onTapGesture {
                                viewStore.send(.clearError)
                            }
                            .padding(.top, isRegularWidth ? 20 : 10)
                    }
                    
                    // Controls row: Preset selector, Buffer size, FFT bands, and Frame rate
                    HStack(spacing: isRegularWidth ? 16 : 10) {
                        // Preset selector
                        HStack(spacing: 4) {
                            Text("Preset:")
                                .font(isRegularWidth ? .body : .caption)
                                .foregroundColor(.secondary)
                            
                            Picker("Visualizer Preset", selection: Binding(
                                get: { viewStore.selectedPreset },
                                set: { viewStore.send(.presetSelected($0)) }
                            )) {
                                ForEach(VisualizerPresetType.allCases) { preset in
                                    Text(preset.displayName)
                                        .tag(preset)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: isRegularWidth ? 180 : 130)
                        }
                        
                        // Buffer size selector
                        HStack(spacing: 4) {
                            Text("Buffer:")
                                .font(isRegularWidth ? .body : .caption)
                                .foregroundColor(.secondary)
                            
                            Picker("Buffer Size", selection: Binding(
                                get: { viewStore.bufferSize },
                                set: { viewStore.send(.bufferSizeSelected($0)) }
                            )) {
                                ForEach(Constants.availableBufferSizes, id: \.self) { size in
                                    Text(formatBufferSize(size))
                                        .tag(size)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: isRegularWidth ? 100 : 80)
                        }
                        
                        // FFT window size selector
                        HStack(spacing: 4) {
                            Text("Window:")
                                .font(isRegularWidth ? .body : .caption)
                                .foregroundColor(.secondary)
                            
                            Picker("FFT Window Size", selection: Binding(
                                get: { viewStore.fftWindowSize },
                                set: { viewStore.send(.fftWindowSizeSelected($0)) }
                            )) {
                                ForEach(Constants.availableFFTWindowSizes, id: \.self) { size in
                                    Text("\(size)")
                                        .tag(size)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: isRegularWidth ? 100 : 80)
                        }
                        
                        // FFT band quantity selector
                        HStack(spacing: 4) {
                            Text("Bands:")
                                .font(isRegularWidth ? .body : .caption)
                                .foregroundColor(.secondary)
                            
                            Picker("FFT Bands", selection: Binding(
                                get: { viewStore.fftBandQuantity },
                                set: { viewStore.send(.fftBandQuantitySelected($0)) }
                            )) {
                                ForEach(Constants.availableFFTBandQuantities, id: \.self) { quantity in
                                    Text("\(quantity)")
                                        .tag(quantity)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: isRegularWidth ? 100 : 80)
                        }
                        
                        // Rendering mode selector
                        HStack(spacing: 4) {
                            Text("Mode:")
                                .font(isRegularWidth ? .body : .caption)
                                .foregroundColor(.secondary)
                            
                            Picker("Rendering Mode", selection: Binding(
                                get: { viewStore.renderingMode },
                                set: { viewStore.send(.renderingModeSelected($0)) }
                            )) {
                                ForEach(RenderingMode.allCases) { mode in
                                    Text(mode.displayName)
                                        .tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: isRegularWidth ? 100 : 80)
                        }
                        
                        // Scrolling rate selector (only visible in scrolling mode)
                        if viewStore.renderingMode == .scrolling {
                            HStack(spacing: 4) {
                                Text("Rate:")
                                    .font(isRegularWidth ? .body : .caption)
                                    .foregroundColor(.secondary)
                                
                                Picker("Scrolling Rate", selection: Binding(
                                    get: { viewStore.scrollingRate },
                                    set: { viewStore.send(.scrollingRateSelected($0)) }
                                )) {
                                    ForEach(Constants.availableScrollingRates, id: \.self) { rate in
                                        Text("\(Int(rate)) fps")
                                            .tag(rate)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: isRegularWidth ? 90 : 70)
                            }
                            
                            // Frame limit selector (only visible in scrolling mode)
                            // For Oscilloscope, use larger frame limits (up to 32k)
                            // For other presets, use standard frame limits
                            HStack(spacing: 4) {
                                Text("Frames:")
                                    .font(isRegularWidth ? .body : .caption)
                                    .foregroundColor(.secondary)
                                
                                if viewStore.selectedPreset == .oscilloscope {
                                    Picker("Frame Limit", selection: Binding(
                                        get: { viewStore.maxScrollingFrames },
                                        set: { viewStore.send(.maxScrollingFramesSelected($0)) }
                                    )) {
                                        ForEach(Constants.availableOscilloscopeScrollingFrameLimits, id: \.self) { limit in
                                            Text("\(limit)")
                                                .tag(limit)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(maxWidth: isRegularWidth ? 100 : 80)
                                } else {
                                    Picker("Frame Limit", selection: Binding(
                                        get: { viewStore.maxScrollingFrames },
                                        set: { viewStore.send(.maxScrollingFramesSelected($0)) }
                                    )) {
                                        ForEach(Constants.availableScrollingFrameLimits, id: \.self) { limit in
                                            Text("\(limit)")
                                                .tag(limit)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(maxWidth: isRegularWidth ? 80 : 60)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        // Frame rate statistics display
                        if viewStore.isMonitoring {
                            let stats = viewStore.fpsStatistics
                            if stats.mean > 0 {
                                VStack(alignment: .trailing, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text("FPS:")
                                            .font(isRegularWidth ? .body : .caption)
                                            .foregroundColor(.secondary)
                                        Text(String(format: "%.1f", stats.mean))
                                            .font(isRegularWidth ? .body.monospacedDigit() : .caption.monospacedDigit())
                                            .foregroundColor(.primary)
                                    }
                                    HStack(spacing: 4) {
                                        Text("min:")
                                            .font(isRegularWidth ? .caption2 : .caption2)
                                            .foregroundColor(.secondary)
                                        Text(String(format: "%.1f", stats.min))
                                            .font(isRegularWidth ? .caption2.monospacedDigit() : .caption2.monospacedDigit())
                                            .foregroundColor(.secondary)
                                        Text("max:")
                                            .font(isRegularWidth ? .caption2 : .caption2)
                                            .foregroundColor(.secondary)
                                        Text(String(format: "%.1f", stats.max))
                                            .font(isRegularWidth ? .caption2.monospacedDigit() : .caption2.monospacedDigit())
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.horizontal, isRegularWidth ? 8 : 6)
                                .padding(.vertical, isRegularWidth ? 4 : 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.secondary.opacity(0.1))
                                )
                            }
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, isRegularWidth ? 10 : 5)
                    
                    // Visualizer preset view
                    let preset = viewStore.selectedPreset.preset
                    let availableWidth = geometry.size.width - (horizontalPadding * 2)
                    // Use displayMagnitudes (interpolated) instead of raw fftMagnitudes for smoother visualization
                    AnyView(
                        preset.makeView(
                            magnitudes: viewStore.displayMagnitudes.isEmpty ? viewStore.fftMagnitudes : viewStore.displayMagnitudes,
                            rawAudioSamples: viewStore.rawAudioSamples,
                            maxMagnitude: viewStore.maxMagnitude,
                            renderingMode: viewStore.renderingMode,
                            scrollingData: viewStore.scrollingData,
                            continuousWaveformData: viewStore.continuousWaveformData,
                            isRegularWidth: isRegularWidth,
                            chartHeight: chartHeight(for: geometry),
                            availableWidth: availableWidth,
                            horizontalPadding: horizontalPadding,
                            leftChannelSamples: viewStore.leftChannelSamples.isEmpty ? nil : viewStore.leftChannelSamples,
                            rightChannelSamples: viewStore.rightChannelSamples.isEmpty ? nil : viewStore.rightChannelSamples
                        )
                    )
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    viewStore.send(.onAppear)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AudioVisualizerView(
        store: Store(initialState: AudioVisualizerFeature.State()) {
            AudioVisualizerFeature()
        }
    )
}

