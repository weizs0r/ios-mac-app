//
//  Created on 05/12/2023.
//
//  Copyright (c) 2023 Proton AG
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

import Dependencies
import GRDB

import Domain
import Ergonomics

extension ServerRepository {
    public static var liveValue: ServerRepository {
        @Dependency(\.appDB) var database

        return ServerRepository(
            serverCount: {
                try database.writer().read { db in
                    return try Endpoint.fetchCount(db)
                }
            },
            insertServers: { vpnServers in
                try database.writer().write { db in
                    try vpnServers.forEach { vpnServer in
                        try vpnServer.logicalRecord.insert(db, onConflict: .replace)
                        try vpnServer.logicalStatus.insert(db, onConflict: .replace)
                        try vpnServer.endpointRecords.forEach { endpoint in
                            try endpoint.insert(db, onConflict: .replace)
                        }
                        try vpnServer.overrideRecords.forEach { overridesInfo in
                            try overridesInfo.insert(db, onConflict: .replace)
                        }
                    }
                }
            },
            server: { filters, order in
                try database.writer().read { db in
                    let request = ServerResult.request(filters: filters, order: order)
                    let result = try ServerResult.fetchOne(db, request)

                    guard let result else { return nil }

                    return Domain.VPNServer(
                        logical: Domain.Logical(
                            staticInfo: result.logical,
                            dynamicInfo: result.logicalStatus
                        ),
                        endpoints: result.endpoints.map {
                            Domain.ServerEndpoint(
                                server: $0.server,
                                overrides: $0.overrideInfo
                            )
                        }
                    )
                }
            },
            servers: { filters, order in
                try database.writer().read { db in
                    let request = ServerInfoResult.request(filters: filters, order: order)

                    let results = try ServerInfoResult.fetchAll(db, request)

                    return results.map {
                        Domain.ServerInfo(
                            logical: Domain.Logical(
                                staticInfo: $0.logical,
                                dynamicInfo: $0.logicalStatus
                            ),
                            protocolSupport: $0.protocolMask
                        )
                    }
                }
            },
            deleteServers: { ids in
                try database.writer().write { db in
                    try Logical.filter(ids.contains(Logical.Columns.id))
                        .deleteAll(db)
                    return
                }
            },
            updateLoads: { loads in
                try database.writer().write { db in
                    let existingLogicalIDs = try String.fetchSet(db, Logical.select(Logical.Columns.id))
                    try loads
                        .filter { existingLogicalIDs.contains($0.serverId) }
                        .forEach { try $0.databaseRecord.insert(db, onConflict: .replace) }
                }
            },
            groups: { filters in
                try database.writer().read { db in
                    let request = GroupInfoResult.request(filters: filters)

                    return try GroupInfoResult.fetchAll(db, request)
                        .map { $0.domainModel }
                }
            }
        )
    }
}
