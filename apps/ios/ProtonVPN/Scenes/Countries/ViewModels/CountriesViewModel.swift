//
//  CountriesSectionViewModel.swift
//  ProtonVPN - Created on 01.07.19.
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

import Foundation
import UIKit
import vpncore

enum ServerItemModel {
    case server(ServerItemViewModel)
    case secureCoreServer(SecureCoreServerItemViewModel)
}

class CountriesViewModel: SecureCoreToggleHandler {
    
    // MARK: vars and init
    private enum ModelState {
        
        case standard([CountryGroup])
        case secureCore([CountryGroup])
        
        var currentContent: [CountryGroup] {
            switch self {
            case .standard(let content):
                return content
            case .secureCore(let content):
                return content
            }
        }

        var serverType: ServerType {
            switch self {
            case .standard:
                return .standard
            case .secureCore:
                return .secureCore
            }
        }
    }
    
    var contentChanged: (() -> Void)?
    
    private let serverManager = ServerManagerImplementation.instance(forTier: CoreAppConstants.VpnTiers.visionary, serverStorage: ServerStorageConcrete())
    private var userTier: Int = 0
    private var state: ModelState = .standard([])
    
    var activeView: ServerType {
        return state.serverType
    }
    
    var secureCoreOn: Bool {
        return state.serverType == .secureCore
    }

    public typealias Factory = AppStateManagerFactory & PropertiesManagerFactory & CoreAlertServiceFactory & LoginServiceFactory & PlanServiceFactory & ConnectionStatusServiceFactory & VpnKeychainFactory
    private let factory: Factory
    
    private lazy var appStateManager: AppStateManager = factory.makeAppStateManager()
    private lazy var propertiesManager: PropertiesManagerProtocol = factory.makePropertiesManager()
    internal lazy var alertService: AlertService = factory.makeCoreAlertService()
    private lazy var loginService: LoginService = factory.makeLoginService()
    private lazy var planService: PlanService = factory.makePlanService()
    private lazy var keychain: VpnKeychainProtocol = factory.makeVpnKeychain()
    private lazy var connectionStatusService = factory.makeConnectionStatusService()
    
    private let countryService: CountryService
    var vpnGateway: VpnGatewayProtocol?
    
    init(factory: Factory, vpnGateway: VpnGatewayProtocol?, countryService: CountryService, loginService: LoginService) {
        self.factory = factory
        self.vpnGateway = vpnGateway
        self.countryService = countryService
        
        setTier()
        setStateOf(type: propertiesManager.serverTypeToggle) // if last showing SC, then launch into SC
        
        addObservers()
    }
    
    func serversByCountryCode(code: String, isSCOn: Bool) -> [ServerModel]? {
        let type = isSCOn ? ServerType.secureCore : ServerType.standard
        let result = serverManager.grouping(for: type).filter { $0.0.countryCode == code }
        if !result.isEmpty {
            return result[0].1
        }
        return nil
    }
    
    var enableViewToggle: Bool {
        return vpnGateway == nil || vpnGateway?.connection != .connecting
    }
    
    var cellHeight: CGFloat {
        return 72
    }
    
    func headerHeight(for section: Int) -> CGFloat {
        if numberOfSections() < 2 { return 0 }
        return titleFor(section: section) != nil ? UIConstants.countriesHeaderHeight : 0
    }
    
    func numberOfSections() -> Int {
        setTier() // good place to update because generally an infrequent call that should be called every table reload
        return CoreAppConstants.VpnTiers.allCases
            .map { self.content(for: $0) }
            .filter { !$0.isEmpty }
            .count
    }
    
    func numberOfRows(in section: Int) -> Int {
        return content(for: section).count
    }
    
    func titleFor(section: Int) -> String? {
        if numberOfRows(in: section) == 0 { return nil }
        let totalCountries = " (\(numberOfRows(in: section)))"
        switch userTier {
        case 0:
            return [LocalizedString.locationsFree, LocalizedString.locationsBasicPlus][section] + totalCountries
        case 1:
            return [LocalizedString.locationsBasic, LocalizedString.locationsPlus][section] + totalCountries
        default:
            return LocalizedString.locationsAll + totalCountries
        }
    }

    func isTierTooLow( for section: Int ) -> Bool {
        if userTier > 1 { return false }
        if userTier == 0 { return section > 0 }
        return section == 1
    }
    
    func cellModel(for row: Int, in section: Int) -> CountryItemViewModel? {
        let countryGroup = content(for: section)[row]
        
        return CountryItemViewModel(countryGroup: countryGroup,
                                    serverType: state.serverType,
                                    appStateManager: appStateManager,
                                    vpnGateway: vpnGateway,
                                    alertService: alertService,
                                    loginService: loginService,
                                    planService: planService,
                                    connectionStatusService: connectionStatusService,
                                    propertiesManager: propertiesManager
        )
    }
    
    func countryViewController(viewModel: CountryItemViewModel) -> CountryViewController? {
        return countryService.makeCountryViewController(country: viewModel)
    }
    
    // MARK: - Private functions
    private func setTier() {
        do {
            if (try keychain.fetch()).isDelinquent {
                userTier = CoreAppConstants.VpnTiers.free
                return
            }
            userTier = try vpnGateway?.userTier() ?? CoreAppConstants.VpnTiers.plus
        } catch {
            userTier = CoreAppConstants.VpnTiers.free
        }
    }
    
    private func content(for section: Int) -> [CountryGroup] {
        switch userTier {
        case 0:
            if section == 0 { return state.currentContent.filter({ $0.0.lowestTier == 0 }) }
            if section == 1 { return state.currentContent.filter({ $0.0.lowestTier > 0 }) }
        case 1:
            if section == 0 { return state.currentContent.filter({ $0.0.lowestTier < 2 }) }
            if section == 1 { return state.currentContent.filter({ $0.0.lowestTier == 2 }) }
        default:
            if section == 0 { return state.currentContent }
        }
        return []
    }
    
    private func addObservers() {
        guard vpnGateway != nil else { return }
        
        NotificationCenter.default.addObserver(self, selector: #selector(activeServerTypeSet),
                                               name: VpnGateway.activeServerTypeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reloadContent),
                                               name: VpnKeychain.vpnPlanChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reloadContent),
                                               name: serverManager.contentChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reloadContent),
                                               name: type(of: propertiesManager).vpnProtocolNotification, object: nil)
    }
    
    internal func setStateOf(type: ServerType) {
        switch type {
        case .standard, .p2p, .tor, .unspecified:
            state = ModelState.standard(serverManager.grouping(for: .standard).filter(onlyWireguardServersAndCountries: propertiesManager.showOnlyWireguardServersAndCountries))
        case .secureCore:
            state = ModelState.secureCore(serverManager.grouping(for: .secureCore).filter(onlyWireguardServersAndCountries: propertiesManager.showOnlyWireguardServersAndCountries))
        }
    }
    
    @objc private func activeServerTypeSet() {
        guard propertiesManager.serverTypeToggle != activeView else { return }
        reloadContent()
    }

    @objc private func reloadContent() {
        setTier()
        setStateOf(type: propertiesManager.serverTypeToggle)
        contentChanged?()
    }
}
