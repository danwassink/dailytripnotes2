import SwiftUI
import PhotosUI
import CoreData
import ImageIO
import Photos
import AVFoundation
import AVKit
import Foundation

struct DayDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    let tripDay: TripDay
    @State private var journalContent: String = ""
    @State private var showingPhotoPicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photosAdded = false
    @State private var photosDeleted = false
    @State private var isProcessing = false
    @State private var showingCustomPhotoPicker = false
    @State private var showingJournalEditor = false
    
    var sortedPhotos: [Photo] {
        let photos = tripDay.photos?.allObjects as? [Photo] ?? []
        
        // Debug logging
        print("DayDetailView: Trip day date: \(tripDay.date ?? Date())")
        print("DayDetailView: Total photos found: \(photos.count)")
        
        // Debug: Show details of each photo
        for (index, photo) in photos.enumerated() {
            print("DayDetailView: Photo \(index): id=\(photo.id?.uuidString ?? "nil"), photoDate=\(photo.photoDate ?? Date()), createdDate=\(photo.createdDate ?? Date()), tripDay=\(photo.tripDay?.date ?? Date())")
        }
        
        // Filter photos to only show those taken on this specific day
        let dayStart = Calendar.current.startOfDay(for: tripDay.date ?? Date())
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        
        print("DayDetailView: Day start: \(dayStart)")
        print("DayDetailView: Day end: \(dayEnd)")
        
        let filteredPhotos = photos.filter { photo in
            let photoDate = photo.photoDate ?? photo.createdDate ?? Date()
            
            let isInDay = photoDate >= dayStart && photoDate < dayEnd
            print("DayDetailView: Photo date: \(photoDate), isInDay: \(isInDay)")
            return isInDay
        }
        
        print("DayDetailView: Filtered photos count: \(filteredPhotos.count)")
        
        return filteredPhotos.sorted { $0.order < $1.order }
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
            
            // Media Section
            Section("Media") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                    ForEach(sortedPhotos, id: \.id) { photo in
                        PhotoThumbnailView(photo: photo, onPhotoDeleted: {
                            photosDeleted.toggle() // Force refresh when photo is deleted
                        })
                    }
                    
                    // Add Photos Button - Custom Date-Filtered Picker
                    Button(action: {
                        showingCustomPhotoPicker = true
                    }) {
                        VStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.blue)
                            Text("Add Media")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        .frame(width: 100, height: 100)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                    .sheet(isPresented: $showingCustomPhotoPicker) {
                        CustomPhotoPickerView(tripDay: tripDay, onPhotosSelected: { selectedAssets in
                            processSelectedPHAssets(selectedAssets)
                        })
                    }
                }
                .padding(.vertical, 8)
            }
            .id("\(photosAdded)-\(photosDeleted)") // Force refresh when photos are added or deleted
            
            // Journal entry section
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Journal Entry")
                        .font(.headline)
                    Spacer()
                    Button(journalContent.isEmpty ? "Add" : "Edit") {
                        showingJournalEditor = true
                    }
                    .foregroundColor(.blue)
                }
                .padding(.horizontal, 20)
                
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
            
            Spacer()
        }
        .navigationTitle("Day Details")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingJournalEditor) {
            JournalEntryView(tripDay: tripDay) {
                loadJournalContent() // Refresh the content when journal is saved
            }
        }
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
    

    
    private func processSelectedPhotos(_ photos: [PhotosPickerItem]) {
        print("DayDetailView: Processing \(photos.count) selected photos")
        isProcessing = true
        
        Task {
            for (index, photoItem) in photos.enumerated() {
                print("DayDetailView: Processing photo \(index + 1) of \(photos.count)")
                if let data = try? await photoItem.loadTransferable(type: Data.self) {
                    print("DayDetailView: Successfully loaded photo data, size: \(data.count) bytes")
                    await MainActor.run {
                        saveMedia(data: data, order: index, mediaType: "photo")
                    }
                } else {
                    print("DayDetailView: Failed to load photo data for photo \(index + 1)")
                }
            }
            
            await MainActor.run {
                isProcessing = false
                photosAdded.toggle() // Force view refresh
                selectedPhotos.removeAll() // Clear selection
                print("DayDetailView: Finished processing photos, photosAdded toggled to: \(photosAdded)")
            }
        }
    }
    
    private func processSelectedPHAssets(_ assets: [PHAsset]) {
        print("DayDetailView: Processing \(assets.count) selected PHAssets")
        isProcessing = true
        
        Task {
            for (index, asset) in assets.enumerated() {
                print("DayDetailView: Processing PHAsset \(index + 1) of \(assets.count)")
                
                let data = await loadMediaDataFromAsset(asset)
                if let data = data {
                    let mediaType = asset.mediaType == PHAssetMediaType.video ? "video" : "photo"
                    print("DayDetailView: Successfully loaded \(mediaType) data, size: \(data.count) bytes")
                    await MainActor.run {
                        saveMedia(data: data, order: index, mediaType: mediaType)
                    }
                } else {
                    print("DayDetailView: Failed to load PHAsset data for asset \(index + 1)")
                }
            }
            
            await MainActor.run {
                isProcessing = false
                photosAdded.toggle() // Force view refresh
                print("DayDetailView: Finished processing PHAssets, photosAdded toggled to: \(photosAdded)")
            }
        }
    }
    
    private func loadMediaDataFromAsset(_ asset: PHAsset) async -> Data? {
        return await withCheckedContinuation { continuation in
            if asset.mediaType == PHAssetMediaType.video {
                // For videos, use PHVideoRequestOptions
                let options = PHVideoRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.isNetworkAccessAllowed = false
                options.version = .current
                
                PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                    if let avAsset = avAsset as? AVURLAsset {
                        // Read the video file data
                        do {
                            let data = try Data(contentsOf: avAsset.url)
                            continuation.resume(returning: data)
                        } catch {
                            print("DayDetailView: Failed to read video data: \(error)")
                            continuation.resume(returning: nil)
                        }
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            } else {
                // For photos, use PHImageRequestOptions
                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.isNetworkAccessAllowed = false
                options.isSynchronous = false
                
                PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                    continuation.resume(returning: data)
                }
            }
        }
    }
    
    private func saveMedia(data: Data, order: Int, mediaType: String) {
        let photo = Photo(context: viewContext)
        photo.id = UUID()
        
        // Set filename based on media type
        if mediaType == "video" {
            photo.filename = "video_\(UUID().uuidString).mov"
        } else {
            photo.filename = "photo_\(UUID().uuidString).jpg"
        }
        
        photo.mediaType = mediaType
        photo.caption = ""
        photo.createdDate = Date()
        
        print("DayDetailView: Saving \(mediaType) with createdDate: \(photo.createdDate ?? Date())")
        
        // Try to extract the actual photo date from the image data (only for photos)
        if mediaType == "photo" {
            if let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
               let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
               let exif = properties["{Exif}"] as? [String: Any],
               let dateString = exif["DateTimeOriginal"] as? String {
                
                print("DayDetailView: Found EXIF date: \(dateString)")
                
                // Parse the EXIF date (format: "2024:01:15 14:30:25")
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
                if let photoDate = formatter.date(from: dateString) {
                    photo.photoDate = photoDate
                    print("DayDetailView: Set photoDate from EXIF: \(photoDate)")
                } else {
                    // Use trip day date instead of current date
                    photo.photoDate = tripDay.date ?? Date()
                    print("DayDetailView: Failed to parse EXIF date, using trip day date: \(tripDay.date ?? Date())")
                }
            } else {
                // If no EXIF data, use trip day date instead of current date
                photo.photoDate = tripDay.date ?? Date()
                print("DayDetailView: No EXIF data found, using trip day date: \(tripDay.date ?? Date())")
            }
        } else {
            // For videos, use trip day date
            photo.photoDate = tripDay.date ?? Date()
            print("DayDetailView: Using trip day date for video: \(tripDay.date ?? Date())")
        }
        
        photo.order = Int32(order)
        photo.tripDay = tripDay
        
        // Save the media file to documents directory
        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let mediaURL = documentsPath.appendingPathComponent(photo.filename!)
            try? data.write(to: mediaURL)
        }
        
        // Save to Core Data
        try? viewContext.save()
        
        print("DayDetailView: \(mediaType.capitalized) saved successfully")
        
        // Debug: Check if the media is properly associated
        print("DayDetailView: \(mediaType.capitalized) tripDay: \(photo.tripDay?.date ?? Date())")
        print("DayDetailView: Media tripDay ID: \(photo.tripDay?.id?.uuidString ?? "nil")")
        
        // Debug: Check the current trip day's media count
        let currentMedia = tripDay.photos?.allObjects as? [Photo] ?? []
        print("DayDetailView: Current trip day has \(currentMedia.count) media items after saving")
        
        // Post notification to refresh trip detail view
        NotificationCenter.default.post(name: .photosAddedToTripDay, object: tripDay)
    }
}

