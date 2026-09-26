import Foundation
import AppKit

// MARK: - Now Playing
/// What's playing in Apple Music or Spotify. Both apps broadcast player changes as
/// distributed notifications, so this needs no microphone and no Automation permission,
/// and it works with headphones (the mic-based AudioMonitor can't hear those).
final class NowPlayingMonitor {
    static let shared = NowPlayingMonitor()

    struct Track: Equatable {
        let name: String
        let artist: String
        let source: String   // "Music" or "Spotify"
    }

    private(set) var isPlaying = false
    private(set) var track: Track?
    /// Called on the main queue when playback starts/stops or the track changes.
    var onChange: ((_ isPlaying: Bool, _ track: Track?, _ isNewTrack: Bool) -> Void)?

    private init() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: NSNotification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main) { [weak self] note in
            self?.handle(note.userInfo, source: "Music")
        }
        center.addObserver(forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] note in
            self?.handle(note.userInfo, source: "Spotify")
        }
    }

    private func handle(_ info: [AnyHashable: Any]?, source: String) {
        let state = (info?["Player State"] as? String)?.lowercased() ?? ""
        let playing = (state == "playing")
        var newTrack = track
        if let name = info?["Name"] as? String, !name.isEmpty {
            newTrack = Track(name: name, artist: (info?["Artist"] as? String) ?? "", source: source)
        }
        let isNewTrack = playing && newTrack != track
        guard playing != isPlaying || isNewTrack else { return }

        isPlaying = playing
        track = newTrack
        print("🎵 [NowPlaying] \(playing ? "Playing" : "Stopped"): \(newTrack?.name ?? "?") — \(newTrack?.artist ?? "?") (\(source))")
        onChange?(playing, newTrack, isNewTrack)
    }
}

// MARK: - Behavior Director
/// Turns what the user is doing into how Byte behaves, so he reads the room:
///
/// | Situation                    | Byte                                                        |
/// |------------------------------|-------------------------------------------------------------|
/// | Music playing                | Dances, headbangs, spins; gets extra excited for artists you play a lot |
/// | Focused work (IDE/terminal)  | Walks aside, sits, and quietly watches your screen          |
/// | Focused work + music         | Sits aside and bobs along now and then, still quiet         |
/// | Video call                   | Moves out of the way and stays completely silent            |
/// | Long focus session ends      | Stretches and cheers you on                                 |
final class BehaviorDirector {
    enum Vibe: String {
        case normal
        case party          // music, not working
        case watchingWork   // focused work, no music
        case vibingWork     // focused work with music
        case meeting        // video call
    }

    private unowned let brain: PetBrain
    private(set) var vibe: Vibe = .normal

    // Hysteresis so a quick alt-tab to a browser doesn't make Byte stand up and sit down again.
    private var candidate: Vibe = .normal
    private var candidateSince = Date()
    private var lastEvaluation = Date.distantPast

    // Where Byte settled for this vibe; if the user drags him off, he goes back.
    private var isSettled = false
    private var lastSettleAttempt = Date.distantPast
    private var workStartedAt: Date?
    private var lastGrooveAt = Date.distantPast
    private var lastTrackCommentAt = Date.distantPast

    private var watchJitter = CGPoint.zero
    private var lastJitterAt = Date.distantPast

    init(brain: PetBrain) {
        self.brain = brain
        NowPlayingMonitor.shared.onChange = { [weak self] playing, track, isNewTrack in
            self?.musicChanged(playing: playing, track: track, isNewTrack: isNewTrack)
        }
    }

    // MARK: Queries used by PetBrain / PetScene

    var isWorking: Bool { vibe == .watchingWork || vibe == .vibingWork }

    /// While true, Byte doesn't chatter on his own or wander off on LLM whims.
    var suppressesAmbient: Bool { isWorking || vibe == .meeting }

    /// Where Byte's eyes should rest while he watches you work: the front window, with
    /// small curious glances around it. In the same units PetScene's lookAt() uses.
    func watchTarget() -> CGPoint? {
        guard isWorking || vibe == .meeting, isSettled else { return nil }
        guard let window = DesktopEnvironmentManager.shared.visibleElements.first(where: { $0.type == .window }) else { return nil }
        let screen = CGDisplayBounds(CGMainDisplayID())
        guard screen.width > 0, screen.height > 0 else { return nil }

        if Date().timeIntervalSince(lastJitterAt) > Double.random(in: 1.5...4.0) {
            lastJitterAt = Date()
            // Mostly small glances; now and then a bigger look, like reading along.
            let range: CGFloat = Double.random(in: 0...1) < 0.2 ? 260 : 90
            watchJitter = CGPoint(x: .random(in: -range...range), y: .random(in: -range * 0.4...range * 0.4))
        }
        // Same screen→world mapping as PetBrain.findFreeCorner(), scaled like lookAt() expects.
        let worldX = (window.frame.midX / screen.width - 0.5) * 70.0
        let worldY = (0.5 - window.frame.midY / screen.height) * 30.0
        return CGPoint(x: worldX * 40 + watchJitter.x, y: worldY * 40 + watchJitter.y)
    }

