import SwiftUI
import CoreData

struct AddTripView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var tripName = ""
    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(7 * 24 * 60 * 60) // Default to 1 week
    @State private var description = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section("Trip Details") {
                    TextField("Trip Name", text: $tripName)
                    
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    DatePicker("End Date", selection: $endDate, displayedComponents: .date)
                }
                
                Section("Description") {
                    TextField("Optional description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("Info") {
                    Text("Days will be automatically created for each date in your trip range, with empty journal entries ready to fill in.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("New Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveTrip()
                    }
                    .disabled(tripName.isEmpty || endDate <= startDate)
                }
            }
        }
    }
    
    private func saveTrip() {
        let newTrip = Trip(context: viewContext)
        newTrip.id = UUID()
        newTrip.name = tripName
        newTrip.startDate = startDate
        newTrip.endDate = endDate
        newTrip.desc = description.isEmpty ? nil : description
        newTrip.createdDate = Date()
        
        // Generate days for the trip
        generateDaysForTrip(newTrip)
        
        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("Error saving trip: \(error)")
        }
    }
    
    private func generateDaysForTrip(_ trip: Trip) {
        let calendar = Calendar.current
        var currentDate = startDate
        var order = 0
        
        while currentDate <= endDate {
            let newDay = TripDay(context: viewContext)
            newDay.id = UUID()
            newDay.date = currentDate
            newDay.order = Int32(order)
            newDay.trip = trip
            
            // Create empty journal entry for this day
            let journalEntry = JournalEntry(context: viewContext)
            journalEntry.id = UUID()
            journalEntry.content = ""
            journalEntry.createdDate = Date()
            journalEntry.tripDay = newDay
            
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
            order += 1
        }
    }
}

#Preview {
    AddTripView()
        .environment(\.managedObjectContext, CoreDataManager.shared.container.viewContext)
}
