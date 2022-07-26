//
//  Created on 2022-07-26.
//
//  Copyright (c) 2022 Proton AG
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
import SystemExtensions
import XCTest

class SystemExtensionManagerMock: SystemExtensionManager {
    var pendingRequests: [(SystemExtensionRequest, ExtensionInfo)] = []
    var installedExtensions: [ExtensionInfo] = []

    var requestIsPending: ((SystemExtensionRequest) -> Void)?
    var requestRequiresUserApproval: ((SystemExtensionRequest) -> Void)?
    var requestFinished: ((SystemExtensionRequest) -> Void)?

    typealias VersionString = String
    typealias BundleVersions = (semanticVersion: VersionString, buildVersion: VersionString)

    var mockVersions: BundleVersions?

    lazy var bundleAppVersions: BundleVersions = {
        let macAppBundle = Bundle(for: SystemExtensionManager.self)
        guard let bundleVersion = macAppBundle.infoDictionary?["CFBundleShortVersionString"] as? String else {
            fatalError("Bundle has no build version?")
        }

        guard let buildVersion = macAppBundle.infoDictionary?["CFBundleVersion"] as? String else {
            fatalError("Bundle has no version?")
        }

        return (bundleVersion, buildVersion)
    }()

    override func request(_ request: SystemExtensionRequest) {
        let extensionVersion = mockVersions ?? bundleAppVersions
        let extensionInfo = ExtensionInfo(version: extensionVersion.semanticVersion,
                                          build: extensionVersion.buildVersion,
                                          bundleId: request.request.identifier)

        if let pending = pendingRequests.first(where: { (_, info) in info == extensionInfo }) {
            guard request.shouldExtension(pending.1, beReplacedBy: extensionInfo) else {
                request.request(request.request, didFailWithError: OSSystemExtensionError(.requestCanceled))
                requestFinished?(request)
                return
            }

            pending.0.request(pending.0.request, didFailWithError: OSSystemExtensionError(.requestSuperseded))
            pendingRequests.removeAll { (pendingRequest, _) in pendingRequest.uuid == pending.0.uuid }
        }

        pendingRequests.append((request, extensionInfo))
        requestIsPending?(request)

        if let installed = installedExtensions.first(where: { info in info == extensionInfo }) {
            guard request.shouldExtension(installed, beReplacedBy: extensionInfo) else {
                pendingRequests.removeAll { (pendingRequest, _) in pendingRequest.uuid == request.uuid }
                request.request(request.request, didFailWithError: OSSystemExtensionError(.requestCanceled))
                requestFinished?(request)
                return
            }

            installedExtensions.removeAll { info in info == installed }
            installedExtensions.append(extensionInfo)

            pendingRequests.removeAll { (pendingRequest, _) in pendingRequest.uuid == request.uuid }
            request.request(request.request, didFinishWithResult: .completed)
            requestFinished?(request)
            return
        }

        request.requestNeedsUserApproval(request.request)
        requestRequiresUserApproval?(request)
    }

    func approve(request: SystemExtensionRequest) {
        var info: ExtensionInfo?
        pendingRequests.removeAll { (pendingRequest, pendingInfo) in
            guard pendingRequest.uuid == request.uuid else {
                return false
            }

            info = pendingInfo // save the item before removing it
            return true
        }

        guard let info = info else {
            XCTFail("Attempted to approve a request that wasn't in pending requests")
            return
        }

        installedExtensions.append(info)
        request.request(request.request, didFinishWithResult: .completed)
        requestFinished?(request)
    }

    func fail(request: SystemExtensionRequest, withError error: Error) {
        pendingRequests.removeAll { (pendingRequest, _) in pendingRequest.uuid == request.uuid }
        request.request(request.request, didFailWithError: error)
        requestFinished?(request)
    }
}