    // MARK: Per-frame update (cheap: re-evaluates once a second)

    func update() {
        let now = Date()
        guard now.timeIntervalSince(lastEvaluation) >= 1.0 else { return }
        lastEvaluation = now

        let desired = desiredVibe()
        if desired != candidate {
            candidate = desired
            candidateSince = now
        }
        guard candidate != vibe, now.timeIntervalSince(candidateSince) >= delay(from: vibe, to: candidate) else { return }
        transition(to: candidate)
    }

    private func desiredVibe() -> Vibe {
        let music = NowPlayingMonitor.shared.isPlaying
        // Manual modes from the menu win: Sleep means leave him be, Play means never "work".
        if brain.currentMode == .sleep { return .normal }
        if brain.currentMode == .play { return music ? .party : .normal }
        let focus = FocusEngine.shared.currentFocusLevel
        switch focus {
        case .meeting:
            return .meeting
        case .deepWork, .debugging:
            return music ? .vibingWork : .watchingWork
        case .casual, .idle:
            return music ? .party : .normal
        }
    }

    /// Enter meetings instantly; settle into work after a few seconds of it; only leave
    /// work after a longer break so glancing at docs doesn't break his focus spot.
    private func delay(from old: Vibe, to new: Vibe) -> TimeInterval {
        if new == .meeting { return 0 }
        let oldWork = (old == .watchingWork || old == .vibingWork)
        let newWork = (new == .watchingWork || new == .vibingWork)
        if oldWork && newWork { return 1 }      // music toggled while working
        if oldWork { return 45 }                // leaving work
        if newWork { return 5 }                 // starting work
        return 2
    }

    private func transition(to newVibe: Vibe) {
        let old = vibe
        vibe = newVibe
        print("🎭 [BehaviorDirector] \(old.rawValue) → \(newVibe.rawValue)")
        guard brain.currentMode != .sleep, brain.currentAction != .sleep else { return }

        switch newVibe {
        case .watchingWork, .vibingWork:
            if workStartedAt == nil { workStartedAt = Date() }
            if old == .watchingWork || old == .vibingWork {
                // Already in his spot; just change the mood.
                brain.currentEmotion = newVibe == .vibingWork ? .happy : .curious
                brain.forceUpdate = true
            } else {
                goAside(emotion: .curious)
            }
        case .meeting:
            goAside(emotion: .normal)
        case .party:
            finishWorkSession()
            isSettled = false
            startGroove(celebrateArtist: true)
        case .normal:
            finishWorkSession()
            isSettled = false
            if old != .normal, brain.currentAction == .sit {
                brain.applyAction(.idle)
            }
        }
    }

    private func goAside(emotion: PetEmotion) {
        isSettled = false
        lastSettleAttempt = Date()
        brain.pendingWalkTarget = findWatchSpot()
        brain.stateMachine.enter(PetWanderState.self)
        brain.arrivalAction = .sit        // after entering: a normal wander clears it
        brain.currentEmotion = emotion
        brain.forceUpdate = true
    }

    /// Called by PetBrain when Byte sits down after walking to his spot.
    func didSettle() {
        guard suppressesAmbient else { return }
        isSettled = true
        brain.currentEmotion = vibe == .vibingWork ? .happy : (vibe == .meeting ? .normal : .curious)
        brain.forceUpdate = true
    }

    private func finishWorkSession() {
        guard let started = workStartedAt else { return }
        workStartedAt = nil
        let minutes = Date().timeIntervalSince(started) / 60
        guard minutes >= 25 else { return }
        // A long stretch of focus is worth a little celebration.
        brain.applyAction(.stretch)
        brain.currentEmotion = .proud
        brain.onShowParticle?(.sparkle)
        if !brain.isMuted && InteractionDirector.shared.shouldSpeak(.reactive) {
            let context = "The user just finished a focused work session of about \(Int(minutes)) minutes and is taking a break. Cheer them on briefly and maybe suggest water or a stretch."
            brain.speakReaction(context: context, emotion: "proud", event: "focus session ended after \(Int(minutes)) minutes")
        }
    }

    // MARK: Idle ticks

