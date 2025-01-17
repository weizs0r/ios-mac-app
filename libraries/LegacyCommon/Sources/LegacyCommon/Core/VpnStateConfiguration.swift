//
//  VpnStateConfiguration.swift
//  ProtonVPN - Created on 2020-10-21.
//
//  Copyright (c) 2021 Proton Technologies AG
//
//  This file is part of ProtonVPN.
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
//

import Foundation
import NetworkExtension

import ProtonCoreFeatureFlags

import Domain
import VPNShared

public protocol VpnStateConfigurationFactory {
    func makeVpnStateConfiguration() -> VpnStateConfiguration
}

public struct VpnStateConfigurationInfo {
    public let state: VpnState
    public let hasConnected: Bool
    public let connection: ConnectionConfiguration?
}

public protocol VpnStateConfiguration {
    func determineActiveVpnProtocol(defaultToIke: Bool, completion: @escaping ((VpnProtocol?) -> Void))
    func determineActiveVpnProtocol(defaultToIke: Bool) async -> VpnProtocol?
    func determineActiveVpnState(vpnProtocol: VpnProtocol, completion: @escaping ((Result<(NEVPNManagerWrapper, VpnState), Error>) -> Void))
    func determineActiveVpnState(vpnProtocol: VpnProtocol) async throws -> (NEVPNManagerWrapper, VpnState)
    func determineNewState(vpnManager: NEVPNManagerWrapper) -> VpnState
    func getInfo(completion: @escaping ((VpnStateConfigurationInfo) -> Void))
    func getInfo() async -> VpnStateConfigurationInfo
}

public class VpnStateConfigurationManager: VpnStateConfiguration {
    private let ikeProtocolFactory: VpnProtocolFactory
    private let wireguardProtocolFactory: VpnProtocolFactory
    private let propertiesManager: PropertiesManagerProtocol

    /// App group is used to read errors from OpenVPN in user defaults
    private let appGroup: String

    public typealias Factory = IkeProtocolFactoryCreator &
        WireguardProtocolFactoryCreator &
        PropertiesManagerFactory

    public convenience init(_ factory: Factory, config: Container.Config) {
        self.init(ikeProtocolFactory: factory.makeIkeProtocolFactory(),
                  wireguardProtocolFactory: factory.makeWireguardProtocolFactory(),
                  propertiesManager: factory.makePropertiesManager(),
                  appGroup: config.appGroup)
    }

    public init(ikeProtocolFactory: VpnProtocolFactory, wireguardProtocolFactory: VpnProtocolFactory, propertiesManager: PropertiesManagerProtocol, appGroup: String) {
        self.ikeProtocolFactory = ikeProtocolFactory
        self.wireguardProtocolFactory = wireguardProtocolFactory
        self.propertiesManager = propertiesManager
        self.appGroup = appGroup
    }

    public func determineNewState(vpnManager: NEVPNManagerWrapper) -> VpnState {
        let status = vpnManager.vpnConnection.status
        let username = vpnManager.protocolConfiguration?.username ?? ""
        let serverAddress = vpnManager.protocolConfiguration?.serverAddress ?? ""

        switch status {
        case .invalid:
            return .invalid
        case .disconnected:
            if let error = lastError() {
                switch error {
                case ProtonVpnError.tlsServerVerification, ProtonVpnError.tlsInitialisation:
                    return .error(error)
                default: break
                }
            }
            return .disconnected
        case .connecting:
            return .connecting(ServerDescriptor(username: username, address: serverAddress))
        case .connected:
            return .connected(ServerDescriptor(username: username, address: serverAddress))
        case .reasserting:
            return .reasserting(ServerDescriptor(username: username, address: serverAddress))
        case .disconnecting:
            return .disconnecting(ServerDescriptor(username: username, address: serverAddress))
        @unknown default:
            return .invalid
        }
    }

