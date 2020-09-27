/////
////  FastRTPSBridge.swift
///   Copyright © 2019 Dmitriy Borovikov. All rights reserved.
//

import Foundation
import CDRCodable

#if SWIFT_PACKAGE
@_exported import FastRTPSWrapper
#endif

public protocol RTPSListenerDelegate {
    func RTPSNotification(reason: RTPSNotification, topic: String)
}

public protocol RTPSParticipantListenerDelegate {
    func participantNotification(reason: RTPSParticipantNotification, participant: String, unicastLocators: String, properties: [String:String])
    func readerWriterNotificaton(reason: RTPSReaderWriterNotification, topic: String, type: String, remoteLocators: String)
}

open class FastRTPSBridge {
    private var wrapper: FastRTPSWrapper
    fileprivate var listenerDelegate: RTPSListenerDelegate?
    fileprivate var participantListenerDelegate: RTPSParticipantListenerDelegate?
    
    public init() {
        wrapper = FastRTPSWrapper()
    }
    
    private func setupBridgeContainer()
    {
        let container = BridgeContainer(
            decoderCallback: {
                (payloadDecoder, sequence, payloadSize, payload) in
                let payloadDecoder = Unmanaged<PayloadDecoderProxy>.fromOpaque(payloadDecoder).takeUnretainedValue()
                payloadDecoder.decode(sequence: sequence,
                                      payloadSize: Int(payloadSize),
                                      payload: payload)
            }, releaseCallback: {
                (payloadDecoder) in
                Unmanaged<PayloadDecoderProxy>.fromOpaque(payloadDecoder).release()
            }, readerWriterListenerCallback: {
                (listenerObject, reason, topicName) in
                let mySelf = Unmanaged<FastRTPSBridge>.fromOpaque(listenerObject).takeUnretainedValue()
                guard let delegate = mySelf.listenerDelegate else { return }
                let topic = String(cString: topicName)
                delegate.RTPSNotification(reason: reason, topic: topic)
            }, discoveryParticipantCallback: {
                (listenerObject, reason, participantName, unicastLocators, properties) in
                let mySelf = Unmanaged<FastRTPSBridge>.fromOpaque(listenerObject).takeUnretainedValue()
                guard let delegate = mySelf.participantListenerDelegate else { return }
                var locators = ""
                var propertiesDict: [String:String] = [:]
                if let unicastLocators = unicastLocators {
                    locators = String(cString: unicastLocators)
                }
                if let properties = properties {
                    var i = 0
                    while properties[i] != nil {
                        let key = String(cString: properties[i]!)
                        let value = String(cString: properties[i+1]!)
                        propertiesDict[key] = value
                        i += 2
                    }
                }
                delegate.participantNotification(reason: reason,
                                                 participant: String(cString: participantName),
                                                 unicastLocators: locators,
                                                 properties: propertiesDict)
            }, discoveryReaderWriterCallback: {
                (listenerObject, reason, topicName, typeName, remoteLocators) in
                let mySelf = Unmanaged<FastRTPSBridge>.fromOpaque(listenerObject).takeUnretainedValue()
                guard let delegate = mySelf.participantListenerDelegate else { return }
                
                let topic = String(cString: topicName)
                let type = String(cString: typeName)
                var locators = ""
                if let remoteLocators = remoteLocators {
                    locators = String(cString: remoteLocators)
                }
                delegate.readerWriterNotificaton(reason: reason, topic: topic, type: type, remoteLocators: locators)
            }, listnerObject: Unmanaged.passUnretained(self).toOpaque())
        
        wrapper.setupBridgeContainer(container: container)
    }
    
    // MARK: Public interface

    #if FASTRTPS_FILTER
    /// Create RTPS participant
    /// - Parameters:
    ///   - name: participant name
    ///   - domainID: Domain Id to be used by the participant
    ///   - localAddress: bind only to localAddress
    ///   - filerAddress: remote locators filter, eg "10.1.1.0/24"
    public func createParticipant(name: String, domainID: UInt32 = 0, localAddress: String? = nil, filterAddress: String? = nil) {
        setupBridgeContainer()
        wrapper.createParticipantFiltered(domain: domainID,
                                          name: name.cString(using: .utf8)!,
                                          localAddress: localAddress?.cString(using: .utf8),
                                          filterAddress: filterAddress?.cString(using: .utf8))
    }

    #else

    /// Create RTPS participant
    /// - Parameters:
    ///   - name: participant name
    ///   - domainID: Domain Id to be used by the participant
    ///   - localAddress: bind only to localAddress
    public func createParticipant(name: String, domainID: UInt32 = 0, localAddress: String? = nil) {
        setupBridgeContainer()
        wrapper.createParticipant(domain: domainID,
                                  name: name.cString(using: .utf8)!,
                                  localAddress: localAddress?.cString(using: .utf8))
    }
    #endif
    
    /// Set RTPS messages listener
    /// Intercepts readers and writers messages - matching and liveliness state changes
    /// - Parameter delegate: RTPSListenerDelegate
    public func setRTPSListener(delegate: RTPSListenerDelegate?) {
        listenerDelegate = delegate
    }
    
    /// Set RTPS participant listener
    /// Intercepts participant messages - discovery and remove participant;
    ///  discovery, remove and QoS change of readers and writers
    /// - Parameter delegate: RTPSParticipantListenerDelegate
    public func setRTPSParticipantListener(delegate: RTPSParticipantListenerDelegate?) {
        participantListenerDelegate = delegate
    }
    
