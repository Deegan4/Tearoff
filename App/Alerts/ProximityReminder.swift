import CoreLocation
import UserNotifications
import VaultCore

/// Pro feature: nudges the user when they're physically near a store that
/// still has an open return window. Deliberately foreground-only — a single
/// "when in use" location fix taken when the app becomes active, compared
/// against each purchase's saved store coordinate, then discarded. No
/// background location, no region monitoring, no "Always" permission, and
/// nothing is stored beyond the purchase's own saved coordinate.
@MainActor
final class ProximityReminder: NSObject {
    static let shared = ProximityReminder()

    /// Anything closer than this counts as "at the store".
    private let thresholdMeters: CLLocationDistance = 200

    private lazy var manager: CLLocationManager = {
        let m = CLLocationManager()
        m.delegate = self
        return m
    }()

    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private var authContinuation: CheckedContinuation<Void, Never>?
    /// Debounced per purchase so walking around the same store doesn't spam
    /// a fresh notification every time the app comes forward.
    private var lastNotified: [UUID: Date] = [:]
    private let renotifyAfter: TimeInterval = 12 * 60 * 60

    /// Check the user's current location against every open, geotagged
    /// purchase and fire a local notification for any match. No-ops silently
    /// if location permission isn't granted — this is an opportunistic nudge,
    /// never a prompt-inducing blocker.
    func checkNearbyStores(purchases: [StoredPurchase]) async {
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        guard let here = await currentLocation() else { return }

        let now = Date()
        for purchase in purchases where !purchase.status.isResolved {
            guard let lat = purchase.storeLatitude, let lon = purchase.storeLongitude else { continue }
            guard let window = ResolverStore.shared.returnWindow(for: purchase), window.deadline >= now else { continue }

            let store = CLLocation(latitude: lat, longitude: lon)
            guard here.distance(from: store) <= thresholdMeters else { continue }

            if let last = lastNotified[purchase.id], now.timeIntervalSince(last) < renotifyAfter { continue }
            lastNotified[purchase.id] = now

            let days = DeadlineDigest.daysRemaining(to: window.deadline, from: now)
            await notify(merchant: purchase.merchant, daysRemaining: days)
        }
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// One-shot capture of the user's current position, for tagging a
    /// purchase with its store's location. Prompts for "when in use"
    /// permission if not yet determined; returns nil if denied or unavailable.
    func captureCurrentLocation() async -> CLLocationCoordinate2D? {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { continuation in
                self.authContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        }
        guard manager.authorizationStatus == .authorizedWhenInUse
            || manager.authorizationStatus == .authorizedAlways else { return nil }
        return await currentLocation()?.coordinate
    }

    private func currentLocation() async -> CLLocation? {
        guard CLLocationManager.locationServicesEnabled() else { return nil }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    private func notify(merchant: String, daysRemaining days: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "You're near \(merchant)"
        content.body = days <= 0
            ? "Your return window closes today."
            : "Your return window closes in \(days) day\(days == 1 ? "" : "s")."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "proximity-\(merchant)-\(Date().timeIntervalSince1970)",
                                             content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

extension ProximityReminder: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            continuation?.resume(returning: locations.last)
            continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(returning: nil)
            continuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.manager.authorizationStatus != .notDetermined else { return }
            authContinuation?.resume()
            authContinuation = nil
        }
    }
}
