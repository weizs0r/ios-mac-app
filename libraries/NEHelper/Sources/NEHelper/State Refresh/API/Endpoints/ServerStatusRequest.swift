//
//  Created on 2022-10-03.
//
//  Copyright (c) 2022 Proton AG
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

import Foundation

public final class ServerStatusRequest: APIRequest {
    let params: Params
    let httpMethod = "GET"
    let hasBody = false

    var endpointUrl: String { "vpn/logicals/\(params.logicalId)/alternatives" }

    public struct Params: Codable {
        let logicalId: String
    }

    public struct Logical: Codable {
        public let id: String
        public let status: Int
        public let servers: [Server]

        enum CodingKeys: String, CodingKey {
            case id = "ID"
            case status = "Status"
            case servers = "Servers"
        }
    }
    
    public struct Server: Codable {
        public let entryIp: String
        public let exitIp: String
        public let domain: String
        public let id: String
        public let status: Int
        public let label: String
        public let x25519PublicKey: String?

        enum CodingKeys: String, CodingKey {
            case entryIp = "EntryIP"
            case exitIp = "ExitIP"
            case domain = "Domain"
            case id = "ID"
            case status = "Status"
            case label = "Label"
            case x25519PublicKey = "X25519PublicKey"
        }
        
        public var underMaintenance: Bool {
            status == 0
        }
    }

    public struct Response: Codable {
        let code: Int
        let original: Logical
        let alternatives: [Logical]

        enum CodingKeys: String, CodingKey {
            case code = "Code"
            case original = "Original"
            case alternatives = "Alternatives"
        }
    }

    public init(params: Params) {
        self.params = params
    }
}