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
    
    private func saveMemories() {
        do {
            let data = try JSONEncoder().encode(facts)
            try data.write(to: fileURL)
            print("Saved memories to \(fileURL.path)")
        } catch {
            print("Failed to save memory graph: \(error)")
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
