//
//  CreateNewProfileViewModel.swift
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

import Cocoa
import vpncore

internal struct ModelState {

    let serverType: ServerType
    let editedProfile: Profile?
}

internal enum DefaultServerOffering {
    
    case fastest
    case random
    
    var name: String {
        switch self {
        case .fastest: return "fastest"
        case .random: return "random"
        }
    }
    
    var index: Int {
        switch self {
        case .fastest: return 0
        case .random: return 1
        }
    }
}

protocol CreateNewProfileViewModelFactory {
    func makeCreateNewProfileViewModel(editProfile: Notification.Name) -> CreateNewProfileViewModel
}

extension DependencyContainer: CreateNewProfileViewModelFactory {
    func makeCreateNewProfileViewModel(editProfile: Notification.Name) -> CreateNewProfileViewModel {
        return CreateNewProfileViewModel(editProfile: editProfile, factory: self)
    }
}

class CreateNewProfileViewModel {
    
    typealias Factory = CoreAlertServiceFactory & VpnKeychainFactory & PropertiesManagerFactory & AppStateManagerFactory & VpnGatewayFactory & ProfileManagerFactory & SystemExtensionsStateCheckFactory
    private let factory: Factory
    
    var prefillContent: ((PrefillInformation) -> Void)?
    var contentChanged: (() -> Void)?
    var contentWarning: ((String) -> Void)?
    var secureCoreWarning: (() -> Void)?
    
    let sessionFinished = NSNotification.Name("CreateNewProfileViewModelSessionFinished") // two observers

    private let serverManager: ServerManager
    private lazy var alertService: CoreAlertService = factory.makeCoreAlertService()
    private lazy var vpnKeychain: VpnKeychainProtocol = factory.makeVpnKeychain()
    private lazy var propertiesManager: PropertiesManagerProtocol = factory.makePropertiesManager()
    private lazy var appStateManager: AppStateManager = factory.makeAppStateManager()
    private lazy var vpnGateway: VpnGatewayProtocol = factory.makeVpnGateway()
    private lazy var profileManager: ProfileManager = factory.makeProfileManager()
    private lazy var sysexStateCheck: SystemExtensionsStateCheck = factory.makeSystemExtensionsStateCheck()

    internal let defaultServerCount = 2
    let colorPickerViewModel = ColorPickerViewModel()

    var sysexPending = false
    private var state = ModelState(serverType: .standard, editedProfile: nil)
    internal var userTier: Int = 0
    
