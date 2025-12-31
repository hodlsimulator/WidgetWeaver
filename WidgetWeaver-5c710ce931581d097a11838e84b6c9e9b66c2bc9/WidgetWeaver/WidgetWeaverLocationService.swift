//
//  WidgetWeaverLocationServic.swift
//  WidgetWeaver
//
//  Created by . . on 12/19/25.
//
//  One-shot async location helper (iOS 26).
//

import Foundation
import CoreLocation

public final class WidgetWeaverLocationService: NSObject, @unchecked Sendable {

    public static let shared = WidgetWeaverLocationService()

    public enum LocationServiceError: LocalizedError, Sendable {
        case notAuthorised(CLAuthorizationStatus)
        case noLocationsReturned
        case requestAlreadyInFlight
        case underlying(String)

        public var errorDescription: String? {
            switch self {
            case .notAuthorised(let status):
                return "Location not authorised (status: \(status.rawValue))."
            case .noLocationsReturned:
                return "No location was returned."
            case .requestAlreadyInFlight:
                return "A location request is already in progress."
            case .underlying(let message):
                return message
            }
        }
    }

    private let manager: CLLocationManager

    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    private override init() {
        self.manager = CLLocationManager()
        super.init()

        self.manager.delegate = self
        self.manager.desiredAccuracy = kCLLocationAccuracyKilometer
        self.manager.distanceFilter = kCLDistanceFilterNone
    }

    public func currentAuthorisationStatus() -> CLAuthorizationStatus {
        manager.authorizationStatus
    }

    @MainActor
    public func ensureWhenInUseAuthorisation() async -> CLAuthorizationStatus {
        let status = manager.authorizationStatus
        guard status == .notDetermined else { return status }

        return await withCheckedContinuation { cont in
            if let existing = authContinuation {
                existing.resume(returning: manager.authorizationStatus)
                authContinuation = nil
            }

            authContinuation = cont
            manager.requestWhenInUseAuthorization()
        }
    }

    @MainActor
    public func fetchOneLocation() async throws -> CLLocation {
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            throw LocationServiceError.notAuthorised(status)
        }

        return try await withCheckedThrowingContinuation { cont in
            if locationContinuation != nil {
                cont.resume(throwing: LocationServiceError.requestAlreadyInFlight)
                return
            }

            locationContinuation = cont
            manager.requestLocation()
        }
    }
}

extension WidgetWeaverLocationService: CLLocationManagerDelegate {

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { [weak self] in
            self?.resolveAuthContinuationIfNeeded()
        }
    }

    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        DispatchQueue.main.async { [weak self] in
            self?.resolveAuthContinuationIfNeeded()
        }
    }

    private func resolveAuthContinuationIfNeeded() {
        guard let cont = authContinuation else { return }
        authContinuation = nil
        cont.resume(returning: manager.authorizationStatus)
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let cont = self.locationContinuation else { return }
            self.locationContinuation = nil

            if let best = locations.max(by: { $0.timestamp < $1.timestamp }) {
                cont.resume(returning: best)
            } else {
                cont.resume(throwing: LocationServiceError.noLocationsReturned)
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let cont = self.locationContinuation else { return }
            self.locationContinuation = nil
            cont.resume(throwing: LocationServiceError.underlying(String(describing: error)))
        }
    }
}
