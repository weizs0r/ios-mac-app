//
//  ErrorCodes.swift
//  vpncore - Created on 26.06.19.
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

import Foundation
import ProtonCoreServices

public class ErrorCode {
    
    public static let descriptionUnavailable = 1
    public static let vpnSessionInProgress = 20
    public static let vpnStuckDisconnecting = 21
    public static let userCredentialsMissing = 30
    public static let userCredentialsExpired = 31
    public static let vpnCredentialsMissing = 32
    public static let decodeFailure = 50
    
    public static let authProperties = 60
    public static let authCredentials = 61
    public static let modulus = 62
    public static let vpnCredentials = 63
    public static let serverInfo = 64
    public static let userIpInfo = 65
    public static let responseFormat = 66
    public static let sessionCount = 67
    public static let existingSession = 68
    public static let loads = 69
    public static let subscriptions = 70
    public static let usernameUnavailable = 71
    public static let refreshToken = 72
    public static let verificationMethods = 73
    
    // application errors
    public static let userCreation = 3000
}

public class NetworkErrorCode {
    
    public static let timedOut = NSURLErrorTimedOut
    public static let cannotFindHost = NSURLErrorCannotFindHost
    public static let cannotConnectToHost = NSURLErrorCannotConnectToHost
    public static let networkConnectionLost = NSURLErrorNetworkConnectionLost
    public static let notConnectedToInternet = NSURLErrorNotConnectedToInternet
    public static let dnsLookupFailed = NSURLErrorDNSLookupFailed
    public static let secureConnectionFailed = NSURLErrorSecureConnectionFailed
    public static let cannotParseResponse = NSURLErrorCannotParseResponse
    public static let potentiallyBlocked = APIErrorCode.potentiallyBlocked
    
    public static let tls = 3500
}

public class ApiErrorCode { // error codes returned by the api
    
    public static let alreadyRegistered = 2500
    
    public static let authInfo = 5001
    public static let appVersionBad = 5003
    public static let srpProof = 5004
    public static let apiVersionBad = 5005
    
    public static let apiOffline = 7001
    
    public static let wrongLoginCredentials = 8002
    
    public static let humanVerificationRequired = 9001
    public static let invalidEmail = 12083
    public static let invalidHumanVerificationCode = 12087
    
    public static let disabled = 10003
    
    public static let signupWithProtonMailAdress = 12220
    
    public static let noActiveSubscription = 22110
    
    public static let vpnIpNotFound = 86031
    
    public static let subuserWithoutSessions = 86300
}
