import SwiftUI
import CoreData
import Photos
import MapKit
import Foundation

enum ViewMode {
    case dates
    case map
}

struct TripDetailView: View {
    let trip: Trip
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingAddDay = false
    @State private var showingEditTrip = false
    @State private var showingFeaturePhotoPicker = false
    @State private var refreshTrigger = false
    @State private var journalRefreshTrigger = false
    @State private var viewMode: ViewMode = .dates
    
    var sortedDays: [TripDay] {
        trip.tripDays?.allObjects as? [TripDay] ?? []
    }
    
    var tripPhotos: [Photo] {
        let allPhotos = sortedDays.flatMap { day in
            let photos = day.photos?.allObjects as? [Photo] ?? []
            
            // Filter photos to only show those taken on this specific day
            let dayStart = Calendar.current.startOfDay(for: day.date ?? Date())
            let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            
            return photos.filter { photo in
                let photoDate = photo.photoDate ?? photo.createdDate ?? Date()
                return photoDate >= dayStart && photoDate < dayEnd
            }
        }
        
        return allPhotos.sorted { $0.order < $1.order }
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
                    
                    // Feature photo section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Feature Photo")
                                .font(.headline)
                            Spacer()
                            Button("Select") {
                                showingFeaturePhotoPicker = true
                            }
                            .foregroundColor(.blue)
                        }
                        .padding(.top, 8)
                        
                        if let featurePhotoFilename = trip.featurePhotoFilename {
                            // Show selected feature photo
                            TripFeaturePhotoView(filename: featurePhotoFilename)
                                .frame(height: 200)
                                .frame(maxWidth: .infinity)
                                .clipped()
                                .cornerRadius(12)
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
                .padding(.vertical, 4)
            }
            
            // View Mode Selector
            Section {
                Picker("View Mode", selection: $viewMode) {
                    Text("Dates").tag(ViewMode.dates)
                    Text("Map").tag(ViewMode.map)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.vertical, 8)
            }
            
