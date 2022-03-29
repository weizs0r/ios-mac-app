//
//  LoginViewModel.swift
//  ProtonVPN - Created on 27.06.19.
//
//  Copyright (c) 2019 Proton Technologies AG
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

import AppKit
import Foundation
import vpncore

final class LoginViewModel {
    
    typealias Factory = NavigationServiceFactory & PropertiesManagerFactory & AppSessionManagerFactory & CoreAlertServiceFactory & UpdateManagerFactory & AuthApiServiceFactory & ProtonReachabilityCheckerFactory
    private let factory: Factory
    
    private lazy var propertiesManager: PropertiesManagerProtocol = factory.makePropertiesManager()
    private lazy var appSessionManager: AppSessionManager = factory.makeAppSessionManager()
    private lazy var navService: NavigationService = factory.makeNavigationService()
    private lazy var alertService: CoreAlertService = factory.makeCoreAlertService()
    private lazy var updateManager: UpdateManager = factory.makeUpdateManager()
    private lazy var authApiService: AuthApiService = factory.makeAuthApiService()
    private lazy var protonReachabilityChecker: ProtonReachabilityChecker = factory.makeProtonReachabilityChecker()
    
    var logInInProgress: (() -> Void)?
    var logInFailure: ((String?) -> Void)?
    var logInFailureWithSupport: ((String?) -> Void)?
    var checkInProgress: ((Bool) -> Void)?

    init (factory: Factory) {
        self.factory = factory
    }
    
    var startOnBoot: Bool {
        return propertiesManager.startOnBoot
    }
    
    func startOnBoot(enabled: Bool) {
        propertiesManager.startOnBoot = enabled
    }
    
    func logInSilently() {
        logInInProgress?()
        appSessionManager.attemptSilentLogIn { [weak self] result in
            switch result {
            case .success:
                NSApp.setActivationPolicy(.accessory)
                self?.silentlyCheckForUpdates()
            case let .failure(error):
                self?.specialErrorCaseNotification(error)
                self?.navService.handleSilentLoginFailure()
            }
        }
    }
    
    func logInApperared() {
        logInInProgress?()
        appSessionManager.attemptSilentLogIn { [weak self] result in
            switch result {
            case .success:
                self?.silentlyCheckForUpdates()
            case let .failure(error):
                self?.specialErrorCaseNotification(error)
                self?.logInFailure?((error as NSError) == ProtonVpnErrorConst.userCredentialsMissing ? nil : error.localizedDescription)
            }
        }
    }
    
    func logIn(username: String, password: String) {
        logInInProgress?()
        appSessionManager.logIn(username: username, password: password, success: { [weak self] in
            self?.silentlyCheckForUpdates()
        }, failure: { [weak self] error in
            guard let `self` = self else { return }
            self.specialErrorCaseNotification(error)

            let nsError = error as NSError
            if nsError.isTlsError || nsError.isNetworkError {
                let alert = UnreachableNetworkAlert(error: error, troubleshoot: { [weak self] in
                    self?.alertService.push(alert: ConnectionTroubleshootingAlert())
                })
                self.alertService.push(alert: alert)
                self.logInFailure?(nil)
            } else if case ProtonVpnError.subuserWithoutSessions = error {
                self.alertService.push(alert: SubuserWithoutConnectionsAlert())
                self.logInFailure?(nil)
            } else {
                self.logInFailure?(error.localizedDescription)
            }
        })
    }

    func updateAvailableDomains() {
        authApiService.getAvailableDomains { _ in }
    }
    
    private func specialErrorCaseNotification(_ error: Error) {
        if error is KeychainError ||
            (error as NSError).code == NetworkErrorCode.timedOut ||
            (error as NSError).code == ApiErrorCode.apiVersionBad ||
            (error as NSError).code == ApiErrorCode.appVersionBad {
            logInFailureWithSupport?(error.localizedDescription)
        }
    }
    
    private func silentlyCheckForUpdates() {
        updateManager.checkForUpdates(appSessionManager, silently: true)
    }
    
    func keychainHelpAction() {
        SafariService.openLink(url: CoreAppConstants.ProtonVpnLinks.supportCommonIssues)
    }
    
    func createAccountAction() {
        checkInProgress?(true)

        protonReachabilityChecker.check { [weak self] reachable in
            self?.checkInProgress?(false)

            if reachable {
                SafariService.openLink(url: CoreAppConstants.ProtonVpnLinks.signUp)
            } else {
                self?.alertService.push(alert: ProtonUnreachableAlert())
            }
        }
    }

    var helpPopoverViewModel: HelpPopoverViewModel {
        return HelpPopoverViewModel(navigationService: navService)
    }
}
