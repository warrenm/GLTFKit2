
import Cocoa
import GLTFKit2

fileprivate let AnimationFrameDuration = 1 / 60.0

class AnimationPlaybackViewController : NSViewController {
    enum AnimationPlaybackState {
        case stopped
        case playing
        case paused
    }

    enum AnimationLoopMode {
        case dontLoop
        case loopOne
        case loopAll
    }

    var sceneView: SCNView!

    var animations: [GLTFSCNAnimation] = [] {
        didSet {
            let names = animations.map { $0.name }
            animationNamePopUp.removeAllItems()
            animationNamePopUp.addItems(withTitles: names)

            if animationNamePopUp.indexOfSelectedItem < animations.count {
                startAnimation(at: animationNamePopUp.indexOfSelectedItem)
            }
            pauseAnimation()
        }
    }

    @IBOutlet var animationNamePopUp: NSPopUpButton!
    @IBOutlet var modeSegmentedControl: NSSegmentedControl!
    @IBOutlet var playPauseButton: NSButton!
    @IBOutlet var progressLabel: NSTextField!
    @IBOutlet var progressSlider: NSSlider!
    @IBOutlet var durationLabel: NSTextField!

    private var currentAnimationDuration: TimeInterval = 0.0
    private var playbackTimer: Timer?
    private var state: AnimationPlaybackState = .stopped
    private var loopMode: AnimationLoopMode = .loopOne
    private var animatedNodes = Set<SCNNode>()
    private let timeFormatter = NumberFormatter()

    override func viewDidLoad() {
        super.viewDidLoad()

        let labelFont = NSFont.monospacedDigitSystemFont(ofSize: progressLabel.font!.pointSize, weight: .regular)
        progressLabel.font = labelFont
        durationLabel.font = labelFont

        progressLabel.stringValue = "-.--"
        durationLabel.stringValue = "-.--"

        timeFormatter.maximumFractionDigits = 2
        timeFormatter.minimumFractionDigits = 2
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        stopAnimation()
    }

    func schedulePlaybackTimer() {
        playbackTimer = Timer.scheduledTimer(timeInterval: AnimationFrameDuration,
                                             target: self,
                                             selector: #selector(playbackTimerDidFire(_:)),
                                             userInfo: nil,
                                             repeats: true)
    }

    func invalidatePlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    func startAnimation(at index: Int) {
        let animation = animations[index]
        var maxDuration: TimeInterval = 0

        for channel in animation.channels {
            let channelAnimation = channel.animation
            channelAnimation.usesSceneTimeBase = true
            let animationPlayer = SCNAnimationPlayer(animation: channelAnimation)
            channel.target.addAnimationPlayer(animationPlayer, forKey: nil)
            animatedNodes.insert(channel.target)
            if channelAnimation.duration > maxDuration {
                maxDuration = channelAnimation.duration
            }
        }

        currentAnimationDuration = maxDuration

        if maxDuration == 0 {
            print("WARNING: Did not find animation with duration > 0; loop modes will not behave correctly")
        }

        progressSlider.minValue = 0
        progressSlider.maxValue = currentAnimationDuration
        progressSlider.floatValue = 0
        sceneView.sceneTime = 0.0

        schedulePlaybackTimer()

        state = .playing
    }

    func stopAnimation() {
        switch state {
        case .paused:
            fallthrough
        case .playing:
            removeAllAnimations()
            invalidatePlaybackTimer()
            progressSlider.minValue = 0
            progressSlider.maxValue = 1
            progressSlider.floatValue = 0
            sceneView.sceneTime = 0
        default:
            break
        }

        state = .stopped
    }

    func pauseAnimation() {
        if state == .playing {
            invalidatePlaybackTimer()
            state = .paused
        }
    }

    func removeAllAnimations() {
        for obj in animatedNodes {
            obj.removeAllAnimations()
        }
        animatedNodes.removeAll()
    }

    func handleAnimationEnd() {
        if state == .playing {
            switch loopMode {
            case .dontLoop:
                pauseAnimation()
            case .loopAll:
                advanceToNextAnimation()
            default:
                break
            }
        }
    }

    func advanceToNextAnimation() {
        stopAnimation()
        let nextIndex = (animationNamePopUp.indexOfSelectedItem + 1) % animationNamePopUp.numberOfItems
        animationNamePopUp.selectItem(at: nextIndex)
        if animationNamePopUp.indexOfSelectedItem < animations.count {
            startAnimation(at: animationNamePopUp.indexOfSelectedItem)
        }

    }

    func updateProgressDisplay(forceUpdateSlider: Bool) {
        let time = sceneView.sceneTime
        if forceUpdateSlider {
            progressSlider.doubleValue = time
        }
        progressLabel.stringValue = timeFormatter.string(from: NSNumber(value: fmod(time, currentAnimationDuration)))!
        durationLabel.stringValue = timeFormatter.string(from: NSNumber(value: currentAnimationDuration))!
    }

    @IBAction
    func didClickPlayPause(_ sender: Any) {
        switch state {
        case .playing:
            invalidatePlaybackTimer()
            state = .paused
        case .paused:
            schedulePlaybackTimer()
            state = .playing
        case .stopped:
            if animationNamePopUp.indexOfSelectedItem < animations.count {
                startAnimation(at: animationNamePopUp.indexOfSelectedItem)
            }
            state = .playing
        }
    }

    @IBAction
    func didSelectAnimationName(_ sender: Any) {
        stopAnimation()
        if animationNamePopUp.indexOfSelectedItem < animations.count {
            startAnimation(at: animationNamePopUp.indexOfSelectedItem)
        }
    }

    @IBAction
    func didSelectMode(_ sender: Any) {
        switch modeSegmentedControl.indexOfSelectedItem {
        case 0: // Loop All
            loopMode = .loopAll
        case 1: // Loop One
            loopMode = .loopOne
        case 2: // No Loop
            loopMode = .dontLoop
        default:
            break
        }
    }

    @IBAction
    func progressValueDidChange(_ sender: Any) {
        switch state {
        case .playing:
            invalidatePlaybackTimer()
            state = .paused
        default:
            break
        }

        sceneView.sceneTime = fmod(progressSlider.doubleValue, currentAnimationDuration)
        updateProgressDisplay(forceUpdateSlider: false)
    }

    @objc
    func playbackTimerDidFire(_ sender: Any) {
        let time = sceneView.sceneTime + AnimationFrameDuration
        let wouldLoop = time > currentAnimationDuration
        if wouldLoop && (loopMode == .dontLoop) {
            sceneView.sceneTime = 0.0
            handleAnimationEnd()
        } else {
            sceneView.sceneTime = fmod(time, currentAnimationDuration)
        }
        updateProgressDisplay(forceUpdateSlider: true)
    }
}