            // Content based on view mode
            if viewMode == .dates {
                Section("Trip Days") {
                if sortedDays.isEmpty {
                    Text("No days added yet")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(sortedDays.sorted { $0.order < $1.order }) { day in
                        NavigationLink(destination: DayDetailView(tripDay: day)) {
                            DayRowView(tripDay: day, refreshTrigger: journalRefreshTrigger)
                        }
                    }
                    .onDelete(perform: deleteDays)
                }
            }
            } else {
                Section("Trip Map") {
                    TripMapView(trip: trip)
                        .frame(height: 400)
                        .listRowInsets(EdgeInsets())
                }
            }
        }
        .navigationTitle("Trip Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if viewMode == .map {
                    Button("Add Day") {
                        showingAddDay = true
                    }
                } else {
                    Button("Edit") {
                        showingEditTrip = true
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddDay) {
            AddDayView(trip: trip)
        }
        .sheet(isPresented: $showingEditTrip) {
            EditTripView(trip: trip)
        }
        .sheet(isPresented: $showingFeaturePhotoPicker) {
            TripFeaturePhotoPickerView(trip: trip, onPhotoSelected: { selectedPhoto in
                setFeaturePhoto(selectedPhoto)
            })
        }
        .onChange(of: showingEditTrip) { _, isShowing in
            if !isShowing {
                // Sheet was dismissed, trigger refresh
                refreshTrigger.toggle()
            }
        }
        .onChange(of: showingAddDay) { _, isShowing in
            if !isShowing {
                // Add day sheet was dismissed, trigger refresh
                refreshTrigger.toggle()
            }
        }
        .onAppear {
            generateDaysIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .journalEntrySaved)) { _ in
            journalRefreshTrigger.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .photosAddedToTripDay)) { notification in
            // Check if the photo was added to a day in this trip
            if let tripDay = notification.object as? TripDay,
               tripDay.trip?.id == trip.id {
                refreshTrigger.toggle() // Force refresh to show new photos
            }
        }
        .id(refreshTrigger) // Force refresh when editing sheet is dismissed
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
    
    private func setFeaturePhoto(_ photo: Photo) {
        // If this is a temporary photo from PHAsset (using localIdentifier as filename)
        if photo.filename?.hasPrefix("temp_") == true || photo.filename?.contains(":") == true {
            // This is a PHAsset, we need to copy the actual image data
            copyPhotoFromPHAsset(photo)
        } else {
            // This is an existing photo, just set the filename
            trip.featurePhotoFilename = photo.filename
            
            do {
                try viewContext.save()
                refreshTrigger.toggle() // Force refresh to show the new feature photo
            } catch {
                print("Error setting feature photo: \(error)")
            }
        }
    }
    
    private func copyPhotoFromPHAsset(_ photo: Photo) {
        guard let localIdentifier = photo.filename else { return }
        
        // Extract the actual PHAsset localIdentifier (remove temp_ prefix if present)
        let assetIdentifier = localIdentifier.hasPrefix("temp_") ? String(localIdentifier.dropFirst(5)) : localIdentifier
        
        // Fetch the PHAsset
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else { return }
        
        // Load the image data
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = false
        options.isSynchronous = false
        
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
            guard let imageData = data else { return }
            
            // Generate a unique filename
            let filename = "feature_photo_\(UUID().uuidString).jpg"
            
            // Save to documents directory
            if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let photoURL = documentsPath.appendingPathComponent(filename)
                try? imageData.write(to: photoURL)
                
                // Update the trip with the new filename
                DispatchQueue.main.async {
                    self.trip.featurePhotoFilename = filename
                    
                    do {
                        try self.viewContext.save()
                        self.refreshTrigger.toggle() // Force refresh to show the new feature photo
                    } catch {
                        print("Error setting feature photo: \(error)")
                    }
                }
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
    let refreshTrigger: Bool
    
    var sortedPhotos: [Photo] {
        let photos = tripDay.photos?.allObjects as? [Photo] ?? []
        
        // Filter photos to only show those taken on this specific day
        let dayStart = Calendar.current.startOfDay(for: tripDay.date ?? Date())
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        
        let filteredPhotos = photos.filter { photo in
            let photoDate = photo.photoDate ?? photo.createdDate ?? Date()
            return photoDate >= dayStart && photoDate < dayEnd
        }
        
        return filteredPhotos.sorted { $0.order < $1.order }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
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
            
            // Photo thumbnails
            if !sortedPhotos.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(sortedPhotos.prefix(3)), id: \.id) { photo in
                        TripPhotoThumbnailView(photo: photo)
                            .frame(width: 40, height: 40)
                    }
                    
                    if sortedPhotos.count > 3 {
                        Text("+\(sortedPhotos.count - 3)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 40, height: 40)
                            .background(Color(.systemGray6))
                            .cornerRadius(6)
                    }
                }
            }
            
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(.vertical, 4)
        .id(refreshTrigger) // Force refresh when journal entries change
    }
}

struct TripFeaturePhotoPickerView: View {
    let trip: Trip
    let onPhotoSelected: (Photo) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var photos: [Photo] = []
    @State private var isLoading = true
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("Loading trip photos...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if photos.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text("No Photos Found")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Add some photos to your trip days first")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                            ForEach(photos, id: \.id) { photo in
                                Button(action: {
                                    onPhotoSelected(photo)
                                    dismiss()
                                }) {
                                    TripPhotoThumbnailView(photo: photo)
                                        .frame(width: 100, height: 100)
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Select Feature Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            loadTripPhotos()
        }
    }
    
