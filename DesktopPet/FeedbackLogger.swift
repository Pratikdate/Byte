import Foundation

enum FeedbackType {
    case positive
    case negative
    case explicit(String)
}

struct FeedbackEvent {
    let timestamp: Date
    let context: String
    let type: FeedbackType
}

class FeedbackLogger {
    static let shared = FeedbackLogger()
    
    private var events: [FeedbackEvent] = []
    
    // We only need a rolling window of recent events for nightly reflection
    private let maxEvents = 20
    
    private init() {}
    
    func logNegative(context: String) {
        let event = FeedbackEvent(timestamp: Date(), context: context, type: .negative)
        addEvent(event)
        print("FeedbackLogger: Logged NEGATIVE feedback for '\(context)'")
    }
    
    func logPositive(context: String) {
        let event = FeedbackEvent(timestamp: Date(), context: context, type: .positive)
        addEvent(event)
        print("FeedbackLogger: Logged POSITIVE feedback for '\(context)'")
    }
    
    func logExplicit(comment: String, context: String) {
        let event = FeedbackEvent(timestamp: Date(), context: context, type: .explicit(comment))
        addEvent(event)
        print("FeedbackLogger: Logged EXPLICIT feedback '\(comment)' for '\(context)'")
    }
    
    private func addEvent(_ event: FeedbackEvent) {
        events.append(event)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
    }
    
    func getRecentEventsForReflection() -> String {
        guard !events.isEmpty else { return "No recent feedback." }
        
        var summary = "Recent Feedback Events:\n"
        for event in events {
            let timeStr = DateFormatter.localizedString(from: event.timestamp, dateStyle: .none, timeStyle: .short)
            switch event.type {
            case .positive:
                summary += "[\(timeStr)] SUCCESS: User reacted positively to '\(event.context)'\n"
            case .negative:
                summary += "[\(timeStr)] FAILURE: User reacted negatively (e.g. dragged away or interrupted) to '\(event.context)'\n"
            case .explicit(let comment):
                summary += "[\(timeStr)] DIRECT COMMENT: User said '\(comment)' regarding '\(event.context)'\n"
            }
        }
        return summary
    }
    
    func hasEvents() -> Bool {
        return !events.isEmpty
    }
    
    func clearEvents() {
        events.removeAll()
    }
}
