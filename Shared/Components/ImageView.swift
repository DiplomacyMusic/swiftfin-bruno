//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import BlurHashKit
import Nuke
import NukeUI
import SwiftUI

// TODO: currently SVGs are only supported for logos, which are only used in a few places.
//       make it so when displaying an SVG there is a unified `image` caller modifier
// TODO: `LazyImage` uses a transaction for view swapping, which will fade out old views
//       and fade in new views, causing a black "flash" between the placeholder and final image.
//       Since we use blur hashes, we actually just want the final image to fade in on top while
//       the blur hash view is at full opacity.
//       - refactor for option
//       - take a look at `RotateContentView`
// TODO: make Image and Placeholder generic constraints rather than any View
struct ImageView<Failure: View>: View {

    // Plain stored input (NOT @State): a stored property reflects the latest view value when the
    // forked CollectionHStack swaps `rootView` on a recycled cell, so the displayed art tracks the
    // CURRENT item. As @State, `sources` froze at the first item's value across reuse → right label,
    // wrong art (the exact trap BrunoFocusArtCycle works around per-frame with `.id`). The only thing
    // that must persist is the load-failure failover, kept in a URL-keyed set so a recycled cell never
    // inherits another item's failures.
    private let sources: [ImageSource]
    @State
    private var failedURLs: Set<URL> = []

    private var image: (Image) -> any View
    private var pipeline: ImagePipeline
    private var placeholder: ((ImageSource) -> any View)?
    private var failure: Failure

    @ViewBuilder
    private func _placeholder(_ currentSource: ImageSource) -> some View {
        if let placeholder {
            placeholder(currentSource)
                .eraseToAnyView()
        } else {
            DefaultPlaceholderView(blurHash: currentSource.blurHash)
        }
    }

    /// First source whose URL hasn't failed to load. Recomputed from `sources` on every render, so a
    /// reused cell renders the CURRENT item's art rather than the stale first-bound one.
    private var currentSource: ImageSource? {
        sources.first { source in
            guard let url = source.url else { return false }
            return !failedURLs.contains(url)
        }
    }

    var body: some View {
        if let currentSource {
            LazyImage(url: currentSource.url, transaction: .init(animation: .linear)) { state in
                if state.isLoading {
                    _placeholder(currentSource)
                } else if let _image = state.image {
                    if let data = state.imageContainer?.data {
                        FastSVGView(data: data)
                    } else {
                        image(_image.resizable())
                            .eraseToAnyView()
                    }
                } else if state.error != nil {
                    failure
                        .onAppear {
                            if let url = currentSource.url { failedURLs.insert(url) }
                        }
                }
            }
            .pipeline(pipeline)
            .onDisappear(.lowerPriority)
        } else {
            failure
        }
    }
}

extension ImageView where Failure == EmptyView {

    init(_ source: ImageSource) {
        self.init([source].compacted(using: \.url))
    }

    init(_ sources: [ImageSource]) {
        self.init(
            sources: sources.compacted(using: \.url),
            image: { $0 },
            pipeline: .shared,
            placeholder: nil,
            failure: EmptyView()
        )
    }

    init(_ source: URL?) {
        self.init([ImageSource(url: source)])
    }

    init(_ sources: [URL?]) {
        let imageSources = sources
            .compacted()
            .map { ImageSource(url: $0) }

        self.init(imageSources)
    }
}

// MARK: Modifiers

extension ImageView {

    func image(@ViewBuilder _ content: @escaping (Image) -> any View) -> Self {
        copy(modifying: \.image, with: content)
    }

    func pipeline(_ pipeline: ImagePipeline) -> Self {
        copy(modifying: \.pipeline, with: pipeline)
    }

    func placeholder(@ViewBuilder _ content: @escaping (ImageSource) -> any View) -> Self {
        copy(modifying: \.placeholder, with: content)
    }

    func failure<NewFailure: View>(@ViewBuilder _ content: @escaping () -> NewFailure) -> ImageView<NewFailure> {
        ImageView<NewFailure>(
            sources: sources,
            image: image,
            pipeline: pipeline,
            placeholder: placeholder,
            failure: content()
        )
    }
}

// MARK: Defaults

struct DefaultFailureView: View {

    var body: some View {
        Color.secondarySystemFill
            .opacity(0.75)
    }
}

struct DefaultPlaceholderView: View {

    let blurHash: String?

    var body: some View {
        if let blurHash {
            BlurHashView(blurHash: blurHash, size: .Square(length: 8))
        }
    }
}
