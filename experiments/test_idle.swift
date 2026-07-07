import CoreGraphics
import Foundation

let idleTime = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!)
print("Idle time:", idleTime)
