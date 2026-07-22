import Foundation
import AppKit
import Vision

/// On-Device Screen & Visual Perception Engine for Byte
/// Uses macOS native Vision Framework (VNRecognizeTextRequest) to give Byte visual awareness
/// of code error stack traces, IDE text, and active documentation without leaving the device.
class ByteVisionEngine {
    static let shared = ByteVisionEngine()

    private(set) var currentVisualContext: String = "No visual target detected."
    private var visionTimer: Timer?

    private init() {
        startVisionMonitoring()
    }

    func startVisionMonitoring() {
        // Run OCR visual scan every 5 seconds on the active window
        visionTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.performScreenVisualScan()
        }
    }

    /// Captures active window image and performs OCR via Apple Vision Framework
    func performScreenVisualScan() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return
        }

        // Find frontmost window bounds & ID
        for window in windowList {
            if let ownerName = window[kCGWindowOwnerName as String] as? String,
               ownerName == frontApp.localizedName,
               let windowID = window[kCGWindowNumber as String] as? CGWindowID {
                
                // Capture window image
                guard let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.boundsIgnoreFraming]) else {
                    continue
                }

                // Analyze text using Vision Framework
                let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                let request = VNRecognizeTextRequest { [weak self] request, error in
                    guard let observations = request.results as? [VNRecognizedTextObservation], error == nil else { return }

                    let recognizedStrings = observations.compactMap { $0.topCandidates(1).first?.string }
                    self?.processRecognizedVisionText(recognizedStrings)
                }
                
                request.recognitionLevel = .fast
                request.usesLanguageCorrection = false
                
                DispatchQueue.global(qos: .userInitiated).async {
                    try? requestHandler.perform([request])
                }
                break
            }
        }
    }

    /// Analyzes recognized text to find high-value context (errors, code functions, warnings)
    private func processRecognizedVisionText(_ lines: [String]) {
        guard !lines.isEmpty else { return }

        var detectedContexts: [String] = []

        for line in lines {
            let lower = line.lowercased()
            if lower.contains("error:") || lower.contains("fatal error") || lower.contains("exception") || lower.contains("failed") {
                detectedContexts.append("Build/Runtime Error: '\(line.prefix(60))'")
            } else if lower.contains("func ") || lower.contains("class ") || lower.contains("struct ") || lower.contains("def ") {
                detectedContexts.append("Writing Code: '\(line.prefix(50))'")
            } else if lower.contains("git commit") || lower.contains("git push") || lower.contains("build succeeded") {
                detectedContexts.append("Milestone: '\(line.prefix(50))'")
            }
        }

        DispatchQueue.main.async {
            if !detectedContexts.isEmpty {
                self.currentVisualContext = detectedContexts.prefix(2).joined(separator: " | ")
            } else {
                let sampleText = lines.prefix(3).joined(separator: " ")
                self.currentVisualContext = "Reading text: '\(sampleText.prefix(60))...'"
            }
        }
    }

    /// Returns clean visual perception text for AI prompt
    func formattedVisionContextForAI() -> String {
        return currentVisualContext
    }
}
