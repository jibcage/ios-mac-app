//
//  VpnKeychain.swift
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
import KeychainAccess

public typealias VpnDowngradeInfo = (from: VpnCredentials, to: VpnCredentials)
public typealias VpnReconnectInfo = (from: ServerModel, to: ServerModel)

public protocol VpnKeychainProtocol {
    
    static var vpnCredentialsChanged: Notification.Name { get }
    static var vpnPlanChanged: Notification.Name { get }
    static var vpnMaxDevicesReached: Notification.Name { get }
    static var vpnUserDelinquent: Notification.Name { get }
    
    func fetch() throws -> VpnCredentials
    func fetchOpenVpnPassword() throws -> Data
    func store(vpnCredentials: VpnCredentials)
    func getServerCertificate() throws -> SecCertificate
    func storeServerCertificate() throws
    func store(wireguardConfiguration: String) throws -> Data
    func fetchWireguardConfigurationReference() throws -> Data
    func fetchWireguardConfiguration() throws -> String?
    func clear()
    
    // Dealing with old vpn password entry.
    // These can be deleted after all users have iOS version > 1.3.2 and MacOs app version > 1.5.5
    func hasOldVpnPassword() -> Bool
    func clearOldVpnPassword() throws
}

public protocol VpnKeychainFactory {
    func makeVpnKeychain() -> VpnKeychainProtocol
}

public class VpnKeychain: VpnKeychainProtocol {
    
    private struct StorageKey {
        static let vpnCredentials = "vpnCredentials"
        static let openVpnPassword_old = "openVpnPassword"
        static let vpnServerPassword = "ProtonVPN-Server-Password"
        static let serverCertificate = "ProtonVPN_ike_root"
        static let wireguardSettings = "ProtonVPN_wg_settings"
    }
    
    private let appKeychain = Keychain(service: KeychainConstants.appKeychain).accessibility(.afterFirstUnlockThisDeviceOnly)
    
    public static let vpnCredentialsChanged = Notification.Name("VpnKeychainCredentialsChanged")
    public static let vpnPlanChanged = Notification.Name("VpnKeychainPlanChanged")
    public static let vpnUserDelinquent = Notification.Name("VpnUserDelinquent")
    public static let vpnMaxDevicesReached = Notification.Name("VpnMaxDevicesReached")
        
    public init() {}
    
    public func fetch() throws -> VpnCredentials {
        
        do {
            if let data = try appKeychain.getData(StorageKey.vpnCredentials) {
                if let vpnCredentials = NSKeyedUnarchiver.unarchiveObject(with: data) as? VpnCredentials {
                    return vpnCredentials
                }
            }
        } catch let error {
            PMLog.D("Keychain (vpn) read error: \(error)", level: .error)
        }
        
        let error = ProtonVpnErrorConst.vpnCredentialsMissing
        PMLog.D(error.localizedDescription, level: .error)
        throw error
    }
    
    public func fetchOpenVpnPassword() throws -> Data {
        do {
            let password = try getPasswordRefference(forKey: StorageKey.vpnServerPassword)
            return password
        } catch let error {
            PMLog.D(error.localizedDescription, level: .error)
            throw ProtonVpnErrorConst.vpnCredentialsMissing
        }
    }
    
    public func store(vpnCredentials: VpnCredentials) {
        
        if let currentCredentials = try? fetch() {
            DispatchQueue.main.async {
                let downgradeInfo = VpnDowngradeInfo(currentCredentials, vpnCredentials)
                if !currentCredentials.isDelinquent, vpnCredentials.isDelinquent {
                    NotificationCenter.default.post(name: VpnKeychain.vpnUserDelinquent, object: downgradeInfo)
                }

                if currentCredentials.maxTier != vpnCredentials.maxTier {
                    NotificationCenter.default.post(name: VpnKeychain.vpnPlanChanged, object: downgradeInfo)
                }
            }
        }

        do {
            try appKeychain.set(NSKeyedArchiver.archivedData(withRootObject: vpnCredentials), key: StorageKey.vpnCredentials)
        } catch let error {
            PMLog.D("Keychain (vpn) write error: \(error)", level: .error)
        }
        
        do {
            try setPassword(vpnCredentials.password, forKey: StorageKey.vpnServerPassword)
        } catch let error {
            PMLog.ET("Error occurred during OpenVPN password storage: \(error.localizedDescription)")
        }
        
        DispatchQueue.main.async { NotificationCenter.default.post(name: VpnKeychain.vpnCredentialsChanged, object: vpnCredentials) }
    }
    
