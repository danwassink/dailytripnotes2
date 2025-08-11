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
    
    var body: some Scene {
        WindowGroup {
            TripListView()
                .environment(\.managedObjectContext, coreDataManager.container.viewContext)
        }
    }
}
