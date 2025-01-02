//
//  RowLabelView.swift
//  idd-softwareupdate
//
//  Created by Klajd Deda on 5/19/24.
//  Copyright (C) 1997-2025 id-design, inc. All rights reserved.
//

import SwiftUI

internal struct RowLabelView<Content: View>: View {
    var label: String
    var width: Double
    let content: Content

    init(
        label: String,
        width: Double = 80,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.width = width
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(label)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(width: width, alignment: .trailing)

            content
            Spacer()
        }
    }
}
