//
//  VpnConnectionPreparer.swift
//  vpncore - Created on 26.06.19.
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

import Foundation

class VpnConnectionPreparer {
    
    private let appStateManager: AppStateManager
    private let vpnApiService: VpnApiService
    private let serverStorage: ServerStorage = ServerStorageConcrete()
    private let serverTierChecker: ServerTierChecker
    private let vpnKeychain: VpnKeychainProtocol
    private let smartProtocolConfig: SmartProtocolConfig
    private let openVpnConfig: OpenVpnConfig
    private let wireguardConfig: WireguardConfig
    
    public weak var alertService: CoreAlertService?
    
    private var smartProtocol: SmartProtocol?
    private var smartPortSelector: SmartPortSelector?
    
    init(appStateManager: AppStateManager, vpnApiService: VpnApiService, alertService: CoreAlertService?, serverTierChecker: ServerTierChecker, vpnKeychain: VpnKeychainProtocol, smartProtocolConfig: SmartProtocolConfig, openVpnConfig: OpenVpnConfig, wireguardConfig: WireguardConfig) {
        self.appStateManager = appStateManager
        self.vpnApiService = vpnApiService
        self.alertService = alertService
        self.serverTierChecker = serverTierChecker
        self.vpnKeychain = vpnKeychain
        self.smartProtocolConfig = smartProtocolConfig
        self.openVpnConfig = openVpnConfig
        self.wireguardConfig = wireguardConfig
    }
    
    func connect(with connectionProtocol: ConnectionProtocol, to server: ServerModel, netShieldType: NetShieldType) {
        guard let serverIp = selectServerIp(server: server) else {
            return
        }
        
        selectVpnProtocol(for: connectionProtocol, toIP: serverIp) { (vpnProtocol, ports) in
            PMLog.D("Connecting with \(vpnProtocol) to \(server.name) via \(serverIp.entryIp):\(ports)")
            self.connect(withProtocol: vpnProtocol, server: server, serverIp: serverIp, netShieldType: netShieldType, ports: ports)
        }
    }
    
    // MARK: - Private functions
    
    private func connect(withProtocol vpnProtocol: VpnProtocol, server: ServerModel, serverIp: ServerIp, netShieldType: NetShieldType, ports: [Int]) {
        if let configuration = formConfiguration(withProtocol: vpnProtocol, fromServer: server, serverIp: serverIp, netShieldType: netShieldType, ports: ports) {
            appStateManager.connect(withConfiguration: configuration)
        }
    }

    private func selectServerIp(server: ServerModel) -> ServerIp? {
        let availableServerIps = server.ips.filter { !$0.underMaintenance }

        guard !availableServerIps.isEmpty else {
            serverTierChecker.notifyResolutionUnavailable(forSpecificCountry: false, type: server.serverType, reason: .existingConnection)
            return nil
        }

        let serverIp = availableServerIps[Int(arc4random_uniform(UInt32(availableServerIps.count)))]
        PMLog.D("Selected \(serverIp.entryIp) as server ip for \(server.domain)")
        return serverIp
    }
    
    private func selectVpnProtocol(for connectionProtocol: ConnectionProtocol, toIP serverIp: ServerIp, completion: @escaping (VpnProtocol, [Int]) -> Void) {
        switch connectionProtocol {
        case .smartProtocol:
            smartProtocol = SmartProtocolImplementation(smartProtocolConfig: smartProtocolConfig, openVpnConfig: openVpnConfig, wireguardConfig: wireguardConfig)
            smartProtocol?.determineBestProtocol(server: serverIp) { (vpnProtocol, ports) in
                completion(vpnProtocol, ports)
            }
            
        case let .vpnProtocol(vpnProtocol):
            let portSelector = SmartPortSelectorImplementation(openVpnConfig: openVpnConfig, wireguardConfig: wireguardConfig)
            portSelector.determineBestPort(for: vpnProtocol, on: serverIp) { ports in
                completion(vpnProtocol, ports)
            }
        }
    }
    
    private func formConfiguration(withProtocol vpnProtocol: VpnProtocol, fromServer server: ServerModel, serverIp: ServerIp, netShieldType: NetShieldType, ports: [Int]) -> ConnectionConfiguration? {
        
        if let requiresUpgrade = serverTierChecker.serverRequiresUpgrade(server), requiresUpgrade {
            return nil
        }
        
        return ConnectionConfiguration(server: server, serverIp: serverIp, vpnProtocol: vpnProtocol, netShieldType: netShieldType, ports: ports)
    }
}
