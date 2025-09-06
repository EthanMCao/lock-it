import Foundation
import LocalAuthentication

enum BiometryError: Error {
    case unavailable
    case failed
    case canceled
}

final class BiometryAuth {
    static let shared = BiometryAuth()
    private init() {}

    func authenticate(reason: String) async throws -> LAContext {
        let context = LAContext()
        var error: NSError?
        
        print("Checking biometry availability...")
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            print("Biometry unavailable: \(error?.localizedDescription ?? "unknown")")
            // Fallback to device passcode if biometry unavailable
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                print("Device authentication unavailable: \(error?.localizedDescription ?? "unknown")")
                throw BiometryError.unavailable
            }
            print("Using device passcode authentication")
            return try await withCheckedThrowingContinuation { continuation in
                context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, evalError in
                    if success {
                        continuation.resume(returning: context)
                    } else {
                        print("Auth failed: \(evalError?.localizedDescription ?? "unknown")")
                        continuation.resume(throwing: BiometryError.failed)
                    }
                }
            }
        }
        
        print("Using biometric authentication")
        return try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, evalError in
                if success {
                    continuation.resume(returning: context)
                } else {
                    print("Biometry failed: \(evalError?.localizedDescription ?? "unknown")")
                    if let err = evalError as? LAError, err.code == .userCancel || err.code == .appCancel || err.code == .systemCancel {
                        continuation.resume(throwing: BiometryError.canceled)
                    } else {
                        continuation.resume(throwing: BiometryError.failed)
                    }
                }
            }
        }
    }
}

