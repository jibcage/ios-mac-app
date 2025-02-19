//
//  QuickSettingsDropdownOptionPresenter.swift
//  ProtonVPN - Created on 10/11/2020.
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

protocol QuickSettingsDropdownOptionPresenter {
    var title: String! { get }
    var icon: NSImage! { get }
    var active: Bool! { get }
    var requiresUpdate: Bool! { get }
    
    var selectCallback: SuccessCallback? { get }
}

class QuickSettingGenericOption: QuickSettingsDropdownOptionPresenter {
    
    let title: String!
    let active: Bool!
    var icon: NSImage! = #imageLiteral(resourceName: "protonvpn-server-tor-list")
    var requiresUpdate: Bool!
    var selectCallback: (() -> Void)?
    
    init( _ title: String, icon: NSImage, active: Bool, requiresUpdate: Bool = false, selectCallback: SuccessCallback? = nil ) {
        self.title = title
        self.active = active
        self.icon = icon
        self.requiresUpdate = requiresUpdate
        self.selectCallback = selectCallback
    }
}

final class QuickSettingNetshieldOption: QuickSettingGenericOption {
    init(level: NetShieldType, vpnGateway: VpnGatewayProtocol, vpnManager: VpnManagerProtocol, netShieldPropertyProvider: NetShieldPropertyProvider, vpnStateConfiguration: VpnStateConfiguration, isActive: Bool, currentUserTier: Int, openUpgradeLink: @escaping () -> Void) {
        var netShieldPropertyProvider = netShieldPropertyProvider

        let text: String
        switch level {
        case .level1:
            text = LocalizedString.quickSettingsNetshieldOptionLevel1
        case .level2:
            text = LocalizedString.quickSettingsNetshieldOptionLevel2
        case .off:
            text = LocalizedString.quickSettingsNetshieldOptionOff
        }

        let icon: NSImage
        switch level {
        case .level1:
            icon = #imageLiteral(resourceName: "qs_netshield_level1")
        case .level2:
            icon = #imageLiteral(resourceName: "qs_netshield_level2")
        case .off:
            icon = #imageLiteral(resourceName: "qs_netshield_off")
        }

        super.init(text, icon: icon, active: isActive, requiresUpdate: level.isUserTierTooLow(currentUserTier), selectCallback: {
            guard !level.isUserTierTooLow(currentUserTier) else {
                openUpgradeLink()
                return
            }

            vpnStateConfiguration.getInfo { info in
                switch VpnFeatureChangeState(state: info.state, vpnProtocol: info.connection?.vpnProtocol) {
                case .withConnectionUpdate:
                    netShieldPropertyProvider.netShieldType = level
                    vpnManager.set(netShieldType: level)
                case .withReconnect:
                    netShieldPropertyProvider.netShieldType = level
                    vpnGateway.reconnect(with: netShieldPropertyProvider.netShieldType)
                case .immediately:
                    netShieldPropertyProvider.netShieldType = level
                }
            }
        })
    }
}
