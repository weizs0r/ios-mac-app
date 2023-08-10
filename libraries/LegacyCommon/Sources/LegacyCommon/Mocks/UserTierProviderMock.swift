//
//  UserTierProviderMock.swift
//  vpncore - Created on 2021-01-06.
//
//  Copyright (c) 2019 Proton Technologies AG
//
//  This file is part of LegacyCommon.
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
//  along with LegacyCommon.  If not, see <https://www.gnu.org/licenses/>.
//

#if DEBUG
import Foundation
import LegacyCommon

public class UserTierProviderMock: UserTierProvider {
    
    public var currentUserTier: Int = -1
    
    public init(_ currentUserTier: Int) {
        self.currentUserTier = currentUserTier
    }
}
#endif