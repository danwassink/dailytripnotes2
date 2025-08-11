import SwiftUI
import CoreData

struct TripDetailView: View {
    let trip: Trip
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingAddDay = false
    @State private var showingEditTrip = false
    
    var sortedDays: [TripDay] {
        trip.tripDays?.allObjects as? [TripDay] ?? []
    }
    
    var body: some View {
        List {
            Section("Trip Info") {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(trip.name ?? "Untitled Trip")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        if let startDate = trip.startDate, let endDate = trip.endDate {
                            Text("\(startDate.formatted(date: .abbreviated, time: .omitted)) - \(endDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            // Add day of week information
                            HStack(spacing: 16) {
                                Text(startDate.formatted(.dateTime.weekday(.abbreviated)))
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                Text("to")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(endDate.formatted(.dateTime.weekday(.abbreviated)))
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        if let desc = trip.desc, !desc.isEmpty {
                            Text(desc)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            
            Section("Trip Days") {
                if sortedDays.isEmpty {
                    Text("No days added yet")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(sortedDays.sorted { $0.order < $1.order }) { day in
                        NavigationLink(destination: DayDetailView(tripDay: day)) {
                            DayRowView(tripDay: day)
                        }
                    }
                    .onDelete(perform: deleteDays)
                }
                
                Button(action: { showingAddDay = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Day")
                    }
                    .foregroundColor(.blue)
                }
            }
        }
        .navigationTitle("Trip Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") {
                    showingEditTrip = true
                }
            }
        }
        .sheet(isPresented: $showingAddDay) {
            AddDayView(trip: trip)
        }
        .sheet(isPresented: $showingEditTrip) {
            EditTripView(trip: trip)
        }
        .onAppear {
            generateDaysIfNeeded()
        }
    }
    
    private func deleteDays(offsets: IndexSet) {
        withAnimation {
            let daysToDelete = offsets.map { sortedDays.sorted { $0.order < $1.order }[$0] }
            daysToDelete.forEach { day in
                viewContext.delete(day)
            }
            
            do {
                try viewContext.save()
            } catch {
                print("Error deleting day: \(error)")
            }
        }
    }
    
    private func generateDaysIfNeeded() {
        guard let startDate = trip.startDate,
              let endDate = trip.endDate,
              sortedDays.isEmpty else { return }
        
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
        
        do {
            try viewContext.save()
        } catch {
            print("Error generating days: \(error)")
        }
    }
}

struct DayRowView: View {
    let tripDay: TripDay
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if let date = tripDay.date {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.headline)
                        
                        Text(date.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.caption)
                            .foregroundColor(.blue)
                            .fontWeight(.medium)
                    }
                }
                
                if let journalEntry = tripDay.journalEntry,
                   let content = journalEntry.content,
                   !content.isEmpty {
                    Text(content)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                } else {
                    Text("No journal entry yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let context = CoreDataManager.shared.container.viewContext
    let trip = Trip(context: context)
    trip.name = "Sample Trip"
    trip.startDate = Date()
    trip.endDate = Date().addingTimeInterval(7 * 24 * 60 * 60)
    
    return NavigationView {
        TripDetailView(trip: trip)
            .environment(\.managedObjectContext, context)
    }
}
