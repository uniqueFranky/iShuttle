import CoreLocation

final class LocationDirectionService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onDirection: ((String, CommuteDirection) -> Void)?

    func requestDirection() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus == .authorizedAlways ||
                manager.authorizationStatus == .authorizedWhenInUse else { return }
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let haidian = CLLocation(latitude: 39.99281, longitude: 116.31088)
        let changping = CLLocation(latitude: 40.177274, longitude: 116.164420)
        let campusRadius: CLLocationDistance = 4_000

        if location.distance(from: haidian) <= campusRadius {
            onDirection?("海淀校区", .toChangping)
        } else if location.distance(from: changping) <= campusRadius {
            onDirection?("昌平校区", .toHaidian)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 定位失败时保留用户当前选择，不影响预约功能。
    }
}
