//
//  Created on 22/03/2024.
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

/// Solution inspired by https://www.objc.io/blog/2018/12/18/atomic-variables/
final public class Atomic<A> {
    private let queue: DispatchQueue
    private var _value: A
    public init(_ value: A, queueLabel: String = "Atomic serial queue") {
        self._value = value
        self.queue = DispatchQueue(label: queueLabel)
    }

    public var value: A {
        queue.sync { self._value }
    }

    public func mutate(_ transform: (inout A) -> ()) {
        queue.sync {
            transform(&self._value)
        }
    }
}
