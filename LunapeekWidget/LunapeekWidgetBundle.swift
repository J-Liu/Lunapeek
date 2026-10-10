// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import WidgetKit
import SwiftUI

@main
struct LunapeekWidgetBundle: WidgetBundle {
    var body: some Widget {
        LunapeekWidget()
        LunapeekWidgetLiveActivity()
    }
}