    public func clear() {
        appKeychain[data: StorageKey.vpnCredentials] = nil
        deleteServerCertificate()
        do {
            try clearPassword(forKey: StorageKey.vpnServerPassword)
            try clearPassword(forKey: StorageKey.wireguardSettings)
            DispatchQueue.main.async { NotificationCenter.default.post(name: VpnKeychain.vpnCredentialsChanged, object: nil) }
        } catch { }
    }
    
    // Password is set and retrieved without using the library because NEVPNProtocol reuquires it to be
    // a "persistent keychain reference to a keychain item containing the password component of the
    // tunneling protocol authentication credential".
    public func getPasswordRefference(forKey key: String) throws -> Data {
        var query = formBaseQuery(forKey: key)
        query[kSecMatchLimit as AnyHashable] = kSecMatchLimitOne
        query[kSecReturnPersistentRef as AnyHashable] = kCFBooleanTrue
        
        var secItem: AnyObject?
        let result = SecItemCopyMatching(query as CFDictionary, &secItem)
        if result != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(result), userInfo: nil)
        }
        
        if let item = secItem as? Data {
            return item
        } else {
            throw ProtonVpnErrorConst.vpnCredentialsMissing
        }
    }
    
    public func setPassword(_ password: String, forKey key: String) throws {
        do {
            var query = formBaseQuery(forKey: key)
            query[kSecMatchLimit as AnyHashable] = kSecMatchLimitOne
            query[kSecReturnAttributes as AnyHashable] = kCFBooleanTrue
            query[kSecReturnData as AnyHashable] = kCFBooleanTrue
            
            var secItem: AnyObject?
            let result = SecItemCopyMatching(query as CFDictionary, &secItem)
            if result != errSecSuccess {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(result), userInfo: nil)
            }
            
            guard let data = secItem as? [String: AnyObject],
                let passwordData = data[kSecValueData as String] as? Data,
                let oldPassword = String(data: passwordData, encoding: String.Encoding.utf8) else {
                    throw NSError(domain: NSOSStatusErrorDomain, code: -1, userInfo: nil)
            }
            
            if password != oldPassword {
                throw NSError(domain: NSOSStatusErrorDomain, code: -1, userInfo: nil)
            }
        } catch {
            do {
                try clearPassword(forKey: key)
            } catch { }
            
            var query = formBaseQuery(forKey: key)
            query[kSecValueData as AnyHashable] = password.data(using: String.Encoding.utf8) as Any
            
            let result = SecItemAdd(query as CFDictionary, nil)
            if result != errSecSuccess {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(result), userInfo: nil)
            }
        }
    }
    
    private func clearPassword(forKey key: String) throws {
        let query = formBaseQuery(forKey: key)
        
        let result = SecItemDelete(query as CFDictionary)
        if result != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(result), userInfo: nil)
        }
    }
    
    private func formBaseQuery(forKey key: String) -> [AnyHashable: Any] {
        return [
            kSecClass as AnyHashable: kSecClassGenericPassword,
            kSecAttrGeneric as AnyHashable: key,
            kSecAttrAccount as AnyHashable: key,
            kSecAttrService as AnyHashable: key,
            kSecAttrAccessible as AnyHashable: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ] as [AnyHashable: Any]
    }
    
    // MARK: -
    // Dealing with old vpn password entry.
    // These can be deleted after all users have iOS version > 1.3.2 and MacOs app version > 1.5.5
    
    public func hasOldVpnPassword() -> Bool {
        var query = formBaseQuery(forKey: StorageKey.openVpnPassword_old)
        query[kSecMatchLimit as AnyHashable] = kSecMatchLimitOne
        query[kSecReturnPersistentRef as AnyHashable] = kCFBooleanTrue
        query[kSecAttrAccessible as AnyHashable] = kSecAttrAccessibleAlwaysThisDeviceOnly
        
        var secItem: AnyObject?
        let result = SecItemCopyMatching(query as CFDictionary, &secItem)
        if result != errSecSuccess {
            return false
        }

        return secItem != nil && secItem is Data
    }
    
    public func clearOldVpnPassword() throws {
        var query = formBaseQuery(forKey: StorageKey.openVpnPassword_old)
        query[kSecAttrAccessible as AnyHashable] = kSecAttrAccessibleAlwaysThisDeviceOnly
        
        let result = SecItemDelete(query as CFDictionary)
        if result != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(result), userInfo: nil)
        }
    }
    
    // MARK: - Certificates
    
    public func getServerCertificate() throws -> SecCertificate {
        let query: [String: Any] = [kSecClass as String: kSecClassCertificate,
                                    kSecAttrLabel as String: StorageKey.serverCertificate,
                                    kSecReturnRef as String: kCFBooleanTrue as Any]
        var item: CFTypeRef?
        let result = SecItemCopyMatching(query as CFDictionary, &item)
        guard result == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(result), userInfo: nil)
        }

        return item as! SecCertificate
    }
    
    public func storeServerCertificate() throws {
        let certificateFile = Bundle.main.path(forResource: StorageKey.serverCertificate, ofType: "der")!
        let certificateData = NSData(contentsOfFile: certificateFile)!
        let certificate = SecCertificateCreateWithData(nil, certificateData)!
        
        let query: [String: Any] = [kSecClass as String: kSecClassCertificate,
                                    kSecValueRef as String: certificate,
                                    kSecAttrLabel as String: StorageKey.serverCertificate]
        
        let result = SecItemAdd(query as CFDictionary, nil)
        guard result == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(result), userInfo: nil)
        }
    }
    
    private func deleteServerCertificate() {
        let query: [String: Any] = [kSecClass as String: kSecClassCertificate,
                                    kSecAttrLabel as String: StorageKey.serverCertificate,
                                    kSecReturnRef as String: kCFBooleanTrue as Any]
        SecItemDelete(query as CFDictionary)
    }
    
    // MARK: - Wireguard
    
    public func store(wireguardConfiguration: String) throws -> Data {
        try setPassword(wireguardConfiguration, forKey: StorageKey.wireguardSettings)
        return try fetchWireguardConfigurationReference()
    }
    
    public func fetchWireguardConfigurationReference() throws -> Data {
        return try getPasswordRefference(forKey: StorageKey.wireguardSettings)
    }
    
    public func fetchWireguardConfiguration() throws -> String? {
        
        var query = formBaseQuery(forKey: StorageKey.wireguardSettings)
        query[kSecMatchLimit as AnyHashable] = kSecMatchLimitOne
        query[kSecValuePersistentRef as AnyHashable] = try fetchWireguardConfigurationReference()
        query[kSecReturnData as AnyHashable] = true
        
        var secItem: AnyObject?
        let result = SecItemCopyMatching(query as CFDictionary, &secItem)
        if result != errSecSuccess {
            PMLog.D("Keychain error: \(result)")
            return nil
        }
        
        if let item = secItem as? Data {
            let config = String(data: item, encoding: String.Encoding.utf8)
            PMLog.D("Config read: \(config ?? "-")")
            return config
            
        } else {
            PMLog.D("Keychain error: can't read data")
            return nil
        }
    }
    
}
