// AuthGate.swift
// Private Judges Workspace - private first-launch access.
//
// Mirrors engine/auth_model.py:
//   - first launch: the owner sets a PIN; only a salted PBKDF2 verifier is
//     stored (Keychain), never the PIN itself
//   - unlock: constant-time verifier comparison
//   - exponential lockout after consecutive failures
//   - optional biometric unlock through LocalAuthentication

import SwiftUI
import CommonCrypto
import LocalAuthentication
import Security

enum AuthModel {
    static let algo = "PBKDF2-HMAC-SHA256"
    static let iterations: UInt32 = 100_000
    static let saltBytes = 16
    static let pinMin = 4
    static let pinMax = 12
    static let failuresBeforeLock = 5
    static let baseLockSeconds = 30.0

    enum AuthError: Error { case badPIN, keychainFailure }

    struct Credential: Codable, Equatable {
        var algo: String
        var iterations: UInt32
        var saltHex: String
        var verifierHex: String
    }

    static func pbkdf2(password: Data, salt: Data, rounds: UInt32) -> Data {
        var derived = [UInt8](repeating: 0, count: 32)
        let status = derived.withUnsafeMutableBytes { dp in
            salt.withUnsafeBytes { sp in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                     password.map { Int8(bitPattern: $0) },
                                     password.count,
                                     sp.bindMemory(to: UInt8.self).baseAddress!, salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                                     rounds,
                                     dp.baseAddress!, 32)
            }
        }
        precondition(status == kCCSuccess, "PBKDF2 failed")
        return Data(derived)
    }

    static func createCredential(pin: String) throws -> Credential {
        guard isPolicyValid(pin: pin) else { throw AuthError.badPIN }
        var salt = [UInt8](repeating: 0, count: saltBytes)
        let status = SecRandomCopyBytes(kSecRandomDefault, saltBytes, &salt)
        guard status == errSecSuccess else { throw AuthError.keychainFailure }
        let verifier = pbkdf2(password: Data(pin.utf8), salt: Data(salt), rounds: iterations)
        return Credential(algo: algo, iterations: iterations,
                          saltHex: Data(salt).map { String(format: "%02x", $0) }.joined(),
                          verifierHex: verifier.map { String(format: "%02x", $0) }.joined())
    }

    static func isPolicyValid(pin: String) -> Bool {
        pin.count >= pinMin && pin.count <= pinMax && pin.allSatisfy(\.isNumber)
    }

    static func verify(credential: Credential, pin: String) -> Bool {
        guard credential.algo == algo,
              isPolicyValid(pin: pin),
              let saltData = credential.saltHex.hexDecoded,
              let expData = credential.verifierHex.hexDecoded else { return false }
        let candidate = pbkdf2(password: Data(pin.utf8), salt: saltData,
                               rounds: credential.iterations)
        // constant-time comparison
        guard candidate.count == expData.count else { return false }
        var diff: UInt8 = 0
        for (a, b) in zip(candidate, expData) { diff |= a ^ b }
        return diff == 0
    }

    /// Exponential lockout seconds after consecutive failures
    /// (mirrors engine/auth_model.py: 30 s -> 60 s -> ..., capped at 1 h).
    static func lockoutSeconds(consecutiveFailures: Int) -> Double {
        guard consecutiveFailures >= failuresBeforeLock else { return 0 }
        let exponent = consecutiveFailures - failuresBeforeLock
        return min(baseLockSeconds * pow(2, Double(exponent)), 3600)
    }
}

extension String {
    /// Decodes a lowercase hex string into Data.
    var hexDecoded: Data? {
        guard count % 2 == 0, allSatisfy({ $0.isHexDigit }) else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(count / 2)
        var index = startIndex
        while index < endIndex {
            guard let hi = UInt8(String(self[index]), radix: 16),
                  let lo = UInt8(String(self[self.index(after: index)]), radix: 16) else {
                return nil
            }
            bytes.append(hi << 4 | lo)
            index = self.index(after: index)
        }
        return Data(bytes)
    }
}

// MARK: - Session state and gating view

@MainActor
final class AuthSession: ObservableObject {
    enum Phase { case setup, locked, unlocked }
    @Published var phase: Phase = .locked
    @Published var errorText: String?
    @Published var consecutiveFailures = 0
    @Published var lockUntil: Date?

