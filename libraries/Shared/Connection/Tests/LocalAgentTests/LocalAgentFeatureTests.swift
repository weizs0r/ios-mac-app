//
//  Created on 11/06/2024.
//
//  Copyright (c) 2024 Proton AG
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
import XCTest

import ComposableArchitecture

import Domain
import DomainTestSupport
@testable import LocalAgent
@testable import LocalAgentTestSupport

final class LocalAgentFeatureTests: XCTestCase {

    @MainActor func testReceivesStateUpdateWhenConnectionIsEstablished() async {
        let mockClock = TestClock()

        let server = ServerEndpoint(id: "serverID", entryIp: "", exitIp: "", domain: "", status: 1, label: "1", x25519PublicKey: nil, protocolEntries: nil)

        let disconnected = LocalAgentFeature.State.disconnected(nil)

        let localAgentMock = LocalAgentMock(state: .disconnected)

        let store = TestStore(initialState: disconnected) {
            LocalAgentFeature()
        } withDependencies: {
            $0.continuousClock = mockClock
            $0.localAgent = localAgentMock
            $0.date = .constant(.now)
        }

        await store.send(.startObservingEvents)
        await store.send(.connect(server, .empty)) {
            $0 = .connecting
        }

        localAgentMock.state = .connected
        await store.receive(\.connectionFinished.success) {
            $0 = .connected
        }

        await store.receive(\.event.state.connected)

        await store.send(.stopObservingEvents)
    }
}