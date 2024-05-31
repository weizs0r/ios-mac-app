//
//  Created on 25/04/2024.
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

import ComposableArchitecture

@Reducer
struct MainFeature {

    enum Tab { case home, search, settings }

    @ObservableState
    struct State: Equatable {
        var currentTab: Tab = .home
        var settings: SettingsFeature.State = .init()
    }

    enum Action {
        case selectTab(Tab)
        case settings(SettingsFeature.Action)
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.settings, action: \.settings) {
            SettingsFeature()
        }
        Reduce { state, action in
            switch action {
            case .selectTab(let tab):
                state.currentTab = tab
                return .none
            case .settings:
                return .none
            }
        }
    }
}