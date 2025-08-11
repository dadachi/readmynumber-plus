# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an iOS SwiftUI application for reading Japanese My Number (マイナンバー) cards using NFC technology. The app reads digital certificates and personal information from My Number cards, displaying them in a user-friendly interface with dark mode support.

## Development Commands

This is an Xcode project with no package.json - use Xcode or command line tools:
- **Build**: `xcodebuild -scheme readmynumber -destination 'platform=iOS Simulator,name=iPhone 15' build`
- **Test**: `xcodebuild -scheme readmynumber -destination 'platform=iOS Simulator,name=iPhone 15' test`
- **Run**: Open `readmynumber.xcodeproj` in Xcode and run the project

## Architecture Overview

### Core Components

**Main App Structure:**
- `readmynumberApp.swift` - SwiftUI app entry point
- `ContentView.swift` - Main interface with certificate reading buttons and NFC management
- `CertificateDetailView.swift` - Display screen for certificate data and personal information

**NFC Certificate Readers:**
- `UserAuthenticationCertificateReader.swift` - Handles authentication certificates (4-digit PIN)
- `SignatureCertificateReader.swift` - Handles signature certificates (6-16 digit PIN)

### Key Architectural Patterns

**Data Management:**
- `CertificateDataManager` - Singleton for managing certificate data and navigation state
- Uses `@Published` properties for SwiftUI reactive updates
- Persists data in UserDefaults (cleared on app navigation)

**NFC Communication:**
- Two separate NFC managers: `NFCManager` (main) and `NFCCardInfoManager` (detail view)
- Implements `NFCTagReaderSessionDelegate` for ISO7816 card communication
- Handles APDU commands for Japanese JPKI (Public Key Infrastructure) standard
- Simulator-friendly with mock data for testing

**Certificate Processing:**
- Reads certificates in ASN.1/DER format
- Converts to Base64 for display and PEM for export
- Supports both authentication (利用者証明用) and signature (署名用) certificates

### NFC Card Communication Flow

1. **AP Selection**: Select JPKI application (`0xD3, 0x92, 0xF0, 0x00, 0x26, 0x01, 0x00, 0x00, 0x00, 0x01`)
2. **PIN Verification**: Different file identifiers for auth (`0x00, 0x18`) vs signature (`0x00, 0x1B`)
3. **Certificate Reading**: Select certificate files and read in 256-byte blocks
4. **Personal Info**: Additional reading of My Number and basic info (name, address, birthdate, gender)

## UI Architecture

- **SwiftUI**: Declarative UI with reactive data binding
- **Navigation**: Uses `NavigationStack` with programmatic navigation
- **Responsive Design**: GeometryReader for adaptive layouts across device sizes
- **Dark Mode**: Full support with conditional styling
- **Accessibility**: Context menus and tap gestures for data copying

## Security Considerations

- PIN input uses secure text fields
- Certificate data temporarily stored in memory and UserDefaults
- Data cleared on navigation back to main screen
- No network communication (fully offline app)

## Testing Notes

- App includes simulator fallback for NFC operations
- Real testing requires physical iOS device with NFC capability
- Japanese My Number card required for full functionality testing