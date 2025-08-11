import SwiftUI
import CoreData

struct EditTripView: View {
    let trip: Trip
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var tripName: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var description: String
    
    init(trip: Trip) {
        self.trip = trip
        _tripName = State(initialValue: trip.name ?? "")
        _startDate = State(initialValue: trip.startDate ?? Date())
        _endDate = State(initialValue: trip.endDate ?? Date())
        _description = State(initialValue: trip.desc ?? "")
    }
    
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
                
                Section("Warning") {
                    Text("Changing trip dates will regenerate all days and may affect existing journal entries.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .navigationTitle("Edit Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(tripName.isEmpty || endDate <= startDate)
                }
            }
        }
    }
    
    private func saveChanges() {
        // Check if dates have changed significantly
        let datesChanged = trip.startDate != startDate || trip.endDate != endDate
        
        // Update trip properties
        trip.name = tripName
        trip.startDate = startDate
        trip.endDate = endDate
        trip.desc = description.isEmpty ? nil : description
        
        // If dates changed significantly, regenerate days
        if datesChanged {
            regenerateDaysForTrip()
        }
        
        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("Error updating trip: \(error)")
        }
    }
    
    private func regenerateDaysForTrip() {
        // Remove existing days and journal entries
        if let existingDays = trip.tripDays?.allObjects as? [TripDay] {
            existingDays.forEach { day in
                viewContext.delete(day)
            }
        }
        
        // Generate new days based on updated dates
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
    let context = CoreDataManager.shared.container.viewContext
    let trip = Trip(context: context)
    trip.name = "Sample Trip"
    trip.startDate = Date()
    trip.endDate = Date().addingTimeInterval(7 * 24 * 60 * 60)
    trip.desc = "A sample trip for preview"
    
    return EditTripView(trip: trip)
        .environment(\.managedObjectContext, context)
}
