import Foundation
import CoreLocation

class WeatherManager: NSObject, CLLocationManagerDelegate {
    static let shared = WeatherManager()
    
    private let locationManager = CLLocationManager()
    var isRaining: Bool = false
    
    func startMonitoring() {
        locationManager.delegate = self
        // Only request when in use for simplicity on Mac, or skip if already determined
        if #available(macOS 10.15, *) {
            locationManager.requestWhenInUseAuthorization()
        }
        locationManager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        locationManager.stopUpdatingLocation() // Only need it once in a while
        
        fetchWeather(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Failed to get location for weather: \(error)")
    }
    
    private func fetchWeather(latitude: Double, longitude: Double) {
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&current=precipitation,rain,showers"
        guard let url = URL(string: urlString) else { return }
        
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let data = data, error == nil else { return }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let current = json["current"] as? [String: Any] {
                    
                    let rain = (current["rain"] as? Double) ?? 0
                    let showers = (current["showers"] as? Double) ?? 0
                    let precipitation = (current["precipitation"] as? Double) ?? 0
                    
                    DispatchQueue.main.async {
                        let currentlyRaining = (rain > 0 || showers > 0 || precipitation > 0)
                        if self?.isRaining != currentlyRaining {
                            self?.isRaining = currentlyRaining
                            NotificationCenter.default.post(name: NSNotification.Name("WeatherChanged"), object: nil)
                        }
                    }
                }
            } catch {
                print("Failed to parse weather data: \(error)")
            }
        }
        task.resume()
        
        // Re-check weather every 30 minutes
        DispatchQueue.main.asyncAfter(deadline: .now() + 1800) { [weak self] in
            self?.locationManager.startUpdatingLocation()
        }
    }
}
