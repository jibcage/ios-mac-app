//
//  AppSessionManager.swift
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

enum SessionStatus {
    
    case notEstablished
    case established
}

protocol AppSessionManagerFactory {
    func makeAppSessionManager() -> AppSessionManager
}

protocol AppSessionManager {
    var sessionStatus: SessionStatus { get set }
    var loggedIn: Bool { get }
    
    var sessionChanged: Notification.Name { get }
    
    func attemptSilentLogIn(success: @escaping () -> Void, failure: @escaping (Error) -> Void)
    func refreshVpnAuthCertificate(success: @escaping () -> Void, failure: @escaping (Error) -> Void)
    func logIn(username: String, password: String, success: @escaping () -> Void, failure: @escaping (Error) -> Void)
    func logOut(force: Bool)
    func logOut()
    
    func replyToApplicationShouldTerminate()
}

class AppSessionManagerImplementation: AppSessionRefresherImplementation, AppSessionManager {

    typealias Factory = VpnApiServiceFactory & AuthApiServiceFactory & AppStateManagerFactory & NavigationServiceFactory & VpnKeychainFactory & PropertiesManagerFactory & ServerStorageFactory & VpnGatewayFactory & CoreAlertServiceFactory & AppSessionRefreshTimerFactory & AnnouncementRefresherFactory & VpnAuthenticationFactory
    private let factory: Factory
    
    internal lazy var appStateManager: AppStateManager = factory.makeAppStateManager()
    private lazy var authApiService: AuthApiService = factory.makeAuthApiService()
    private var navService: NavigationService? {
        return factory.makeNavigationService()
    }

    private lazy var refreshTimer: AppSessionRefreshTimer = factory.makeAppSessionRefreshTimer()
    private lazy var announcementRefresher: AnnouncementRefresher = factory.makeAnnouncementRefresher()
    private lazy var vpnAuthentication: VpnAuthentication = factory.makeVpnAuthentication()

    let sessionChanged = Notification.Name("AppSessionManagerSessionChanged")
    var sessionStatus: SessionStatus = .notEstablished
    
    init(factory: Factory) {
        self.factory = factory
        super.init(factory: factory)
        self.propertiesManager.restoreStartOnBootStatus()
    }
    
    // MARK: - Beginning of the log in logic.
    override func attemptSilentLogIn(success: @escaping () -> Void, failure: @escaping (Error) -> Void) {
        guard AuthKeychain.fetch() != nil else {
            failure(ProtonVpnErrorConst.userCredentialsMissing)
            return
        }
        
        success()
        
        retrievePropertiesAndLogIn(success: success, failure: { error in
            DispatchQueue.main.async { failure(error) }
        })
    }
    
    func logIn(username: String, password: String, success: @escaping () -> Void, failure: @escaping (Error) -> Void) {
        authApiService.authenticate(username: username, password: password, success: { [weak self] authCredentials in
            do {
                try AuthKeychain.store(authCredentials)
            } catch {
                DispatchQueue.main.async { failure(ProtonVpnError.keychainWriteFailed) }
                return
            }
            self?.retrievePropertiesAndLogIn(success: success, failure: failure)
            
        }, failure: { error in
            PMLog.ET("Failed to obtain user's auth credentials: \(error)")
            DispatchQueue.main.async { failure(error) }
        })
    }

    func refreshVpnAuthCertificate(success: @escaping () -> Void, failure: @escaping (Error) -> Void) {
        guard loggedIn else {
            success()
            return
        }

        self.vpnAuthentication.refreshCertificates { result in
            switch result {
            case .success:
                success()
            case let .failure(error):
                failure(error)
            }
        }
    }
    
    private func retrievePropertiesAndLogIn(success: @escaping () -> Void, failure: @escaping (Error) -> Void) {
        vpnApiService.vpnProperties(lastKnownIp: propertiesManager.userIp, success: { [weak self] properties in
            guard let `self` = self else { return }
            
            if let credentials = properties.vpnCredentials {
                self.vpnKeychain.store(vpnCredentials: credentials)
            }
            self.serverStorage.store(properties.serverModels)
            
            if self.appStateManager.state.isDisconnected {
                self.propertiesManager.userIp = properties.ip
            }
            self.propertiesManager.openVpnConfig = properties.clientConfig.openVPNConfig
            self.propertiesManager.wireguardConfig = properties.clientConfig.wireGuardConfig
            self.propertiesManager.smartProtocolConfig = properties.clientConfig.smartProtocolConfig
            self.propertiesManager.streamingServices = properties.streamingResponse?.streamingServices ?? [:]
            self.propertiesManager.streamingResourcesUrl = properties.streamingResponse?.resourceBaseURL
            self.propertiesManager.featureFlags = properties.clientConfig.featureFlags
            self.propertiesManager.maintenanceServerRefreshIntereval = properties.clientConfig.serverRefreshInterval
            if self.propertiesManager.featureFlags.pollNotificationAPI {
                self.announcementRefresher.refresh()
            }

            self.resolveActiveSession(success: { [weak self] in
                self?.setAndNotify(for: .established)
                ProfileManager.shared.refreshProfiles()
                self?.refreshVpnAuthCertificate(success: success, failure: failure)
            }, failure: { error in
                self.logOutCleanup()
                failure(error)
            })
        }, failure: { [weak self] error in
            PMLog.D("Failed to obtain user's VPN properties: \(error.localizedDescription)", level: .error)
            guard let `self` = self, // only fail if there is a major reason
                  !self.serverStorage.fetch().isEmpty,
                  self.propertiesManager.userIp != nil,
                  !(error is KeychainError) else {
                failure(error)
                return
            }
            
            self.setAndNotify(for: .established)
            ProfileManager.shared.refreshProfiles()
            self.refreshVpnAuthCertificate(success: success, failure: failure)
        })
    }
    
