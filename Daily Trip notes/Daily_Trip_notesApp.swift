//
//  Daily_Trip_notesApp.swift
//  Daily Trip notes
//
//  Created by Dan Wassink on 8/10/25.
//

import SwiftUI

@main
struct Daily_Trip_notesApp: App {
    let coreDataManager = CoreDataManager.shared
    @State private var showOnboarding = false
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                TripListView()
                    .environment(\.managedObjectContext, coreDataManager.container.viewContext)
                
                if showOnboarding {
                    OnboardingView(showOnboarding: $showOnboarding)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .onAppear {
                // Check if user has completed onboarding
                let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
                if !hasCompletedOnboarding {
                    showOnboarding = true
                }
            }
        }
    }
}
