import Foundation

class EnvironmentMonitor {
    static let shared = EnvironmentMonitor()
    
    var isBatteryLow = false
    var isCPUHigh = false
    
    private var timer: Timer?
    
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.checkBattery()
            self?.checkThermalState()
        }
        timer?.fire()
    }
    
    private func checkThermalState() {
        let state = ProcessInfo.processInfo.thermalState
        isCPUHigh = (state == .serious || state == .critical)
        
        // As a fallback for testing, we can also check load averages if we wanted, 
        // but thermal state is the modern Apple way to know if the computer is working too hard.
    }
    
    private func checkBattery() {
        let task = Process()
        task.launchPath = "/usr/bin/pmset"
        task.arguments = ["-g", "batt"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // Parse percentage
                if let range = output.range(of: "([0-9]+)%", options: .regularExpression) {
                    let percentStr = output[range].dropLast()
                    if let percent = Int(percentStr) {
                        isBatteryLow = percent < 20
                    }
                }
            }
        } catch {
            print("Failed to read battery: \(error)")
        }
    }
}