    init(editProfile: Notification.Name, factory: Factory) {
        serverManager = ServerManagerImplementation.instance(forTier: CoreAppConstants.VpnTiers.visionary, serverStorage: ServerStorageConcrete())
        self.factory = factory
        
        NotificationCenter.default.addObserver(self, selector: #selector(editProfile(_:)), name: editProfile, object: nil)
        setupUserTier()
    }
    
    @objc private func editProfile(_ notification: Notification) {
        if let profile = notification.object as? Profile {
            prefillInfo(for: profile)
        }
    }
    
    private func setupUserTier() {
        do {
            userTier = try vpnKeychain.fetchCached().maxTier
        } catch {
            alertService.push(alert: CannotAccessVpnCredentialsAlert())
        }
    }
    
    private func prefillInfo(for profile: Profile) {
        guard profile.profileType == .user, case ProfileIcon.circle(let color) = profile.profileIcon else {
            return
        }
        
        let tIndex: Int = ProfileUtility.index(for: profile.serverType)
        let grouping = serverManager.grouping(for: profile.serverType)
        
        let cIndex: Int
        let sIndex: Int
        
        switch profile.serverOffering {
        case .fastest(let cCode):
            cIndex = ServerUtility.countryIndex(in: grouping, countryCode: cCode!) ?? 0
            sIndex = DefaultServerOffering.fastest.index
        case .random(let cCode):
            cIndex = ServerUtility.countryIndex(in: grouping, countryCode: cCode!) ?? 0
            sIndex = DefaultServerOffering.random.index
        case .custom(let sWrapper):
            cIndex = ServerUtility.countryIndex(in: grouping, countryCode: sWrapper.server.countryCode) ?? 0
            sIndex = defaultServerCount + (ServerUtility.serverIndex(in: grouping, model: sWrapper.server) ?? 0)
        }
        state = ModelState(serverType: profile.serverType, editedProfile: profile)
        let profileVpnProtocol: VpnProtocol
        switch profile.connectionProtocol {
        case .smartProtocol:
            profileVpnProtocol = propertiesManager.vpnProtocol
        case let .vpnProtocol(vpnProtocol):
            profileVpnProtocol = vpnProtocol
        }
        let info = PrefillInformation(name: profile.name, color: NSColor(rgbHex: color),
                                      typeIndex: tIndex, countryIndex: cIndex, serverIndex: sIndex,
                                      vpnProtocolIndex: availableVpnProtocols.index(of: profileVpnProtocol) ?? 0)
        
        prefillContent?(info)
    }
    
    func cancelCreation() {
        state = ModelState(serverType: .standard, editedProfile: nil)
        NotificationCenter.default.post(name: sessionFinished, object: nil)
    }

    // swiftlint:disable function_parameter_count
    func createProfile(name: String, color: NSColor, typeIndex: Int, countryIndex: Int, serverIndex: Int, vpnProtocolIndex: Int) {
        let serverType = serverTypeFrom(index: typeIndex)
        let grouping = serverManager.grouping(for: serverType)
        let countryModel = ServerUtility.country(in: grouping, index: countryIndex)!
        let countryCode = countryModel.countryCode

        let id: String
        if let editedProfile = state.editedProfile {
            id = editedProfile.id
        } else {
            id = String.randomString(length: Profile.idLength)
        }

        let accessTier: Int
        let serverOffering: ServerOffering

        if serverIndex == DefaultServerOffering.fastest.index {
            accessTier = countryModel.lowestTier
            serverOffering = .fastest(countryCode)
        } else if serverIndex == DefaultServerOffering.random.index {
            accessTier = countryModel.lowestTier
            serverOffering = .random(countryCode)
        } else {
            let adjustedServerIndex = serverIndex - defaultServerCount
            let serverModel = ServerUtility.server(in: grouping, countryIndex: countryIndex, serverIndex: adjustedServerIndex)!
            accessTier = serverModel.tier
            serverOffering = .custom(ServerWrapper(server: serverModel))
        }

        let profile = Profile(id: id, accessTier: accessTier, profileIcon: .circle(color.hexRepresentation),
                              profileType: .user, serverType: serverType, serverOffering: serverOffering,
                              name: name, connectionProtocol: .vpnProtocol(availableVpnProtocols[vpnProtocolIndex]))

        let result = state.editedProfile != nil ? profileManager.updateProfile(profile) : profileManager.createProfile(profile)

        switch result {
        case .success:
            state = ModelState(serverType: .standard, editedProfile: nil)
            NotificationCenter.default.post(name: sessionFinished, object: nil)
        case .nameInUse:
            contentWarning?(LocalizedString.profileNameNeedsToBeUnique)
        }
    }
    // swiftlint:enable function_parameter_count
    
    private func serverTypeFrom(index: Int) -> ServerType {
        switch index {
        case 0:
            return .standard
        case 1:
            return .secureCore
        case 2:
            return .p2p
        default:
            return .tor
        }
    }
    
    var typeCount: Int {
        return 4
    }
    
    var isNetshieldEnabled: Bool {
        return propertiesManager.featureFlags.netShield
    }

    let availableVpnProtocols = [VpnProtocol.ike, VpnProtocol.openVpn(.tcp), VpnProtocol.openVpn(.udp), VpnProtocol.wireGuard]
    
    func countryCount(for typeIndex: Int) -> Int {
        let type = ProfileUtility.serverType(for: typeIndex)
        return serverManager.grouping(for: type).count
    }

    func serverCount(for typeIndex: Int, and countryIndex: Int) -> Int {
        let type = ProfileUtility.serverType(for: typeIndex)
        return defaultServerCount + serverManager.grouping(for: type)[countryIndex].1.count
    }
    
    func type(for index: Int) -> NSAttributedString {
        let title: String
        switch index {
        case 0:
            title = LocalizedString.standard
        case 1:
            title = LocalizedString.secureCore
        case 2:
            title = LocalizedString.p2p
        default:
            title = LocalizedString.tor
        }
        
        return self.style(title, font: .themeFont(.heading4), alignment: .left)
    }

    func vpnProtocolIndex(for vpnProtocol: VpnProtocol) -> Int? {
        availableVpnProtocols.firstIndex(of: vpnProtocol)
    }

    func vpnProtocolString(for vpnProtocol: VpnProtocol) -> NSAttributedString {
        let title: String
        switch vpnProtocol {
        case .ike:
            title = LocalizedString.ikev2
        case let .openVpn(transport):
            switch transport {
            case .tcp:
                title = "\(LocalizedString.openvpn) (\(LocalizedString.tcp))"
            case .udp:
                title = "\(LocalizedString.openvpn) (\(LocalizedString.udp))"
            }
        case .wireGuard:
            title = LocalizedString.wireguard
        }

        return self.style(title, font: .themeFont(.heading4), alignment: .left)
    }
    
    func country(for typeIndex: Int, index countryIndex: Int) -> NSAttributedString {
        let type = ProfileUtility.serverType(for: typeIndex)
        let country = serverManager.grouping(for: type)[countryIndex].0
        return countryDescriptor(for: country)
    }
    
    func server(for typeIndex: Int, and countryIndex: Int, index serverIndex: Int) -> NSAttributedString {
        if serverIndex < defaultServerCount {
            return defaultServerDescriptor(forIndex: serverIndex)
        }
        
        let type = ProfileUtility.serverType(for: typeIndex)
        let adjustedServerIndex = serverIndex - defaultServerCount
        
        let server = serverManager.grouping(for: type)[countryIndex].1[adjustedServerIndex]
        return serverDescriptor(for: server)
    }
    
    func checkNetshieldOption( _ netshieldIndex: Int ) -> Bool {
        guard let netshieldType = NetShieldType(rawValue: netshieldIndex), !netshieldType.isUserTierTooLow(userTier) else {
            let upgradeAlert = NetShieldRequiresUpgradeAlert(continueHandler: {
                SafariService.openLink(url: CoreAppConstants.ProtonVpnLinks.accountDashboard)
            })
            self.alertService.push(alert: upgradeAlert)
            return false
        }
        return true
    }

    func refreshSysexPending(for vpnProtocolIndex: Int) {
        sysexPending = vpnProtocolIndex < availableVpnProtocols.count &&
            availableVpnProtocols[vpnProtocolIndex].requiresSystemExtension &&
            !propertiesManager.sysexSuccessWasShown
    }

    func shouldShowSysexProgress(for vpnProtocolIndex: Int) -> Bool {
        vpnProtocolIndex < availableVpnProtocols.count &&
        availableVpnProtocols[vpnProtocolIndex].requiresSystemExtension &&
        sysexPending
    }

    func checkSysexInstallation(vpnProtocolIndex: Int, completion: @escaping (Result<SystemExtensionsStateCheck.SuccessResultType, Error>) -> Void) {
        let vpnProtocol = availableVpnProtocols[vpnProtocolIndex]
        guard vpnProtocol.requiresSystemExtension else {
            return
        }

        // Before the callback is called, user will get an error alert
        // if installation failed, and will be re-prompted for installation if they try
        // to connect from the profile overview after failure/while installation is pending.
        // Note that this callback can be called twice if the user closes the sysex tour window
        // before going to system preferences!
        sysexStateCheck.startCheckAndInstallIfNeeded(userInitiated: true) { result in
            DispatchQueue.main.async {
                self.sysexPending = false
                completion(result)
            }
        }
    }
}

extension CreateNewProfileViewModel: CustomStyleContext {
    func customStyle(context: AppTheme.Context) -> AppTheme.Style {
        switch context {
        case .field, .text:
            return .normal
        case .border, .background:
            return .weak
        default:
            break
        }
        assertionFailure("Context not handled: \(context)")
        return .normal
    }
}
