import SwiftUI
import CoreData

struct DayDetailView: View {
    let tripDay: TripDay
    @Environment(\.managedObjectContext) private var viewContext
    @State private var journalContent: String = ""
    @State private var isEditing = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with date - redesigned without gray background
            VStack(spacing: 12) {
                if let date = tripDay.date {
                    // Main date in large, prominent text (without day to avoid duplication)
                    Text(date.formatted(.dateTime.month(.wide).day().year()))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    // Day of week in blue, medium size
                    Text(date.formatted(.dateTime.weekday(.wide)))
                        .font(.title2)
                        .foregroundColor(.blue)
                        .fontWeight(.semibold)
                    
                    // Day number with subtle styling
                    Text("Day \(tripDay.order + 1)")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray6))
                        )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 24)
            
            // Journal entry editor
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Journal Entry")
                        .font(.headline)
                    Spacer()
                    Button(isEditing ? "Done" : (journalContent.isEmpty ? "Add" : "Edit")) {
                        if isEditing {
                            saveJournalEntry()
                        }
                        isEditing.toggle()
                    }
                    .foregroundColor(.blue)
                }
                .padding(.horizontal, 20)
                
                if isEditing {
                    TextEditor(text: $journalContent)
                        .frame(minHeight: 200)
                        .padding(12)
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.separator), lineWidth: 1)
                        )
                        .padding(.horizontal, 20)
                } else {
                    ScrollView {
                        if journalContent.isEmpty {
                            Text("No journal entry yet. Tap Add to write about your day.")
                                .foregroundColor(.secondary)
                                .italic()
                                .padding(.horizontal, 20)
                                .padding(.vertical, 40)
                        } else {
                            Text(journalContent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            
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
