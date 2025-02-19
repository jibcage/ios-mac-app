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

import Alamofire
import Foundation
import vpncore

class LoginViewModel {
    
    typealias Factory = NavigationServiceFactory & PropertiesManagerFactory & AppSessionManagerFactory & CoreAlertServiceFactory & UpdateManagerFactory
    private let factory: Factory
    
    private lazy var propertiesManager: PropertiesManagerProtocol = factory.makePropertiesManager()
    private lazy var appSessionManager: AppSessionManager = factory.makeAppSessionManager()
    private lazy var navService: NavigationService = factory.makeNavigationService()
    private lazy var alertService: CoreAlertService = factory.makeCoreAlertService()
    private lazy var updateManager: UpdateManager = factory.makeUpdateManager()
    
    var logInInProgress: (() -> Void)?
    var logInFailure: ((String?) -> Void)?
    var logInFailureWithSupport: ((String?) -> Void)?

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
        appSessionManager.attemptSilentLogIn(success: { [silantlyCheckForUpdates] in
            NSApp.setActivationPolicy(.accessory)
            silantlyCheckForUpdates()
        }, failure: { [weak self] error in
            guard let `self` = self else { return }
            self.specialErrorCaseNotification(error)
            self.navService.handleSilentLoginFailure()
        })
    }
    
    func logInApperared() {
        logInInProgress?()
        appSessionManager.attemptSilentLogIn(success: { [silantlyCheckForUpdates] in
            silantlyCheckForUpdates()
        }, failure: { [weak self] error in
            guard let `self` = self else { return }
            self.specialErrorCaseNotification(error)
            self.logInFailure?((error as NSError) == ProtonVpnErrorConst.userCredentialsMissing ? nil : error.localizedDescription)
        })
    }
    
    func logIn(username: String, password: String) {
        logInInProgress?()
        appSessionManager.logIn(username: username, password: password, success: { [silantlyCheckForUpdates] in
            silantlyCheckForUpdates()
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
            } else if error as? UserError == UserError.failedHumanValidation {
                self.logInFailure?(nil)
            } else {
                self.logInFailure?(error.localizedDescription)
            }
        })
    }
    
    private func specialErrorCaseNotification(_ error: Error) {
        if error is KeychainError ||
            (error as NSError).code == NetworkErrorCode.timedOut ||
            (error as NSError).code == ApiErrorCode.apiVersionBad ||
            (error as NSError).code == ApiErrorCode.appVersionBad {
            logInFailureWithSupport?(error.localizedDescription)
        }
    }
    
    private func silantlyCheckForUpdates() {
        updateManager.checkForUpdates(appSessionManager, silently: true)
    }
    
    func keychainHelpAction() {
        SafariService.openLink(url: CoreAppConstants.ProtonVpnLinks.supportCommonIssues)
    }
    
    func createAccountAction() {
        SafariService.openLink(url: CoreAppConstants.ProtonVpnLinks.signUp)
    }
}