    /// PetIdleState asks this before picking its own next action. Returns the seconds until
    /// the next tick if the director handled it, or nil to fall back to normal behavior.
    func handleIdleTick() -> TimeInterval? {
        switch vibe {
        case .normal:
            return nil

        case .watchingWork, .meeting:
            resettleIfNeeded()
            return TimeInterval.random(in: 8...15)

        case .vibingWork:
            resettleIfNeeded()
            // Bob along quietly now and then, then sit back down.
            if isSettled, Date().timeIntervalSince(lastGrooveAt) > Double.random(in: 25...45) {
                lastGrooveAt = Date()
                brain.applyAction(.headbang)
                brain.currentEmotion = .happy
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
                    guard let self = self, self.vibe == .vibingWork, self.brain.currentAction == .headbang else { return }
                    self.brain.applyAction(.sit)
                    self.brain.currentEmotion = .happy
                }
            }
            return TimeInterval.random(in: 6...10)

        case .party:
            startGroove(celebrateArtist: false)
            return TimeInterval.random(in: 4...8)
        }
    }

    /// If the user dragged or clicked him away from his spot, walk back after a moment.
    private func resettleIfNeeded() {
        guard brain.currentAction != .sit, brain.currentAction != .headbang,
              Date().timeIntervalSince(lastSettleAttempt) > 10 else { return }
        goAside(emotion: vibe == .meeting ? .normal : .curious)
    }

    private func startGroove(celebrateArtist: Bool) {
        let isFavorite = NowPlayingMonitor.shared.track.map { isFavoriteArtist($0.artist) } ?? false
        let moves: [PetAction] = [.dance, .dance, .headbang, .spin, .jump, .dance, .backflip]
        brain.applyAction(moves.randomElement() ?? .dance)
        brain.currentEmotion = isFavorite ? .love : .excited
        if celebrateArtist && isFavorite {
            brain.onShowParticle?(.heart)
        }
    }

    // MARK: Music personalization

    private func musicChanged(playing: Bool, track: NowPlayingMonitor.Track?, isNewTrack: Bool) {
        guard playing, isNewTrack, let track = track else { return }
        // Remember who they listen to. Repeat plays raise the fact's rank in Byte's memory,
        // so their favorite artists come up naturally in conversation.
        if !track.artist.isEmpty {
            MemoryGraph.shared.addFact(subject: "User", predicate: "listens to", object: track.artist)
        }

        guard vibe == .party else { return }   // stay quiet while they work
        let favorite = isFavoriteArtist(track.artist)
        brain.onShowParticle?(favorite ? .heart : .sparkle)

        // An occasional word about the song, not a DJ announcement for every track.
        guard !brain.isMuted, Date().timeIntervalSince(lastTrackCommentAt) > 600,
              InteractionDirector.shared.shouldSpeak(.reactive) else { return }
        lastTrackCommentAt = Date()
        let byArtist = track.artist.isEmpty ? "" : " by \(track.artist)"
        let fondness = favorite ? " They play this artist a lot; you know it's one of their favorites." : ""
        let context = "The user just started playing '\(track.name)'\(byArtist) in \(track.source).\(fondness) React in one short, excited line while you dance."
        brain.speakReaction(context: context, emotion: "excited", event: "song started")
    }

    private func isFavoriteArtist(_ artist: String) -> Bool {
        guard !artist.isEmpty else { return false }
        return MemoryGraph.shared.mentionCount(subject: "User", predicate: "listens to", object: artist) >= 5
    }

    // MARK: Spot finding

    /// A bottom corner away from the window the user is working in, so Byte is out of
    /// the way but can still see the screen. In PetBrain.findFreeCorner()'s world units.
    private func findWatchSpot() -> (CGFloat, CGFloat) {
        let screen = CGDisplayBounds(CGMainDisplayID())
        let windows = DesktopEnvironmentManager.shared.visibleElements.filter { $0.type == .window }
        let focus = windows.first?.frame ?? CGRect(x: screen.midX, y: screen.midY, width: 1, height: 1)

        let spots = [CGPoint(x: screen.width * 0.08, y: screen.height * 0.9),
                     CGPoint(x: screen.width * 0.92, y: screen.height * 0.9)]
        let best = spots.max { a, b in
            score(a, focus: focus, windows: windows) < score(b, focus: focus, windows: windows)
        } ?? spots[0]

        return ((best.x / screen.width - 0.5) * 70.0, (0.5 - best.y / screen.height) * 30.0)
    }

    private func score(_ p: CGPoint, focus: CGRect, windows: [DesktopElement]) -> CGFloat {
        let distance = hypot(p.x - focus.midX, p.y - focus.midY)
        let covered = windows.contains { $0.frame.contains(p) } ? 400 : 0
        return distance - CGFloat(covered)
    }
}
