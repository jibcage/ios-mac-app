//
//  KillSwitchDropdownPresenter.swift
//  ProtonVPN - Created on 04/11/2020.
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
import vpncore
import AppKit

class KillSwitchDropdownPresenter: QuickSettingDropdownPresenter {
    
    typealias Factory = VpnGatewayFactory & PropertiesManagerFactory & AppStateManagerFactory & CoreAlertServiceFactory
    
    private let factory: Factory
    
    private lazy var propertiesManager: PropertiesManagerProtocol = factory.makePropertiesManager()
    private lazy var alertService: CoreAlertService = factory.makeCoreAlertService()
    
    override var learnLink: String {
        return CoreAppConstants.ProtonVpnLinks.killSwitchSupport
    }
    
    override var title: String! {
        return LocalizedString.killSwitch
    }
    
    init( _ factory: Factory ) {
        self.factory = factory
        super.init(factory.makeVpnGateway(), appStateManager: factory.makeAppStateManager())
    }
    
    override var options: [QuickSettingsDropdownOptionPresenter] {
        return [killSwitchOff, killSwitchOn]
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        viewController?.dropdownDescription.attributedStringValue = LocalizedString.quickSettingsKillSwitchDescription.attributed(withColor: .protonWhite(), fontSize: 12, alignment: .left)
        viewController?.dropdownNote.attributedStringValue = LocalizedString.quickSettingsKillSwitchNote.attributed(withColor: .protonGreyUnselectedWhite(), fontSize: 12, italic: true, alignment: .left)
        viewController?.dropdownUgradeButton.isHidden = true
        if propertiesManager.featureFlags.netShield {
            viewController?.arrowHorizontalConstraint.constant = ((AppConstants.Windows.sidebarWidth - 18) / 3) - 7
        } else {
            viewController?.arrowHorizontalConstraint.constant = ((AppConstants.Windows.sidebarWidth - 18) / 5) + 12
        }
    }
    
    // MARK: - Private
    
    private var killSwitchOff: QuickSettingGenericOption {
        let active = propertiesManager.killSwitch
        let text = LocalizedString.killSwitch + " " + LocalizedString.switchSideButtonOff.capitalized
        let icon = #imageLiteral(resourceName: "qs_killswitch_off")
        return QuickSettingGenericOption(text, icon: icon, active: !active, selectCallback: {
            self.propertiesManager.killSwitch = false
            if self.vpnGateway.connection == .connected {
                self.vpnGateway.retryConnection()
            }
        })
    }
    
    private var killSwitchOn: QuickSettingGenericOption {
        let active = propertiesManager.killSwitch
        let text = LocalizedString.killSwitch + " " + LocalizedString.switchSideButtonOn.capitalized
        let icon = #imageLiteral(resourceName: "qs_killswitch_on")
        return QuickSettingGenericOption(text, icon: icon, active: active, selectCallback: {
            let wrapper = {
                self.propertiesManager.killSwitch = true
                self.propertiesManager.excludeLocalNetworks = false
                if self.vpnGateway.connection == .connected {
                    self.vpnGateway.retryConnection()
                }
            }
            
            guard self.propertiesManager.excludeLocalNetworks else {
                wrapper()
                return
            }
            
            self.alertService.push(alert: TurnOnKillSwitchAlert(confirmHandler: wrapper, cancelHandler: nil))
        })
    }
}