struct PhotoThumbnailView: View {
    let photo: Photo
    let onPhotoDeleted: () -> Void
    @State private var image: UIImage?
    @State private var showingDeleteAlert = false
    @State private var showingVideoPlayer = false
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
        .onTapGesture {
            if photo.mediaType == "video" {
                showingVideoPlayer = true
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
        .task {
            await loadPhoto()
        }
    }
    
    private func loadPhoto() async {
        guard let filename = photo.filename else { return }
        
        // Handle videos differently - generate thumbnail
        if photo.mediaType == "video" {
            await generateVideoThumbnail(filename: filename)
        } else {
            // Load photo as before
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            let fileURL = documentsPath?.appendingPathComponent(filename)
            
            if let fileURL = fileURL,
               let imageData = try? Data(contentsOf: fileURL),
               let loadedImage = UIImage(data: imageData) {
                image = loadedImage
            }
        }
    }
    
    private func generateVideoThumbnail(filename: String) async {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let videoURL = documentsPath.appendingPathComponent(filename)
        
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        do {
            let result = try await imageGenerator.image(at: .zero)
            await MainActor.run {
                self.image = UIImage(cgImage: result.image)
            }
        } catch {
            print("Failed to generate video thumbnail: \(error)")
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

struct CustomPhotoPickerView: View {
    let tripDay: TripDay
    let onPhotosSelected: ([PHAsset]) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var photos: [PHAsset] = []
    @State private var selectedPhotos: [PHAsset] = []
    @State private var isLoading = true
    @State private var alreadyAddedPhotos: [String] = [] // Store filenames of already added photos
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("Loading photos from \(formatDate(tripDay.date))...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if photos.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text("No Media Found")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("No photos or videos were taken on \(formatDate(tripDay.date))")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                            ForEach(photos, id: \.localIdentifier) { asset in
                                let isAlreadyAdded = isPhotoAlreadyAdded(asset)
                                PhotoAssetView(
                                    asset: asset, 
                                    isSelected: selectedPhotos.contains(asset),
                                    isDisabled: isAlreadyAdded
                                ) {
                                    // Only allow selection if not already added
                                    if !isAlreadyAdded {
                                        if selectedPhotos.contains(asset) {
                                            selectedPhotos.removeAll { $0.localIdentifier == asset.localIdentifier }
                                        } else {
                                            selectedPhotos.append(asset)
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Media from \(formatDate(tripDay.date))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add \(selectedPhotos.count) Media") {
                        onPhotosSelected(selectedPhotos)
                        dismiss()
                    }
                    .disabled(selectedPhotos.isEmpty)
                }
            }
        }
        .onAppear {
            loadPhotosFromDate()
            checkAlreadyAddedPhotos()
            print("CustomPhotoPickerView: onAppear - tripDay has \(tripDay.photos?.count ?? 0) photos")
        }
    }
    
    private func checkAlreadyAddedPhotos() {
        // Get filenames of photos already added to this trip day
        let existingFilenames = tripDay.photos?.compactMap { photo in
            (photo as? Photo)?.filename
        } ?? []
        
        alreadyAddedPhotos = existingFilenames
        print("CustomPhotoPickerView: Found \(alreadyAddedPhotos.count) already added photos")
    }
    
    private func isPhotoAlreadyAdded(_ asset: PHAsset) -> Bool {
        // Check if this photo is already added using multiple strategies
        guard let creationDate = asset.creationDate else { return false }
        
        // Strategy 1: Compare creation dates with tolerance
        let tolerance: TimeInterval = 2.0 // Increased tolerance to 2 seconds
        
        for photo in tripDay.photos ?? [] {
            guard let coreDataPhoto = photo as? Photo else { continue }
            
            // Check photoDate if available
            if let photoDate = coreDataPhoto.photoDate {
                let timeDifference = abs(photoDate.timeIntervalSince(creationDate))
                if timeDifference <= tolerance {
                    print("CustomPhotoPickerView: Duplicate detected by photoDate - difference: \(timeDifference)s")
                    return true
                }
            }
            
            // Strategy 2: Check createdDate if available
            if let createdDate = coreDataPhoto.createdDate {
                let timeDifference = abs(createdDate.timeIntervalSince(creationDate))
                if timeDifference <= tolerance {
                    print("CustomPhotoPickerView: Duplicate detected by createdDate - difference: \(timeDifference)s")
                    return true
                }
            }
        }
        
        // Strategy 3: Check if we have multiple photos with very similar timestamps
        // This catches cases where the same photo might have slightly different timestamps
        let similarPhotos = (tripDay.photos ?? []).compactMap { photo -> Date? in
            guard let coreDataPhoto = photo as? Photo else { return nil }
            return coreDataPhoto.photoDate ?? coreDataPhoto.createdDate
        }
        
        // If we have multiple photos from the same time period, be more strict
        if similarPhotos.count > 1 {
            let extendedTolerance: TimeInterval = 5.0 // 5 seconds for multiple photos
            for photoDate in similarPhotos {
                let timeDifference = abs(photoDate.timeIntervalSince(creationDate))
                if timeDifference <= extendedTolerance {
                    print("CustomPhotoPickerView: Duplicate detected by extended tolerance - difference: \(timeDifference)s")
                    return true
                }
            }
        }
        
        return false
    }
    
    private func loadPhotosFromDate() {
        guard let tripDate = tripDay.date else { return }
        
        // Check photo library permission first
        let status = PHPhotoLibrary.authorizationStatus()
        guard status == .authorized || status == .limited else {
            print("CustomPhotoPickerView: Photo library permission not granted: \(status.rawValue)")
            DispatchQueue.main.async {
                self.isLoading = false
            }
            return
        }
        
        let dayStart = Calendar.current.startOfDay(for: tripDate)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        
        print("CustomPhotoPickerView: Fetching photos from \(dayStart) to \(dayEnd)")
        
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", dayStart as NSDate, dayEnd as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        // Fetch images and videos separately since fetchAssets doesn't support arrays
        let imageFetchResult = PHAsset.fetchAssets(with: PHAssetMediaType.image, options: options)
        let videoFetchResult = PHAsset.fetchAssets(with: PHAssetMediaType.video, options: options)
        
        print("CustomPhotoPickerView: Found \(imageFetchResult.count) images and \(videoFetchResult.count) videos for this date")
        
        var tempPhotos: [PHAsset] = []
        
        // Add images first
        imageFetchResult.enumerateObjects { asset, _, _ in
            tempPhotos.append(asset)
        }
        
        // Add videos
        videoFetchResult.enumerateObjects { asset, _, _ in
            tempPhotos.append(asset)
        }
        
        DispatchQueue.main.async {
            self.photos = tempPhotos
            self.isLoading = false
            print("CustomPhotoPickerView: Loaded \(tempPhotos.count) photos from date")
            
            // Debug: Check each photo for duplicate status
            for (index, asset) in tempPhotos.enumerated() {
                let isDuplicate = self.isPhotoAlreadyAdded(asset)
                print("CustomPhotoPickerView: Photo \(index): creationDate=\(asset.creationDate?.description ?? "nil"), isDuplicate=\(isDuplicate)")
            }
        }
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Unknown Date" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

struct PhotoAssetView: View {
    let asset: PHAsset
    let isSelected: Bool
    let isDisabled: Bool
    let onTap: () -> Void
    
    @State private var image: UIImage?
    
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
                            .fill(isDisabled ? Color.black.opacity(0.4) : Color.clear)
                    )
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 100, height: 100)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.8)
                    )
            }
            
