import SwiftUI
import CoreData
import Photos

struct EditTripView: View {
    let trip: Trip
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var tripName: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var description: String
    @State private var showingFeaturePhotoPicker = false
    @State private var selectedFeaturePhotoFilename: String?
    @State private var isAddingFeaturePhoto = false
    
    init(trip: Trip) {
        self.trip = trip
        _tripName = State(initialValue: trip.name ?? "")
        _startDate = State(initialValue: trip.startDate ?? Date())
        _endDate = State(initialValue: trip.endDate ?? Date())
        _description = State(initialValue: trip.desc ?? "")
        _selectedFeaturePhotoFilename = State(initialValue: trip.featurePhotoFilename)
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
                
                Section("Feature Photo") {
                    VStack(alignment: .leading, spacing: 12) {
                        if let featurePhotoFilename = selectedFeaturePhotoFilename {
                            // Show current feature photo
                            TripFeaturePhotoView(filename: featurePhotoFilename)
                                .frame(height: 200)
                                .frame(maxWidth: .infinity)
                                .clipped()
                                .cornerRadius(12)
                            
                            HStack {
                                Button("Change Photo") {
                                    showingFeaturePhotoPicker = true
                                }
                                .foregroundColor(.blue)
                                
                                Spacer()
                                
                                Button("Remove Photo") {
                                    removeFeaturePhoto()
                                }
                                .foregroundColor(.red)
                            }
                        } else {
                            // Show placeholder when no feature photo is selected
                            Button(action: {
                                showingFeaturePhotoPicker = true
                            }) {
                                VStack(spacing: 12) {
                                    Image(systemName: "photo.badge.plus")
                                        .font(.system(size: 40))
                                        .foregroundColor(.blue)
                                    Text("Select a feature photo")
                                        .font(.subheadline)
                                        .foregroundColor(.blue)
                                }
                                .frame(height: 200)
                                .frame(maxWidth: .infinity)
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                            }
                        }
                    }
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
            .sheet(isPresented: $showingFeaturePhotoPicker) {
                TripFeaturePhotoPickerView(trip: trip, onPhotoSelected: { selectedPhoto in
                    setFeaturePhoto(selectedPhoto)
                })
            }
            .onChange(of: showingFeaturePhotoPicker) { oldValue, newValue in
                print("EditTripView: showingFeaturePhotoPicker changed from \(oldValue) to \(newValue)")
            }
        }
    }
    
    private func setFeaturePhoto(_ photo: Photo) {
        // If this is a temporary photo from PHAsset (using localIdentifier as filename)
        if photo.filename?.hasPrefix("temp_") == true || photo.filename?.contains(":") == true {
            // This is a PHAsset, we need to copy the actual image data
            copyPhotoFromPHAsset(photo)
        } else {
            // This is an existing photo, just set the filename
            trip.featurePhotoFilename = photo.filename
            selectedFeaturePhotoFilename = photo.filename
        }
    }
    
    private func copyPhotoFromPHAsset(_ photo: Photo) {
        // Use assetIdentifier if available, otherwise extract from filename
        let assetIdentifier: String
        if let identifier = photo.assetIdentifier {
            assetIdentifier = identifier
        } else if let localIdentifier = photo.filename {
            // Extract the actual PHAsset localIdentifier (remove temp_ prefix if present)
            assetIdentifier = localIdentifier.hasPrefix("temp_") ? String(localIdentifier.dropFirst(5)) : localIdentifier
        } else {
            print("EditTripView: No asset identifier or filename available")
            return
        }
        
        print("EditTripView: Copying photo with asset identifier: \(assetIdentifier)")
        
        // Fetch the PHAsset
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else { 
            print("EditTripView: No PHAsset found for identifier: \(assetIdentifier)")
            return 
        }
        
        // Load the image data using modern API
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        let targetSize = CGSize(width: 1200, height: 1200) // High quality for feature photo
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            guard let image = image else { 
                print("EditTripView: Failed to load image from PHAsset")
                return 
            }
            
            // Convert image to JPEG data
            guard let imageData = image.jpegData(compressionQuality: 0.9) else {
                print("EditTripView: Failed to convert image to JPEG data")
                return
            }
            
            // Generate a unique filename
            let filename = "feature_photo_\(UUID().uuidString).jpg"
            
            // Save to documents directory
            if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let photoURL = documentsPath.appendingPathComponent(filename)
                do {
                    try imageData.write(to: photoURL)
                    print("EditTripView: Successfully saved feature photo to: \(filename)")
                    
                    // Update both the trip and the local state immediately
                    DispatchQueue.main.async {
                        self.trip.featurePhotoFilename = filename
                        self.selectedFeaturePhotoFilename = filename
                        print("EditTripView: Updated trip feature photo filename to: \(filename)")
                        print("EditTripView: Updated local state to show feature photo immediately")
                    }
                } catch {
                    print("EditTripView: Error saving feature photo: \(error)")
                }
            }
        }
    }
    
    private func removeFeaturePhoto() {
        print("EditTripView: Removing feature photo")
        print("EditTripView: Before removal - showingFeaturePhotoPicker: \(showingFeaturePhotoPicker)")
        
        // Ensure photo picker is not showing
        showingFeaturePhotoPicker = false
        
        trip.featurePhotoFilename = nil
        selectedFeaturePhotoFilename = nil
        print("EditTripView: Feature photo removed, local state: \(selectedFeaturePhotoFilename ?? "nil")")
        print("EditTripView: After removal - showingFeaturePhotoPicker: \(showingFeaturePhotoPicker)")
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