    private func getFactory(for vpnProtocol: VpnProtocol) -> VpnProtocolFactory {
        switch vpnProtocol {
        case .ike:
            return ikeProtocolFactory
        case .openVpn:
            fatalError("OpenVPN has been deprecated")
        case .wireGuard:
            return wireguardProtocolFactory
        }
    }

    public func determineActiveVpnProtocol(defaultToIke: Bool, completion: @escaping ((VpnProtocol?) -> Void)) {
        let protocols: [VpnProtocol] = [.ike, .wireGuard(.udp)]
        var activeProtocols: [VpnProtocol] = []

        let dispatchGroup = DispatchGroup()
        for vpnProtocol in protocols {
            dispatchGroup.enter()
            self.getFactory(for: vpnProtocol).vpnProviderManager(for: .status) { [weak self] manager, error in
                defer { dispatchGroup.leave() }
                guard let self = self, let manager = manager else {
                    guard let error = error else { return }

                    log.error("Couldn't determine if protocol \"\(vpnProtocol.localizedString)\" is active: \"\(String(describing: error))\"", category: .connection)
                    return
                }

                let state = self.determineNewState(vpnManager: manager)
                if state.stableConnection || state.volatileConnection {
                    activeProtocols.append(vpnProtocol)
                }
            }
        }

        dispatchGroup.notify(queue: .main) {
            // WireGuard takes precedence but if neither are active, then it should remain unchanged
            if activeProtocols.contains(.wireGuard(.udp)) {
                completion(.wireGuard(.udp))
            } else if activeProtocols.contains(.ike) {
                completion(.ike)
            } else if defaultToIke {
                log.info("No active protocols detected. Defaulting to `.ike`", category: .connection)
                completion(.ike)
            } else {
                completion(nil)
            }
        }
    }

    public func determineActiveVpnProtocol(defaultToIke: Bool) async -> VpnProtocol? {
        let protocols: [VpnProtocol] = [.ike, .wireGuard(.udp)]

        var activeProtocols: [VpnProtocol] = []

        for vpnProtocol in protocols {
            do {
                let manager = try await getFactory(for: vpnProtocol).vpnProviderManager(for: .status)

                let state = self.determineNewState(vpnManager: manager)
                if state.stableConnection || state.volatileConnection {
                    activeProtocols.append(vpnProtocol)
                }
            } catch {
                log.error("Couldn't determine if protocol \"\(vpnProtocol.localizedString)\" is active: \"\(String(describing: error))\"", category: .connection)
                continue
            }
        }
        let activeDeprecatedProtocols = Set(VpnProtocol.deprecatedProtocols).intersection(activeProtocols)
        if !activeDeprecatedProtocols.isEmpty {
            log.assertionFailure("activeProtocols contain a deprecated protocols: \(activeDeprecatedProtocols)")
        }
        return await MainActor.run { [activeProtocols] in
            // OpenVPN takes precedence but if neither are active, then it should remain unchanged
            if activeProtocols.contains(.openVpn(.tcp)) {
                return .openVpn(.tcp)
            } else if activeProtocols.contains(.wireGuard(.udp)) {
                return .wireGuard(.udp)
            } else if activeProtocols.contains(.ike) {
                return .ike
            } else if defaultToIke {
                log.info("No active protocols detected. Defaulting to `.ike`", category: .connection)
                return .ike
            } else {
                return nil
            }
        }
    }

    public func determineActiveVpnState(vpnProtocol: VpnProtocol, completion: @escaping ((Result<(NEVPNManagerWrapper, VpnState), Error>) -> Void)) {
        getFactory(for: vpnProtocol).vpnProviderManager(for: .status) { [weak self] vpnManager, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let self = self, let vpnManager = vpnManager else {
                return
            }

            let newState = self.determineNewState(vpnManager: vpnManager)
            completion(.success((vpnManager, newState)))
        }
    }