    private func resolveActiveSession(success: @escaping () -> Void, failure: @escaping (Error) -> Void) {

        DispatchQueue.main.async { [weak self] in
            self?.navService?.sessionRefreshed()
        }
        
        guard appStateManager.state.isConnected else {
            success()
            return
        }
        
        guard let activeUsername = appStateManager.state.descriptor?.username else {
            failure(ProtonVpnError.fetchSession)
            return
        }
        
        do {
            let vpnCredentials = try vpnKeychain.fetch()
            
            if activeUsername.removeSubstring(startingWithCharacter: VpnManagerConfiguration.configConcatChar)
                == vpnCredentials.name.removeSubstring(startingWithCharacter: VpnManagerConfiguration.configConcatChar) {
                success()
                return
            }
            
            let confirmationClosure: () -> Void = { [weak self] in
                guard let `self` = self else { return }
                if self.appStateManager.state.isConnected {
                    self.appStateManager.disconnect { success() }
                    return
                }
                success()
            }
            
            let cancelationClosure: () -> Void = {
                failure(ProtonVpnErrorConst.vpnSessionInProgress)
            }
            
            let alert = ActiveSessionWarningAlert(confirmHandler: confirmationClosure, cancelHandler: cancelationClosure)
            alertService.push(alert: alert)
        } catch {
            alertService.push(alert: CannotAccessVpnCredentialsAlert(confirmHandler: {
                failure(ProtonVpnError.fetchSession)
            }))
            return
        }
    }
    
    // MARK: - Log out
    func logOut(force: Bool) {
        loggedIn = false
        
        if force || !appStateManager.state.isConnected {
            confirmLogout()
        } else {
            let logoutAlert = LogoutWarningLongAlert(confirmHandler: { [confirmLogout] in
                confirmLogout()
            })
            alertService.push(alert: logoutAlert)
        }
    }
    
    func logOut() {
        logOut(force: false)
    }
    
    private func confirmLogout() {
        switch appStateManager.state {
        case .connecting:
            appStateManager.cancelConnectionAttempt { [logoutRoutine] in logoutRoutine() }
        default:
            appStateManager.disconnect { [logoutRoutine] in logoutRoutine() }
        }
    }
    
    private func logoutRoutine() {
        setAndNotify(for: .notEstablished)
        logOutCleanup()
    }
    
    private func logOutCleanup() {
        refreshTimer.stop()
        loggedIn = false
        
        AuthKeychain.clear()
        vpnKeychain.clear()
        vpnAuthentication.clear()
        announcementRefresher.clear()
        
        propertiesManager.logoutCleanup()
    }
    // End of the logout logic
    // MARK: -
    
    private func setAndNotify(for state: SessionStatus) {
        guard !loggedIn else { return }
        
        loggedIn = true
        sessionStatus = state
        
        var object: Any?
        if state == .established {
            object = factory.makeVpnGateway()
            
            // No need to connect twice on macOS 10.15+
            if #available(OSX 10.15, *) {
                PropertiesManager().hasConnected = true
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let `self` = self else { return }
            NotificationCenter.default.post(name: self.sessionChanged, object: object)
        }
        
        refreshTimer.start()
    }
    
    // MARK: - AppDelegate quit behaviour
    
    func replyToApplicationShouldTerminate() {
        guard sessionStatus == .established && !appStateManager.state.isSafeToEnd && !propertiesManager.rememberLoginAfterUpdate else {
            NSApp.reply(toApplicationShouldTerminate: true)
            return
        }
        
        let confirmationClosure: () -> Void = { [weak self] in
            self?.appStateManager.disconnect {
                DispatchQueue.main.async {
                    NSApp.reply(toApplicationShouldTerminate: true)
                }
            }
        }

        // ensure application data hasn't been cleared
        guard Storage.userDefaults().bool(forKey: AppConstants.UserDefaults.launchedBefore) else {
            confirmationClosure()
            return
        }
        
        let cancelationClosure: () -> Void = { NSApp.reply(toApplicationShouldTerminate: false) }
        
        let alert = QuitWarningAlert(confirmHandler: confirmationClosure, cancelHandler: cancelationClosure)
        alertService.push(alert: alert)
    }
}
