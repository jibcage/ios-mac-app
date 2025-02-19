//
//  VpnManager+LocalAgent.swift
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

extension VpnManager {
    func connectLocalAgent(data: VpnAuthenticationData? = nil) {
        guard self.currentVpnProtocol?.authenticationType == .certificate else {
            return
        }

        let connect = { (data: VpnAuthenticationData) in
            guard let configuration = LocalAgentConfiguration(propertiesManager: self.propertiesManager, vpnProtocol: self.currentVpnProtocol) else {
                PMLog.ET("Cannot reconnect to the local agent with missing configuraton")
                return
            }

            self.disconnectLocalAgent()
            self.localAgent = LocalAgentImplementation()
            self.localAgent?.delegate = self
            self.localAgent?.connect(data: data, configuration: configuration)
        }

        if let authenticationData = data {
            connect(authenticationData)
            return
        }

        // load last authentication data (that should be available)
        vpnAuthentication.loadAuthenticationData { result in
            switch result {
            case .failure:
                PMLog.ET("Failed to initialize local agent because of missing authentication data")
            case let .success(data):
                connect(data)
            }
        }
    }

    func disconnectLocalAgent() {
        if localAgent != nil {
            PMLog.D("Disconnecting Local agent")
        }

        isLocalAgentConnected = false
        localAgent?.disconnect()
        localAgent = nil
    }

    func refreshCertificateWithError(success: @escaping (VpnAuthenticationData) -> Void) {
        vpnAuthentication.refreshCertificates { [weak self] result in
            switch result {
            case let .success(data):
                success(data)
            case let .failure(error):
                PMLog.ET("Trying to refresh expired or revoked certificate for current connection failed with \(error), showing error and disconnecting")
                self?.alertService?.push(alert: VPNAuthCertificateRefreshErrorAlert())
                self?.disconnect { [weak self] in
                    self?.localAgent?.disconnect()
                }
            }
        }
    }

    func reconnectWithNewKeyAndCertificate() {
        vpnAuthentication.clear()
        refreshCertificateWithError { _ in
            PMLog.D("Generated new keys and got new certificate, asking to reconnect")
            executeOnUIThread {
                NotificationCenter.default.post(name: VpnGateway.needsReconnectNotification, object: nil)
            }
        }
    }

    func disconnectWithAlert(alert: SystemAlert) {
        disconnect { }
        alertService?.push(alert: alert)
    }

    func updateActiveConnection(netShieldType: NetShieldType) {
        propertiesManager.lastConnectionRequest = propertiesManager.lastConnectionRequest?.withChanged(netShieldType: netShieldType)
        switch currentVpnProtocol {
        case .ike:
            propertiesManager.lastIkeConnection = propertiesManager.lastIkeConnection?.withChanged(netShieldType: netShieldType)
        case .openVpn:
            propertiesManager.lastOpenVpnConnection = propertiesManager.lastOpenVpnConnection?.withChanged(netShieldType: netShieldType)
        case .wireGuard:
            propertiesManager.lastWireguardConnection = propertiesManager.lastWireguardConnection?.withChanged(netShieldType: netShieldType)
        case nil:
            break
        }
    }
}

extension VpnManager: LocalAgentDelegate {
    // swiftlint:disable cyclomatic_complexity
    func didReceiveError(error: LocalAgentError) {
        switch error {
        case .certificateExpired, .certificateNotProvided:
            PMLog.D("Local agent reported expired or missing, trying to refresh and reconnect")
            refreshCertificateWithError { [weak self] data in
                PMLog.D("Reconnecting to local agent with new certificate")
                self?.connectLocalAgent(data: data)
            }
        case .badCertificateSignature, .certificateRevoked:
            PMLog.D("Local agent reported invalid certificate signature or revoked certificate, trying to generate new key and certificate and reconnect")
            reconnectWithNewKeyAndCertificate()
        case .keyUsedMultipleTimes:
            PMLog.D("Key used multiple times, trying to generate new key and certificate and reconnect")
            reconnectWithNewKeyAndCertificate()
        case .maxSessionsBasic, .maxSessionsPro, .maxSessionsFree, .maxSessionsPlus, .maxSessionsUnknown, .maxSessionsVisionary:
            disconnect { }
            guard let credentials = try? vpnKeychain.fetch() else {
                PMLog.ET("Cannot show max session alert because getting credentials failed")
                return
            }
            alertService?.push(alert: MaxSessionsAlert(userCurrentCredentials: credentials))
        case .serverError:
            PMLog.D("Server error occured, showing the user an alert and disconnecting")
            disconnectWithAlert(alert: VpnServerErrorAlert())
        case .guestSession:
            PMLog.ET("Internal status that should never be seen, check the app implementation")
            disconnect { }
        case .policyViolationDelinquent:
            PMLog.D("Disconnecting because of unpaid invoces")
            disconnectWithAlert(alert: DelinquentUserAlert())
        case .policyViolationLowPlan:
            disconnectWithAlert(alert: VpnServerSubscriptionErrorAlert())
        case .userTorrentNotAllowed, .userBadBehavior:
            PMLog.ET("Local agent reported error \(error) that the app does not handle, just disconnecting")
            disconnect { }
        case .restrictedServer:
            PMLog.D("Local agent reported restricted server error, waiting for the local agent to recover")
        }
    }
    // swiftlint:enable cyclomatic_complexity

    func didChangeState(state: LocalAgentState) {
        PMLog.D("Local agent state changed to \(state)")

        isLocalAgentConnected = state == .connected

        switch state {
        case .clientCertificateError:
            // because the local agent shared library does not return certificate expired error when connecting with expired certificate 🤷‍♀️
            // instead use this state as the certificate expired error
            didReceiveError(error: LocalAgentError.certificateExpired)
        default:
            break
        }
    }

    func didReceiveFeature(vpnAccelerator: Bool) {
        guard propertiesManager.vpnAcceleratorEnabled != vpnAccelerator else {
            return
        }

        PMLog.D("VPN Accelerator was set to \(propertiesManager.vpnAcceleratorEnabled), changing to \(vpnAccelerator) received from local agent")
        propertiesManager.vpnAcceleratorEnabled = vpnAccelerator
    }

    func didReceiveFeature(netshield: NetShieldType) {
        let currentNetshield = propertiesManager.netShieldType ?? NetShieldType.off
        guard currentNetshield != netshield else {
            return
        }

        PMLog.D("Netshield was set to \(currentNetshield), changing to \(netshield) received from local agent")
        updateActiveConnection(netShieldType: netshield)
        propertiesManager.netShieldType = netshield
    }
}
