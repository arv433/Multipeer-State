//
//  Message.swift
//  MultipeerState
//
//  Created by Arvin Zojaji on 2018-12-27.
//  Copyright © 2018 Arvin Zojaji. All rights reserved.
//

import Foundation

struct Message: Codable {
    let body: String
}

extension Device {
    func send(text: String) throws {
        let message = Message(body: text)
        let payload = try JSONEncoder().encode(message)
        try self.session?.send(payload, toPeers: [self.peerID], with: .reliable)
    }
}
