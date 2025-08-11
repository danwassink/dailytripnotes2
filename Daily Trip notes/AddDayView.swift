import SwiftUI
import CoreData

struct AddDayView: View {
    let trip: Trip
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedDate = Date()
    @State private var customOrder: Int = 0
    
    var body: some View {
        NavigationView {
            Form {
                Section("Day Details") {
                    DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                    
                    Stepper("Order: \(customOrder)", value: $customOrder, in: 0...100)
                }
                
                Section("Info") {
                    Text("This will create a new day entry for your trip with an empty journal entry that you can fill in later.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Add Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        addDay()
                    }
                }
            }
            .onAppear {
                // Set default order to be after existing days
                if let tripDays = trip.tripDays?.allObjects as? [TripDay] {
                    customOrder = tripDays.count
                }
            }
        }
    }
    
    private func addDay() {
        let newDay = TripDay(context: viewContext)
        newDay.id = UUID()
        newDay.date = selectedDate
        newDay.order = Int32(customOrder)
        newDay.trip = trip
        
        // Create empty journal entry for this day
        let journalEntry = JournalEntry(context: viewContext)
        journalEntry.id = UUID()
        journalEntry.content = ""
        journalEntry.createdDate = Date()
        journalEntry.tripDay = newDay
        
        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("Error adding day: \(error)")
        }
    }
}

#Preview {
    let context = CoreDataManager.shared.container.viewContext
    let trip = Trip(context: context)
    trip.name = "Sample Trip"
    
    return AddDayView(trip: trip)
        .environment(\.managedObjectContext, context)
}
