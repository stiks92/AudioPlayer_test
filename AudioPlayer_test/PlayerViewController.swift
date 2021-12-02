//
//  ViewController.swift
//  AudioPlayer_test
//
//  Created by Вадим Брацюн on 29.11.2021.
//

import UIKit
import AVFoundation

class PlayerViewController: UIViewController {
    
//    MARK: - Propeties
    
    var player: AVPlayer?
    public var position: Int = 0
    var initialSongs = SongsManager.shared.configureSongs()
    var isPlaying = false
    
//    MARK: - Outlets
    
    @IBOutlet weak var albumImage: UIImageView!
    @IBOutlet weak var nameOfSongLabel: UILabel!
    @IBOutlet weak var currentTimeLabel: UILabel!
    @IBOutlet weak var fullTimeLabel: UILabel!
    @IBOutlet weak var timeProgressSlider: UISlider!
    @IBOutlet weak var playPauseButton: UIButton!
    @IBOutlet weak var backwordButton: UIButton!
    @IBOutlet weak var forwardButton: UIButton!
    @IBOutlet weak var volumeButton: UISlider!
    @IBOutlet weak var playlistButton: UIButton!
    @IBOutlet weak var volumeSlider: UISlider!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        volumeSlider.value = 0.5
        player?.volume = 0.5
        configure()
        updateFullTime()
        timeProgressSlider.maximumValue = Float(player?.currentItem?.asset.duration.seconds ?? 0)
        updateCurrentTime()
        
        if isPlaying == false {
            playPauseButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        } else {
            playPauseButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        }
    }
//    MARK: - Methods
    
//    Update status label and status slider method
    func updateCurrentTime() {
        guard let currentTime = player?.currentTime() else { return }
        let currentSeconds = CMTimeGetSeconds(currentTime)
        currentTimeLabel.text = "\(Int(currentSeconds).secondsToString())"
        player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 1000), queue: .main) { [weak self] (time) in
            guard let self = self else { return }
            self.timeProgressSlider.value = Float(time.seconds)
            self.currentTimeLabel.text = "\(Int(time.seconds).secondsToString())"
        }
    }
    
//    Update duration time of song label method
    func updateFullTime() {
        guard let duration = player?.currentItem!.asset.duration else { return }
        let durationSeconds = CMTimeGetSeconds(duration)
        fullTimeLabel.text = "\(Int(durationSeconds).secondsToString())"
    }
    
//    Configure player method
    func configure() {
        let song = initialSongs[position]
        let urlString = Bundle.main.path(forResource: song.trackName, ofType: "mp3")
        self.albumImage.image = UIImage(named: song.imageName)
        self.nameOfSongLabel.text = song.name
        
        do {
            try AVAudioSession.sharedInstance().setMode(.default)
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            
            guard let urlString = urlString else {
                return
            }
            player = AVPlayer(url: URL(fileURLWithPath: urlString))
            guard let player = player else {
                return
            }
            if isPlaying == true {
                player.play()
            }
        }
        catch {
            print("error")
        }
    }
    
//    MARK: - Actions
    
//    Status slider action
    @IBAction func changeCurrentTime(_ sender: Any) {
        self.player?.seek(to: CMTime(seconds: Double(timeProgressSlider.value), preferredTimescale: 1))
        player?.play()
    }
    
//    Play/pause button action
    @IBAction func didTapPlayPause(_ sender: Any) {
        if isPlaying == true {
            isPlaying = false
            player?.pause()
            playPauseButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        } else {
            isPlaying = true
            player?.play()
            playPauseButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        }
    }
    
//    Perviosly button action
    @IBAction func didTapPrev(_ sender: Any) {
        if position > 0 {
            position = position - 1
            configure()
            updateFullTime()
            updateCurrentTime()
        } else {
            position = 16
            configure()
            updateFullTime()
            updateCurrentTime()
        }
    }
    
//    Next button action
    @IBAction func didTapNext(_ sender: Any) {
        if position < (initialSongs.count - 1) {
            position = position + 1
            configure()
            updateFullTime()
            updateCurrentTime()
        } else {
            position = 0
            configure()
            updateFullTime()
            updateCurrentTime()
        }
    }
    
//    Volume slider action
    @IBAction func changeVolume(_ sender: Any) {
        let value = volumeSlider.value
        player?.volume = value
    }
    
//    Playlist button action
    @IBAction func playlistOpen(_ sender: Any) {
        self.dismiss(animated: true, completion: nil)
        player?.pause()
    }
}

//Type extension for display in label
extension Int{
    func secondsToString() -> String {
        let minutes = self / 60
        let seconds = self % 60
        
        return String(format: "%d:%02d", minutes, seconds)
    }
}

