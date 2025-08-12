import SwiftUI
import PhotosUI
import CoreData

struct DayDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    let tripDay: TripDay
    @State private var journalContent: String = ""
    @State private var showingPhotoPicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photosAdded = false
    @State private var isEditing = false
    @State private var photosDeleted = false
    
    var sortedPhotos: [Photo] {
        let photos = tripDay.photos?.allObjects as? [Photo] ?? []
        return photos.sorted { $0.order < $1.order }
    }
    
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
            
            // Photos Section
            Section("Photos") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                    ForEach(sortedPhotos, id: \.id) { photo in
                        PhotoThumbnailView(photo: photo, onPhotoDeleted: {
                            photosDeleted.toggle() // Force refresh when photo is deleted
                        })
                    }
                    
                    // Add Photos Button - Direct PhotosPicker
                    PhotosPicker(
                        selection: $selectedPhotos,
                        maxSelectionCount: 50,
                        matching: .images
                    ) {
                        VStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.blue)
                            Text("Add Photos")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        .frame(width: 100, height: 100)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                    .onChange(of: selectedPhotos) { _, newPhotos in
                        if !newPhotos.isEmpty {
                            processSelectedPhotos(newPhotos)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .id(photosAdded, photosDeleted) // Force refresh when photos are added or deleted
            
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
    
    private func processSelectedPhotos(_ photos: [PhotosPickerItem]) {
        Task {
            for (index, photoItem) in photos.enumerated() {
                if let data = try? await photoItem.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        savePhoto(data: data, order: index)
                    }
                }
            }
            
            await MainActor.run {
                photosAdded.toggle() // Force view refresh
                selectedPhotos.removeAll() // Clear selection
            }
        }
    }
    
    private func savePhoto(data: Data, order: Int) {
        let photo = Photo(context: viewContext)
        photo.id = UUID()
        photo.filename = "photo_\(UUID().uuidString).jpg"
        photo.caption = ""
        photo.createdDate = Date()
        photo.photoDate = Date()
        photo.order = Int32(order)
        photo.tripDay = tripDay
        
        // Save the photo file to documents directory
        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let photoURL = documentsPath.appendingPathComponent(photo.filename!)
            try? data.write(to: photoURL)
        }
        
        // Save to Core Data
        try? viewContext.save()
    }
}

struct PhotoThumbnailView: View {
    let photo: Photo
    let onPhotoDeleted: () -> Void
    @State private var image: UIImage?
    @State private var showingDeleteAlert = false
    @Environment(\.managedObjectContext) private var viewContext
    
    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 100, height: 100)
                    .clipped()
                    .cornerRadius(8)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 100, height: 100)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.8)
                    )
            }
            
            // Caption indicator
            if let caption = photo.caption, !caption.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "text.bubble.fill")
                            .foregroundColor(.white)
                            .background(Color.blue)
                            .clipShape(Circle())
                            .font(.caption)
                            .padding(4)
                    }
                }
            }
        }
        .onLongPressGesture {
            showingDeleteAlert = true
        }
        .alert("Delete Photo", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                deletePhoto()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this photo? This action cannot be undone.")
        }
        .task {
            await loadPhoto()
        }
    }
    
    private func loadPhoto() async {
        guard let filename = photo.filename else { return }
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let fileURL = documentsPath?.appendingPathComponent(filename)
        
        if let fileURL = fileURL,
           let imageData = try? Data(contentsOf: fileURL),
           let loadedImage = UIImage(data: imageData) {
            image = loadedImage
        }
    }
    
    private func deletePhoto() {
        // Delete the photo file from storage
        if let filename = photo.filename {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            let fileURL = documentsPath?.appendingPathComponent(filename)
            
            if let fileURL = fileURL {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        
        // Remove from Core Data
        viewContext.delete(photo)
        
        // Save changes
        try? viewContext.save()
        onPhotoDeleted() // Notify parent view
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
