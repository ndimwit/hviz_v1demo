import SwiftUI
import UIKit

@main
struct ScreenTestApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Force full screen by removing safe area insets at window level
                    setupFullScreenWindow()
                }
        }
    }
    
    private func setupFullScreenWindow() {
        #if !targetEnvironment(macCatalyst)
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first else {
                return
            }
            
            // Set window background to clear
            window.backgroundColor = .clear
            
            // Find root view controller and remove safe area insets
            var rootVC = window.rootViewController
            while let presented = rootVC?.presentedViewController {
                rootVC = presented
            }
            
            if let rootVC = rootVC {
                // Remove all safe area insets
                rootVC.additionalSafeAreaInsets = .zero
                
                // Ensure view extends to full screen
                rootVC.view.frame = window.bounds
                rootVC.view.backgroundColor = .clear
            }
        }
        #endif
    }
}

struct ContentView: View {
    @State private var testMethod: TestMethod = .ignoresSafeArea
    
    enum TestMethod: String, CaseIterable {
        case ignoresSafeArea = "ignoresSafeArea"
        case fullScreenCover = "fullScreenCover"
        case contentMargins = "contentMargins"
        case uiViewController = "UIViewController"
        case geometryReader = "GeometryReader"
    }
    
    var body: some View {
        VStack {
            Picker("Test Method", selection: $testMethod) {
                ForEach(TestMethod.allCases, id: \.self) { method in
                    Text(method.rawValue).tag(method)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            switch testMethod {
            case .ignoresSafeArea:
                IgnoresSafeAreaTest()
            case .fullScreenCover:
                FullScreenCoverTest()
            case .contentMargins:
                ContentMarginsTest()
            case .uiViewController:
                UIViewControllerTest()
            case .geometryReader:
                GeometryReaderTest()
            }
        }
    }
}

// MARK: - Test 1: ignoresSafeArea
struct IgnoresSafeAreaTest: View {
    var body: some View {
        ZStack {
            // Background that should extend to edges
            Color.blue
                .ignoresSafeArea(.all, edges: .all)
            
            VStack {
                Text("ignoresSafeArea Test")
                    .font(.title)
                    .foregroundColor(.white)
                Text("Background should extend to top and bottom")
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
            }
            .padding()
        }
    }
}

// MARK: - Test 2: fullScreenCover
struct FullScreenCoverTest: View {
    @State private var showFullScreen = true
    
    var body: some View {
        Color.clear
            .fullScreenCover(isPresented: $showFullScreen) {
                ZStack {
                    Color.green
                        .ignoresSafeArea(.all, edges: .all)
                    
                    VStack {
                        Text("fullScreenCover Test")
                            .font(.title)
                            .foregroundColor(.white)
                        Text("This view is presented as a full screen cover")
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                    }
                    .padding()
                }
            }
    }
}

// MARK: - Test 3: contentMargins (iOS 17+)
struct ContentMarginsTest: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.purple
                    .ignoresSafeArea(.all, edges: .all)
                
                VStack {
                    Text("contentMargins Test")
                        .font(.title)
                        .foregroundColor(.white)
                    Text("Note: contentMargins API may vary")
                        .foregroundColor(.white.opacity(0.8))
                    Text("Using ignoresSafeArea instead")
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                }
                .padding()
            }
        }
    }
}

// MARK: - Test 4: UIViewController approach with UIHostingController
struct UIViewControllerTest: View {
    var body: some View {
        FullScreenHostingControllerWrapper()
    }
}

struct FullScreenHostingControllerWrapper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let hostingController = UIHostingController(rootView: FullScreenTestView())
        
        // Configure for full screen
        hostingController.view.backgroundColor = .orange
        hostingController.additionalSafeAreaInsets = .zero
        
        // Remove safe area insets
        DispatchQueue.main.async {
            if let window = hostingController.view.window {
                hostingController.view.frame = window.bounds
            }
        }
        
        return hostingController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Update if needed
        uiViewController.additionalSafeAreaInsets = .zero
    }
}

struct FullScreenTestView: View {
    var body: some View {
        ZStack {
            Color.orange
                .ignoresSafeArea(.all, edges: .all)
            
            VStack {
                Text("UIHostingController Test")
                    .font(.title)
                    .foregroundColor(.white)
                Text("Using UIHostingController with zero safe area insets")
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
            }
            .padding()
        }
    }
}


// MARK: - Test 5: GeometryReader with explicit frame
struct GeometryReaderTest: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.red
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
                    )
                    .offset(y: -geometry.safeAreaInsets.top)
                
                VStack {
                    Text("GeometryReader Test")
                        .font(.title)
                        .foregroundColor(.white)
                    Text("Using explicit frame with safe area compensation")
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                }
                .padding()
            }
        }
        .ignoresSafeArea(.all, edges: .all)
    }
}

// MARK: - Preview
#Preview {
    ContentView()
}

