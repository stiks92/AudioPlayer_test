//
//  SongsManager.swift
//  AudioPlayer_test
//
//  Created by Вадим Брацюн on 02.12.2021.
//

import Foundation

//MARK: - Open added songs manager
class SongsManager {
    static let shared = SongsManager()
    
    func configureSongs() -> [SongModel]{
        var songs = [SongModel]()
        songs.append(SongModel(name: "Hoyt's Office",
                               imageName: "cover",
                               trackName: "song1"))
        songs.append(SongModel(name: "Defeated Clown",
                               imageName: "cover",
                               trackName: "song2"))
        songs.append(SongModel(name: "Following Sophie",
                               imageName: "cover",
                               trackName: "song3"))
        songs.append(SongModel(name: "Penny in the Hospital",
                               imageName: "cover",
                               trackName: "song4"))
        songs.append(SongModel(name: "Young Penny",
                               imageName: "cover",
                               trackName: "song5"))
        songs.append(SongModel(name: "Meeting Bruce Wayne",
                               imageName: "cover",
                               trackName: "song6"))
        songs.append(SongModel(name: "Hiding in the Fridge",
                               imageName: "cover",
                               trackName: "song7"))
        songs.append(SongModel(name: "A Bad Comedian",
                               imageName: "cover",
                               trackName: "song8"))
        songs.append(SongModel(name: "Arthur Comes to Sophie",
                               imageName: "cover",
                               trackName: "song9"))
        songs.append(SongModel(name: "Looking for Answers",
                               imageName: "cover",
                               trackName: "song10"))
        songs.append(SongModel(name: "Penny Taken to the Hospital",
                               imageName: "cover",
                               trackName: "song11"))
        songs.append(SongModel(name: "Subway",
                               imageName: "cover",
                               trackName: "song12"))
        songs.append(SongModel(name: "Bathroom Dance",
                               imageName: "cover",
                               trackName: "song13"))
        songs.append(SongModel(name: "Learning How to Act Normal",
                               imageName: "cover",
                               trackName: "song14"))
        songs.append(SongModel(name: "Confession",
                               imageName: "cover",
                               trackName: "song15"))
        songs.append(SongModel(name: "Escape from the Train",
                               imageName: "cover",
                               trackName: "song16"))
        songs.append(SongModel(name: "Call Me Joker",
                               imageName: "cover",
                               trackName: "song17"))
        
        return songs
    }
}
