import Foundation

/// A sidebar shortcut that lists matching files from the whole storage, like Android's Files app.
enum FileCategory: String, CaseIterable, Identifiable {
    case recent = "Recent"
    case images = "Images"
    case videos = "Videos"
    case audio = "Audio"
    case documents = "Documents"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .recent: "clock"
        case .images: "photo"
        case .videos: "film"
        case .audio: "music.note"
        case .documents: "doc.text"
        }
    }

    /// File extensions in the category; empty means every file.
    var extensions: [String] {
        switch self {
        case .recent: []
        case .images: ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "dng"]
        case .videos: ["mp4", "mkv", "mov", "webm", "3gp", "avi", "m4v"]
        case .audio: ["mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "amr"]
        case .documents: ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "md", "rtf", "csv", "odt", "epub"]
        }
    }

    /// The folders (under the storage root) the category is looked for in, where such files normally live.
    /// Recent covers all of them.
    var folders: [String] {
        switch self {
        case .recent: ["DCIM", "Pictures", "Movies", "Music", "Podcasts", "Audiobooks", "Recordings", "Documents", "Download"]
        case .images: ["DCIM", "Pictures", "Download"]
        case .videos: ["DCIM", "Movies", "Download"]
        case .audio: ["Music", "Podcasts", "Audiobooks", "Recordings", "Download"]
        case .documents: ["Documents", "Download"]
        }
    }

    /// Recent only covers files changed within this many days.
    var days: Int? { self == .recent ? 7 : nil }

    /// Where the phone's media index lists the category: a content path and an optional SQL filter.
    /// `since` is the cutoff (epoch seconds) for Recent.
    func indexQuery(since: Int) -> (path: String, filter: String?) {
        switch self {
        case .recent: ("file", "date_modified>\(since) AND _data NOT LIKE '%/Android/%' AND mime_type IS NOT NULL")
        case .images: ("images/media", nil)
        case .videos: ("video/media", nil)
        case .audio: ("audio/media", nil)
        case .documents: ("file", "media_type=6")
        }
    }
}
