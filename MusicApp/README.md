//
//  ReadMe.swift
//  MusicApp
//
//  Created by Linh Le on 15/3/26.
//

<!--PlaybackController = người ra quyết định-->
<!--AVPlayerEngine = người phát nhạc thật-->
<!--PlaybackContextStore = sổ ghi queue hiện tại-->
<!--PlaybackPersistence = chỗ lưu trạng thái resume-->
<!---->
<!---->
<!--1. TrackResolver-->
<!--    Vai trò PlaybackController chỉ giữ trackID, không giữ cả Song.-->
<!--    Nên nó cần 1 lớp để hỏi:-->
<!---->
<!--    id này là bài nào?-->
<!--    id này phát bằng URL nào?-->
<!---->
<!--2. UserDefaultsPlaybackPersistence-->
<!--    Vai trò Lớp này dùng để:-->
<!---->
<!--    lưu snapshot player-->
<!--    load snapshot khi mở app lại-->
<!--    clear snapshot-->
<!--    Nó là implementation thật của PlaybackPersistence.-->
