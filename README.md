# LockIT

A macOS app that securely locks and unlocks folders using Touch ID.

## Features

- **Touch ID Authentication** - Secure access with biometric verification
- **AES-256 Encryption** - Military-grade folder encryption
- **Choose or Create Folders** - Select existing folders or create new ones (up to 3)
- **Auto-Lock** - Automatically locks folders when app quits or system sleeps
- **Menu Bar Access** - Quick lock/unlock from the menu bar

## How It Works

1. **Lock**: Compresses folder → Encrypts with AES-256 → Stores key in Keychain → Deletes original
2. **Unlock**: Touch ID verification → Retrieves key → Decrypts → Restores folder

## Requirements

- macOS 13.0+
- Touch ID or device passcode
- Xcode 15+ (for building)

## Installation

1. Clone the repository
2. Open `LockIT.xcodeproj` in Xcode
3. Build and run

## Tech Stack

- **Swift** & **SwiftUI**
- **CryptoKit** (AES encryption)
- **LocalAuthentication** (Touch ID)
- **Keychain Services** (secure key storage)
- **ZIPFoundation** (compression)

---

⚠️ **Important**: This app securely deletes original folders when locked. Always backup important data.
