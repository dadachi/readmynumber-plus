//
//  MDocReader.swift
//  readmynumber
//
//  M-Doc Reader Implementation for iOS
//

import Foundation
import CoreBluetooth
import CoreNFC
import AVFoundation
import CryptoKit
import Combine

// MARK: - M-Doc Reader

/// Main M-Doc reader class for handling ISO/IEC 18013-5 documents
class MDocReader: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var isReading: Bool = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var readProgress: Double = 0.0
    @Published var lastError: MDocError?
    @Published var receivedDocument: Document?
    
    // MARK: - Connection Status
    enum ConnectionStatus: Equatable {
        case disconnected
        case scanning
        case connecting
        case connected
        case transferring
        case completed
        case failed(Error)
        
        static func == (lhs: ConnectionStatus, rhs: ConnectionStatus) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected),
                 (.scanning, .scanning),
                 (.connecting, .connecting),
                 (.connected, .connected),
                 (.transferring, .transferring),
                 (.completed, .completed):
                return true
            case (.failed, .failed):
                return true
            default:
                return false
            }
        }
    }
    
    // MARK: - Private Properties
    private var centralManager: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    private var connectedPeripheral: CBPeripheral?
    private var nfcSession: NFCTagReaderSession?
    private var currentDeviceEngagement: DeviceEngagement?
    private var sessionEncryption: SessionEncryption?
    private var cancellables = Set<AnyCancellable>()
    
    // BLE Service and Characteristic UUIDs for M-Doc
    private let mdocServiceUUID = CBUUID(string: "00000001-A123-48CE-8965-FC7E22C3D2EE")
    private let mdocStateCharacteristicUUID = CBUUID(string: "00000002-A123-48CE-8965-FC7E22C3D2EE")
    private let mdocClientCharacteristicUUID = CBUUID(string: "00000003-A123-48CE-8965-FC7E22C3D2EE")
    private let mdocServerCharacteristicUUID = CBUUID(string: "00000004-A123-48CE-8965-FC7E22C3D2EE")
    
    // MARK: - Initialization
    override init() {
        super.init()
        setupBluetooth()
    }
    
    // MARK: - Public Methods
    
    /// Start reading M-Doc from QR code
    func startQRCodeReading(completion: @escaping (Result<DeviceEngagement, Error>) -> Void) {
        isReading = true
        connectionStatus = .scanning
        
        // In a real implementation, this would trigger the camera for QR code scanning
        // For now, we'll simulate QR code reading
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            // Simulated QR code data
            let simulatedQRData = self?.createSimulatedDeviceEngagement()
            
            if let engagement = simulatedQRData {
                self?.currentDeviceEngagement = engagement
                completion(.success(engagement))
            } else {
                completion(.failure(MDocError.qrCodeInvalid))
            }
        }
    }
    
    /// Start BLE connection using device engagement
    func connectBLE(with deviceEngagement: DeviceEngagement) {
        guard let centralManager = centralManager else {
            connectionStatus = .failed(MDocError.bluetoothUnavailable)
            return
        }
        
        connectionStatus = .connecting
        currentDeviceEngagement = deviceEngagement
        
        // Extract BLE parameters from device engagement
        if let bleMethod = deviceEngagement.deviceRetrievalMethods.first(where: { $0.type == 2 }),
           case .ble(let bleOptions) = bleMethod.retrievalOptions {
            
            // Start scanning for the M-Doc peripheral
            if let uuid = bleOptions.peripheralServerModeUUID {
                centralManager.scanForPeripherals(
                    withServices: [CBUUID(nsuuid: uuid)],
                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
                )
            } else {
                centralManager.scanForPeripherals(
                    withServices: [mdocServiceUUID],
                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
                )
            }
        }
    }
    
    /// Start NFC session for M-Doc reading
    func startNFCReading() {
        guard NFCTagReaderSession.readingAvailable else {
            connectionStatus = .failed(MDocError.nfcUnavailable)
            return
        }
        
        isReading = true
        connectionStatus = .scanning
        
        nfcSession = NFCTagReaderSession(pollingOption: .iso14443, delegate: self)
        nfcSession?.alertMessage = "M-Docカードを近づけてください"
        nfcSession?.begin()
    }
    
    /// Request specific data elements from M-Doc
    func requestDataElements(docType: String, elements: [String: [String]]) -> DeviceRequest {
        var nameSpaces: [String: [String: Bool]] = [:]
        
        for (namespace, elementNames) in elements {
            var elementRequests: [String: Bool] = [:]
            for elementName in elementNames {
                elementRequests[elementName] = false // false means not intent to retain
            }
            nameSpaces[namespace] = elementRequests
        }
        
        let itemsRequest = ItemsRequest(
            docType: docType,
            nameSpaces: nameSpaces,
            requestInfo: nil
        )
        
        let docRequest = DocRequest(
            itemsRequest: itemsRequest,
            readerAuth: nil
        )
        
        return DeviceRequest(
            version: "1.0",
            docRequests: [docRequest]
        )
    }
    
    /// Send device request and receive response
    func sendRequest(_ request: DeviceRequest, completion: @escaping (Result<DeviceResponse, Error>) -> Void) {
        guard connectionStatus == .connected else {
            completion(.failure(MDocError.sessionEstablishmentFailed))
            return
        }
        
        connectionStatus = .transferring
        
        // Encode request to CBOR
        do {
            let requestData = try encodeToCBOR(request)
            
            // Send via BLE or NFC depending on connection
            if connectedPeripheral != nil {
                // Send via BLE
                sendDataViaBLE(requestData) { [weak self] result in
                    switch result {
                    case .success(let responseData):
                        do {
                            let response = try self?.decodeFromCBOR(responseData, type: DeviceResponse.self)
                            if let response = response {
                                self?.connectionStatus = .completed
                                self?.receivedDocument = response.documents?.first
                                completion(.success(response))
                            }
                        } catch {
                            completion(.failure(error))
                        }
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            } else {
                // Send via NFC if available
                completion(.failure(MDocError.sessionEstablishmentFailed))
            }
        } catch {
            completion(.failure(error))
        }
    }
    
    // MARK: - Private Methods
    
    private func setupBluetooth() {
        centralManager = CBCentralManager(delegate: self, queue: nil)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }
    
    private func createSimulatedDeviceEngagement() -> DeviceEngagement {
        // Create simulated device engagement for testing
        let securityInfo = SecurityInfo(
            cipherSuiteIdentifier: 1, // P-256 with SHA-256
            eSenderKeyBytes: Data(repeating: 0x01, count: 65) // Simulated public key
        )
        
        let bleOptions = BLEOptions(
            supportPeripheralServerMode: true,
            supportCentralClientMode: false,
            peripheralServerModeUUID: UUID(),
            centralClientModeUUID: nil,
            peripheralServerDeviceAddress: nil,
            centralClientDeviceAddress: nil
        )
        
        let bleMethod = DeviceRetrievalMethod(
            type: 2, // BLE
            version: 1,
            retrievalOptions: .ble(bleOptions)
        )
        
        return DeviceEngagement(
            version: "1.0",
            security: securityInfo,
            deviceRetrievalMethods: [bleMethod],
            serverRetrievalMethods: nil,
            protocolInfo: nil
        )
    }
    
    private func sendDataViaBLE(_ data: Data, completion: @escaping (Result<Data, Error>) -> Void) {
        // Implementation for BLE data transfer
        // This would write to the characteristic and wait for response
        
        // For simulation, return mock response
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let mockResponse = self.createMockDeviceResponse()
            do {
                let responseData = try self.encodeToCBOR(mockResponse)
                completion(.success(responseData))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    private func createMockDeviceResponse() -> DeviceResponse {
        // Create mock M-Doc response for testing
        let nameSpacesDict = [
            MobileDrivingLicense.isoMdlNamespace: [
                IssuerSignedItem(
                    digestID: 1,
                    random: Data(repeating: 0x00, count: 32),
                    elementIdentifier: "family_name",
                    elementValue: .string("山田")
                ),
                IssuerSignedItem(
                    digestID: 2,
                    random: Data(repeating: 0x01, count: 32),
                    elementIdentifier: "given_name",
                    elementValue: .string("太郎")
                ),
                IssuerSignedItem(
                    digestID: 3,
                    random: Data(repeating: 0x02, count: 32),
                    elementIdentifier: "birth_date",
                    elementValue: .string("1990-01-01")
                ),
                IssuerSignedItem(
                    digestID: 4,
                    random: Data(repeating: 0x03, count: 32),
                    elementIdentifier: "document_number",
                    elementValue: .string("123456789")
                )
            ]
        ]
        
        let nameSpaces = IssuerNameSpaces(nameSpaces: nameSpacesDict)
        
        let issuerAuth = IssuerAuth(
            algorithm: "ES256",
            signature: Data(repeating: 0xFF, count: 64),
            certificateChain: [Data(repeating: 0xAA, count: 256)]
        )
        
        let issuerSigned = IssuerSigned(
            nameSpaces: nameSpaces,
            issuerAuth: issuerAuth
        )
        
        let document = Document(
            docType: MobileDrivingLicense.docType,
            issuerSigned: issuerSigned,
            deviceSigned: nil,
            errors: nil
        )
        
        return DeviceResponse(
            version: "1.0",
            documents: [document],
            documentErrors: nil,
            status: 0
        )
    }
    
    // MARK: - CBOR Encoding/Decoding
    
    private func encodeToCBOR<T: Encodable>(_ value: T) throws -> Data {
        // In a real implementation, this would use a CBOR library like SwiftCBOR
        // For now, we'll use JSON as a placeholder
        let encoder = JSONEncoder()
        return try encoder.encode(value)
    }
    
    private func decodeFromCBOR<T: Decodable>(_ data: Data, type: T.Type) throws -> T {
        // In a real implementation, this would use a CBOR library
        // For now, we'll use JSON as a placeholder
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data)
    }
    
    // MARK: - Session Establishment
    
    private func establishSecureSession(with deviceEngagement: DeviceEngagement) throws {
        // Generate ephemeral key pair
        let privateKey = P256.KeyAgreement.PrivateKey()
        let _ = privateKey.publicKey
        
        // Perform ECDH with device's public key
        guard deviceEngagement.security.eSenderKeyBytes.count == 65 else {
            throw MDocError.sessionEstablishmentFailed
        }
        
        // Create session encryption context
        // This is a simplified version - real implementation would follow ISO 18013-5
        sessionEncryption = SessionEncryption(
            sessionEstablishmentObject: Data(),
            deviceEngagementObject: Data(),
            handOverObject: Data()
        )
    }
}

// MARK: - CBCentralManagerDelegate

extension MDocReader: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            // BLE is ready
            break
        case .poweredOff, .unauthorized, .unsupported:
            connectionStatus = .failed(MDocError.bluetoothUnavailable)
        default:
            break
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Found M-Doc peripheral
        connectedPeripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        central.connect(peripheral, options: nil)
        connectionStatus = .connecting
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionStatus = .connected
        peripheral.discoverServices([mdocServiceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionStatus = .failed(error ?? MDocError.bluetoothUnavailable)
    }
}

// MARK: - CBPeripheralDelegate

extension MDocReader: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil,
              let services = peripheral.services else {
            connectionStatus = .failed(error ?? MDocError.bluetoothUnavailable)
            return
        }
        
        for service in services {
            peripheral.discoverCharacteristics(
                [mdocStateCharacteristicUUID, mdocClientCharacteristicUUID, mdocServerCharacteristicUUID],
                for: service
            )
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil,
              let characteristics = service.characteristics else {
            connectionStatus = .failed(error ?? MDocError.bluetoothUnavailable)
            return
        }
        
        // Subscribe to notifications for server characteristic
        for characteristic in characteristics {
            if characteristic.uuid == mdocServerCharacteristicUUID {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil,
              let data = characteristic.value else {
            return
        }
        
        // Process received M-Doc data
        processReceivedData(data)
    }
    
    private func processReceivedData(_ data: Data) {
        // Process the received CBOR data
        do {
            let response = try decodeFromCBOR(data, type: DeviceResponse.self)
            receivedDocument = response.documents?.first
            connectionStatus = .completed
        } catch {
            connectionStatus = .failed(error)
        }
    }
}

// MARK: - CBPeripheralManagerDelegate

extension MDocReader: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        // Handle peripheral manager state updates if acting as M-Doc holder
    }
}

// MARK: - NFCTagReaderSessionDelegate

extension MDocReader: NFCTagReaderSessionDelegate {
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        // NFC session is active
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        isReading = false
        connectionStatus = .failed(error)
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first,
              case .iso7816(let iso7816Tag) = tag else {
            session.invalidate(errorMessage: "M-Docカードが検出できませんでした")
            return
        }
        
        Task {
            do {
                try await session.connect(to: tag)
                
                // Select M-Doc application
                let selectCommand = NFCISO7816APDU(
                    instructionClass: 0x00,
                    instructionCode: 0xA4,
                    p1Parameter: 0x04,
                    p2Parameter: 0x0C,
                    data: Data([0xA0, 0x00, 0x00, 0x02, 0x48, 0x04, 0x00]), // M-Doc AID
                    expectedResponseLength: -1
                )
                
                let (_, sw1, sw2) = try await iso7816Tag.sendCommand(apdu: selectCommand)
                
                if sw1 == 0x90 && sw2 == 0x00 {
                    // Successfully selected M-Doc application
                    await MainActor.run {
                        session.alertMessage = "M-Docを読み取り中..."
                    }
                    
                    // Continue with M-Doc reading protocol
                    // This would involve device engagement, session establishment, and data transfer
                    
                    await MainActor.run {
                        session.invalidate()
                        self.connectionStatus = .completed
                    }
                } else {
                    await MainActor.run {
                        session.invalidate(errorMessage: "M-Docアプリケーションの選択に失敗しました")
                    }
                }
            } catch {
                await MainActor.run {
                    session.invalidate(errorMessage: "読み取りエラー: \(error.localizedDescription)")
                    self.connectionStatus = .failed(error)
                }
            }
        }
    }
}