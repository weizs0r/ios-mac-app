//
//  Created on 12/05/2023.
//
//  Copyright (c) 2023 Proton AG
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
import VPNShared

public final class VpnAuthenticationManager {
    private let operationDispatchQueue = DispatchQueue(label: "ch.protonvpn.mac.async_cert_refresh",
                                                       qos: .userInitiated)
    private let queue = OperationQueue()
    private let storage: VpnAuthenticationStorage
    private let networking: Networking
    private let safeModePropertyProvider: SafeModePropertyProvider

    public typealias Factory = NetworkingFactory &
        VpnAuthenticationStorageFactory &
        SafeModePropertyProviderFactory

    public convenience init(_ factory: Factory) {
        self.init(networking: factory.makeNetworking(),
                  storage: factory.makeVpnAuthenticationStorage(),
                  safeModePropertyProvider: factory.makeSafeModePropertyProvider())
    }

    public init(networking: Networking,
                storage: VpnAuthenticationStorage,
                safeModePropertyProvider: SafeModePropertyProvider) {
        self.networking = networking
        self.storage = storage
        self.safeModePropertyProvider = safeModePropertyProvider
        queue.maxConcurrentOperationCount = 1
        queue.underlyingQueue = operationDispatchQueue

        NotificationCenter.default.addObserver(self, selector: #selector(userDowngradedPlanOrBecameDelinquent), name: VpnKeychain.vpnPlanChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(userDowngradedPlanOrBecameDelinquent), name: VpnKeychain.vpnUserDelinquent, object: nil)
    }

    @objc private func userDowngradedPlanOrBecameDelinquent(_ notification: NSNotification) {
        log.info("User plan downgraded or delinquent, deleting keys and certificate and getting new ones", category: .userCert)

        // certificate refresh requests might be in progress so first cancel all fo them
        queue.cancelAllOperations()

        // Save last used features before cleanup
        let features = storage.getStoredCertificateFeatures()

        // then delete evertyhing
        clearEverything { [weak self] in
            guard let self = self else {
                return
            }

            // and get new certificates
            self.queue.addOperation(CertificateRefreshAsyncOperation(storage: self.storage,
                                                                     features: features,
                                                                     networking: self.networking,
                                                                     safeModePropertyProvider: self.safeModePropertyProvider))
        }
    }

    /// Created for the purposes of sharing refresh logic between VpnAuthenticationManager and VpnAuthenticationRemoteClient. When VpnAuthenticationManager
    /// is fully replaced by VpnAuthenticationRemoteClient on macOS, this function will be absorbed into VpnAuthenticationRemoteClient.
    fileprivate static func loadAuthenticationDataBase(storage: VpnAuthenticationStorage,
                                                       safeModePropertyProvider: SafeModePropertyProvider,
                                                       features: VPNConnectionFeatures? = nil,
                                                       completion: @escaping AuthenticationDataCompletion) {
        // keys are generated, certificate is stored, use it
        if let keys = storage.getStoredKeys(), let existingCertificate = storage.getStoredCertificate(), features == nil || features?.equals(other: storage.getStoredCertificateFeatures(), safeModeEnabled: safeModePropertyProvider.safeModeFeatureEnabled) == true {
            log.debug("Loading stored vpn authentication data", category: .userCert)
            if existingCertificate.isExpired {
                log.info("Stored vpn authentication certificate is expired (\(existingCertificate.validUntil)), the local agent will connect but certificate refresh will be needed", category: .userCert, event: .newCertificate)
            }
            completion(.success(VpnAuthenticationData(clientKey: keys.privateKey,
                                                      clientCertificate: existingCertificate.certificate)))
            return
        }

        completion(.failure(ProtonVpnError.vpnCredentialsMissing))
    }
}

extension VpnAuthenticationManager: VpnAuthentication {
    public func clearEverything(completion: @escaping (() -> Void)) {
        // First cancel all pending certificate refreshes so a certificate is not fetched from the backend and stored after deleting keychain in this call
        queue.cancelAllOperations()

        // Delete everything from the keychain
        storage.deleteKeys()
        storage.deleteCertificate()

        completion()
    }

    /// - Parameter features: The features used for the current connection.
    /// - Parameter completion: A function which will be invoked on the UI thread with the refreshed
    ///                         certificate, or an error if the refresh failed.
    public func refreshCertificates(features: VPNConnectionFeatures?, completion: @escaping CertificateRefreshCompletion) {
        // If new feature set is given, use it, otherwise try to get certificate with the same features as previous
        let newFeatures = features ?? storage.getStoredCertificateFeatures()

        queue.addOperation(CertificateRefreshAsyncOperation(storage: storage, features: newFeatures, networking: networking, safeModePropertyProvider: safeModePropertyProvider, completion: { result in
            executeOnUIThread { completion(result) }
        }))
    }

    public func loadAuthenticationData(features: VPNConnectionFeatures? = nil, completion: @escaping AuthenticationDataCompletion) {
        Self.loadAuthenticationDataBase(storage: storage, safeModePropertyProvider: safeModePropertyProvider, features: features) { result in
            guard case .failure(ProtonVpnError.vpnCredentialsMissing) = result else {
                completion(result)
                return
            }

            // certificate is missing or no longer valid, refresh it and use
            self.refreshCertificates(features: features, completion: completion)
        }
    }

    public func loadClientPrivateKey() -> PrivateKey {
        return storage.getKeys().privateKey
    }
}