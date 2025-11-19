import SwiftUI
import AudioVisualizer
import ComposableArchitecture

@main
struct AudioVisualizerApp: App {
    var body: some Scene {
        WindowGroup {
            AudioVisualizerView(
                store: Store(initialState: AudioVisualizerFeature.State()) {
                    AudioVisualizerFeature()
                }
            )
        }
    }
}

