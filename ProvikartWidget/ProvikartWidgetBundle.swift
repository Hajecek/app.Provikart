//
//  ProvikartWidgetBundle.swift
//  ProvikartWidget
//

import ActivityKit
import WidgetKit
import SwiftUI

@main
struct ProvikartWidgetBundle: WidgetBundle {
    var body: some Widget {
        ProvikartWidget()
        ProvikartReportsWidget()
        ProvikartInstallationsWidget()
        CommissionLiveActivityWidget()
    }
}