    private func loadTripPhotos() {
        guard let startDate = trip.startDate,
              let endDate = trip.endDate else {
            DispatchQueue.main.async {
                self.photos = []
                self.isLoading = false
            }
            return
        }
        
        // Check photo library permission first
        let status = PHPhotoLibrary.authorizationStatus()
        guard status == .authorized || status == .limited else {
            print("TripFeaturePhotoPickerView: Photo library permission not granted: \(status.rawValue)")
            DispatchQueue.main.async {
                self.photos = []
                self.isLoading = false
            }
            return
        }
        
        let tripStart = Calendar.current.startOfDay(for: startDate)
        let tripEnd = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: endDate)) ?? endDate
        
        print("TripFeaturePhotoPickerView: Fetching photos from \(tripStart) to \(tripEnd)")
        
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", tripStart as NSDate, tripEnd as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
        
        print("TripFeaturePhotoPickerView: Found \(fetchResult.count) photos for this trip period")
        
        // Convert PHAssets to Photo objects for consistency
        var tempPhotos: [Photo] = []
        fetchResult.enumerateObjects { asset, _, _ in
            // Create a temporary Photo object for display
            let photo = Photo(context: CoreDataManager.shared.container.viewContext)
            photo.id = UUID()
            photo.filename = "temp_\(asset.localIdentifier)" // Use temp_ prefix to identify PHAssets
            photo.createdDate = asset.creationDate ?? Date()
            photo.photoDate = asset.creationDate ?? Date()
            photo.order = 0
            tempPhotos.append(photo)
        }
        
        print("TripFeaturePhotoPickerView: Created \(tempPhotos.count) temporary photo objects")
        
        DispatchQueue.main.async {
            self.photos = tempPhotos
            self.isLoading = false
            print("TripFeaturePhotoPickerView: Set photos array, count: \(self.photos.count)")
        }
    }
}

struct TripFeaturePhotoView: View {
    let filename: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .cornerRadius(12)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray5))
                    .frame(maxWidth: .infinity)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.8)
                    )
            }
        }
        .task {
            await loadPhoto()
        }
    }

    private func loadPhoto() async {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let fileURL = documentsPath?.appendingPathComponent(filename)

        if let fileURL = fileURL,
           let imageData = try? Data(contentsOf: fileURL),
           let loadedImage = UIImage(data: imageData) {
            image = loadedImage
        }
    }
}

struct TripPhotoThumbnailView: View {
    let photo: Photo
    @State private var image: UIImage?
    
    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipped()
                    .cornerRadius(6)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemGray5))
                    .frame(width: 40, height: 40)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.6)
                    )
            }
        }
        .task {
            await loadPhoto()
        }
    }
    
    private func loadPhoto() async {
        guard let filename = photo.filename else { 
            print("TripPhotoThumbnailView: No filename provided")
            return 
        }
        
        print("TripPhotoThumbnailView: Loading photo with filename: \(filename)")
        
        // Check if this is a temporary photo from PHAsset
        if filename.hasPrefix("temp_") {
            print("TripPhotoThumbnailView: Loading from PHAsset")
            await loadPhotoFromPHAsset(filename)
        } else {
            print("TripPhotoThumbnailView: Loading from documents directory")
            // Load from documents directory
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            let fileURL = documentsPath?.appendingPathComponent(filename)
            
            if let fileURL = fileURL,
               let imageData = try? Data(contentsOf: fileURL),
               let loadedImage = UIImage(data: imageData) {
                print("TripPhotoThumbnailView: Successfully loaded image from documents")
                image = loadedImage
            } else {
                print("TripPhotoThumbnailView: Failed to load image from documents")
            }
        }
    }
    
    private func loadPhotoFromPHAsset(_ filename: String) async {
        // Extract the actual PHAsset localIdentifier
        let assetIdentifier = String(filename.dropFirst(5)) // Remove "temp_" prefix
        print("TripPhotoThumbnailView: Extracted asset identifier: \(assetIdentifier)")
        
        // Fetch the PHAsset
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else { 
            print("TripPhotoThumbnailView: No PHAsset found for identifier: \(assetIdentifier)")
            return 
        }
        
        print("TripPhotoThumbnailView: Found PHAsset, requesting image")
        
        // Load the thumbnail with more flexible options
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic // More flexible than fastFormat
        options.isNetworkAccessAllowed = true // Allow network access for iCloud photos
        options.resizeMode = .fast // Use fast resize mode
        
        let targetSize = CGSize(width: 100, height: 100)
        
        await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                DispatchQueue.main.async {
                    if let image = image {
                        print("TripPhotoThumbnailView: Successfully loaded image from PHAsset")
                        self.image = image
                    } else {
                        print("TripPhotoThumbnailView: Failed to load image from PHAsset")
                        // Try fallback method with different options
                        self.loadPhotoWithFallback(asset: asset)
                    }
                }
                continuation.resume()
            }
        }
    }
    
    private func loadPhotoWithFallback(asset: PHAsset) {
        print("TripPhotoThumbnailView: Trying fallback method")
        
        // Try with completely different options
        let fallbackOptions = PHImageRequestOptions()
        fallbackOptions.deliveryMode = .highQualityFormat
        fallbackOptions.isNetworkAccessAllowed = true
        fallbackOptions.isSynchronous = false
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize, // Request full size
            contentMode: .aspectFit,
            options: fallbackOptions
        ) { image, info in
            DispatchQueue.main.async {
                if let image = image {
                    print("TripPhotoThumbnailView: Fallback method succeeded")
                    // Scale down the full image to thumbnail size
                    let thumbnailSize = CGSize(width: 100, height: 100)
                    UIGraphicsBeginImageContextWithOptions(thumbnailSize, false, 0.0)
                    image.draw(in: CGRect(origin: .zero, size: thumbnailSize))
                    let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
                    UIGraphicsEndImageContext()
                    
                    self.image = thumbnail
                } else {
                    print("TripPhotoThumbnailView: Fallback method also failed")
                    // Show a placeholder or error state
                }
            }
        }
    }
}

