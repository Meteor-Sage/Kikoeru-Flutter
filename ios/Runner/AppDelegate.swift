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
    private let dummyVideoBase64 = "AAAAHGZ0eXBtcDQyAAAAAWlzb21tcDQxbXA0MgAAAAFtZGF0AAAAAAAAAPAAAAAeBgUaR1ZK3FxMQz+U78URPNFDqAHdzMzdAgAI6YCAAAAAeyW4IAX/8QJz/GmH5ojGf7TPN7+nV8VhVGWvLk5AAAADATq0wr9+feS/mlJDhSFZNf/4hRF+6oyeBBnUM5xSMqmb8QFtnSOPLNO3XBJMqgABUi4AByNU+UFwm4gdXXCykATptDAQ02nHTpwhEqHUVhZMvYh3tIZP4G5VQAAAABsh4QhE/wAGhiENK/5aD+Fa4IQ5b0OeIW1T2vEAAAAcIeIQRv/kQUkTxE79KjKNfMiUEQ2axpWzkkhgUwAAAuFtb292AAAAbG12aGQAAAAA2/A0ytvwNMoAAAJYAAAGDQABAAABAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAACbXRyYWsAAABcdGtoZAAAAAHb8DTK2/A0ygAAAAEAAAAAAAAGDQAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAEAAAAABngAAANAAAAAAACRlZHRzAAAAHGVsc3QAAAAAAAAAAQAABg0AAAJYAAEAAAAAAeVtZGlhAAAAIG1kaGQAAAAA2/A0ytvwNMoAAAJYAAAIZVXEAAAAAAAxaGRscgAAAAAAAAAAdmlkZQAAAAAAAAAAAAAAAENvcmUgTWVkaWEgVmlkZW8AAAABjG1pbmYAAAAUdm1oZAAAAAEAAAAAAAAAAAAAACRkaW5mAAAAHGRyZWYAAAAAAAAAAQAAAAx1cmwgAAAAAQAAAUxzdGJsAAAAkXN0c2QAAAAAAAAAAQAAAIFhdmMxAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAZ4A0ABIAAAASAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAGP//AAAAK2F2Y0MBZAAN/+EAECdkAA2sVsGhvrmoEBAVIEABAAQo7jyw/fj4AAAAACBzdHRzAAAAAAAAAAIAAAACAAACWAAAAAEAAAO1AAAAGGN0dHMAAAAAAAAAAQAAAAMAAAJYAAAAFHN0c3MAAAAAAAAAAQAAAAEAAAAPc2R0cAAAAAAgEBAAAAAcc3RzYwAAAAAAAAABAAAAAQAAAAEAAAABAAAAIHN0c3oAAAAAAAAAAAAAAAMAAAChAAAAHwAAACAAAAAcc3RjbwAAAAAAAAADAAAALAAAAM0AAADs"

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
