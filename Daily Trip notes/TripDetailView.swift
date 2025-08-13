import SwiftUI
import CoreData
import Photos
import MapKit
import Foundation
import AVFoundation

enum ViewMode {
    case dates
    case map
    case photos
}

struct TripDetailView: View {
    let trip: Trip
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingAddDay = false
    @State private var showingEditTrip = false
    @State private var showingTripPhotoPicker = false // New state variable
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
                }
                .padding(.vertical, 4)
            }
            
            // Feature Photo Display (Read-only)
            if let featurePhotoFilename = trip.featurePhotoFilename {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Feature Photo")
                            .font(.headline)
                        
                        TripFeaturePhotoView(filename: featurePhotoFilename)
                            .frame(height: 200)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .cornerRadius(12)
                    }
                    .padding(16)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                }
            }
            
            // Add Photos to Trip Days Card
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Add Photos to Trip Days")
                            .font(.headline)
                        Spacer()
                        Button("Add Photos") {
                            showingTripPhotoPicker = true
                        }
                        .foregroundColor(.blue)
                    }
                    
                    Text("Add multiple photos that will be automatically distributed to the appropriate trip days based on their creation date.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .padding(16)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            }
            
            // View Mode Selector
            Section {
                Picker("View Mode", selection: $viewMode) {
                    Text("Dates").tag(ViewMode.dates)
                    Text("Map").tag(ViewMode.map)
                    Text("Photos").tag(ViewMode.photos)
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
            } else if viewMode == .map {
                Section("Trip Map") {
                    TripMapView(trip: trip)
                        .frame(height: 400)
                        .listRowInsets(EdgeInsets())
                }
            } else if viewMode == .photos {
                Section("Trip Photos") {
                    TripPhotosView(trip: trip)
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
        .sheet(isPresented: $showingTripPhotoPicker) {
            TripPhotoPickerView(trip: trip)
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
        
        // First try to load from assetIdentifier if available
        if let assetIdentifier = photo.assetIdentifier {
            print("TripPhotoThumbnailView: Loading from assetIdentifier: \(assetIdentifier)")
            await loadPhotoFromPHAsset(assetIdentifier)
            return
        }
        
        // Check if this is a temporary photo from PHAsset (old format)
        if filename.hasPrefix("temp_") {
            print("TripPhotoThumbnailView: Loading from PHAsset (temp_ format)")
            let assetIdentifier = String(filename.dropFirst(5)) // Remove "temp_" prefix
            await loadPhotoFromPHAsset(assetIdentifier)
            return
        }
        
        // Try loading from documents directory
        print("TripPhotoThumbnailView: Loading from documents directory")
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let fileURL = documentsPath?.appendingPathComponent(filename)
        
        if let fileURL = fileURL,
           let imageData = try? Data(contentsOf: fileURL),
           let loadedImage = UIImage(data: imageData) {
            print("TripPhotoThumbnailView: Successfully loaded image from documents")
            image = loadedImage
        } else {
            print("TripPhotoThumbnailView: Failed to load image from documents")
            // Try to extract asset identifier from filename if it contains one
            if filename.contains(":") {
                let assetIdentifier = filename
                print("TripPhotoThumbnailView: Trying to load from filename as asset identifier: \(assetIdentifier)")
                await loadPhotoFromPHAsset(assetIdentifier)
            }
        }
    }
    
    private func loadPhotoFromPHAsset(_ assetIdentifier: String) async {
        print("TripPhotoThumbnailView: Loading from asset identifier: \(assetIdentifier)")
        
        // Fetch the PHAsset
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else { 
            print("TripPhotoThumbnailView: No PHAsset found for identifier: \(assetIdentifier)")
            return 
        }
        
        print("TripPhotoThumbnailView: Found PHAsset, requesting image")
        
        // Try multiple approaches to load the image
        await loadPhotoWithMultipleAttempts(asset: asset)
    }
    
    private func loadPhotoWithMultipleAttempts(asset: PHAsset) async {
        // Attempt 1: Fast thumbnail with opportunistic delivery
        let fastOptions = PHImageRequestOptions()
        fastOptions.deliveryMode = .opportunistic
        fastOptions.isNetworkAccessAllowed = true
        fastOptions.resizeMode = .fast
        
        let targetSize = CGSize(width: 80, height: 80) // 2x for retina
        
        await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: fastOptions
            ) { image, info in
                DispatchQueue.main.async {
                    if let image = image {
                        print("TripPhotoThumbnailView: Successfully loaded image with fast method")
                        self.image = image
                        continuation.resume()
                        return
                    }
                    
                    // Attempt 2: Try with different options
                    print("TripPhotoThumbnailView: Fast method failed, trying fallback")
                    self.loadPhotoWithFallback(asset: asset)
                    continuation.resume()
                }
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
                    let thumbnailSize = CGSize(width: 80, height: 80) // Match the target size
                    UIGraphicsBeginImageContextWithOptions(thumbnailSize, false, 0.0)
                    image.draw(in: CGRect(origin: .zero, size: thumbnailSize))
                    let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
                    UIGraphicsEndImageContext()
                    
                    self.image = thumbnail
                } else {
                    print("TripPhotoThumbnailView: Fallback method also failed")
                    // Try one more approach with different options
                    self.loadPhotoWithFinalAttempt(asset: asset)
                }
            }
        }
    }
    
    private func loadPhotoWithFinalAttempt(asset: PHAsset) {
        print("TripPhotoThumbnailView: Trying final attempt with different options")
        
        // Try with synchronous loading and different delivery mode
        let finalOptions = PHImageRequestOptions()
        finalOptions.deliveryMode = .fastFormat
        finalOptions.isNetworkAccessAllowed = true
        finalOptions.isSynchronous = true
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 80, height: 80),
            contentMode: .aspectFill,
            options: finalOptions
        ) { image, info in
            DispatchQueue.main.async {
                if let image = image {
                    print("TripPhotoThumbnailView: Final attempt succeeded")
                    self.image = image
                } else {
                    print("TripPhotoThumbnailView: All attempts failed")
                    // At this point, we've tried everything - show a placeholder
                    // The placeholder is already shown by the ZStack when image is nil
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
                PhotoAnnotationView(annotation: annotation)
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

struct PhotoAnnotationView: View {
    let annotation: PhotoAnnotation
    @State private var image: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        VStack(spacing: 4) {
            // Photo thumbnail
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            } else if isLoading {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 60, height: 60)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.8)
                    )
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray4))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                    )
            }
            
            // Date label
            Text(annotation.title)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white)
                .foregroundColor(.black)
                .cornerRadius(6)
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
        }
        .onAppear {
            loadPhotoThumbnail()
        }
    }
    
    private func loadPhotoThumbnail() {
        guard let filename = annotation.photo.filename else { return }
        
        // Check if this is a temporary photo from PHAsset
        if filename.hasPrefix("temp_") || filename.contains(":") {
            loadPhotoFromPHAsset(filename)
        } else {
            loadPhotoFromDocuments(filename)
        }
    }
    
    private func loadPhotoFromDocuments(_ filename: String) {
        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let photoURL = documentsPath.appendingPathComponent(filename)
            if let imageData = try? Data(contentsOf: photoURL),
               let loadedImage = UIImage(data: imageData) {
                DispatchQueue.main.async {
                    self.image = loadedImage
                    self.isLoading = false
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }
    }
    
    private func loadPhotoFromPHAsset(_ filename: String) {
        // Extract the actual PHAsset localIdentifier
        let assetIdentifier = filename.hasPrefix("temp_") ? String(filename.dropFirst(5)) : filename
        
        // Fetch the PHAsset
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else { 
            DispatchQueue.main.async {
                self.isLoading = false
            }
            return 
        }
        
        // Load the thumbnail
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        
        let targetSize = CGSize(width: 120, height: 120) // 2x for retina
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, info in
            DispatchQueue.main.async {
                if let image = image {
                    self.image = image
                }
                self.isLoading = false
            }
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

// MARK: - Trip Photo Picker View
struct TripPhotoPickerView: View {
    let trip: Trip
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var photos: [PHAsset] = []
    @State private var selectedPhotos: [PHAsset] = []
    @State private var isLoading = true
    @State private var hasPhotoLibraryAccess = false
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("Loading photos...")
                } else if !hasPhotoLibraryAccess {
                    Text("Photo Library Access Denied")
                        .foregroundColor(.red)
                        .padding()
                    Text("Please enable photo access in Settings to add photos.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                } else if photos.isEmpty {
                    Text("No photos found for this trip's dates.")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                            ForEach(photos, id: \.localIdentifier) { asset in
                                TripPhotoAssetView(
                                    asset: asset,
                                    isSelected: selectedPhotos.contains(where: { $0.localIdentifier == asset.localIdentifier }),
                                    isDisabled: isPhotoAlreadyAdded(asset)
                                ) {
                                    if isPhotoAlreadyAdded(asset) {
                                        // Do nothing if already added
                                    } else if selectedPhotos.contains(where: { $0.localIdentifier == asset.localIdentifier }) {
                                        selectedPhotos.removeAll(where: { $0.localIdentifier == asset.localIdentifier })
                                    } else {
                                        selectedPhotos.append(asset)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Add Trip Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add (\(selectedPhotos.count))") {
                        addSelectedPhotos()
                    }
                    .disabled(selectedPhotos.isEmpty)
                }
            }
            .onAppear(perform: loadPhotos)
        }
    }
    
    private func checkPhotoLibraryPermission() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                self.hasPhotoLibraryAccess = status == .authorized
                if status == .authorized {
                    loadPhotos()
                } else {
                    self.isLoading = false
                }
            }
        }
    }
    
    private func loadPhotos() {
        isLoading = true
        hasPhotoLibraryAccess = false
        
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                self.hasPhotoLibraryAccess = status == .authorized
                guard status == .authorized else {
                    self.isLoading = false
                    return
                }
                
                let fetchOptions = PHFetchOptions()
                fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                
                var allAssets: [PHAsset] = []
                
                // Fetch images
                let imageAssets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
                imageAssets.enumerateObjects { (asset, _, _) in
                    if let creationDate = asset.creationDate,
                       let startDate = trip.startDate,
                       let endDate = trip.endDate,
                       creationDate >= startDate && creationDate <= endDate.addingTimeInterval(24*60*60) {
                        allAssets.append(asset)
                    }
                }
                
                // Fetch videos
                let videoAssets = PHAsset.fetchAssets(with: .video, options: fetchOptions)
                videoAssets.enumerateObjects { (asset, _, _) in
                    if let creationDate = asset.creationDate,
                       let startDate = trip.startDate,
                       let endDate = trip.endDate,
                       creationDate >= startDate && creationDate <= endDate.addingTimeInterval(24*60*60) {
                        allAssets.append(asset)
                    }
                }
                
                self.photos = allAssets.sorted { ($0.creationDate ?? Date.distantPast) > ($1.creationDate ?? Date.distantPast) }
                self.isLoading = false
                
                // Remove any already added photos from selection when photos load
                self.selectedPhotos.removeAll { asset in
                    self.isPhotoAlreadyAdded(asset)
                }
            }
        }
    }
    
    private func isPhotoAlreadyAdded(_ asset: PHAsset) -> Bool {
        guard let tripDays = trip.tripDays as? Set<TripDay> else { return false }
        
        for tripDay in tripDays {
            if let photosInDay = tripDay.photos as? Set<Photo> {
                for coreDataPhoto in photosInDay {
                    if let storedIdentifier = coreDataPhoto.assetIdentifier {
                        if storedIdentifier == asset.localIdentifier {
                            return true
                        }
                    }
                }
            }
        }
        return false
    }
    
    private func addSelectedPhotos() {
        guard !selectedPhotos.isEmpty else { return }
        
        Task {
            var results: [PhotoProcessingResult] = []
            
            for asset in selectedPhotos {
                let result = await processPhotoAsset(asset)
                results.append(result)
            }
            
            await MainActor.run {
                // Show results and dismiss
                dismiss()
                NotificationCenter.default.post(name: .photosAddedToTripDay, object: nil)
            }
        }
    }
    
    private func processPhotoAsset(_ asset: PHAsset) async -> PhotoProcessingResult {
        guard let creationDate = asset.creationDate else {
            return PhotoProcessingResult(asset: asset, success: false, message: "No creation date", assignedDay: nil)
        }
        
        // Find the correct trip day for this photo
        guard let tripDays = trip.tripDays as? Set<TripDay> else {
            return PhotoProcessingResult(asset: asset, success: false, message: "No trip days found", assignedDay: nil)
        }
        
        let sortedTripDays = tripDays.sorted { ($0.date ?? Date.distantPast) < ($1.date ?? Date.distantPast) }
        
        guard let tripDay = sortedTripDays.first(where: { day in
            guard let dayDate = day.date else { return false }
            let calendar = Calendar.current
            return calendar.isDate(creationDate, inSameDayAs: dayDate)
        }) else {
            return PhotoProcessingResult(asset: asset, success: false, message: "No matching trip day found", assignedDay: nil)
        }
        
        // Check for duplicates again right before saving (race condition prevention)
        if isPhotoAlreadyAdded(asset) {
            return PhotoProcessingResult(asset: asset, success: false, message: "Already added", assignedDay: tripDay)
        }
        
        // Save the photo
        do {
            let photo = Photo(context: viewContext)
            photo.id = UUID()
            photo.filename = "photo_\(UUID().uuidString).jpg"
            photo.mediaType = asset.mediaType == .video ? "video" : "photo"
            photo.caption = ""
            photo.createdDate = Date()
            photo.assetIdentifier = asset.localIdentifier
            photo.photoDate = creationDate
            photo.order = Int32((tripDay.photos?.count ?? 0))
            photo.tripDay = tripDay
            
            // Save the actual media file
            let fileManager = FileManager.default
            let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            let fileURL = documentsDirectory.appendingPathComponent(photo.filename!)
            
            if asset.mediaType == .video {
                let videoOptions = PHVideoRequestOptions()
                videoOptions.deliveryMode = .highQualityFormat
                videoOptions.isNetworkAccessAllowed = true
                
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    PHImageManager.default().requestAVAsset(forVideo: asset, options: videoOptions) { avAsset, audioMix, info in
                        if let urlAsset = avAsset as? AVURLAsset {
                            do {
                                let videoData = try Data(contentsOf: urlAsset.url)
                                try videoData.write(to: fileURL)
                                continuation.resume(returning: ())
                            } catch {
                                print("Error saving video: \(error.localizedDescription)")
                                continuation.resume(returning: ())
                            }
                        } else {
                            print("Error loading video asset")
                            continuation.resume(returning: ())
                        }
                    }
                }
            } else {
                let imageOptions = PHImageRequestOptions()
                imageOptions.deliveryMode = .highQualityFormat
                imageOptions.isNetworkAccessAllowed = true
                imageOptions.isSynchronous = false
                
                await withCheckedContinuation { (continuation: CheckedContinuation<Data, Never>) in
                    PHImageManager.default().requestImage(
                        for: asset,
                        targetSize: PHImageManagerMaximumSize,
                        contentMode: .aspectFit,
                        options: imageOptions
                    ) { image, info in
                        if let image = image,
                           let imageData = image.jpegData(compressionQuality: 0.8) {
                            continuation.resume(returning: imageData)
                        } else {
                            continuation.resume(returning: Data())
                        }
                    }
                }
            }
            
            try viewContext.save()
            
            return PhotoProcessingResult(
                asset: asset,
                success: true,
                message: "Added to \(tripDay.date?.formatted(date: .abbreviated, time: .omitted) ?? "trip day")",
                assignedDay: tripDay
            )
        } catch {
            print("Error saving photo: \(error.localizedDescription)")
            return PhotoProcessingResult(asset: asset, success: false, message: "Save failed: \(error.localizedDescription)", assignedDay: nil)
        }
    }
}

