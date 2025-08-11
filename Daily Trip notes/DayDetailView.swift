import SwiftUI
import CoreData

struct DayDetailView: View {
    let tripDay: TripDay
    @Environment(\.managedObjectContext) private var viewContext
    @State private var journalContent: String = ""
    @State private var isEditing = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with date
            VStack(spacing: 8) {
                if let date = tripDay.date {
                    Text(date.formatted(date: .complete, time: .omitted))
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    // Add day of week prominently
                    Text(date.formatted(.dateTime.weekday(.wide)))
                        .font(.title3)
                        .foregroundColor(.blue)
                        .fontWeight(.medium)
                }
                
                Text("Day \(tripDay.order + 1)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            
            // Journal entry editor
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Journal Entry")
                        .font(.headline)
                    Spacer()
                    Button(isEditing ? "Done" : "Edit") {
                        if isEditing {
                            saveJournalEntry()
                        }
                        isEditing.toggle()
                    }
                    .foregroundColor(.blue)
                }
                
                if isEditing {
                    TextEditor(text: $journalContent)
                        .frame(minHeight: 200)
                        .padding(8)
                        .background(Color(.systemBackground))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(.separator), lineWidth: 1)
                        )
                } else {
                    ScrollView {
                        if journalContent.isEmpty {
                            Text("No journal entry yet. Tap Edit to write about your day.")
                                .foregroundColor(.secondary)
                                .italic()
                                .padding()
                        } else {
                            Text(journalContent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .padding()
            
            Spacer()
        }
        .navigationTitle("Day Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadJournalContent()
        }
    }
    
    private func loadJournalContent() {
        if let journalEntry = tripDay.journalEntry,
           let content = journalEntry.content {
            journalContent = content
        } else {
            journalContent = ""
        }
    }
    
    private func saveJournalEntry() {
        var journalEntry = tripDay.journalEntry
        
        if journalEntry == nil {
            journalEntry = JournalEntry(context: viewContext)
            journalEntry?.id = UUID()
            journalEntry?.createdDate = Date()
            journalEntry?.tripDay = tripDay
        }
        
        journalEntry?.content = journalContent
        
        do {
            try viewContext.save()
        } catch {
            print("Error saving journal entry: \(error)")
        }
    }
}

#Preview {
    let context = CoreDataManager.shared.container.viewContext
    let tripDay = TripDay(context: context)
    tripDay.date = Date()
    tripDay.order = 0
    
    return NavigationView {
        DayDetailView(tripDay: tripDay)
            .environment(\.managedObjectContext, context)
    }
}
