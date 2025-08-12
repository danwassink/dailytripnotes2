import SwiftUI
import CoreData

struct JournalEntryView: View {
    let tripDay: TripDay
    let onSave: () -> Void
    
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @State private var journalContent: String = ""
    @State private var isInitialized = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with date info
                VStack(spacing: 12) {
                    if let date = tripDay.date {
                        Text(date.formatted(.dateTime.month(.wide).day().year()))
                            .font(.title2)
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.center)
                        
                        Text(date.formatted(.dateTime.weekday(.wide)))
                            .font(.headline)
                            .foregroundColor(.blue)
                            .fontWeight(.medium)
                        
                        Text("Day \(tripDay.order + 1)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.systemGray6))
                            )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)
                
                // Journal content editor
                VStack(alignment: .leading, spacing: 16) {
                    Text("Journal Entry")
                        .font(.headline)
                        .padding(.horizontal, 20)
                    
                    TextEditor(text: $journalContent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(16)
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.separator), lineWidth: 1)
                        )
                        .padding(.horizontal, 20)
                        .placeholder(when: journalContent.isEmpty) {
                            Text("Write about your day...")
                                .foregroundColor(.secondary)
                                .italic()
                                .padding(.leading, 20)
                                .padding(.top, 20)
                        }
                }
            }
            .navigationTitle("Journal Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveJournalEntry()
                        dismiss()
                    }
                    .disabled(journalContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            if !isInitialized {
                loadJournalContent()
                isInitialized = true
            }
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
        
        journalEntry?.content = journalContent.trimmingCharacters(in: .whitespacesAndNewlines)
        
        do {
            try viewContext.save()
            // Post notification to refresh trip details view
            NotificationCenter.default.post(name: .journalEntrySaved, object: nil)
            onSave()
        } catch {
            print("Error saving journal entry: \(error)")
        }
    }
}

// Extension to add placeholder functionality to TextEditor
extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

#Preview {
    let context = CoreDataManager.shared.container.viewContext
    let tripDay = TripDay(context: context)
    tripDay.date = Date()
    tripDay.order = 0
    
    return JournalEntryView(tripDay: tripDay) {
        print("Journal saved")
    }
    .environment(\.managedObjectContext, context)
}
