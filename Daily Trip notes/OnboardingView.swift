import SwiftUI
import Photos

struct OnboardingView: View {
    @Binding var showOnboarding: Bool
    @State private var currentPage = 0
    @State private var photoPermissionGranted = false
    @State private var isRequestingPermission = false
    
    let onboardingPages = [
        OnboardingPage(
            title: "Welcome to Daily Trip Notes",
            subtitle: "Your personal travel journal",
            description: "Capture every moment of your adventures with photos, daily entries, and memories that last a lifetime.",
            icon: "book.closed.fill",
            color: .blue
        ),
        OnboardingPage(
            title: "Document Your Journey",
            subtitle: "Day by day memories",
            description: "Create daily entries with photos, notes, and memories. Each day becomes a chapter in your travel story.",
            icon: "calendar.badge.plus",
            color: .orange
        ),
        OnboardingPage(
            title: "Photo Access",
            subtitle: "We need photo access",
            description: "To add photos to your trip journal, we need access to your photo library. This lets you select photos from your adventures.",
            icon: "photo.on.rectangle",
            color: .purple
        ),
        OnboardingPage(
            title: "Ready to Start?",
            subtitle: "Your adventure begins now",
            description: "Start creating your first trip, add days, and begin documenting your journey with photos and memories.",
            icon: "checkmark.circle.fill",
            color: .green
        )
    ]
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Page content
                TabView(selection: $currentPage) {
                    ForEach(0..<onboardingPages.count, id: \.self) { index in
                        OnboardingPageView(page: onboardingPages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)
                .onChange(of: currentPage) { _, newPage in
                    // Check current permission status when landing on photo page
                    if newPage == 2 { // Photo page
                        checkPhotoPermissionStatus()
                    }
                }
                
                // Bottom controls
                VStack(spacing: 20) {
                    // Page indicators
                    HStack(spacing: 8) {
                        ForEach(0..<onboardingPages.count, id: \.self) { index in
                            Circle()
                                .fill(index == currentPage ? onboardingPages[currentPage].color : Color(.tertiaryLabel))
                                .frame(width: 8, height: 8)
                                .scaleEffect(index == currentPage ? 1.2 : 1.0)
                                .animation(.easeInOut(duration: 0.2), value: currentPage)
                        }
                    }
                    
                    // Navigation buttons
                    HStack {
                        if currentPage > 0 {
                            Button("Back") {
                                withAnimation {
                                    currentPage -= 1
                                }
                            }
                            .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if currentPage < onboardingPages.count - 1 {
                            // Show different button text based on permission status
                            if currentPage == 2 && !photoPermissionGranted {
                                Button(action: requestPhotoPermission) {
                                    if isRequestingPermission {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        Text("Request Photo Access")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .disabled(isRequestingPermission)
                            } else {
                                Button("Next") {
                                    withAnimation {
                                        currentPage += 1
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        } else {
                            Button("Get Started") {
                                // Mark onboarding as completed
                                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showOnboarding = false
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            // Check initial permission statuses
            checkPhotoPermissionStatus()
        }
    }
    
    private func checkPhotoPermissionStatus() {
        // Don't check permissions during view load to avoid crashes
        // Only check when user actually requests permissions
        photoPermissionGranted = false
    }
    
    private func requestPhotoPermission() {
        isRequestingPermission = true
        
        // Only request permissions when user taps the button
        // This avoids calling photo APIs during view initialization
        PHPhotoLibrary.requestAuthorization { status in
            DispatchQueue.main.async {
                self.isRequestingPermission = false
                // Accept any level of access as success
                self.photoPermissionGranted = (status == .authorized || status == .limited)
                
                // If permission granted, advance to next page
                if self.photoPermissionGranted {
                    withAnimation {
                        self.currentPage += 1
                    }
                }
            }
        }
    }
}

struct OnboardingPage {
    let title: String
    let subtitle: String
    let description: String
    let icon: String
    let color: Color
}

struct OnboardingPageView: View {
    let page: OnboardingPage
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Icon
            Image(systemName: page.icon)
                .font(.system(size: 100))
                .foregroundColor(page.color)
                .padding(.bottom, 20)
            
            // Text content
            VStack(spacing: 16) {
                Text(page.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text(page.subtitle)
                    .font(.title2)
                    .foregroundColor(page.color)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                
                Text(page.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            
            Spacer()
        }
    }
}

#Preview {
    OnboardingView(showOnboarding: .constant(true))
}
