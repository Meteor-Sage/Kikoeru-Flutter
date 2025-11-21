import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }
  
  override func applicationDidFinishLaunching(_ notification: Notification) {
    let controller : FlutterViewController = mainFlutterWindow?.contentViewController as! FlutterViewController
    FloatingLyricPlugin.register(with: controller.registrar(forPlugin: "FloatingLyricPlugin"))
    super.applicationDidFinishLaunching(notification)
  }
}

public class FloatingLyricPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.kikoeru.flutter/floating_lyric", binaryMessenger: registrar.messenger)
        let instance = FloatingLyricPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    private var lyricWindow: FloatingLyricWindow?

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "show":
            let args = call.arguments as? [String: Any]
            let text = args?["text"] as? String ?? "♪ - ♪"
            show(text: text)
            result(true)
        case "hide":
            hide()
            result(true)
        case "updateText":
            let args = call.arguments as? [String: Any]
            let text = args?["text"] as? String ?? ""
            updateText(text: text)
            result(true)
        case "updateStyle":
            if let args = call.arguments as? [String: Any] {
                updateStyle(args: args)
            }
            result(true)
        case "hasPermission":
            result(true)
        case "requestPermission":
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func show(text: String) {
        if lyricWindow == nil {
            lyricWindow = FloatingLyricWindow()
        }
        lyricWindow?.updateText(text)
        lyricWindow?.orderFront(nil)
    }

    private func hide() {
        lyricWindow?.orderOut(nil)
        lyricWindow = nil
    }

    private func updateText(text: String) {
        lyricWindow?.updateText(text)
    }

    private func updateStyle(args: [String: Any]) {
        lyricWindow?.updateStyle(args: args)
    }
}

class FloatingLyricWindow: NSPanel {
    private let lyricView = NSTextField()
    private let backgroundView = NSView()
    
    // Style properties
    private var _fontSize: CGFloat = 24.0
    private var _textColor: NSColor = .white
    private var _backgroundColor: NSColor = .black.withAlphaComponent(0.5)
    private var _cornerRadius: CGFloat = 8.0
    private var _paddingHorizontal: CGFloat = 16.0
    private var _paddingVertical: CGFloat = 8.0

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.level = .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.isMovableByWindowBackground = true
        
        setupUI()
        center()
    }
    
    private func setupUI() {
        // Setup background view for rounded corners and color
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = _cornerRadius
        backgroundView.layer?.backgroundColor = _backgroundColor.cgColor
        
        self.contentView = backgroundView
        
        // Setup text field
        lyricView.isEditable = false
        lyricView.isBordered = false
        lyricView.drawsBackground = false
        lyricView.alignment = .center
        lyricView.textColor = _textColor
        lyricView.font = NSFont.systemFont(ofSize: _fontSize, weight: .bold)
        
        backgroundView.addSubview(lyricView)
    }
    
    func updateText(_ text: String) {
        lyricView.stringValue = text
        resizeToFit()
    }
    
    func updateStyle(args: [String: Any]) {
        if let fontSize = args["fontSize"] as? Double {
            _fontSize = CGFloat(fontSize)
        }
        if let textColorInt = args["textColor"] as? Int {
            _textColor = colorFromInt(textColorInt)
        }
        if let bgColorInt = args["backgroundColor"] as? Int {
            _backgroundColor = colorFromInt(bgColorInt)
        }
        if let cornerRadius = args["cornerRadius"] as? Double {
            _cornerRadius = CGFloat(cornerRadius)
        }
        if let paddingH = args["paddingHorizontal"] as? Double {
            _paddingHorizontal = CGFloat(paddingH)
        }
        if let paddingV = args["paddingVertical"] as? Double {
            _paddingVertical = CGFloat(paddingV)
        }
        
        // Apply styles
        lyricView.font = NSFont.systemFont(ofSize: _fontSize, weight: .bold)
        lyricView.textColor = _textColor
        backgroundView.layer?.backgroundColor = _backgroundColor.cgColor
        backgroundView.layer?.cornerRadius = _cornerRadius
        
        resizeToFit()
    }
    
    private func resizeToFit() {
        let text = lyricView.stringValue
        let font = lyricView.font ?? NSFont.systemFont(ofSize: _fontSize)
        let size = (text as NSString).size(withAttributes: [.font: font])
        
        let width = size.width + _paddingHorizontal * 2
        let height = size.height + _paddingVertical * 2
        
        // Keep current position
        let currentFrame = self.frame
        let newFrame = NSRect(x: currentFrame.origin.x, y: currentFrame.origin.y, width: width, height: height)
        
        self.setFrame(newFrame, display: true)
        
        lyricView.frame = NSRect(x: _paddingHorizontal, y: _paddingVertical, width: size.width, height: size.height)
        backgroundView.frame = NSRect(x: 0, y: 0, width: width, height: height)
    }
    
    private func colorFromInt(_ value: Int) -> NSColor {
        let alpha = CGFloat((value >> 24) & 0xFF) / 255.0
        let red = CGFloat((value >> 16) & 0xFF) / 255.0
        let green = CGFloat((value >> 8) & 0xFF) / 255.0
        let blue = CGFloat(value & 0xFF) / 255.0
        return NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}
