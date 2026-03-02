//
//  ProvikartWidgetBundle.swift
//  ProvikartWidget
//

import WidgetKit
import SwiftUI

@main
struct ProvikartWidgetBundle: WidgetBundle {
    var body: some Widget {
        ProvikartWidget()
        ProvikartReportsWidget()
    }
}
