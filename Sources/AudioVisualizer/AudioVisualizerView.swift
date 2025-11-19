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
                    
                    // Preset selector dropdown
                    HStack {
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
                        .frame(maxWidth: isRegularWidth ? 200 : 150)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, isRegularWidth ? 10 : 5)
                    
                    // Visualizer preset view
                    let preset = viewStore.selectedPreset.preset
                    AnyView(
                        preset.makeView(
                            magnitudes: viewStore.fftMagnitudes,
                            downsampledMagnitudes: viewStore.downsampledMagnitudes,
                            maxMagnitude: viewStore.maxMagnitude,
                            isRegularWidth: isRegularWidth,
                            chartHeight: chartHeight(for: geometry),
                            horizontalPadding: horizontalPadding
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

