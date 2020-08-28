/////
////  RovTopic.swift
///   Copyright © 2020 Dmitriy Borovikov. All rights reserved.
//

import Foundation
import FastRTPSBridge

enum ReaderTopic: String, DDSReaderTopic {
    case rovDepth                    = "rov_depth"                         // orov::msg::sensor::Depth
    
    var transientLocal: Bool { false }
    var reliable: Bool { false }
}