    private let account = "owner"
    private let service = "PrivateJudgesWorkspace.auth"

    var biometricsAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    init() {
        phase = Keychain.load(account: account, service: service) != nil ? .locked : .setup
    }

    var isLockedOut: Bool {
        if let until = lockUntil, until > Date() { return true }
        return false
    }

    func setup(pin: String, confirm: String) {
        guard pin == confirm else { errorText = "PIN entries do not match."; return }
        do {
            let cred = try AuthModel.createCredential(pin: pin)
            guard let encoded = try? JSONEncoder().encode(cred),
                  Keychain.save(encoded, account: account, service: service) else {
                errorText = "Keychain unavailable."; return
            }
            errorText = nil
            phase = .unlocked
        } catch {
            errorText = "PIN must be \(AuthModel.pinMin)-\(AuthModel.pinMax) digits."
        }
    }

    func unlock(pin: String) {
        if isLockedOut { return }
        guard let data = Keychain.load(account: account, service: service),
              let cred = try? JSONDecoder().decode(AuthModel.Credential.self, from: data) else {
            phase = .setup
            return
        }
        if AuthModel.verify(credential: cred, pin: pin) {
            consecutiveFailures = 0
            lockUntil = nil
            errorText = nil
            phase = .unlocked
        } else {
            consecutiveFailures += 1
            let seconds = AuthModel.lockoutSeconds(consecutiveFailures: consecutiveFailures)
            if seconds > 0 {
                lockUntil = Date().addingTimeInterval(seconds)
            }
            errorText = "Incorrect PIN (\(consecutiveFailures) failed attempts)."
        }
    }

    func unlockWithBiometrics() {
        guard biometricsAvailable, !isLockedOut else { return }
        let context = LAContext()
        context.evaluatePolicy(.deviceOwnerAuthentication,
                               localizedReason: "Unlock the private judges workspace") { [weak self] success, _ in
            Task { @MainActor in
                if success {
                    self?.consecutiveFailures = 0
                    self?.lockUntil = nil
                    self?.errorText = nil
                    self?.phase = .unlocked
                }
            }
        }
    }
}

struct AuthGate<Content: View>: View {
    @StateObject private var session = AuthSession()
    @ViewBuilder let content: () -> Content

    var body: some View {
        switch session.phase {
        case .setup: SetupView(session: session)
        case .locked: LockView(session: session)
        case .unlocked: content()
        }
    }
}

struct SetupView: View {
    @ObservedObject var session: AuthSession
    @State private var pin = ""
    @State private var confirm = ""

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield").font(.system(size: 56))
            Text("Private Judges Workspace").font(.title.bold())
            Text("First launch: set the private access PIN.\nOnly a salted PBKDF2 verifier is stored on this device.")
                .multilineTextAlignment(.center)
                .font(.footnote)
                .foregroundStyle(.secondary)
            SecureField("PIN", text: $pin)
                .textFieldStyle(.roundedBorder).keyboardType(.numberPad)
                .frame(maxWidth: 240)
            SecureField("Confirm PIN", text: $confirm)
                .textFieldStyle(.roundedBorder).keyboardType(.numberPad)
                .frame(maxWidth: 240)
            if let err = session.errorText {
                Text(err).font(.callout).foregroundStyle(.red)
            }
            Button("Set PIN and continue") { session.setup(pin: pin, confirm: confirm) }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

struct LockView: View {
    @ObservedObject var session: AuthSession
    @State private var pin = ""

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill").font(.system(size: 56))
            Text("Private access locked").font(.title.bold())
            SecureField("PIN", text: $pin)
                .textFieldStyle(.roundedBorder).keyboardType(.numberPad)
                .frame(maxWidth: 240)
            if let err = session.errorText {
                Text(err).font(.callout).foregroundStyle(.red)
            }
            if session.isLockedOut, let until = session.lockUntil {
                Text("Locked until \(until.formatted(date: .omitted, time: .standard))")
                    .font(.footnote).foregroundStyle(.orange)
            }
            Button("Unlock") { session.unlock(pin: pin) }
                .buttonStyle(.borderedProminent)
                .disabled(session.isLockedOut)
            if session.biometricsAvailable {
                Button {
                    session.unlockWithBiometrics()
                } label: {
                    Label("Use device biometrics", systemImage: "faceid")
                }
                .disabled(session.isLockedOut)
            }
        }
        .padding()
    }
}
