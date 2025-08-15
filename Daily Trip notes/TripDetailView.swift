import SwiftUI
import CoreData
import Photos
import MapKit
import Foundation
import AVFoundation

enum ViewMode {
    case dates
    case photos
    case map
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
                VStack(alignment: .leading, spacing: 12) {
                    Text("Feature Photo")
                        .font(.headline)
                    
                    TripFeaturePhotoView(filename: featurePhotoFilename)
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .cornerRadius(12)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            

            
            // View Mode Selector
            Section {
                Picker("View Mode", selection: $viewMode) {
                    Text("Dates").tag(ViewMode.dates)
                    Text("Photos").tag(ViewMode.photos)
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
            } else if viewMode == .map {
                Section("Trip Map") {
                    TripMapView(trip: trip)
                        .frame(height: 400)
                        .listRowInsets(EdgeInsets())
                }
            } else if viewMode == .photos {
                TripPhotosView(trip: trip)
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
                    Menu {
                        Button("Edit Trip") {
                            showingEditTrip = true
                        }
                        
                        Button("Add Photos to Trip") {
                            showingTripPhotoPicker = true
                        }
                    } label: {
                        Image(systemName: "ellipsis")
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
            // Refresh when photos are added to any day in this trip
            // The notification might not contain a specific tripDay object
            // but we know photos were added to this trip
            print("TripDetailView: Received photosAddedToTripDay notification, refreshing...")
            refreshTrigger.toggle() // Force refresh to show new photos
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
        let _ = print("DayRowView: tripDay.photos count: \(photos.count)")
        
        // Filter photos to only show those taken on this specific day
        let dayStart = Calendar.current.startOfDay(for: tripDay.date ?? Date())
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        
        let filteredPhotos = photos.filter { photo in
            let photoDate = photo.photoDate ?? photo.createdDate ?? Date()
            return photoDate >= dayStart && photoDate < dayEnd
        }
        
        let _ = print("DayRowView: filteredPhotos count: \(filteredPhotos.count)")
        
        return filteredPhotos.sorted { $0.order < $1.order }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            }
            
            // Photo thumbnails below the text
            let _ = print("TripDetailView: sortedPhotos count: \(sortedPhotos.count)")
            let _ = print("TripDetailView: sortedPhotos isEmpty: \(sortedPhotos.isEmpty)")
            
            if !sortedPhotos.isEmpty {
                let _ = print("TripDetailView: Creating photo thumbnails")
                HStack(spacing: 8) {
                    ForEach(Array(sortedPhotos.prefix(3)), id: \.id) { photo in
                        let _ = print("TripDetailView: Creating TripPhotoThumbnailView for photo: \(photo.filename ?? "nil")")
                        TripPhotoThumbnailView(photo: photo, onPhotoDeleted: {})
                            .frame(width: 60, height: 60)
                            .clipped()
                            .cornerRadius(8)
                    }
                    
                    if sortedPhotos.count > 3 {
                        Text("+\(sortedPhotos.count - 3)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 60, height: 60)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }
                }
            } else {
                let _ = print("TripDetailView: No photos to display")
            }
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
                                    TripPhotoThumbnailView(photo: photo, onPhotoDeleted: {})
                                        .frame(width: 100, height: 100)
                                        .aspectRatio(contentMode: .fill)
                                        .clipped()
                                        .cornerRadius(8)
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
            photo.assetIdentifier = asset.localIdentifier // Add the asset identifier for proper loading
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
    @State private var isLoading = true
    @State private var hasError = false

    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .cornerRadius(12)
            } else if isLoading {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray5))
                    .frame(maxWidth: .infinity)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.8)
                    )
            } else if hasError {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemRed).opacity(0.3))
                    .frame(maxWidth: .infinity)
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
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray5))
                    .frame(maxWidth: .infinity)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                            .font(.title2)
                    )
            }
        }
        .task {
            await loadPhoto()
        }
    }

    private func loadPhoto() async {
        PhotoLoader.shared.loadPhoto(
            filename: filename,
            assetIdentifier: nil,
            mediaType: "photo"
        ) { image, isLoading, hasError in
            Task { @MainActor in
                self.image = image
                self.isLoading = isLoading
                self.hasError = hasError
            }
        }
    }
}

