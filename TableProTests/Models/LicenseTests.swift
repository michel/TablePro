//
//  LicenseTests.swift
//  TablePro
//
//  Tests for License models and related types
//

import Foundation
@testable import TablePro
import Testing

@Suite("License")
struct LicenseTests {
    // MARK: - LicenseStatus.isValid Tests

    @Test("LicenseStatus.isValid returns true for active status")
    func licenseStatusActiveIsValid() {
        #expect(LicenseStatus.active.isValid == true)
    }

    @Test("LicenseStatus.isValid returns false for unlicensed status")
    func licenseStatusUnlicensedIsNotValid() {
        #expect(LicenseStatus.unlicensed.isValid == false)
    }

    @Test("LicenseStatus.isValid returns false for non-active statuses")
    func licenseStatusNonActiveIsNotValid() {
        #expect(LicenseStatus.expired.isValid == false)
        #expect(LicenseStatus.suspended.isValid == false)
        #expect(LicenseStatus.deactivated.isValid == false)
        #expect(LicenseStatus.validationFailed.isValid == false)
    }

    // MARK: - License.isExpired Tests

    @Test("isExpired returns false when expiresAt is nil")
    func isExpiredNilExpiresAt() {
        let license = License(
            key: "test-key",
            email: "test@test.com",
            status: .active,
            expiresAt: nil,
            lastValidatedAt: Date(),
            machineId: "machine1",
            signedPayload: SignedLicensePayload(
                data: LicensePayloadData(
                    licenseKey: "test-key",
                    email: "test@test.com",
                    status: "active",
                    expiresAt: nil,
                    issuedAt: "2024-01-01T00:00:00Z"
                ),
                signature: "sig"
            )
        )
        #expect(license.isExpired == false)
    }

    @Test("isExpired returns false when expiresAt is in the future")
    func isExpiredFutureDate() {
        let futureDate = Date().addingTimeInterval(86_400 * 30)
        let license = License(
            key: "test-key",
            email: "test@test.com",
            status: .active,
            expiresAt: futureDate,
            lastValidatedAt: Date(),
            machineId: "machine1",
            signedPayload: SignedLicensePayload(
                data: LicensePayloadData(
                    licenseKey: "test-key",
                    email: "test@test.com",
                    status: "active",
                    expiresAt: "2025-01-01T00:00:00Z",
                    issuedAt: "2024-01-01T00:00:00Z"
                ),
                signature: "sig"
            )
        )
        #expect(license.isExpired == false)
    }

    @Test("isExpired returns true when expiresAt is in the past")
    func isExpiredPastDate() {
        let pastDate = Date().addingTimeInterval(-86_400 * 30)
        let license = License(
            key: "test-key",
            email: "test@test.com",
            status: .expired,
            expiresAt: pastDate,
            lastValidatedAt: Date(),
            machineId: "machine1",
            signedPayload: SignedLicensePayload(
                data: LicensePayloadData(
                    licenseKey: "test-key",
                    email: "test@test.com",
                    status: "expired",
                    expiresAt: "2024-01-01T00:00:00Z",
                    issuedAt: "2023-01-01T00:00:00Z"
                ),
                signature: "sig"
            )
        )
        #expect(license.isExpired == true)
    }

    // MARK: - License.daysSinceLastValidation Tests

    @Test("daysSinceLastValidation returns 0 when lastValidatedAt is today")
    func daysSinceLastValidationToday() {
        let license = License(
            key: "test-key",
            email: "test@test.com",
            status: .active,
            expiresAt: nil,
            lastValidatedAt: Date(),
            machineId: "machine1",
            signedPayload: SignedLicensePayload(
                data: LicensePayloadData(
                    licenseKey: "test-key",
                    email: "test@test.com",
                    status: "active",
                    expiresAt: nil,
                    issuedAt: "2024-01-01T00:00:00Z"
                ),
                signature: "sig"
            )
        )
        #expect(license.daysSinceLastValidation == 0)
    }

    @Test("daysSinceLastValidation returns correct days when lastValidatedAt is 5 days ago")
    func daysSinceLastValidationFiveDaysAgo() {
        guard let fiveDaysAgo = Calendar.current.date(byAdding: .day, value: -5, to: Date()) else {
            Issue.record("Failed to create date 5 days ago")
            return
        }
        let license = License(
            key: "test-key",
            email: "test@test.com",
            status: .active,
            expiresAt: nil,
            lastValidatedAt: fiveDaysAgo,
            machineId: "machine1",
            signedPayload: SignedLicensePayload(
                data: LicensePayloadData(
                    licenseKey: "test-key",
                    email: "test@test.com",
                    status: "active",
                    expiresAt: nil,
                    issuedAt: "2024-01-01T00:00:00Z"
                ),
                signature: "sig"
            )
        )
        #expect(license.daysSinceLastValidation == 5)
    }

    // MARK: - License.from Status Mapping Tests

    @Test("License.from maps active status correctly")
    func licenseFromMapsActiveStatus() {
        let payloadData = LicensePayloadData(
            licenseKey: "test-key",
            email: "test@test.com",
            status: "active",
            expiresAt: nil,
            issuedAt: "2024-01-01T00:00:00Z"
        )
        let signedPayload = SignedLicensePayload(data: payloadData, signature: "sig")
        let license = License.from(
            payload: payloadData,
            signedPayload: signedPayload,
            machineId: "machine1"
        )
        #expect(license.status == .active)
    }

    @Test("License.from maps expired status correctly")
    func licenseFromMapsExpiredStatus() {
        let payloadData = LicensePayloadData(
            licenseKey: "test-key",
            email: "test@test.com",
            status: "expired",
            expiresAt: "2024-01-01T00:00:00Z",
            issuedAt: "2023-01-01T00:00:00Z"
        )
        let signedPayload = SignedLicensePayload(data: payloadData, signature: "sig")
        let license = License.from(
            payload: payloadData,
            signedPayload: signedPayload,
            machineId: "machine1"
        )
        #expect(license.status == .expired)
    }

    @Test("License.from maps suspended status correctly")
    func licenseFromMapsSuspendedStatus() {
        let payloadData = LicensePayloadData(
            licenseKey: "test-key",
            email: "test@test.com",
            status: "suspended",
            expiresAt: nil,
            issuedAt: "2024-01-01T00:00:00Z"
        )
        let signedPayload = SignedLicensePayload(data: payloadData, signature: "sig")
        let license = License.from(
            payload: payloadData,
            signedPayload: signedPayload,
            machineId: "machine1"
        )
        #expect(license.status == .suspended)
    }

    @Test("License.from maps unknown status to validationFailed")
    func licenseFromMapsUnknownStatusToValidationFailed() {
        let payloadData = LicensePayloadData(
            licenseKey: "test-key",
            email: "test@test.com",
            status: "unknown",
            expiresAt: nil,
            issuedAt: "2024-01-01T00:00:00Z"
        )
        let signedPayload = SignedLicensePayload(data: payloadData, signature: "sig")
        let license = License.from(
            payload: payloadData,
            signedPayload: signedPayload,
            machineId: "machine1"
        )
        #expect(license.status == .validationFailed)
    }
}
