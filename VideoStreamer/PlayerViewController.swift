//
//  PlayerViewController.swift
//  VideoStreamer
//
//  Created by Ritam Sarmah on 9/2/16.
//  Copyright © 2016 Ritam Sarmah. All rights reserved.
//

import UIKit
import AVKit
import XCDYouTubeKit

class PlayerViewController: AVPlayerViewController {
    
    var video: Video?
    var rateToken: NSKeyValueObservation?
    var statusToken: NSKeyValueObservation?
    var backgroundPlayer: AVPlayer?
    
    override var shouldAutorotate: Bool {
        return !SettingsManager.shared.lockLandscapePlayback
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if SettingsManager.shared.lockLandscapePlayback {
            return .landscape
        } else {
            return .allButUpsideDown
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        addPlaybackMenu()
//        addPlaybackControlGestures()
        configurePlayer()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if SettingsManager.shared.backgroundPlay {
            NotificationCenter.default.addObserver(self, selector: #selector(enableBackgroundPlay), name: .UIApplicationDidEnterBackground, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(reconnectPlayer), name: .UIApplicationWillEnterForeground, object: nil)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let player = player {
            video?.lastPlayedTime = SettingsManager.shared.resumePlayback ? player.currentTime() : nil
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if !SettingsManager.shared.backgroundPlay {
            player?.pause()
            backgroundPlayer?.pause()
        }
        player?.replaceCurrentItem(with: nil)
    }
    
    func configurePlayer() {
        guard let video = video else {
            Alert.presentPlaybackError(on: self)
            return
        }
        
        if video.isDownloaded {
            playVideo(withURL: video.filePath)
            return
        }
        
        switch video.type {
        case .url, .broadcast:
            playVideo(withURL: video.url)
        case .youtube:
            XCDYouTubeClient.default().getVideoWithIdentifier(video.youtubeID) { (video, error) in
                if let streamURLs = video?.streamURLs, let streamURL = (streamURLs[XCDYouTubeVideoQualityHTTPLiveStreaming] ?? streamURLs[YouTubeVideoQuality.hd720] ?? streamURLs[YouTubeVideoQuality.medium360] ?? streamURLs[YouTubeVideoQuality.small240]) {
                    self.playVideo(withURL: streamURL)
                } else {
                    DispatchQueue.main.async {
                        Alert.presentPlaybackError(on: self)
                    }
                }
            }
        }
    }
    
    func playVideo(withURL url: URL) {
        DispatchQueue.main.async {
            let playerItem = AVPlayerItem(url: url)
            self.player = AVPlayer(playerItem: playerItem)
            self.rateToken = self.player?.observe(\.rate, options: [.old, .new], changeHandler: { (player, change) in
                let userRate = SettingsManager.shared.playbackSpeed
                if change.oldValue == 0.0 && change.newValue != userRate {
                    player.rate = userRate
                }
            })
            self.statusToken = self.player?.observe(\.status, options: .new, changeHandler: { (playerItem, change) in
                if playerItem.status == .readyToPlay {
                    self.player?.play()
                } else {
                    Alert.presentPlaybackError(on: self)
                }
            })
            
            if SettingsManager.shared.resumePlayback {
                if let time = self.video?.lastPlayedTime  {
                    self.player?.seek(to: time, toleranceBefore: kCMTimeZero, toleranceAfter: kCMTimeZero)
                }
            }
            self.player?.play()
        }
    }
    
    @objc func enableBackgroundPlay() {
        // Disconnect the AVPlayer from the presentation when entering background
        backgroundPlayer = player
        player = nil
    }
    
    @objc func reconnectPlayer() {
        // Reconnect the AVPlayer to the presentation when returning to foreground
        if let backgroundPlayer = backgroundPlayer {
            player = backgroundPlayer
        }
    }
    
    // MARK: - Playback Gestures
    
    func addPlaybackControlGestures() {
        let backwardView = UIView()
        let forwardView = UIView()
        let stackView = UIStackView()
        
        backwardView.backgroundColor = .green
        forwardView.backgroundColor = .orange
        
        view.addSubview(stackView)
        
        // Configure backward double tap action
        let backRecognizer = UITapGestureRecognizer()
        backRecognizer.numberOfTouchesRequired = 2
        backRecognizer.addTarget(self, action: #selector(skipBack))
        backwardView.addGestureRecognizer(backRecognizer)
        
        // Configure forward double tap action
        let forwardRecognizer = UITapGestureRecognizer()
        forwardRecognizer.numberOfTouchesRequired = 2
        forwardRecognizer.addTarget(self, action: #selector(skipForward))
        forwardView.addGestureRecognizer(forwardRecognizer)

        // Configure stackView
        stackView.addArrangedSubview(backwardView)
        stackView.addArrangedSubview(forwardView)
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        stackView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        stackView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
    }
    
    @objc func skipBack() {
        print("back")
    }
    
    @objc func skipForward() {
        print("forward")
    }
    
    // MARK: - Playback Settings
    
    func addPlaybackMenu() {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(openMenu))
        view.addGestureRecognizer(recognizer)
    }
    
    @objc func openMenu() {
        let menu = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        
        let speedAction = UIAlertAction(title: "Playback Speed", style: .default) { _ in
            let submenu = UIAlertController(title: "Playback Speed", message: nil, preferredStyle: .actionSheet)
            for speed in Settings.Speeds {
                var actionTitle = "\(speed)"
                if SettingsManager.shared.playbackSpeed == speed {
                    actionTitle += "*"
                }
                submenu.addAction(UIAlertAction(title: actionTitle, style: .default, handler: { _ in
                    SettingsManager.shared.playbackSpeed = speed
                    self.player?.rate = speed
                }))
            }
            submenu.addAction(cancelAction)
            self.present(submenu, animated: true, completion: nil)
        }
        
        let restartAction = UIAlertAction(title: "Start Over", style: .default) { _ in
            self.player?.seek(to: CMTime(seconds: 0, preferredTimescale: 1), toleranceBefore: kCMTimeZero, toleranceAfter: kCMTimeZero)
        }
        
        let musicModeAction = UIAlertAction(title: "Enable Music Mode", style: .default) { _ in
            
        }
        
        menu.addAction(musicModeAction)
        menu.addAction(restartAction)
        menu.addAction(speedAction)
        menu.addAction(cancelAction)
        
        present(menu, animated: true, completion: nil)
    }
    
}

