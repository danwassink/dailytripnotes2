import SwiftUI
import PhotosUI
import CoreData
import ImageIO
import Photos
import AVFoundation
import AVKit
import Foundation

// MARK: - Unified Photo Loading Utility
class PhotoLoader: ObservableObject {
    static let shared = PhotoLoader()
    
    private init() {}
    
    // Unified photo loading function that works consistently across all views
    func loadPhoto(
        filename: String?,
        assetIdentifier: String?,
        mediaType: String?,
        completion: @escaping (UIImage?, Bool, Bool) -> Void
    ) {
        guard let filename = filename else {
            completion(nil, false, true) // No filename, show error
            return
        }
        
        // FIRST PRIORITY: Try loading from documents directory (most reliable for saved photos)
        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = documentsPath.appendingPathComponent(filename)
            
            if FileManager.default.fileExists(atPath: fileURL.path) {
                do {
                    let imageData = try Data(contentsOf: fileURL)
                    if let loadedImage = UIImage(data: imageData) {
                        completion(loadedImage, false, false) // Success, not loading, no error
                        return
                    }
                } catch {
                    print("PhotoLoader: Failed to read file data: \(error)")
                }
            }
        }
        
        // SECOND PRIORITY: Try loading from PHAsset if available
        if let assetIdentifier = assetIdentifier {
            loadPhotoFromPHAsset(assetIdentifier) { image, hasError in
                completion(image, false, hasError)
            }
            return
        }
        
        // THIRD PRIORITY: Check if filename contains asset identifier (old format)
        if filename.hasPrefix("temp_") {
            let assetIdentifier = String(filename.dropFirst(5))
            loadPhotoFromPHAsset(assetIdentifier) { image, hasError in
                completion(image, false, hasError)
            }
            return
        }
        
        // FOURTH PRIORITY: Try to extract asset identifier from filename
        if filename.contains(":") {
            loadPhotoFromPHAsset(filename) { image, hasError in
                completion(image, false, hasError)
            }
            return
        }
        
