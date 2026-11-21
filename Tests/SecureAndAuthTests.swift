// SecureAndAuthTests.swift
// Vault encryption and the PIN auth model (mirrors engine/auth_model.py).

import XCTest
import CryptoKit
@testable import PrivateJudgesWorkspace

final class SecureStoreTests: XCTestCase {

    func testVaultSealOpenRoundTrip() throws {
        let vault = Vault.ephemeralVault()
        let payload = Data("crosshair record payload 1234,567".utf8)
        let sealed = try vault.seal(payload)
        XCTAssertNotEqual(sealed, payload)
        XCTAssertEqual(try vault.open(sealed), payload)
    }

    func testTamperedCiphertextRejected() throws {
        let vault = Vault.ephemeralVault()
        var sealed = try vault.seal(Data("integrity".utf8))
        sealed[sealed.count - 1] ^= 0xFF
        XCTAssertThrowsError(try vault.open(sealed))
    }

    func testDifferentKeysCannotReadEachOther() throws {
        let a = Vault.ephemeralVault()
        let b = Vault.ephemeralVault()
        let sealed = try a.seal(Data("secret".utf8))
        XCTAssertThrowsError(try b.open(sealed))
    }

    func testSealedRecordFileIsNotPlainJSON() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pjw-tests-vault-\(UUID().uuidString)")
        let store = RecordsStore(root: root, vault: Vault.ephemeralVault())
        let record = CrosshairRecordFile(competitionId: "PJV-2026-R1", judgeId: "JUDGE-01",
                                         imageId: String(repeating: "a", count: 64),
                                         imageWidthPx: 1920, imageHeightPx: 1080,
                                         xPx: 10, yPx: 20, note: "",
                                         createdAt: "2026-11-21T10:00:00Z",
                                         engineVersion: CoordinateEngine.engineVersion)
        let recordId = try store.save(record: record)
        let fileData = try Data(contentsOf: root.appendingPathComponent(recordId + ".rec"))
        XCTAssertNil(try? JSONSerialization.jsonObject(with: fileData),
                     "on-device record files must be encrypted, not plain JSON")
    }
}

final class AuthModelTests: XCTestCase {

    func testSetupAndUnlock() throws {
        let cred = try AuthModel.createCredential(pin: "1234")
        XCTAssertTrue(AuthModel.verify(credential: cred, pin: "1234"))
        XCTAssertFalse(AuthModel.verify(credential: cred, pin: "4321"))
        XCTAssertFalse(AuthModel.verify(credential: cred, pin: "12345"))
    }

    func testVerifierNeverContainsPINAndSaltsUnique() throws {
        let c1 = try AuthModel.createCredential(pin: "998877")
        let c2 = try AuthModel.createCredential(pin: "998877")
        XCTAssertNotEqual(c1.saltHex, c2.saltHex, "salts must be unique per setup")
        XCTAssertNotEqual(c1.verifierHex, c2.verifierHex,
                          "same PIN with different salts must give different verifiers")
        // hex verifier of 32 bytes; PIN digits do not appear as plaintext
        XCTAssertEqual(c1.verifierHex.count, 64)
        XCTAssertFalse(c1.verifierHex.contains("998877"))
    }

    func testPINPolicyEnforced() {
        XCTAssertThrowsError(try AuthModel.createCredential(pin: "123"))
        XCTAssertThrowsError(try AuthModel.createCredential(pin: "1234567890123"))
        XCTAssertThrowsError(try AuthModel.createCredential(pin: "12ab"))
        XCTAssertNoThrow(try AuthModel.createCredential(pin: "0000"))
        XCTAssertFalse(AuthModel.isPolicyValid(pin: "12 4"))
        XCTAssertTrue(AuthModel.isPolicyValid(pin: "123456789012"))
        XCTAssertFalse(AuthModel.isPolicyValid(pin: "1234567890123"))
    }

    func testLockoutSchedule() {
        XCTAssertEqual(AuthModel.lockoutSeconds(consecutiveFailures: 4), 0)
        XCTAssertEqual(AuthModel.lockoutSeconds(consecutiveFailures: 5), 30)
        XCTAssertEqual(AuthModel.lockoutSeconds(consecutiveFailures: 6), 60)
        XCTAssertEqual(AuthModel.lockoutSeconds(consecutiveFailures: 7), 120)
        XCTAssertEqual(AuthModel.lockoutSeconds(consecutiveFailures: 20), 3600)
    }

    func testPBKDF2KnownShape() throws {
        let out = AuthModel.pbkdf2(password: Data("pin".utf8),
                                   salt: Data(repeating: 1, count: 16), rounds: 1000)
        XCTAssertEqual(out.count, 32)
        let again = AuthModel.pbkdf2(password: Data("pin".utf8),
                                     salt: Data(repeating: 1, count: 16), rounds: 1000)
        XCTAssertEqual(out, again, "PBKDF2 must be deterministic for fixed input")
    }
}