    /// Set RTPS partition (default: "*")
    /// - Parameter name: partition name
    public func setPartition(name: String) {
        wrapper.setPartition(partition: name.cString(using: .utf8)!)
    }
    
    /// Register RTPS reader for topic with raw data callback
    /// - Parameters:
    ///   - topic: DDSReaderTopic topic description
    ///   - ddsType: DDSType topic DDS data type
    ///   - completion: (sequence: UInt64, data: Data) -> Void
    ///      where data is topic ..................
    public func registerReaderRaw<D: DDSType, T: DDSReaderTopic>(topic: T, ddsType: D.Type, completion: @escaping (UInt64, Data)->Void) {
        let payloadDecoderProxy = Unmanaged.passRetained(PayloadDecoderProxy(completion: completion)).toOpaque()
        wrapper.registerReader(topicName: topic.rawValue.cString(using: .utf8)!,
                               typeName: D.ddsTypeName.cString(using: .utf8)!,
                               keyed: ddsType is DDSKeyed,
                               transientLocal: topic.transientLocal,
                               reliable: topic.reliable,
                               payloadDecoder: payloadDecoderProxy)
    }
    
    /// Register a RTPS reader for topic with Result data callback
    /// - Parameters:
    ///   - topic: DDSReader topic description
    ///   - completion: callback with Result<D, Error>, where D is deserialized data
    public func registerReader<D: DDSType, T: DDSReaderTopic>(topic: T, completion: @escaping (Result<D, Error>)->Void) {
        registerReaderRaw(topic: topic, ddsType: D.self) { (_, data) in
            let decoder = CDRDecoder()
            let result = Result.init { try decoder.decode(D.self, from: data) }
            completion(result)
        }
    }
    
    /// Register a RTPS reader for topic with deserialized data callback
    /// - Parameters:
    ///   - topic: DDSReaderTopic topic description
    ///   - completion: callback with deserialized data
    public func registerReader<D: DDSType, T: DDSReaderTopic>(topic: T, completion: @escaping (D)->Void) {
        registerReaderRaw(topic: topic, ddsType: D.self) { (_, data) in
            let decoder = CDRDecoder()
            do {
                let t = try decoder.decode(D.self, from: data)
                completion(t)
            } catch {
                print(topic.rawValue, error)
            }
        }
    }
    
    /// Remove a RTPS reader for topic
    /// - Parameter topic: DDSReader topic descriptor
    public func removeReader<T: DDSReaderTopic>(topic: T) {
        wrapper.removeReader(topicName: topic.rawValue.cString(using: .utf8)!)
    }
    
    /// Register a RTPS writer for topic
    /// Writer must be registered before send data
    /// - Parameters:
    /// - Parameter topic: DDSWriterTopic topic descriptor
    ///   - ddsType: data type descriptor
    public func registerWriter<D: DDSType, T: DDSWriterTopic>(topic: T, ddsType: D.Type)  {
        wrapper.registerWriter(topicName: topic.rawValue.cString(using: .utf8)!,
                               typeName: D.ddsTypeName.cString(using: .utf8)!,
                               keyed: ddsType is DDSKeyed,
                               transientLocal: topic.transientLocal,
                               reliable: topic.reliable)
    }
    
    /// Remove RTPS writer for topic
    /// - Parameter topic: DDSWriterTopic topic descriptor
    public func removeWriter<T: DDSWriterTopic>(topic: T) {
        wrapper.removeWriter(topicName: topic.rawValue.cString(using: .utf8)!)
    }
    
    /// Send data change for topic
    /// - Parameters:
    /// - Parameter topic: DDSWriter topic descriptor
    ///   - ddsData: any DDSType object
    public func send<D: DDSType, T: DDSWriterTopic>(topic: T, ddsData: D) {
        let encoder = CDREncoder()
        do {
            let data = try encoder.encode(ddsData)
            data.withUnsafeBytes { dataPtr in
                if ddsData is DDSKeyed {
                    var key = (ddsData as! DDSKeyed).key
                    if key.isEmpty {
                        key = Data([0])
                    }
                    key.withUnsafeBytes { keyPtr in
                        wrapper.sendDataWithKey(topicName: topic.rawValue.cString(using: .utf8)!,
                                                data: dataPtr.baseAddress!,
                                                length: UInt32(data.count),
                                                key: keyPtr.baseAddress!,
                                                keyLength: UInt32(key.count))
                    }
                } else {
                    wrapper.sendData(topicName: topic.rawValue.cString(using: .utf8)!,
                                     data: dataPtr.baseAddress!,
                                     length: UInt32(data.count))
                }
            }
        } catch {
            fatalError(error.localizedDescription)
        }
    }
    
    /// Remove all readers and writers from participant
    public func resignAll() {
        wrapper.resignAll()
    }
    
    /// Method to shut down all RTPS participants, readers, writers, etc. It may be called at the end of the process to avoid memory leaks.
    public func stopAll() {
        wrapper.stopAll()
    }
    
    /// Remove all readers/writers and then remove participant
    public func removeParticipant() {
        wrapper.removeParticipant()
    }
    
    /// Set FastRTPS log messages level
    /// - Parameter level: error, warning, info
    public func setlogLevel(_ level: FastRTPSLogLevel) {
        FastRTPSWrapper.logLevel(level: level)
    }

}
