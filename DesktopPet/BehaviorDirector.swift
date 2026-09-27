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

// MARK: - Xcode Builds
/// Notices when an Xcode build finishes, from Xcode or `xcodebuild`, by watching for new
/// .xcactivitylog files in each project's DerivedData/…/Logs/Build. Every build writes
/// one, and a failed build's log contains "Build failed". (LogStoreManifest.plist looked
/// easier but skips some failed builds entirely.) No Xcode plugin or permission needed.
final class XcodeBuildMonitor {
    /// (failed, project name), on the main queue.
    var onBuildFinished: ((Bool, String) -> Void)?

    private let derivedData = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Developer/Xcode/DerivedData")
    private var timer: Timer?
    private var seen = Set<String>()
    /// Logs from before Byte started are history, not news.
    private let startedAt = Date()
    private let queue = DispatchQueue(label: "com.byte.buildmonitor", qos: .utility)

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            self?.queue.async { self?.poll() }
        }
    }

    private func poll() {
        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(atPath: derivedData.path) else { return }
        let settled = Date().addingTimeInterval(-2)       // written and closed, not mid-write
        for project in projects {
            let logsDir = derivedData.appendingPathComponent(project).appendingPathComponent("Logs/Build")
            guard let names = try? fm.contentsOfDirectory(atPath: logsDir.path) else { continue }
            for name in names where name.hasSuffix(".xcactivitylog") && !seen.contains(name) {
                let url = logsDir.appendingPathComponent(name)
                guard let mtime = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else { continue }
                if mtime < startedAt { seen.insert(name); continue }
                guard mtime < settled else { continue }
                seen.insert(name)
                let failed = logSaysFailed(url)
                // "DesktopPet-glpgbx…" → "DesktopPet"
                let projectName = project.components(separatedBy: "-").dropLast().joined(separator: "-")
                print("🔨 [XcodeBuildMonitor] \(projectName) build \(failed ? "failed" : "succeeded")")
                DispatchQueue.main.async { self.onBuildFinished?(failed, projectName.isEmpty ? project : projectName) }
            }
        }
    }

    /// .xcactivitylog is gzip; decompress with the system gzip (fixed path and arguments).
    private func logSaysFailed(_ url: URL) -> Bool {
        let gzip = Process()
        gzip.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        gzip.arguments = ["-dc", url.path]
        let out = Pipe()
        gzip.standardOutput = out
        gzip.standardError = FileHandle.nullDevice
        guard (try? gzip.run()) != nil else { return false }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        gzip.waitUntilExit()
        return data.range(of: Data("Build failed".utf8)) != nil
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
/// | Back after 5+ minutes away   | Wakes up, waves, welcomes you back by name                  |
/// | First time at the Mac today  | A good morning / afternoon / evening                        |
/// | Xcode build fails            | Sympathy (and a nudge after repeated failures)              |
/// | Build passes after failures  | Cheers                                                      |
/// | Call ends                    | Stretches and asks how it went                              |
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

    // Day events
    private var awayStartedAt: Date?
    private static let awayThreshold: TimeInterval = 300    // same as InteractionDirector's "away"
    private static let dailyGreetingKey = "byte.lastDailyGreetingDay"
    private let buildMonitor = XcodeBuildMonitor()
    private var consecutiveBuildFailures = 0
    private var lastBuildRemarkAt = Date.distantPast

    init(brain: PetBrain) {
        self.brain = brain
        NowPlayingMonitor.shared.onChange = { [weak self] playing, track, isNewTrack in
            self?.musicChanged(playing: playing, track: track, isNewTrack: isNewTrack)
        }
        buildMonitor.onBuildFinished = { [weak self] failed, project in
            self?.buildFinished(failed: failed, project: project)
        }
        buildMonitor.start()
        #if DEBUG
        // Lets a developer (or a test) trigger a day event without waiting for it:
        //   distributed notification "com.byte.debug.dayEvent", userInfo ["event": "returned"]
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.byte.debug.dayEvent"), object: nil, queue: .main) { [weak self] note in
            self?.simulate(note.userInfo?["event"] as? String ?? "")
        }
        #endif
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

        checkPresence(now: now)

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

        if old == .meeting && newVibe != .meeting { callEnded() }

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

    // MARK: Day events

    /// Tracks stepping away and coming back, and the first moment at the Mac each day.
    private func checkPresence(now: Date) {
        let idle = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!)
        if idle >= Self.awayThreshold {
            if awayStartedAt == nil { awayStartedAt = now.addingTimeInterval(-idle) }
            return
        }
        guard idle < 3 else { return }           // wait for real input, not just "not away"

        if greetForNewDayIfNeeded(now: now) {
            awayStartedAt = nil                  // one greeting, not two
            return
        }
        if let since = awayStartedAt {
            awayStartedAt = nil
            welcomeBack(minutes: max(5, Int(now.timeIntervalSince(since) / 60)))
        }
    }

    private func callEnded() {
        react(event: "call ended", context: "The user's video call just ended. Ask briefly how it went.",
              emotion: .happy, action: .stretch)
    }

    private func welcomeBack(minutes: Int) {
        let project = MemoryGraph.shared.compactMemory(for: "project working building", musicContext: false, maxFacts: 1)
        let about = project.isEmpty ? "" : " What you know: \(project)."
        react(event: "back after \(minutes) minutes away",
              context: "The user just came back after \(minutes) minutes away. Welcome them back warmly, once.\(about)",
              emotion: .happy, action: .wave)
    }

    /// Returns true if it greeted.
    private func greetForNewDayIfNeeded(now: Date) -> Bool {
        let day = ISO8601DateFormatter.string(from: now, timeZone: .current, formatOptions: [.withFullDate])
        guard UserDefaults.standard.string(forKey: Self.dailyGreetingKey) != day else { return false }
        UserDefaults.standard.set(day, forKey: Self.dailyGreetingKey)

        let hour = Calendar.current.component(.hour, from: now)
        let part = hour < 12 ? "morning" : (hour < 17 ? "afternoon" : "evening")
        react(event: "first time today, \(part)",
              context: "It's the user's first time at the Mac today (\(part)). Greet them for the day.",
              emotion: hour < 9 ? .sleepy : .happy, action: hour < 9 ? .stretch : .wave)
        return true
    }

    private func buildFinished(failed: Bool, project: String) {
        guard vibe != .meeting else { return }
        let now = Date()
        if failed {
            consecutiveBuildFailures += 1
            let again = consecutiveBuildFailures > 1
            // A face every time, words only now and then: failing builds come in bursts.
            let speak = now.timeIntervalSince(lastBuildRemarkAt) > 180 || consecutiveBuildFailures == 3
            if speak { lastBuildRemarkAt = now }
            react(event: again ? "build failed again" : "build failed",
                  context: "The user's Xcode build of \(project) just failed\(again ? " again (\(consecutiveBuildFailures) times in a row)" : ""). Be briefly supportive.",
                  emotion: .sad, action: nil, particle: .sweat, speak: speak)
        } else {
            defer { consecutiveBuildFailures = 0 }
            guard consecutiveBuildFailures > 0 else { return }     // routine green builds: stay quiet
            lastBuildRemarkAt = now
            react(event: "build succeeded after several failures",
                  context: "The user's Xcode build of \(project) just passed after failing. Cheer briefly.",
                  emotion: .proud, action: .jump, particle: .sparkle)
        }
    }

    /// Shared reaction: expression and particle always; a move only if it won't pull Byte
    /// out of his work spot; words only if InteractionDirector allows a reactive remark.
    private func react(event: String, context: String, emotion: PetEmotion, action: PetAction?,
                       particle: ParticleType? = nil, speak: Bool = true) {
        guard brain.currentMode != .sleep else { return }
        print("📅 [BehaviorDirector] Day event: \(event)")
        InteractionDirector.shared.consumeReturnGreeting()   // this is the greeting; don't send another

        if brain.currentAction == .sleep { brain.applyAction(.idle) }
        let staysInSpot: Set<PetAction> = [.sit, .idle, .wave, .headbang, .bow]
        if let action = action, !suppressesAmbient || staysInSpot.contains(action) {
            brain.applyAction(action)
        }
        brain.currentEmotion = emotion
        brain.forceUpdate = true
        if let particle = particle { brain.onShowParticle?(particle) }

        if speak && !brain.isMuted && InteractionDirector.shared.shouldSpeak(.reactive) {
            brain.speakReaction(context: context, emotion: emotion.rawValue, event: event)
        }
    }

    #if DEBUG
    private func simulate(_ event: String) {
        print("🧪 [BehaviorDirector] Simulating day event: \(event)")
        switch event {
        case "returned":        welcomeBack(minutes: 45)
        case "morning":
            UserDefaults.standard.removeObject(forKey: Self.dailyGreetingKey)
            _ = greetForNewDayIfNeeded(now: Date())
        case "buildFailed":     buildFinished(failed: true, project: "DesktopPet")
        case "buildSucceeded":  buildFinished(failed: false, project: "DesktopPet")
        case "callEnded":       callEnded()
        default: print("   unknown event; use returned, morning, buildFailed, buildSucceeded, callEnded")
        }
    }
    #endif

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
