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
struct AppFeature {
    @ObservableState
    struct State {
        var welcome = WelcomeFeature.State()
        var main: MainFeature.State?
    }

    enum Action {
        case main(MainFeature.Action)
        case welcome(WelcomeFeature.Action)
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.welcome, action: \.welcome) {
          WelcomeFeature()
        }
        .ifLet(\.main, action: \.main) {
            MainFeature()
        }
        Reduce { state, action in
            switch action {
            case .main(.settings(.signOut)):
                state.welcome.destination = nil
                state.main = nil
                return .none
            case .main:
                return .none
            case .welcome(.destination(.presented(.signIn(.signInSuccess(let username))))):
                state.main = MainFeature.State(currentTab: .home, settings: .init(userName: username))
                return .none
            case .welcome:
                return .none
            }
        }
    }
}