struct TripPhotoThumbnailView: View {
    let photo: Photo
    let onPhotoDeleted: () -> Void
    @State private var image: UIImage?
    @State private var showingDeleteAlert = false
    @State private var showingVideoPlayer = false
    @State private var showingFullScreenPhoto = false
    @State private var isLoading = true
    @State private var hasError = false
    @Environment(\.managedObjectContext) private var viewContext
    
    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
                    .cornerRadius(6)
            } else if isLoading {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemGray5))
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.6)
                    )
            } else if hasError {
                // Show error state
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemRed).opacity(0.3))
                    .overlay(
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.red)
                            .font(.caption)
                    )
            } else {
                // Show placeholder when not loading and no image
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemGray4))
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                            .font(.title2)
                    )
            }
            
            // Video indicator
            if photo.mediaType == "video" {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "play.circle.fill")
                            .foregroundColor(.white)
                            .background(Color.blue)
                            .clipShape(Circle())
                            .font(.title2)
                            .padding(4)
                    }
                }
            }
        }
        .onTapGesture {
            if photo.mediaType == "video" {
                showingVideoPlayer = true
            } else {
                showingFullScreenPhoto = true
            }
        }
        .onLongPressGesture {
            showingDeleteAlert = true
        }
        .alert("Delete Media", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                deletePhoto()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this \(photo.mediaType ?? "media")? This action cannot be undone.")
        }
        .sheet(isPresented: $showingVideoPlayer) {
            if let filename = photo.filename {
                VideoPlayerView(filename: filename)
            }
        }
        .sheet(isPresented: $showingFullScreenPhoto) {
            // Get the photos from the parent view context
            if let trip = photo.tripDay?.trip {
                let allPhotos = trip.tripDays?.compactMap { $0 as? TripDay }
                    .flatMap { $0.photos?.compactMap { $0 as? Photo } ?? [] } ?? []
                if let currentIndex = allPhotos.firstIndex(of: photo) {
                    FullScreenPhotoView(photos: allPhotos, currentIndex: currentIndex, onPhotoDeleted: onPhotoDeleted)
                } else {
                    FullScreenPhotoView(photo: photo, onPhotoDeleted: onPhotoDeleted)
                }
            } else {
                FullScreenPhotoView(photo: photo, onPhotoDeleted: onPhotoDeleted)
            }
        }
        .task {
            await loadPhoto()
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
    
    private func loadPhoto() async {
        guard let filename = photo.filename else { 
            DispatchQueue.main.async {
                self.isLoading = false
                self.hasError = true
            }
            return 
        }
        
        // Handle videos differently - generate thumbnail
        if photo.mediaType == "video" {
            await generateVideoThumbnail(filename: filename)
        } else {
            // Use the unified PhotoLoader for photos
            PhotoLoader.shared.loadPhoto(
                filename: filename,
                assetIdentifier: photo.assetIdentifier,
                mediaType: photo.mediaType
            ) { image, isLoading, hasError in
                Task { @MainActor in
                    self.image = image
                    self.isLoading = isLoading
                    self.hasError = hasError
                }
            }
        }
    }
    
    private func generateVideoThumbnail(filename: String) async {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { 
            await MainActor.run {
                self.isLoading = false
                self.hasError = true
            }
            return 
        }
        let videoURL = documentsPath.appendingPathComponent(filename)
        
        // First try: Use AVAssetImageGenerator with more flexible options
        do {
            let asset = AVAsset(url: videoURL)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: 200, height: 200)
            
            // Try to generate thumbnail at the beginning
            let result = try await imageGenerator.image(at: .zero)
            await MainActor.run {
                self.image = UIImage(cgImage: result.image)
                self.isLoading = false
                self.hasError = false
            }
            return
        } catch {
            print("AVAssetImageGenerator failed: \(error)")
        }
        
        // Second try: Try with PHAsset if we have an asset identifier
        if let assetIdentifier = photo.assetIdentifier {
            await generateThumbnailFromPHAsset(assetIdentifier)
            return
        }
        
        // Third try: Try to extract thumbnail using AVAsset with different approach
        do {
            let asset = AVAsset(url: videoURL)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: 100, height: 100)
            
            // Try to get a frame from a different time position
            let duration = try await asset.load(.duration)
            let timePosition = CMTime(seconds: min(duration.seconds / 2, 1.0), preferredTimescale: 600)
            
            let result = try await imageGenerator.image(at: timePosition)
            await MainActor.run {
                self.image = UIImage(cgImage: result.image)
                self.isLoading = false
                self.hasError = false
            }
            return
        } catch {
            print("Second AVAssetImageGenerator attempt failed: \(error)")
        }
        
        // Final fallback: Show a video placeholder
        await MainActor.run {
            self.isLoading = false
            self.hasError = false
            // Create a simple video placeholder image
            self.createVideoPlaceholder()
        }
    }
    
    private func generateThumbnailFromPHAsset(_ assetIdentifier: String) async {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else {
            await MainActor.run {
                self.isLoading = false
                self.hasError = true
            }
            return
        }
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        
        let targetSize = CGSize(width: 200, height: 200)
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, info in
            Task { @MainActor in
                if let image = image {
                    self.image = image
                    self.isLoading = false
                    self.hasError = false
                } else {
                    self.isLoading = false
                    self.hasError = true
                }
            }
        }
    }
    
    private func createVideoPlaceholder() {
        // Create a simple video placeholder with play button
        let size = CGSize(width: 100, height: 100)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let placeholderImage = renderer.image { context in
            // Background
            UIColor.systemGray5.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            
            // Play button
            let playButtonSize: CGFloat = 40
            let playButtonRect = CGRect(
                x: (size.width - playButtonSize) / 2,
                y: (size.height - playButtonSize) / 2,
                width: playButtonSize,
                height: playButtonSize
            )
            
            UIColor.blue.setFill()
            context.cgContext.fillEllipse(in: playButtonRect)
            
            // Play triangle
            let trianglePath = UIBezierPath()
            trianglePath.move(to: CGPoint(x: playButtonRect.midX + 8, y: playButtonRect.midY))
            trianglePath.addLine(to: CGPoint(x: playButtonRect.midX - 8, y: playButtonRect.midY - 8))
            trianglePath.addLine(to: CGPoint(x: playButtonRect.midX - 8, y: playButtonRect.midY + 8))
            trianglePath.close()
            
            UIColor.white.setFill()
            trianglePath.fill()
        }
        
        self.image = placeholderImage
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
        Map {
            ForEach(photoAnnotations) { annotation in
                Annotation(annotation.title, coordinate: annotation.coordinate) {
                    PhotoAnnotationView(annotation: annotation)
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

struct PhotoAnnotationView: View {
    let annotation: PhotoAnnotation
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var showingFullScreenPhoto = false
    
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
            Task {
                await loadPhotoThumbnail()
            }
        }
        .onTapGesture {
            showingFullScreenPhoto = true
        }
        .sheet(isPresented: $showingFullScreenPhoto) {
            // Get the photos from the parent view context
            if let trip = annotation.photo.tripDay?.trip {
                let allPhotos = trip.tripDays?.compactMap { $0 as? TripDay }
                    .flatMap { $0.photos?.compactMap { $0 as? Photo } ?? [] } ?? []
                if let currentIndex = allPhotos.firstIndex(of: annotation.photo) {
                    FullScreenPhotoView(photos: allPhotos, currentIndex: currentIndex, onPhotoDeleted: {
                        // Refresh the map annotations after deletion
                        // This will be handled by the parent view's refresh logic
                    })
                } else {
                    FullScreenPhotoView(photo: annotation.photo, onPhotoDeleted: {
                        // Refresh the map annotations after deletion
                        // This will be handled by the parent view's refresh logic
                    })
                }
            } else {
                FullScreenPhotoView(photo: annotation.photo, onPhotoDeleted: {
                    // Refresh the map annotations after deletion
                    // This will be handled by the parent view's refresh logic
                })
            }
        }
    }
    
    private func loadPhotoThumbnail() async {
        guard let filename = annotation.photo.filename else { return }
        
        // Handle videos differently - generate thumbnail
        if annotation.photo.mediaType == "video" {
            await generateVideoThumbnail(filename: filename)
            return
        }
        
        // Use unified photo loader for consistency
        PhotoLoader.shared.loadPhoto(
            filename: annotation.photo.filename,
            assetIdentifier: annotation.photo.assetIdentifier,
            mediaType: annotation.photo.mediaType
        ) { image, isLoading, hasError in
            Task { @MainActor in
                self.image = image
                self.isLoading = isLoading
            }
        }
    }
    
    private func generateVideoThumbnail(filename: String) async {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { 
            await MainActor.run {
                self.isLoading = false
            }
            return 
        }
        let videoURL = documentsPath.appendingPathComponent(filename)
        
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        do {
            let result = try await imageGenerator.image(at: .zero)
            await MainActor.run {
                self.image = UIImage(cgImage: result.image)
                self.isLoading = false
            }
        } catch {
            print("Failed to generate video thumbnail: \(error)")
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
}

struct FullScreenPhotoView: View {
    let photos: [Photo]
    let currentIndex: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var showingVideoPlayer = false
    @State private var currentPhotoIndex: Int
    @State private var dragOffset: CGFloat = 0
    @State private var showingDeleteAlert = false
    @State private var onPhotoDeleted: (() -> Void)?
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    init(photos: [Photo], currentIndex: Int, onPhotoDeleted: (() -> Void)? = nil) {
        self.photos = photos
        self.currentIndex = currentIndex
        self._currentPhotoIndex = State(initialValue: currentIndex)
        self.onPhotoDeleted = onPhotoDeleted
    }
    
    // Convenience initializer for single photo (backward compatibility)
    init(photo: Photo, onPhotoDeleted: (() -> Void)? = nil) {
        self.photos = [photo]
        self.currentIndex = 0
        self._currentPhotoIndex = State(initialValue: 0)
        self.onPhotoDeleted = onPhotoDeleted
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .scaleEffect(scale)
                        .offset(x: offset.width + dragOffset, y: offset.height)
                        .gesture(
                            // Pinch to zoom
                            MagnificationGesture()
                                .onChanged { value in
                                    let delta = value / lastScale
                                    lastScale = value
                                    scale = min(max(scale * delta, 1.0), 4.0)
                                }
                                .onEnded { _ in
                                    lastScale = 1.0
                                    // Snap to bounds if over-zoomed
                                    if scale < 1.0 {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            scale = 1.0
                                            offset = .zero
                                        }
                                    }
                                }
                        )
                        .gesture(
                            // Pan gesture for zoomed image
                            DragGesture()
                                .onChanged { value in
                                    if scale > 1.0 {
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    } else {
                                        // Only track horizontal movement for photo navigation when not zoomed
                                        dragOffset = value.translation.width
                                    }
                                }
                                .onEnded { value in
                                    if scale > 1.0 {
                                        lastOffset = offset
                                    } else {
                                        let horizontalThreshold: CGFloat = 100
                                        let verticalThreshold: CGFloat = 150
                                        
                                        // Check if it's primarily a horizontal or vertical swipe
                                        let horizontalDistance = abs(value.translation.width)
                                        let verticalDistance = abs(value.translation.height)
                                        
                                        if horizontalDistance > verticalDistance {
                                            // Horizontal swipe - navigate between photos
                                            if value.translation.width > horizontalThreshold && currentPhotoIndex > 0 {
                                                // Swipe right - go to previous photo
                                                currentPhotoIndex -= 1
                                                loadCurrentPhoto()
                                            } else if value.translation.width < -horizontalThreshold && currentPhotoIndex < photos.count - 1 {
                                                // Swipe left - go to next photo
                                                currentPhotoIndex += 1
                                                loadCurrentPhoto()
                                            }
                                        } else if verticalDistance > verticalThreshold {
                                            // Vertical swipe - close the sheet
                                            if value.translation.height > 0 {
                                                // Swipe down - close
                                                dismiss()
                                            }
                                        }
                                        
                                        // Reset offset with animation
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            dragOffset = 0
                                        }
                                    }
                                }
                        )
                        .onTapGesture(count: 2) {
                            // Double tap to zoom in/out
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if scale > 1.0 {
                                    scale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    scale = 2.0
                                }
                            }
                        }
                } else if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .foregroundColor(.white)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "photo")
                            .font(.system(size: 60))
                            .foregroundColor(.white)
                        Text("Photo not available")
                            .foregroundColor(.white)
                            .font(.headline)
                    }
                }
                
                // Video indicator and play button
                if photos[currentPhotoIndex].mediaType == "video" {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: {
                                showingVideoPlayer = true
                            }) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 80))
                                    .foregroundColor(.white)
                                    .background(Color.blue)
                                    .clipShape(Circle())
                            }
                            .padding(.bottom, 100)
                            .padding(.trailing, 30)
                        }
                    }
                }
                
                // Photo counter (only show if there are multiple photos)
                if photos.count > 1 {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text("\(currentPhotoIndex + 1) of \(photos.count)")
                                .foregroundColor(.white)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(12)
                                .padding(.bottom, 100)
                        }
                    }
                }
            }
            .navigationTitle("Photo")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                
                if photos[currentPhotoIndex].mediaType == "video" {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Play") {
                            showingVideoPlayer = true
                        }
                        .foregroundColor(.white)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingDeleteAlert = true
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .sheet(isPresented: $showingVideoPlayer) {
            if let filename = photos[currentPhotoIndex].filename {
                VideoPlayerView(filename: filename)
            }
        }
        .alert("Delete Photo", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                deleteCurrentPhoto()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this photo? This action cannot be undone.")
        }
        .task {
            loadCurrentPhoto()
        }
    }
    
    private func loadCurrentPhoto() {
        let currentPhoto = photos[currentPhotoIndex]
        guard let filename = currentPhoto.filename else { return }
        
        // Reset loading state and zoom
        isLoading = true
        image = nil
        scale = 1.0
        offset = .zero
        lastOffset = .zero
        
        // Handle videos differently
        if currentPhoto.mediaType == "video" {
            isLoading = false
            return
        }
        
        // Use unified photo loader for consistency
        PhotoLoader.shared.loadPhoto(
            filename: filename,
            assetIdentifier: currentPhoto.assetIdentifier,
            mediaType: currentPhoto.mediaType
        ) { image, isLoading, hasError in
            Task { @MainActor in
                self.image = image
                self.isLoading = isLoading
            }
        }
    }
    
    private func deleteCurrentPhoto() {
        let currentPhoto = photos[currentPhotoIndex]
        onPhotoDeleted?() // Notify parent view
        
        // Delete the photo file from storage
        if let filename = currentPhoto.filename {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            let fileURL = documentsPath?.appendingPathComponent(filename)
            
            if let fileURL = fileURL {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        
        // Remove from Core Data
        viewContext.delete(currentPhoto)
        
        // Save changes
        try? viewContext.save()
        
        // Dismiss the sheet
        dismiss()
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
    @State private var isAddingPhotos = false
    @State private var addingProgress = 0
    @State private var totalPhotosToAdd = 0
    
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
                } else if isAddingPhotos {
                    // Show loading state when adding photos
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        
                        Text("Adding Photos...")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("\(addingProgress) of \(totalPhotosToAdd) photos processed")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        ProgressView(value: Double(addingProgress), total: Double(totalPhotosToAdd))
                            .progressViewStyle(LinearProgressViewStyle())
                            .frame(width: 200)
                        
                        Text("This may take a while for large photos or iCloud photos")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    HStack(spacing: 16) {
                        // Select All button - only show if there are photos to select
                        if !photos.isEmpty {
                            Button("Select All") {
                                selectAllAvailablePhotos()
                            }
                            .disabled(selectedPhotos.count == getAvailablePhotosCount())
                        }
                        
                        Button("Add (\(selectedPhotos.count))") {
                            addSelectedPhotos()
                        }
                        .disabled(selectedPhotos.isEmpty)
                    }
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
    
    private func getAvailablePhotosCount() -> Int {
        // Count photos that aren't already added
        return photos.filter { !isPhotoAlreadyAdded($0) }.count
    }
    
    private func selectAllAvailablePhotos() {
        // Use the existing photos array which already has the correct date range
        let availablePhotos = photos.filter { !isPhotoAlreadyAdded($0) }
        
        // Clear current selection and add all available photos
        selectedPhotos = availablePhotos
        
        print("TripPhotoPickerView: Selected all \(availablePhotos.count) available photos for trip dates")
    }
    
    private func addSelectedPhotos() {
        guard !selectedPhotos.isEmpty else { return }
        
        // Set up loading state
        isAddingPhotos = true
        addingProgress = 0
        totalPhotosToAdd = selectedPhotos.count
        
        Task {
            var results: [PhotoProcessingResult] = []
            
            for (index, asset) in selectedPhotos.enumerated() {
                let result = await processPhotoAsset(asset)
                results.append(result)
                
                // Update progress
                await MainActor.run {
                    addingProgress = index + 1
                }
            }
            
            await MainActor.run {
                // Reset loading state and dismiss
                isAddingPhotos = false
                addingProgress = 0
                totalPhotosToAdd = 0
                
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
                
                let imageData = await withCheckedContinuation { (continuation: CheckedContinuation<Data, Never>) in
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
                
                // Save the image data to file
                try imageData.write(to: fileURL)
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
                        // Light overlay for disabled photos (already added)
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isDisabled ? Color.white.opacity(0.7) : Color.clear)
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
            
            // Checkmark indicators - only show for selection, not for disabled photos
            if isSelected {
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
            } else if !isDisabled {
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
            // No indicator for disabled photos - they're already dark enough
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
                LazyVStack(spacing: 16) {
                    ForEach(sortedDays.sorted { $0.order < $1.order }) { day in
                        DayPhotosSection(day: day)
                    }
                }
                .padding(.horizontal, 8)
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
            VStack(alignment: .leading, spacing: 6) {
                // Day header - full width with day name
                VStack(alignment: .leading, spacing: 4) {
                    Text(day.date?.formatted(.dateTime.weekday(.wide).month().day().year()) ?? "Unknown Date")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text("\(dayPhotos.count) photo\(dayPhotos.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray6))
                        .cornerRadius(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Photos grid
                PhotosGrid(photos: dayPhotos)
            }
        }
    }
}

struct PhotosGrid: View {
    let photos: [Photo]
    
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            ForEach(photos.sorted { $0.order < $1.order }) { photo in
                TripPhotoThumbnailView(photo: photo, onPhotoDeleted: {})
                    .frame(width: 100, height: 100)
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
