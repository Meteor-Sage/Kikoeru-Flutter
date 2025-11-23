import Flutter
import UIKit
import AVKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var floatingLyricManager: FloatingLyricManager?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    floatingLyricManager = FloatingLyricManager(controller: controller)
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

class FloatingLyricManager: NSObject, AVPictureInPictureControllerDelegate {
    private var pipController: AVPictureInPictureController?
    private var playerLayer: AVPlayerLayer?
    private var player: AVPlayer?
    private var lyricView: UILabel?
    private var channel: FlutterMethodChannel
    
    // Base64 of a 1-second black MP4 video
    private let dummyVideoBase64 = "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"

    init(controller: FlutterViewController) {
        channel = FlutterMethodChannel(name: "com.kikoeru.flutter/floating_lyric", binaryMessenger: controller.binaryMessenger)
        super.init()
        
        channel.setMethodCallHandler { [weak self] (call, result) in
            self?.handleMethodCall(call, result: result)
        }
        
        setupAudioSession()
        setupPlayer(in: controller.view)
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }
    
    private func setupPlayer(in view: UIView) {
        guard let data = Data(base64Encoded: dummyVideoBase64) else { return }
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("pip_video.mp4")
        try? data.write(to: fileURL)
        
        let playerItem = AVPlayerItem(url: fileURL)
        player = AVPlayer(playerItem: playerItem)
        player?.isMuted = true
        player?.allowsExternalPlayback = true
        // Loop the video
        player?.actionAtItemEnd = .none
        NotificationCenter.default.addObserver(self,
                                             selector: #selector(playerItemDidReachEnd(notification:)),
                                             name: .AVPlayerItemDidPlayToEndTime,
                                             object: player?.currentItem)
        
        playerLayer = AVPlayerLayer(player: player)
        playerLayer?.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        playerLayer?.opacity = 0.01
        view.layer.addSublayer(playerLayer!)
        
        if AVPictureInPictureController.isPictureInPictureSupported() {
            pipController = AVPictureInPictureController(playerLayer: playerLayer!)
            pipController?.delegate = self
            // Hide controls
            pipController?.setValue(1, forKey: "controlsStyle")
        }
    }
    
    @objc func playerItemDidReachEnd(notification: Notification) {
        if let playerItem = notification.object as? AVPlayerItem {
            playerItem.seek(to: CMTime.zero, completionHandler: nil)
        }
    }
    
    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "show":
            let args = call.arguments as? [String: Any]
            let text = args?["text"] as? String ?? "Lyrics"
            show(text: text, args: args)
            result(true)
        case "hide":
            hide()
            result(true)
        case "updateText":
            let args = call.arguments as? [String: Any]
            let text = args?["text"] as? String ?? ""
            updateText(text)
            result(true)
        case "updateStyle":
            let args = call.arguments as? [String: Any]
            updateStyle(args: args)
            result(true)
        case "hasPermission":
            result(true)
        case "requestPermission":
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func show(text: String, args: [String: Any]?) {
        if pipController?.isPictureInPictureActive == true {
            updateText(text)
            updateStyle(args: args)
            return
        }
        
        player?.play()
        pipController?.startPictureInPicture()
        prepareLyricView(text: text)
        updateStyle(args: args)
    }
    
    private func hide() {
        pipController?.stopPictureInPicture()
        player?.pause()
    }
    
    private func updateText(_ text: String) {
        DispatchQueue.main.async {
            self.lyricView?.text = text
            self.lyricView?.setNeedsLayout()
        }
    }
    
    private func updateStyle(args: [String: Any]?) {
        guard let args = args else { return }
        
        DispatchQueue.main.async {
            guard let view = self.lyricView else { return }
            
            if let fontSize = args["fontSize"] as? Double {
                view.font = UIFont.systemFont(ofSize: CGFloat(fontSize), weight: .medium)
            }
            
            if let textColorInt = args["textColor"] as? Int {
                view.textColor = self.colorFromInt(textColorInt)
            }
            
            if let backgroundColorInt = args["backgroundColor"] as? Int {
                view.backgroundColor = self.colorFromInt(backgroundColorInt)
            }
            
            if let cornerRadius = args["cornerRadius"] as? Double {
                view.layer.cornerRadius = CGFloat(cornerRadius)
            }
        }
    }
    
    private func colorFromInt(_ argb: Int) -> UIColor {
        let a = CGFloat((argb >> 24) & 0xFF) / 255.0
        let r = CGFloat((argb >> 16) & 0xFF) / 255.0
        let g = CGFloat((argb >> 8) & 0xFF) / 255.0
        let b = CGFloat(argb & 0xFF) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
    
    private func prepareLyricView(text: String) {
        if lyricView == nil {
            lyricView = UILabel()
            lyricView?.textColor = .white
            lyricView?.backgroundColor = UIColor(white: 0.0, alpha: 0.3) // Default style
            lyricView?.font = UIFont.systemFont(ofSize: 20, weight: .medium)
            lyricView?.textAlignment = .center
            lyricView?.numberOfLines = 0
            lyricView?.layer.cornerRadius = 8
            lyricView?.clipsToBounds = true
            // Remove shadow
            lyricView?.shadowColor = .clear
            lyricView?.shadowOffset = .zero
        }
        lyricView?.text = text
    }
    
    // MARK: - AVPictureInPictureControllerDelegate
    
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        // Add view to the PiP window
        // Note: This relies on the fact that the PiP window becomes available in windows list
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let window = UIApplication.shared.windows.first {
                if let view = self.lyricView {
                    view.frame = window.bounds
                    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    window.addSubview(view)
                    window.bringSubviewToFront(view)
                }
            }
        }
    }
    
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        lyricView?.removeFromSuperview()
        player?.pause()
        channel.invokeMethod("onClose", arguments: nil)
    }
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        print("PiP failed: \(error)")
    }
}
