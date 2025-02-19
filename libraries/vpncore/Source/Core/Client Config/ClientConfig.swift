//
//  ClientConfig.swift
//  vpncore - Created on 2020-09-08.
//
//  Copyright (c) 2019 Proton Technologies AG
//
//  This file is part of vpncore.
//
//  vpncore is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  vpncore is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with vpncore.  If not, see <https://www.gnu.org/licenses/>.
//

import Foundation

public struct ClientConfig {
    public let openVPNConfig: OpenVpnConfig
    public let featureFlags: FeatureFlags
    public let serverRefreshInterval: Int
    public let wireGuardConfig: WireguardConfig
    public let smartProtocolConfig: SmartProtocolConfig

    public init(openVPNConfig: OpenVpnConfig, featureFlags: FeatureFlags, serverRefreshInterval: Int, wireGuardConfig: WireguardConfig, smartProtocolConfig: SmartProtocolConfig) {
        self.openVPNConfig = openVPNConfig
        self.featureFlags = featureFlags
        self.serverRefreshInterval = serverRefreshInterval
        self.wireGuardConfig = wireGuardConfig
        self.smartProtocolConfig = smartProtocolConfig
    }

    public init() {
        self.init(openVPNConfig: OpenVpnConfig(), featureFlags: FeatureFlags(), serverRefreshInterval: CoreAppConstants.Maintenance.defaultMaintenanceCheckTime, wireGuardConfig: WireguardConfig(), smartProtocolConfig: SmartProtocolConfig())
    }
}
