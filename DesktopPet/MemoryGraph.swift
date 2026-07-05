import Foundation

struct MemoryFact: Codable, Equatable {
    let subject: String
    let predicate: String
    let object: String
    
    var description: String {
        return "\(subject) \(predicate) \(object)"
    }
}

class MemoryGraph {
    static let shared = MemoryGraph()
    
    private var facts: [MemoryFact] = []
    
    private var fileURL: URL {
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDir = urls[0]
        let petDir = documentsDir.appendingPathComponent("DesktopPet", isDirectory: true)
        
        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: petDir.path) {
            try? FileManager.default.createDirectory(at: petDir, withIntermediateDirectories: true, attributes: nil)
        }
        
        return petDir.appendingPathComponent("memory_graph.json")
    }
    
    private init() {
        loadMemories()
    }
    
    func addFact(subject: String, predicate: String, object: String) {
        let newFact = MemoryFact(subject: subject, predicate: predicate, object: object)
        if !facts.contains(newFact) {
            facts.append(newFact)
            saveMemories()
        }
    }
    
    func getAllFactsString() -> String {
        if facts.isEmpty { return "None" }
        return facts.map { $0.description }.joined(separator: ", ")
    }
    
    /// Returns only facts that are about the User (filters out Byte's internal system rules)
    func getUserFactsString() -> String {
        let userFacts = facts.filter { fact in
            let sub = fact.subject.lowercased()
            // Exclude system rules like "Action: wander", "Emotion: happy", "Byte", "Humans", "Active Windows", "Rule"
            if sub.starts(with: "action:") || sub.starts(with: "emotion:") || sub == "byte" || sub == "humans" || sub == "active windows" || sub == "taskbar (dock)" || sub == "mouse cursor" || sub == "the desktop" || sub == "explore loops" || sub == "rule" {
                return false
            }
            return true
        }
        
        if userFacts.isEmpty { return "No personal facts known yet." }
        return userFacts.map { $0.description }.joined(separator: ", ")
    }
    
    /// Returns only behavioral rules that the AI must follow
    func getBehavioralRulesString() -> String {
        let ruleFacts = facts.filter { fact in
            return fact.subject.lowercased() == "rule" || fact.subject.lowercased() == "byte"
        }
        
        if ruleFacts.isEmpty { return "No specific behavioral rules." }
        return ruleFacts.map { "- \($0.description)" }.joined(separator: "\n")
    }
    
    private func saveMemories() {
        let factsCopy = facts
        let url = fileURL
        DispatchQueue.global(qos: .background).async {
            do {
                let data = try JSONEncoder().encode(factsCopy)
                try data.write(to: url)
                print("Saved memories to \(url.path)")
            } catch {
                print("Failed to save memory graph: \(error)")
            }
        }
    }
    
    private func loadMemories() {
        do {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            let data = try Data(contentsOf: fileURL)
            facts = try JSONDecoder().decode([MemoryFact].self, from: data)
            print("Loaded \(facts.count) memories.")
        } catch {
            print("Failed to load memory graph: \(error)")
        }
    }
}
