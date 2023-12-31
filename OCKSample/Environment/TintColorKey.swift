//
//  TintColorKey.swift
//  OCKSample
//
//  Created by Corey Baker on 10/16/21.
//  Copyright © 2021 Network Reconnaissance Lab. All rights reserved.
//

import Foundation
import SwiftUI

struct TintColorKey: EnvironmentKey {
    static var defaultValue: UIColor {
        #if os(iOS)
        return UIColor { $0.userInterfaceStyle == .light ?  #colorLiteral(red: 0, green: 0.568627451, blue: 0.5764705882, alpha: 1) : #colorLiteral(red: 0.06253327429, green: 0.6597633362, blue: 0.8644603491, alpha: 1) }
        #else
        return #colorLiteral(red: 0, green: 0.568627451, blue: 0.5764705882, alpha: 1)
        #endif
    }
}

extension EnvironmentValues {
    var tintColor: UIColor {
        self[TintColorKey.self]
    }
}
