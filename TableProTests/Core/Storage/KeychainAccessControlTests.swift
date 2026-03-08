//
//  KeychainAccessControlTests.swift
//  TableProTests
//

import Foundation
import Security
import Testing
@testable import TablePro

@Suite("Keychain Access Control")
struct KeychainAccessControlTests {
    @Test("kSecAttrAccessibleWhenUnlockedThisDeviceOnly constant is available")
    func correctConstantAvailable() {
        let expected = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        #expect(expected != nil)

        let lessSecure = kSecAttrAccessibleAfterFirstUnlock
        #expect(expected as String != lessSecure as String)
    }
}
