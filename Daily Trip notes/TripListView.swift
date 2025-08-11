import SwiftUI
import CoreData

struct TripListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Trip.createdDate, ascending: false)],
        animation: .default)
    private var trips: FetchedResults<Trip>
    
    @State private var showingAddTrip = false
    
    var body: some View {
        NavigationView {
            List {
                ForEach(trips) { trip in
                    NavigationLink(destination: TripDetailView(trip: trip)) {
                        TripRowView(trip: trip)
                    }
                }
                .onDelete(perform: deleteTrips)
            }
            .navigationTitle("My Trips")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddTrip = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddTrip) {
                AddTripView()
            }
        }
    }
    
    private func deleteTrips(offsets: IndexSet) {
        withAnimation {
            offsets.map { trips[$0] }.forEach(viewContext.delete)
            
            do {
                try viewContext.save()
            } catch {
                print("Error deleting trip: \(error)")
            }
        }
    }
}

struct TripRowView: View {
    let trip: Trip
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(trip.name ?? "Untitled Trip")
                .font(.headline)
            
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
                    .lineLimit(2)
            }
            
            // Show day count
            if let tripDays = trip.tripDays?.allObjects as? [TripDay] {
                let dayCount = tripDays.count
                Text("\(dayCount) day\(dayCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    TripListView()
        .environment(\.managedObjectContext, CoreDataManager.shared.container.viewContext)
}
