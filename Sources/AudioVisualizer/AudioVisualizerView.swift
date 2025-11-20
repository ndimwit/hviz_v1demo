import SwiftUI
import Charts
import ComposableArchitecture

/// Parameter type for the unified control selector
private enum ControlParameter: String, CaseIterable, Identifiable {
    case preset = "Preset"
    case buffer = "Buffer"
    case window = "Window"
    case bands = "Bands"
    case mode = "Mode"
    case rate = "Rate"
    case frames = "Frames"
    
    var id: String { rawValue }
    
    var displayName: String { rawValue }
}

/// Main view for the Audio Visualizer feature
public struct AudioVisualizerView: View {
    public let store: StoreOf<AudioVisualizerFeature>
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var selectedParameter: ControlParameter = .preset
    
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
                    
                    // Controls row: Parameter selector, Value selector, and FPS tracking
                    HStack(alignment: .top, spacing: isRegularWidth ? 16 : 10) {
                        // Vertical stack for the two pickers
                        VStack(alignment: .leading, spacing: isRegularWidth ? 8 : 6) {
                            // First dropdown: Select which parameter to control
                            Picker("Parameter", selection: $selectedParameter) {
                                ForEach(ControlParameter.allCases) { parameter in
                                    // Only show Rate and Frames if in scrolling mode
                                    if parameter == .rate || parameter == .frames {
                                        if viewStore.renderingMode == .scrolling {
                                            Text(parameter.displayName)
                                                .font(isRegularWidth ? .callout : .caption2)
                                                .tag(parameter)
                                        }
                                    } else {
                                        Text(parameter.displayName)
                                            .font(isRegularWidth ? .callout : .caption2)
                                            .tag(parameter)
                                    }
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            // Second dropdown: Show options for the selected parameter
                            Group {
                                switch selectedParameter {
                                case .preset:
                                    Picker("Visualizer Preset", selection: Binding(
                                        get: { viewStore.selectedPreset },
                                        set: { viewStore.send(.presetSelected($0)) }
                                    )) {
                                        ForEach(VisualizerPresetType.allCases) { preset in
                                            Text(preset.displayName)
                                                .font(isRegularWidth ? .callout : .caption2)
                                                .tag(preset)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    
                                case .buffer:
                                    Picker("Buffer Size", selection: Binding(
                                        get: { viewStore.bufferSize },
                                        set: { viewStore.send(.bufferSizeSelected($0)) }
                                    )) {
                                        ForEach(Constants.availableBufferSizes, id: \.self) { size in
                                            Text(formatBufferSize(size))
                                                .font(isRegularWidth ? .callout : .caption2)
                                                .tag(size)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    
                                case .window:
                                    Picker("FFT Window Size", selection: Binding(
                                        get: { viewStore.fftWindowSize },
                                        set: { viewStore.send(.fftWindowSizeSelected($0)) }
                                    )) {
                                        ForEach(Constants.availableFFTWindowSizes, id: \.self) { size in
                                            Text("\(size)")
                                                .font(isRegularWidth ? .callout : .caption2)
                                                .tag(size)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    
                                case .bands:
                                    Picker("FFT Bands", selection: Binding(
                                        get: { viewStore.fftBandQuantity },
                                        set: { viewStore.send(.fftBandQuantitySelected($0)) }
                                    )) {
                                        ForEach(Constants.availableFFTBandQuantities, id: \.self) { quantity in
                                            Text("\(quantity)")
                                                .font(isRegularWidth ? .callout : .caption2)
                                                .tag(quantity)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    
                                case .mode:
                                    Picker("Rendering Mode", selection: Binding(
                                        get: { viewStore.renderingMode },
                                        set: { viewStore.send(.renderingModeSelected($0)) }
                                    )) {
                                        ForEach(RenderingMode.allCases) { mode in
                                            Text(mode.displayName)
                                                .font(isRegularWidth ? .callout : .caption2)
                                                .tag(mode)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    
                                case .rate:
                                    if viewStore.renderingMode == .scrolling {
                                        Picker("Scrolling Rate", selection: Binding(
                                            get: { viewStore.scrollingRate },
                                            set: { viewStore.send(.scrollingRateSelected($0)) }
                                        )) {
                                            ForEach(Constants.availableScrollingRates, id: \.self) { rate in
                                                Text("\(Int(rate)) fps")
                                                    .font(isRegularWidth ? .callout : .caption2)
                                                    .tag(rate)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                    } else {
                                        // Fallback if mode changed away from scrolling
                                        Text("N/A")
                                            .font(isRegularWidth ? .callout : .caption2)
                                            .foregroundColor(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    
                                case .frames:
                                    if viewStore.renderingMode == .scrolling {
                                        if viewStore.selectedPreset == .oscilloscope {
                                            Picker("Frame Limit", selection: Binding(
                                                get: { viewStore.maxScrollingFrames },
                                                set: { viewStore.send(.maxScrollingFramesSelected($0)) }
                                            )) {
                                                ForEach(Constants.availableOscilloscopeScrollingFrameLimits, id: \.self) { limit in
                                                    Text("\(limit)")
                                                        .font(isRegularWidth ? .callout : .caption2)
                                                        .tag(limit)
                                                }
                                            }
                                            .pickerStyle(.menu)
                                        } else {
                                            Picker("Frame Limit", selection: Binding(
                                                get: { viewStore.maxScrollingFrames },
                                                set: { viewStore.send(.maxScrollingFramesSelected($0)) }
                                            )) {
                                                ForEach(Constants.availableScrollingFrameLimits, id: \.self) { limit in
                                                    Text("\(limit)")
                                                        .font(isRegularWidth ? .callout : .caption2)
                                                        .tag(limit)
                                                }
                                            }
                                            .pickerStyle(.menu)
                                        }
                                    } else {
                                        // Fallback if mode changed away from scrolling
                                        Text("N/A")
                                            .font(isRegularWidth ? .callout : .caption2)
                                            .foregroundColor(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity)
                        
                        Spacer()
                        
                        // Frame rate statistics display
                        if viewStore.isMonitoring {
                            let stats = viewStore.fpsStatistics
                            if stats.mean > 0 {
                                VStack(alignment: .trailing, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text("FPS:")
                                            .font(isRegularWidth ? .callout : .caption2)
                                            .foregroundColor(.secondary)
                                        Text(String(format: "%.1f", stats.mean))
                                            .font(isRegularWidth ? .callout.monospacedDigit() : .caption2.monospacedDigit())
                                            .foregroundColor(.primary)
                                    }
                                    HStack(spacing: 4) {
                                        Text("min:")
                                            .font(isRegularWidth ? .caption2 : .system(size: 9))
                                            .foregroundColor(.secondary)
                                        Text(String(format: "%.1f", stats.min))
                                            .font(isRegularWidth ? .caption2.monospacedDigit() : .system(size: 9).monospacedDigit())
                                            .foregroundColor(.secondary)
                                        Text("max:")
                                            .font(isRegularWidth ? .caption2 : .system(size: 9))
                                            .foregroundColor(.secondary)
                                        Text(String(format: "%.1f", stats.max))
                                            .font(isRegularWidth ? .caption2.monospacedDigit() : .system(size: 9).monospacedDigit())
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
                    .onChange(of: viewStore.renderingMode) { oldValue, newValue in
                        // If mode changed away from scrolling and we're on rate/frames, switch to preset
                        if newValue != .scrolling && (selectedParameter == .rate || selectedParameter == .frames) {
                            selectedParameter = .preset
                        }
                    }
                    
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