    public func determineActiveVpnState(vpnProtocol: VpnProtocol) async throws -> (NEVPNManagerWrapper, VpnState) {
        let vpnManager = try await getFactory(for: vpnProtocol).vpnProviderManager(for: .status)
        return (vpnManager, determineNewState(vpnManager: vpnManager))
    }

    public func getInfo(completion: @escaping ((VpnStateConfigurationInfo) -> Void)) {
        // Note the double-negative: not-not defaulting to IKEv2. We want to gradually roll out noDefault as a feature.
        let defaultToIke = !FeatureFlagsRepository.shared.isEnabled(VPNFeatureFlagType.noDefaultToIke)
        let defaulting = defaultToIke ? "Defaulting" : "Not defaulting"
        log.info("Getting protocol information. \(defaulting) to IKEv2 if no provider available.")
        determineActiveVpnProtocol(defaultToIke: defaultToIke) { [weak self] vpnProtocol in
            guard let self = self else {
                return
            }

            guard let vpnProtocol = vpnProtocol else {
                completion(VpnStateConfigurationInfo(state: .disconnected,
                                                     hasConnected: self.propertiesManager.hasConnected,
                                                     connection: nil))
                return
            }

            let connection: ConnectionConfiguration?
            switch vpnProtocol {
            case .ike:
                connection = self.propertiesManager.lastIkeConnection
            case .openVpn:
                connection = self.propertiesManager.lastOpenVpnConnection
            case .wireGuard:
                connection = self.propertiesManager.lastWireguardConnection
            }

            self.determineActiveVpnState(vpnProtocol: vpnProtocol) { result in
                switch result {
                case let .failure(error):
                    completion(VpnStateConfigurationInfo(state: VpnState.error(error),
                                                         hasConnected: self.propertiesManager.hasConnected,
                                                         connection: connection))
                case let .success((_, state)):
                    completion(VpnStateConfigurationInfo(state: state,
                                                         hasConnected: self.propertiesManager.hasConnected,
                                                         connection: connection))
                }
            }
        }
    }

    public func getInfo() async -> VpnStateConfigurationInfo {
        // Note the double-negative: not-not defaulting to IKEv2. We want to gradually roll out noDefault as a feature.
        let defaultToIke = !FeatureFlagsRepository.shared.isEnabled(VPNFeatureFlagType.noDefaultToIke)
        let defaulting = defaultToIke ? "Defaulting" : "Not defaulting"
        log.info("Getting protocol information. \(defaulting) to IKEv2 if no provider available.")
        guard let vpnProtocol = await determineActiveVpnProtocol(defaultToIke: defaultToIke) else {
            return VpnStateConfigurationInfo(state: .disconnected,
                                             hasConnected: self.propertiesManager.hasConnected,
                                             connection: nil)
        }

        let connection: ConnectionConfiguration?
        switch vpnProtocol {
        case .ike:
            connection = self.propertiesManager.lastIkeConnection
        case .openVpn:
            connection = self.propertiesManager.lastOpenVpnConnection
        case .wireGuard:
            connection = self.propertiesManager.lastWireguardConnection
        }
        do {
            let (_, state) = try await determineActiveVpnState(vpnProtocol: vpnProtocol)
            return VpnStateConfigurationInfo(state: state,
                                             hasConnected: self.propertiesManager.hasConnected,
                                             connection: connection)
        } catch {
            return VpnStateConfigurationInfo(state: VpnState.error(error),
                                             hasConnected: self.propertiesManager.hasConnected,
                                             connection: connection)
        }
    }

    private func lastError() -> Error? {
        let defaults = UserDefaults(suiteName: appGroup)
        let errorKey = "TunnelKitLastError"
        guard let lastError = defaults?.object(forKey: errorKey) as? String else {
            return nil
        }

        switch lastError {
        case "tlsServerVerification":
            return ProtonVpnError.tlsServerVerification
        case "tlsInitialization":
            return ProtonVpnError.tlsInitialisation
        default:
            return NSError(code: 0, localizedDescription: lastError)
        }
    }
}
