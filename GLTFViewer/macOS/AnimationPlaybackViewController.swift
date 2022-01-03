
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

    private var nominalStartTime: TimeInterval = 0.0
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

        var minStartTime: TimeInterval = TimeInterval.greatestFiniteMagnitude
        var maxDuration: TimeInterval = 0
        var longestAnimation: SCNAnimation? = nil

        for channel in animation.channels {
            if channel.animation.startDelay < minStartTime {
                minStartTime = channel.animation.startDelay
            }
            channel.animation.usesSceneTimeBase = true

            channel.target.addAnimation(channel.animation, forKey:nil)
            animatedNodes.insert(channel.target)
            if channel.animation.duration > maxDuration {
                maxDuration = channel.animation.duration
                longestAnimation = channel.animation
            }
        }

        currentAnimationDuration = maxDuration
        nominalStartTime = minStartTime

        let endEvent = SCNAnimationEvent(keyTime: 1.0) { [weak self] animation, animatedObject, playingBackwards in
            DispatchQueue.main.async {
                self?.handleAnimationEnd()
            }
        }
        longestAnimation?.animationEvents = [endEvent]

        if longestAnimation == nil {
            print("WARNING: Did not find animation with duration > 0 loop modes will not behave correctly")
        }

        progressSlider.minValue = 0
        progressSlider.maxValue = currentAnimationDuration
        progressSlider.floatValue = 0
        sceneView.sceneTime = nominalStartTime

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
        let time = sceneView.sceneTime - nominalStartTime
        if forceUpdateSlider {
            progressSlider.doubleValue = fmod(time, currentAnimationDuration)
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

        sceneView.sceneTime = progressSlider.doubleValue + nominalStartTime
        updateProgressDisplay(forceUpdateSlider: false)
    }

    @objc
    func playbackTimerDidFire(_ sender: Any) {
        let time = sceneView.sceneTime + AnimationFrameDuration
        sceneView.sceneTime = time
        updateProgressDisplay(forceUpdateSlider: true)
    }
}