            // Selection indicator
            if isSelected {
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
            }
            
            // Already added indicator
            if isDisabled {
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
            }
        }
        .onTapGesture {
            // Only allow tap if not disabled
            if !isDisabled {
                onTap()
            }
        }
        .task {
            await loadThumbnail()
        }
    }
    
    private func loadThumbnail() async {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = false
        options.resizeMode = .exact
        
        // Try to load a smaller thumbnail first
        let targetSize = CGSize(width: 100, height: 100)
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, info in
            DispatchQueue.main.async {
                if let image = image {
                    self.image = image
                } else {
                    // If thumbnail fails, try to get the full image
                    self.loadFullImage()
                }
            }
        }
    }
    
    private func loadFullImage() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = false
        options.isSynchronous = false
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            DispatchQueue.main.async {
                if let image = image {
                    // Scale down the full image to thumbnail size
                    let thumbnailSize = CGSize(width: 100, height: 100)
                    UIGraphicsBeginImageContextWithOptions(thumbnailSize, false, 0.0)
                    image.draw(in: CGRect(origin: .zero, size: thumbnailSize))
                    let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
                    UIGraphicsEndImageContext()
                    
                    self.image = thumbnail
                } else {
                    // If all else fails, show a placeholder
                    print("Failed to load image for asset: \(self.asset.localIdentifier)")
                }
            }
        }
    }
}

struct VideoPlayerView: View {
    let filename: String
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    
    var body: some View {
        NavigationView {
            ZStack {
                if let player = player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                } else {
                    ProgressView("Loading video...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Video Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            loadVideo()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
    
    private func loadVideo() {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let videoURL = documentsPath.appendingPathComponent(filename)
        
        if FileManager.default.fileExists(atPath: videoURL.path) {
            player = AVPlayer(url: videoURL)
            player?.play()
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
