//
//  PlaylistViewController.swift
//  AudioPlayer_test
//
//  Created by Вадим Брацюн on 01.12.2021.
//

import UIKit

class PlaylistViewController: UIViewController {
    
//    MARK: - Outlets
    
    @IBOutlet weak var playlistTableView: UITableView!
    
//    MARK: - Propeties
    
    var position: Int = 0
    var songs = SongsManager.shared.configureSongs()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        playlistTableView.delegate = self
        playlistTableView.dataSource = self
    }
}

//MARK: - TableView methods

extension PlaylistViewController: UITableViewDelegate, UITableViewDataSource {
    
//    MARK: - TableView DataSource
    
//    NumberOfRowsInSection method
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return songs.count
    }
    
//    CellForRowAt method
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = playlistTableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let song = songs[indexPath.row]
        cell.textLabel?.text = song.name
        cell.accessoryType = .disclosureIndicator
        cell.imageView?.image = UIImage(named: song.imageName)
        cell.textLabel?.font = UIFont(name: "Helvetica-bold", size: 17)
        return cell
    }
    
//    HeightForRowAt method
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 100
    }
    
//    MARK: - TableView Delegate
    
//    DidSelectRowAt method
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        self.position = indexPath.row
        self.performSegue(withIdentifier: "showPlayer", sender: self)
    }
    
//    MARK: - Segue method
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let vc = segue.destination as? PlayerViewController, segue.identifier == "showPlayer"{
            vc.position = self.position
            vc.isPlaying = true
            vc.player?.pause()
        }
    }
}
