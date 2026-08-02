//
//  RoutePicker.swift
//  Sonava
//
//  The AirPlay / output-route button.
//
//  There wasn't one. A player whose listeners own hi-fi gear — the exact
//  people who keep FLAC libraries and self-hosted servers — had no way to
//  reach a HomePod, an Apple TV or a Bluetooth receiver except by leaving
//  the app for Control Centre. Competitors advertise AirPlay 2 in the second
//  paragraph of their store listing.
//
//  `AVRoutePickerView` is the only supported way to present the picker;
//  there is no SwiftUI equivalent and no public API to open it manually. So
//  this is a thin representable, tinted to the app's own colours.
//

import SwiftUI
import AVKit

struct RoutePickerButton: UIViewRepresentable {
    var tint: Color = .white
    var activeTint: Color = Theme.accentSoft
    var size: CGFloat = 22

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = UIColor(tint)
        // The colour the glyph takes while audio is actually routed
        // elsewhere — the one moment this control has something to say.
        view.activeTintColor = UIColor(activeTint)
        view.prioritizesVideoDevices = false
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        view.tintColor = UIColor(tint)
        view.activeTintColor = UIColor(activeTint)
    }

    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: AVRoutePickerView,
                      context: Context) -> CGSize? {
        CGSize(width: size + 12, height: size + 12)
    }
}
