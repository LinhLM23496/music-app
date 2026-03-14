//
//  ReadMe.swift
//  MusicApp
//
//  Created by Linh Le on 15/3/26.
//

PlayerCoordinator = người ra quyết định
AVPlaybackEngine = người phát nhạc thật
PlayerSessionStore = sổ ghi queue hiện tại
PlayerPersistence = chỗ lưu trạng thái resume


1. TrackResolving
    Vai trò PlayerCoordinator chỉ giữ trackID, không giữ cả Song.
    Nên nó cần 1 lớp để hỏi:

    id này là bài nào?
    id này phát bằng URL nào?

2. UserDefaultsPlayerPersistence
    Vai trò Lớp này dùng để:

    lưu snapshot player
    load snapshot khi mở app lại
    clear snapshot
    Nó là implementation thật của PlayerPersistence.
