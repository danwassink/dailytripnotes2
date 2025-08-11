//
//  ContentView.swift
//  Daily Trip notes
//
//  Created by Dan Wassink on 8/10/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "airplane")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Daily Trip Notes")
                .font(.title)
            Text("Navigate to TripListView for the main app")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
