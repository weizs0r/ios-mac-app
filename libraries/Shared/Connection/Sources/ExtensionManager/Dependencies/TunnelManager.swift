//
//  Created on 29/05/2024.
//
//  Copyright (c) 2024 Proton AG
//
//  ProtonVPN is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  ProtonVPN is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with ProtonVPN.  If not, see <https://www.gnu.org/licenses/>.

import Foundation
import enum NetworkExtension.NEVPNStatus

import Dependencies

import Domain

protocol TunnelManager {
    @discardableResult func startTunnel(to server: VPNServer) async throws -> VPNSession
    func stopTunnel() async throws -> Void
    var session: VPNSession { get async throws }
    var statusStream: AsyncStream<NEVPNStatus> { get async throws }
}

enum TunnelManagerKey: DependencyKey {
#if targetEnvironment(simulator)
    static let liveValue: TunnelManager = MockTunnelManager()
#else
    static let liveValue: TunnelManager = PacketTunnelManager()
#endif
}

final class PacketTunnelManager: TunnelManager {
    private var cachedLoadedManager: TunnelProviderManager?

    /// Creates and loads a new `TunnelProviderManager`.
    private func loadManager() async throws -> TunnelProviderManager {
        @Dependency(\.tunnelProviderManagerFactory) var managerFactory
        // TODO: Provide bundle ID using a Dependency
        let bundleID = "ch.protonmail.vpn.WireGuard-tvOS"
        let manager = try await managerFactory.loadManager(forProviderBundleID: bundleID)
        self.cachedLoadedManager = manager
        return manager
    }

    /// Returning a loaded manager is handy since actions like connecting and updating protocol settings require the
    /// manager to have been loaded at least once after the app has been launched.
    ///
    /// Relevant Apple Developer documentation:
    /// > You must call `loadFromPreferencesWithCompletionHandler` at least once before calling this method the first
    /// time after your app launches.
    /// > [saveToPreferences(completionHandler:)](https://developer.apple.com/documentation/networkextension/nevpnmanager/1405985-savetopreferences)
    private var loadedManager: TunnelProviderManager {
        get async throws {
            if let cachedLoadedManager {
                return cachedLoadedManager
            }

            return try await loadManager()
        }
    }

    private func updateTunnel(for operation: TunnelConfigurationOperation) async throws -> TunnelProviderManager {
        @Dependency(\.tunnelProviderConfigurator) var configurator
        var manager = try await loadedManager
        try await configurator.configure(&manager, for: operation)
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        cachedLoadedManager = manager
        return manager
    }

    func startTunnel(to server: VPNServer) async throws -> VPNSession {
        let manager = try await updateTunnel(for: .connection(server))
        try manager.session.startTunnel()
        return manager.session
    }

    func stopTunnel() async throws {
        let manager = try await updateTunnel(for: .disconnection)
        manager.session.stopTunnel()
    }

    var session: VPNSession {
        get async throws {
            try await loadedManager.session
        }
    }

    var statusStream: AsyncStream<NEVPNStatus> {
        get async throws {
            let manager = try await loadedManager
            let statusChangedNotifications = NotificationCenter.default
                .notifications(named: Notification.Name.NEVPNStatusDidChange, object: manager.session)
                .map { _ in manager.session.status }
            return AsyncStream(statusChangedNotifications)
        }
    }
}

extension DependencyValues {
    var tunnelManager: TunnelManager {
        get { self[TunnelManagerKey.self] }
        set { self[TunnelManagerKey.self] = newValue }
    }
}