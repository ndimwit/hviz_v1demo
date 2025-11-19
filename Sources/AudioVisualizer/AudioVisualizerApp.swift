import SwiftUI
import ComposableArchitecture

/// App configuration helper
/// 
/// Note: This is a library package. To create an app, create an iOS app target
/// and use this in your app's @main entry point:
///
/// ```swift
/// @main
/// struct MyApp: App {
///     var body: some Scene {
///         WindowGroup {
///             AudioVisualizerView(
///                 store: Store(initialState: AudioVisualizerFeature.State()) {
///                     AudioVisualizerFeature()
///                 }
///             )
///         }
///     }
/// }
/// ```
public struct AudioVisualizerAppConfig {
    public static func createView() -> some View {
        AudioVisualizerView(
            store: Store(initialState: AudioVisualizerFeature.State()) {
                AudioVisualizerFeature()
            }
        )
    }
}

