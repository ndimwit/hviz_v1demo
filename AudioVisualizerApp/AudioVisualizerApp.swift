import SwiftUI
import AudioVisualizer
import ComposableArchitecture
#if targetEnvironment(macCatalyst)
import UIKit
#endif

@main
struct AudioVisualizerApp: App {
    var body: some Scene {
        WindowGroup {
            AudioVisualizerView(
                store: Store(initialState: AudioVisualizerFeature.State()) {
                    AudioVisualizerFeature()
                }
            )
            #if targetEnvironment(macCatalyst)
            .background(WindowSizeSetter())
            #endif
        }
        #if targetEnvironment(macCatalyst)
        .defaultSize(width: 1024, height: 768)
        #endif
    }
}
    
#if targetEnvironment(macCatalyst)
/// View that sets window size on Mac Catalyst
private struct WindowSizeSetter: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        
        // Use a small delay to ensure window scene is available
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            setWindowSize()
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
    
    private func setWindowSize() {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            return
        }
        
        let preferredSize = CGSize(width: 1024, height: 768)
        
        // Set window frame directly
        if let window = windowScene.windows.first {
            var frame = window.frame
            // Only resize if the window is significantly different from desired size
            // This allows user resizing while still applying default on first launch
            if abs(frame.size.width - preferredSize.width) > 50 || 
               abs(frame.size.height - preferredSize.height) > 50 {
                // Center the window
                if let screen = windowScene.screen {
                    frame.origin.x = max(0, (screen.bounds.width - preferredSize.width) / 2)
                    frame.origin.y = max(0, (screen.bounds.height - preferredSize.height) / 2)
                }
                frame.size = preferredSize
                window.frame = frame
            }
        }
    }
}
#endif

