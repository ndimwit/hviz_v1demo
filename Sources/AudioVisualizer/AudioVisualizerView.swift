import SwiftUI
import Charts
import ComposableArchitecture

/// Main view for the Audio Visualizer feature
public struct AudioVisualizerView: View {
    public let store: StoreOf<AudioVisualizerFeature>
    
    public init(store: StoreOf<AudioVisualizerFeature>) {
        self.store = store
    }
    
    /// Gradient for the chart visualization
    private let chartGradient = LinearGradient(
        gradient: Gradient(colors: [.blue, .purple, .red]),
        startPoint: .leading,
        endPoint: .trailing
    )
    
    public var body: some View {
        WithViewStore(self.store, observe: { $0 }) { viewStore in
            VStack(spacing: 20) {
                // Title
                Text("Live Audio Waveform")
                    .font(.title2.bold())
                    .padding(.top, 20)
                
                // Error message
                if let errorMessage = viewStore.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                        .onTapGesture {
                            viewStore.send(.clearError)
                        }
                }
                
                // Chart visualization
                Chart(viewStore.downsampledMagnitudes.indices, id: \.self) { index in
                    LineMark(
                        x: .value("Frequency", index * Constants.downsampleFactor),
                        y: .value("Magnitude", viewStore.downsampledMagnitudes[index])
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                    .foregroundStyle(chartGradient)
                }
                .chartYScale(domain: 0...viewStore.maxMagnitude)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 300)
                .padding()
                .animation(.easeOut, value: viewStore.downsampledMagnitudes)
                
                Spacer()
                
                // Start/Stop button
                Button(action: {
                    viewStore.send(.toggleMonitoringTapped)
                }) {
                    Label(
                        viewStore.isMonitoring ? "Stop" : "Start",
                        systemImage: viewStore.isMonitoring ? "stop.fill" : "waveform"
                    )
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewStore.isMonitoring ? Color.red : Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 20)
            .padding()
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

