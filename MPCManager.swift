//
//  MPCManager.swift
//  MultipeerState
//
//  Created by Arvin Zojaji on 2018-12-27.
//  Copyright © 2018 Arvin Zojaji. All rights reserved.
//

import Foundation
import MultipeerConnectivity

class MPCManager: NSObject {
    var advertiser: MCNearbyServiceAdvertiser
    var browser: MCNearbyServiceBrowser
    
    static let instance = MPCManager()
    
    let localPeerID: MCPeerID
    let serviceType = "MPC-Testing"
    
    var devices: [Device] = []
    
    override init() {
        // Get archived peerID if it exists or create a new one in the device's name and store it
        if let data = UserDefaults.standard.data(forKey: "peerID"), let id = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: data) {
            self.localPeerID = id!
        } else {
            let peerID = MCPeerID(displayName: UIDevice.current.name)
            let data = try? NSKeyedArchiver.archivedData(withRootObject: peerID, requiringSecureCoding: false)
            UserDefaults.standard.set(data, forKey: "peerID")
            self.localPeerID = peerID
        }

        self.advertiser = MCNearbyServiceAdvertiser(peer: localPeerID, discoveryInfo: nil, serviceType: self.serviceType)
        self.browser = MCNearbyServiceBrowser(peer: localPeerID, serviceType: self.serviceType)
        
        super.init()

        self.advertiser.delegate = self
        self.browser.delegate = self
    }
    
    func device(for id: MCPeerID) -> Device {
        // If the device is already in the devices property, return it
        for device in devices {
            if device.peerID == id { return device }
        }
        
        // Otherwise create a new device with the given ID
        let device = Device(peerID: id)
        
        // Append to the devices property and return it
        devices.append(device)
        return device
    }
    
    func start() {
        self.advertiser.startAdvertisingPeer()
        self.browser.startBrowsingForPeers()
        
        NotificationCenter.default.addObserver(self, selector: #selector(enteredBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    @objc func enteredBackground() {
        for device in self.devices {
            device.disconnect()
        }
    }

    struct Notifications {
        static let deviceDidChangeState = Notification.Name("deviceDidChangeState")
    }
}


extension MPCManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let device = MPCManager.instance.device(for: peerID)
        device.connect()
        invitationHandler(true, device.session)
    }
}

extension MPCManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        let device = MPCManager.instance.device(for: peerID)
        device.invite()
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

}

extension MPCManager {
    var connectedDevices: [Device] {
        return self.devices.filter{ $0.state == .connected }
    }
}


// Class for invidual Devices
class Device: NSObject {
    let peerID: MCPeerID
    var session: MCSession?
    var name: String
    var state = MCSessionState.notConnected
    var lastMessageRecieved: Message?
    
    init(peerID: MCPeerID) {
        self.name = peerID.displayName
        self.peerID = peerID
        super.init()
    }
    
    func invite() {
        MPCManager.instance.browser.invitePeer(self.peerID, to: self.session!, withContext: nil, timeout: 10)
    }
    
    func connect() {
        // Do not run if there already exists a session
        if self.session != nil { return }
        
        self.session = MCSession(peer: MPCManager.instance.localPeerID, securityIdentity: nil, encryptionPreference: .required)
        self.session?.delegate = self
    }
    
    func disconnect() {
        self.session?.disconnect()
        self.session = nil
    }
}

extension Device: MCSessionDelegate {
    static let messageRecievedNotification = Notification.Name("DeviceDidRecieveMessage")

    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        self.state = state
        NotificationCenter.default.post(name: MPCManager.Notifications.deviceDidChangeState, object: self)
    }
    
    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let message = try? JSONDecoder().decode(Message.self, from: data) {
            lastMessageRecieved = message
            NotificationCenter.default.post(name: Device.messageRecievedNotification, object: message, userInfo: ["from": self])
        }
    }

    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension Device {
    func send(text: String) throws {
        let message = Message(body: text)
        let payload = try JSONEncoder().encode(message)
        try self.session?.send(payload, toPeers: [self.peerID], with: .reliable)
    }
}

// Message structure containing body
struct Message: Codable {
    let body: String
}
