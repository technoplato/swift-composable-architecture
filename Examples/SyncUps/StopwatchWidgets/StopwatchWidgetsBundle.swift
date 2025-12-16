//
//  StopwatchWidgetsBundle.swift
//  StopwatchWidgets
//
//  Created by Michael Lustig on 12/16/25.
//

import WidgetKit
import SwiftUI

@main
struct StopwatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        StopwatchWidgets()
        StopwatchWidgetsControl()
        StopwatchWidgetsLiveActivity()
    }
}