// MARK: - Supporting Models
struct PhotoProcessingResult {
    let asset: PHAsset
    let success: Bool
    let message: String
    let assignedDay: TripDay?
}

enum PhotoLoadingError: Error, LocalizedError {
    case failedToLoad
    
    var errorDescription: String? {
        switch self {
        case .failedToLoad:
            return "Failed to load photo"
        }
    }
}

// MARK: - Trip Photo Asset View
struct TripPhotoAssetView: View {
    let asset: PHAsset
    let isSelected: Bool
    let isDisabled: Bool
    let onTap: () -> Void
    
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var hasError = false
    
    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 100, height: 100)
                    .clipped()
                    .cornerRadius(8)
                    .overlay(
                        // Gray overlay for disabled photos
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isDisabled ? Color.black.opacity(0.6) : Color.clear)
                    )
            } else if hasError {
                // Show error state
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemRed).opacity(0.3))
                    .frame(width: 100, height: 100)
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.red)
                                .font(.caption)
                            Text("Error")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                    )
            } else {
                // Show loading state
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 100, height: 100)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.8)
                    )
            }
            
            // Checkmark indicators - prioritize disabled state over selection
            if isDisabled {
                // Already added indicator (green checkmark)
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.white)
                            .background(Color.green)
                            .clipShape(Circle())
                            .font(.title2)
                    }
                    Spacer()
                }
                    .padding(4)
            } else if isSelected {
                // Selection indicator (blue checkmark) - only show if not disabled
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.white)
                            .background(Color.blue)
                            .clipShape(Circle())
                            .font(.title2)
                    }
                    Spacer()
                }
                    .padding(4)
            } else {
                // Plus symbol for selectable photos (not disabled, not selected)
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.white)
                            .background(Color.blue)
                            .clipShape(Circle())
                            .font(.title2)
                    }
                    Spacer()
                }
                    .padding(4)
            }
        }
        .onTapGesture(perform: onTap)
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        isLoading = true
        hasError = false
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 100, height: 100),
            contentMode: .aspectFill,
            options: options
        ) { image, info in
            DispatchQueue.main.async {
                if let image = image {
                    self.image = image
                    self.isLoading = false
                } else {
                    self.hasError = true
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - Trip Photos View
struct TripPhotosView: View {
    let trip: Trip
    
    var sortedDays: [TripDay] {
        trip.tripDays?.allObjects as? [TripDay] ?? []
    }
    
    var body: some View {
        if sortedDays.isEmpty {
            Text("No photos added yet")
                .foregroundColor(.secondary)
                .italic()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
        } else {
            ScrollView {
                LazyVStack(spacing: 20) {
                    ForEach(sortedDays.sorted { $0.order < $1.order }) { day in
                        DayPhotosSection(day: day)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

struct DayPhotosSection: View {
    let day: TripDay
    
    var dayPhotos: [Photo] {
        day.photos?.allObjects as? [Photo] ?? []
    }
    
    var body: some View {
        if !dayPhotos.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                // Day header
                HStack {
                    Text(day.date?.formatted(date: .complete, time: .omitted) ?? "Unknown Date")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text("\(dayPhotos.count) photo\(dayPhotos.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
                
                // Photos grid
                PhotosGrid(photos: dayPhotos)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        }
    }
}

struct PhotosGrid: View {
    let photos: [Photo]
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(photos.sorted { $0.order < $1.order }) { photo in
                TripPhotoThumbnailView(photo: photo)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .cornerRadius(8)
            }
        }
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