struct TripMapView: View {
    let trip: Trip
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // Default to San Francisco
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    @State private var photoAnnotations: [PhotoAnnotation] = []
    
    var body: some View {
        Map(coordinateRegion: $region, annotationItems: photoAnnotations) { annotation in
            MapAnnotation(coordinate: annotation.coordinate) {
                VStack(spacing: 0) {
                    Image(systemName: "photo.circle.fill")
                        .font(.title)
                        .foregroundColor(.blue)
                        .background(Color.white)
                        .clipShape(Circle())
                    
                    Text(annotation.title)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(8)
                }
            }
        }
        .onAppear {
            loadPhotoAnnotations()
        }
    }
    
    private func loadPhotoAnnotations() {
        let allPhotos = trip.tripDays?.allObjects.compactMap { $0 as? TripDay } ?? []
        var annotations: [PhotoAnnotation] = []
        
        for day in allPhotos {
            let photos = day.photos?.allObjects as? [Photo] ?? []
            for photo in photos {
                // For now, we'll use a default location based on the trip dates
                // In a real app, you'd extract GPS coordinates from the photo metadata
                let coordinate = CLLocationCoordinate2D(
                    latitude: 37.7749 + Double.random(in: -0.01...0.01), // Random offset for demo
                    longitude: -122.4194 + Double.random(in: -0.01...0.01)
                )
                
                let annotation = PhotoAnnotation(
                    coordinate: coordinate,
                    title: day.date?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown Date",
                    subtitle: photo.caption ?? "Photo",
                    photo: photo
                )
                annotations.append(annotation)
            }
        }
        
        photoAnnotations = annotations
        
        // Update map region to show all annotations
        if !annotations.isEmpty {
            let latitudes = annotations.map { $0.coordinate.latitude }
            let longitudes = annotations.map { $0.coordinate.longitude }
            
            let minLat = latitudes.min() ?? 37.7749
            let maxLat = latitudes.max() ?? 37.7749
            let minLon = longitudes.min() ?? -122.4194
            let maxLon = longitudes.max() ?? -122.4194
            
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: (minLat + maxLat) / 2,
                    longitude: (minLon + maxLon) / 2
                ),
                span: MKCoordinateSpan(
                    latitudeDelta: (maxLat - minLat) * 1.5,
                    longitudeDelta: (maxLon - minLon) * 1.5
                )
            )
        }
    }
}

struct PhotoAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let title: String
    let subtitle: String
    let photo: Photo
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
