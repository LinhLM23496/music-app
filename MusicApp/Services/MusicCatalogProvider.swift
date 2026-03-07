import Foundation
import SwiftUI

struct InitialCatalogData {
    let songs: [Song]
    let featuredSongIDs: [UUID]
    let favoriteSongIDs: Set<UUID>
    let playlists: [Playlist]
}

protocol MusicCatalogProviding {
    func loadInitialCatalog() -> InitialCatalogData
}

struct MockMusicCatalogProvider: MusicCatalogProviding {
    func loadInitialCatalog() -> InitialCatalogData {
        let songs: [Song] = [
            Song(id: UUID(), titleEN: "Afterglow", titleVI: "Du Am Hoang Hon", artist: "Nova Lane", album: "Neon Nights", coverSymbol: "music.note.tv", audioFileName: "demo_track_1.wav", localFilePath: nil, duration: 228, accent: .pink),
            Song(id: UUID(), titleEN: "Ocean Drive", titleVI: "Duong Ven Bien", artist: "Skyline Echo", album: "City Pulse", coverSymbol: "car.fill", audioFileName: "demo_track_2.wav", localFilePath: nil, duration: 201, accent: .blue),
            Song(id: UUID(), titleEN: "Dream Circuit", titleVI: "Mach Mo", artist: "Synth Bloom", album: "Pulse", coverSymbol: "waveform.path.ecg", audioFileName: "demo_track_3.wav", localFilePath: nil, duration: 245, accent: .mint),
            Song(id: UUID(), titleEN: "Golden Hour", titleVI: "Gio Vang", artist: "Maya Quill", album: "Sunset Tape", coverSymbol: "sun.max.fill", audioFileName: "demo_track_1.wav", localFilePath: nil, duration: 231, accent: .orange),
            Song(id: UUID(), titleEN: "Lost in Motion", titleVI: "Lac Trong Chuyen Dong", artist: "Vera K", album: "Midnight Run", coverSymbol: "figure.run", audioFileName: "demo_track_2.wav", localFilePath: nil, duration: 214, accent: .purple),
            Song(id: UUID(), titleEN: "Moonline", titleVI: "Duong Trang", artist: "Ari Voss", album: "Night Signals", coverSymbol: "moon.stars.fill", audioFileName: "demo_track_3.wav", localFilePath: nil, duration: 196, accent: .cyan)
        ]

        let playlists: [Playlist] = [
            Playlist(id: UUID(), nameEN: "Late Night Focus", nameVI: "Tap Trung Dem Khuya", coverSymbol: "moon.fill", songIDs: [songs[0].id, songs[3].id, songs[5].id]),
            Playlist(id: UUID(), nameEN: "Morning Boost", nameVI: "Nang Luong Sang", coverSymbol: "sunrise.fill", songIDs: [songs[1].id, songs[2].id]),
            Playlist(id: UUID(), nameEN: "Weekend Chill", nameVI: "Thu Gian Cuoi Tuan", coverSymbol: "beach.umbrella.fill", songIDs: [songs[4].id])
        ]

        return InitialCatalogData(
            songs: songs,
            featuredSongIDs: Array(songs.prefix(4).map(\.id)),
            favoriteSongIDs: Set([songs[0].id, songs[2].id]),
            playlists: playlists
        )
    }
}
