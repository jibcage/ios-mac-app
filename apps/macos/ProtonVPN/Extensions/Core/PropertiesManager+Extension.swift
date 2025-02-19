//
//  PropertiesManager+Extension.swift
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

import Foundation
import ServiceManagement
import vpncore

extension PropertiesManagerProtocol {
    var earlyAccess: Bool {
        get {
            return Storage.userDefaults().bool(forKey: AppConstants.UserDefaults.earlyAccess)
        }
        set {
            Storage.setValue(newValue, forKey: AppConstants.UserDefaults.earlyAccess)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: PropertiesManager.earlyAccessNotification, object: newValue)
            }
        }
    }
    
    var unprotectedNetworkNotifications: Bool {
        get {
            return (Storage.userDefaults().object(forKey: AppConstants.UserDefaults.unprotectedNetworkNotifications) as? Bool) ?? true
        }
        set {
            Storage.setValue(newValue, forKey: AppConstants.UserDefaults.unprotectedNetworkNotifications)
        }
    }
    
    var dontAskAboutSwift5: Bool {
        get {
            return (Storage.userDefaults().object(forKey: AppConstants.UserDefaults.dontAskAboutSwift5) as? Bool) ?? false
        }
        set {
            Storage.setValue(newValue, forKey: AppConstants.UserDefaults.dontAskAboutSwift5)
        }
    }
    
    var rememberLoginAfterUpdate: Bool {
        get {
            return Storage.userDefaults().bool(forKey: AppConstants.UserDefaults.rememberLoginAfterUpdate)
        }
        set {
            Storage.setValue(newValue, forKey: AppConstants.UserDefaults.rememberLoginAfterUpdate)
        }
    }
    
    var startMinimized: Bool {
        get {
            return Storage.userDefaults().bool(forKey: AppConstants.UserDefaults.startMinimized)
        }
        set {
            Storage.setValue(newValue, forKey: AppConstants.UserDefaults.startMinimized)
        }
    }
    
    var startOnBoot: Bool {
        get {
            return Storage.userDefaults().bool(forKey: AppConstants.UserDefaults.startOnBoot)
        }
        set {
            Storage.setValue(newValue, forKey: AppConstants.UserDefaults.startOnBoot)
            self.setLoginItem(enabled: newValue)
        }
    }
    
    var systemNotifications: Bool {
        get {
            return Storage.userDefaults().bool(forKey: AppConstants.UserDefaults.systemNotifications)
        }
        set {
            Storage.setValue(newValue, forKey: AppConstants.UserDefaults.systemNotifications)
        }
    }
    
    var sysexSuccessWasShown: Bool {
        get {
            return Storage.userDefaults().bool(forKey: AppConstants.UserDefaults.sysexSuccessWasShown)
        }
        set {
            Storage.setValue(newValue, forKey: AppConstants.UserDefaults.sysexSuccessWasShown)
        }
    }
    
    func restoreStartOnBootStatus() {
        let enabled = self.startOnBoot
        self.setLoginItem(enabled: enabled)
    }
    
    // MARK: - Private
    private func setLoginItem(enabled: Bool) {
        let launcherAppIdentifier = "ch.protonvpn.ProtonVPNStarter"
        if SMLoginItemSetEnabled(launcherAppIdentifier as CFString, enabled) {
            if enabled {
                PMLog.printToConsole("Successfully add login item.")
            } else {
                PMLog.printToConsole("Successfully remove login item.")
            }
        } else {
            PMLog.printToConsole("Failed to add login item.")
        }
    }
}