        // No more attempts, show error
        completion(nil, false, true)
    }
    
    private func loadPhotoFromPHAsset(_ assetIdentifier: String, completion: @escaping (UIImage?, Bool) -> Void) {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else {
            completion(nil, true)
            return
        }
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        
        let targetSize = CGSize(width: 200, height: 200) // 2x for retina
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, info in
            DispatchQueue.main.async {
                if let image = image {
                    completion(image, false)
                } else {
                    completion(nil, true)
                }
            }
        }
    }
}

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
        ScrollView {
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
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
                .id("\(photosAdded)-\(photosDeleted)") // Force refresh when photos are added or deleted
                
                // Journal entry section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Journal Entry")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    
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
                
                // Add bottom padding to ensure content isn't hidden behind FABs
                Spacer(minLength: 120)
            }
        }
        .navigationTitle("Day Details")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingJournalEditor) {
            JournalEntryView(tripDay: tripDay) {
                loadJournalContent() // Refresh the content when journal is saved
            }
        }
        .sheet(isPresented: $showingCustomPhotoPicker) {
            CustomPhotoPickerView(tripDay: tripDay, onPhotosSelected: { selectedAssets in
                processSelectedPHAssets(selectedAssets)
            })
        }
        .onAppear {
            loadJournalContent()
        }
        .overlay(
            // Stacked FABs in lower right corner
            VStack(spacing: 12) {
                // Journal FAB
                Button(action: {
                    showingJournalEditor = true
                }) {
                    Image(systemName: "pencil")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.blue)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                
                // Photos FAB
                Button(action: {
                    showingCustomPhotoPicker = true
                }) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.green)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                }
            }
            .padding(.trailing, 20)
            .padding(.bottom, 20),
            alignment: .bottomTrailing
        )
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
                        // For PhotosPicker items, we don't have the PHAsset, so we can't store the identifier
                        // This is a limitation of PhotosPicker vs CustomPhotoPickerView
                        saveMedia(data: data, order: index, mediaType: "photo", asset: nil)
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
        print("DayDetailView: Assets: \(assets.map { "\($0.localIdentifier) (\($0.mediaType == .video ? "video" : "photo"))" })")
        isProcessing = true
        
        Task {
            for (index, asset) in assets.enumerated() {
                print("DayDetailView: Processing PHAsset \(index + 1) of \(assets.count): \(asset.localIdentifier)")
                print("DayDetailView: Asset media type: \(asset.mediaType.rawValue)")
                print("DayDetailView: Asset creation date: \(asset.creationDate?.description ?? "nil")")
                
                let data = await loadMediaDataFromAsset(asset)
                if let data = data {
                    let mediaType = asset.mediaType == PHAssetMediaType.video ? "video" : "photo"
                    print("DayDetailView: Successfully loaded \(mediaType) data, size: \(data.count) bytes")
                    await MainActor.run {
                        saveMedia(data: data, order: index, mediaType: mediaType, asset: asset)
                    }
                } else {
                    print("DayDetailView: Failed to load PHAsset data for asset \(index + 1): \(asset.localIdentifier)")
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
        print("DayDetailView: Starting to load media data for asset: \(asset.localIdentifier)")
        
        if asset.mediaType == PHAssetMediaType.video {
            print("DayDetailView: Loading video data...")
            return await loadVideoDataFromAsset(asset)
        } else {
            print("DayDetailView: Loading photo data...")
            return await loadPhotoDataFromAsset(asset)
        }
    }
    
    private func loadVideoDataFromAsset(_ asset: PHAsset) async -> Data? {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = false
        options.version = .current
        
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, error in
                if let error = error {
                    print("DayDetailView: Video request error: \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                
                if let avAsset = avAsset as? AVURLAsset {
                    print("DayDetailView: Got AVAsset for video, reading data...")
                    do {
                        let data = try Data(contentsOf: avAsset.url)
                        print("DayDetailView: Successfully read video data: \(data.count) bytes")
                        continuation.resume(returning: data)
                    } catch {
                        print("DayDetailView: Failed to read video data: \(error)")
                        continuation.resume(returning: nil)
                    }
                } else {
                    print("DayDetailView: Failed to get AVAsset for video")
                    continuation.resume(returning: nil)
                    return
                }
            }
        }
    }
    
    private func loadPhotoDataFromAsset(_ asset: PHAsset) async -> Data? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = false
        options.isSynchronous = false
        
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, dataUTI, orientation, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    print("DayDetailView: Photo request error: \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                
                if let data = data {
                    print("DayDetailView: Successfully got photo data: \(data.count) bytes")
                    continuation.resume(returning: data)
                } else {
                    print("DayDetailView: No photo data received")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private func saveMedia(data: Data, order: Int, mediaType: String, asset: PHAsset?) {
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
        photo.assetIdentifier = asset?.localIdentifier
        
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
            print("DayDetailView: Attempting to save \(mediaType) to: \(mediaURL.path)")
            
            do {
                try data.write(to: mediaURL)
                print("DayDetailView: Successfully saved \(mediaType) data to file")
                
                // Verify the file was actually saved
                let fileManager = FileManager.default
                if fileManager.fileExists(atPath: mediaURL.path) {
                    let fileSize = try fileManager.attributesOfItem(atPath: mediaURL.path)[.size] as? Int64 ?? 0
                    print("DayDetailView: File exists at path, size: \(fileSize) bytes")
                } else {
                    print("DayDetailView: ERROR - File does not exist after saving!")
                }
            } catch {
                print("DayDetailView: ERROR - Failed to save \(mediaType) data: \(error)")
            }
        } else {
            print("DayDetailView: ERROR - Could not get documents directory path")
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
                    .frame(width: 100, height: 100)
                    .clipped()
                    .cornerRadius(8)
            } else if hasError {
                // Show error state with retry button
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
                            Button("Retry") {
                                Task {
                                    await loadPhoto()
                                }
                            }
                            .font(.caption2)
                            .foregroundColor(.blue)
                        }
                    )
            } else if isLoading {
                // Show loading state
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 100, height: 100)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.8)
                    )
            } else {
                // Show placeholder when not loading and no image
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 100, height: 100)
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
            // Get the photos from the parent view context for navigation
            if let tripDay = photo.tripDay,
               let trip = tripDay.trip {
                let allPhotos = trip.tripDays?.compactMap { $0 as? TripDay }
                    .flatMap { $0.photos?.compactMap { $0 as? Photo } ?? [] } ?? []
                if let currentIndex = allPhotos.firstIndex(of: photo) {
                    FullScreenPhotoView(photos: allPhotos, currentIndex: currentIndex, onPhotoDeleted: {
                        onPhotoDeleted() // Notify parent view when photo is deleted
                    })
                } else {
                    FullScreenPhotoView(photo: photo, onPhotoDeleted: {
                        onPhotoDeleted() // Notify parent view when photo is deleted
                    })
                }
            } else {
                FullScreenPhotoView(photo: photo, onPhotoDeleted: {
                    onPhotoDeleted() // Notify parent view when photo is deleted
                })
            }
        }
        .task {
            await loadPhoto()
        }
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
            // Use the unified PhotoLoader
            PhotoLoader.shared.loadPhoto(
                filename: filename,
                assetIdentifier: photo.assetIdentifier,
                mediaType: photo.mediaType
            ) { image, isLoading, hasError in
                DispatchQueue.main.async {
                    self.image = image
                    self.isLoading = isLoading
                    self.hasError = hasError
                }
            }
        }
    }
    
    private func generateVideoThumbnail(filename: String) async {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { 
            DispatchQueue.main.async {
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
            DispatchQueue.main.async {
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
            DispatchQueue.main.async {
                self.image = UIImage(cgImage: result.image)
                self.isLoading = false
                self.hasError = false
            }
            return
        } catch {
            print("Second AVAssetImageGenerator attempt failed: \(error)")
        }
        
        // Final fallback: Show a video placeholder
        DispatchQueue.main.async {
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
                                            print("CustomPhotoPickerView: Removed asset \(asset.localIdentifier) from selection")
                                        } else {
                                            selectedPhotos.append(asset)
                                            print("CustomPhotoPickerView: Added asset \(asset.localIdentifier) to selection")
                                        }
                                    } else {
                                        print("CustomPhotoPickerView: Blocked selection of already added asset \(asset.localIdentifier)")
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
                    HStack(spacing: 16) {
                        // Select All button - only show if there are photos to select
                        if !photos.isEmpty {
                            Button("Select All") {
                                selectAllAvailablePhotos()
                            }
                            .disabled(selectedPhotos.count == getAvailablePhotosCount())
                        }
                        
                        Button("Add \(selectedPhotos.count) Media") {
                            onPhotosSelected(selectedPhotos)
                            dismiss()
                        }
                        .disabled(selectedPhotos.isEmpty)
                    }
                }
            }
        }
        .onAppear {
            loadPhotosFromDate()
            checkAlreadyAddedPhotos()
            print("CustomPhotoPickerView: onAppear - tripDay has \(tripDay.photos?.count ?? 0) photos")
        }
        .onChange(of: photos) { _ in
            // Remove any already added photos from selection when photos change
            let beforeCount = selectedPhotos.count
            selectedPhotos.removeAll { asset in
                let isAlready = isPhotoAlreadyAdded(asset)
                if isAlready {
                    print("CustomPhotoPickerView: onChange - Removing already added asset \(asset.localIdentifier) from selection")
                }
                return isAlready
            }
            let afterCount = selectedPhotos.count
            print("CustomPhotoPickerView: onChange - Selection count changed from \(beforeCount) to \(afterCount)")
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
        // Check if this photo is already added using ONLY photo ID matching
        // This is much more reliable than date comparison
        
        print("CustomPhotoPickerView: Checking if asset with identifier \(asset.localIdentifier) is already added")
        print("CustomPhotoPickerView: TripDay has \(tripDay.photos?.count ?? 0) photos")
        
        for (index, photo) in (tripDay.photos ?? []).enumerated() {
            guard let coreDataPhoto = photo as? Photo else { 
                print("CustomPhotoPickerView: Photo \(index) is not a Photo entity")
                continue 
            }
            
            print("CustomPhotoPickerView: Checking Photo \(index):")
            print("  - filename: \(coreDataPhoto.filename ?? "nil")")
            print("  - assetIdentifier: \(coreDataPhoto.assetIdentifier ?? "nil")")
            
            // Only check if this photo was saved from the same PHAsset by comparing identifiers
            if let storedIdentifier = coreDataPhoto.assetIdentifier {
                if storedIdentifier == asset.localIdentifier {
                    print("CustomPhotoPickerView: ✅ Duplicate detected by asset identifier match!")
                    return true
                }
            }
        }
        
        print("CustomPhotoPickerView: ❌ No duplicate detected for asset with identifier \(asset.localIdentifier)")
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
        
        // Add images first, but filter out potentially problematic ones
        imageFetchResult.enumerateObjects { asset, _, _ in
            // Only add assets that have valid creation dates and are accessible
            if asset.creationDate != nil && asset.mediaType == .image {
                tempPhotos.append(asset)
            } else {
                print("CustomPhotoPickerView: Skipping image asset - creationDate: \(asset.creationDate?.description ?? "nil"), mediaType: \(asset.mediaType.rawValue)")
            }
        }
        
        // Add videos
        videoFetchResult.enumerateObjects { asset, _, _ in
            if asset.creationDate != nil && asset.mediaType == .video {
                tempPhotos.append(asset)
            } else {
                print("CustomPhotoPickerView: Skipping video asset - creationDate: \(asset.creationDate?.description ?? "nil"), mediaType: \(asset.mediaType.rawValue)")
            }
        }
        
        DispatchQueue.main.async {
            self.photos = tempPhotos
            self.isLoading = false
            print("CustomPhotoPickerView: Loaded \(tempPhotos.count) valid photos from date")
            
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

    private func getAvailablePhotosCount() -> Int {
        // Count photos that aren't already added
        return photos.filter { !isPhotoAlreadyAdded($0) }.count
    }

    private func selectAllAvailablePhotos() {
        // Use the existing photos array which already has duplicates filtered out
        let availablePhotos = photos.filter { !isPhotoAlreadyAdded($0) }
        
        // Clear current selection and add all available photos
        selectedPhotos = availablePhotos
        
        print("CustomPhotoPickerView: Selected all \(availablePhotos.count) available photos for date \(tripDay.date ?? Date())")
    }
}

struct PhotoAssetView: View {
    let asset: PHAsset
    let isSelected: Bool
    let isDisabled: Bool
    let onTap: () -> Void
    
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var hasError = false
    
    // Static semaphore to limit concurrent photo loading
    private static let photoLoadingSemaphore = DispatchSemaphore(value: 5)
    
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
        // Wait for semaphore to prevent too many concurrent photo loads
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                Self.photoLoadingSemaphore.wait()
                continuation.resume()
            }
        }
        
        defer {
            // Always signal the semaphore when done
            Self.photoLoadingSemaphore.signal()
        }
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        
        // Try to load a smaller thumbnail first
        let targetSize = CGSize(width: 100, height: 100)
        
        // Use a flag to prevent multiple callback handling
        var hasHandledCallback = false
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, info in
            // Prevent multiple callback handling
            guard !hasHandledCallback else { return }
            hasHandledCallback = true
            
            DispatchQueue.main.async {
                if let image = image {
                    self.image = image
                    self.isLoading = false
                    self.hasError = false
                } else {
                    // Check if there's an error
                    if let error = info?[PHImageErrorKey] as? Error {
                        print("PhotoAssetView: Thumbnail loading error: \(error.localizedDescription)")
                        self.hasError = true
                        self.isLoading = false
                    } else {
                        // If thumbnail fails, try to get the full image
                        self.loadFullImage()
                    }
                }
            }
        }
    }
    
    private func loadFullImage() {
        // Wait for semaphore to prevent too many concurrent photo loads
        Task {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    Self.photoLoadingSemaphore.wait()
                    continuation.resume()
                }
            }
            
            defer {
                // Always signal the semaphore when done
                Self.photoLoadingSemaphore.signal()
            }
            
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            
            // Use a flag to prevent multiple callback handling
            var hasHandledCallback = false
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                // Prevent multiple callback handling
                guard !hasHandledCallback else { return }
                hasHandledCallback = true
                
                DispatchQueue.main.async {
                    if let image = image {
                        // Scale down the full image to thumbnail size
                        let thumbnailSize = CGSize(width: 100, height: 100)
                        UIGraphicsBeginImageContextWithOptions(thumbnailSize, false, 0.0)
                        image.draw(in: CGRect(origin: .zero, size: thumbnailSize))
                        let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
                        UIGraphicsEndImageContext()
                        
                        self.image = thumbnail
                        self.isLoading = false
                        self.hasError = false
                    } else {
                        // Check if there's an error
                        if let error = info?[PHImageErrorKey] as? Error {
                            print("PhotoAssetView: Full image loading error: \(error.localizedDescription)")
                            self.hasError = true
                            self.isLoading = false
                        } else {
                            // If all else fails, show error state
                            print("PhotoAssetView: Failed to load image for asset: \(self.asset.localIdentifier)")
                            self.hasError = true
                            self.isLoading = false
                        }
                    }
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
