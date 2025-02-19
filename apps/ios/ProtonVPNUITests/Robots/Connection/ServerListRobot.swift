//
//  ServerListRobot.swift
//  ProtonVPNUITests
//
//  Created by Egle Predkelyte on 2021-08-10.
//  Copyright © 2021 Proton Technologies AG. All rights reserved.
//

import pmtest

fileprivate let buttonConnectDisconnect = "con available"

class ServerListRobot: CoreElements {
    
    let verify = Verify()
    
    func connectToAServerViaServer() -> ConnectionStatusRobot {
        button(buttonConnectDisconnect).byIndex(0).tap()
        return ConnectionStatusRobot()
    }
    
    func disconectFromAServerViaServer() -> MainRobot {
        button(buttonConnectDisconnect).byIndex(0).tap()
        return MainRobot()
    }
    
    func connectToAPlusServer(_ name: String) -> MainRobot {
        staticText(name).tap()
        return MainRobot()
    }
    
    class Verify: CoreElements {
        
        @discardableResult
        func serverListIsOpen(_ name: String) -> ServerListRobot {
            staticText(name).wait().checkExists()
            return ServerListRobot()
        }
    }
}
