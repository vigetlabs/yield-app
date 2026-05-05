import AppKit
import SwiftUI

/// An item group for grouped dropdowns (like HTML optgroup).
struct DropdownGroup {
    let label: String?
    let items: [(id: Int, title: String)]
}

/// A native NSPopUpButton-backed dropdown that works reliably inside MenuBarExtra panels.
/// SwiftUI Menu/Picker can drop selections due to ViewBridge disconnects in this context.
struct DropdownPicker: View {
    let label: String
    let placeholder: String
    var isLoading: Bool = false
    var items: [(id: Int, title: String)] = []
    var groups: [DropdownGroup]? = nil
    var selectedId: Int?
    var isDisabled: Bool = false
    /// Item ids that should render with a leading star icon — used to
    /// surface favorited tasks inline with the rest of the list.
    var favoritedIds: Set<Int> = []
    /// When true, the dropdown behaves as an action menu (pull-down)
    /// rather than a value picker (pop-up). The button's title stays
    /// pinned to `placeholder`; selecting an item just fires
    /// `onSelect` and doesn't change the displayed title.
    var isPullDown: Bool = false
    /// Pre-composed attributed titles, one per item — overrides
    /// `items` when supplied. Use this when you need rich per-item
    /// rendering (multi-line, leading icons, mixed fonts) that the
    /// plain `items` API can't express.
    var richItems: [(id: Int, attributedTitle: NSAttributedString)]? = nil
    /// When true, an `NSMenuItem.separator()` is inserted between
    /// each item (or rich item). Doesn't apply to grouped mode,
    /// which already uses separators between groups.
    var showsItemSeparators: Bool = false
    let onSelect: (Int) -> Void

    var body: some View {
        if isLoading {
            loadingView
                .transition(.opacity)
        } else {
            NativePopUpButton(
                items: items,
                groups: groups,
                selectedId: selectedId,
                placeholder: placeholder,
                label: label,
                isDisabled: isDisabled,
                favoritedIds: favoritedIds,
                isPullDown: isPullDown,
                richItems: richItems,
                showsItemSeparators: showsItemSeparators,
                onSelect: onSelect
            )
            .frame(height: YieldDimensions.controlHeight)
            .background(YieldColors.surfaceDefault)
            .yieldBorder()
        }
    }

    private var loadingView: some View {
        HStack {
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 10, height: 10)
                Text("Loading...")
                    .font(YieldFonts.titleSmall)
                    .foregroundStyle(YieldColors.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: YieldDimensions.controlHeight)
        .accessibilityLabel(label)
        .background(YieldColors.surfaceDefault)
        .yieldBorder()
    }
}

// MARK: - NSPopUpButton Wrapper

private struct NativePopUpButton: NSViewRepresentable {
    let items: [(id: Int, title: String)]
    let groups: [DropdownGroup]?
    let selectedId: Int?
    let placeholder: String
    let label: String
    let isDisabled: Bool
    let favoritedIds: Set<Int>
    let isPullDown: Bool
    let richItems: [(id: Int, attributedTitle: NSAttributedString)]?
    let showsItemSeparators: Bool
    let onSelect: (Int) -> Void

    /// Build a menu-item attributed title with a leading star glyph
    /// when `isFavorited`. Inlining the star as a text attachment lets
    /// us match the text color (`.labelColor` adapts across light and
    /// dark) and nudge the baseline so it aligns with the text's cap
    /// height rather than sitting low on the line — controls the
    /// `NSMenuItem.image` API doesn't expose. The same attributed
    /// title is rendered both in the open menu and in the closed
    /// popup's selected state.
    private static func attributedTitle(for title: String, font: NSFont, isFavorited: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString()
        if isFavorited, let star = favoriteIcon(forFont: font) {
            let attachment = NSTextAttachment()
            attachment.image = star
            let glyphSize = font.pointSize
            // Negative y lowers the attachment below the baseline. The
            // SF Symbol star occupies its full bounds, but visually
            // reads as sitting above the text baseline at y: 0; -1pt
            // drops it to align with the cap-to-baseline span of the
            // surrounding text.
            attachment.bounds = NSRect(x: 0, y: -1, width: glyphSize, height: glyphSize)
            result.append(NSAttributedString(attachment: attachment))
            result.append(NSAttributedString(string: "  ", attributes: [.font: font]))
        }
        result.append(NSAttributedString(string: title, attributes: [.font: font]))
        return result
    }

    private static func favoriteIcon(forFont font: NSFont) -> NSImage? {
        let glyphSize = font.pointSize
        let config = NSImage.SymbolConfiguration(pointSize: glyphSize, weight: .semibold)
            .applying(.init(paletteColors: [.labelColor]))
        let image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: "Favorite")?
            .withSymbolConfiguration(config)
        image?.size = NSSize(width: glyphSize, height: glyphSize)
        return image
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeNSView(context: Context) -> NSView {
        let container = ClickForwardingView()

        // Popup button. Pull-down mode pins the title to the first
        // menu item permanently; pop-up mode updates the title to
        // reflect the selected item.
        let popup = NSPopUpButton(frame: .zero, pullsDown: isPullDown)
        popup.bezelStyle = .inline
        popup.isBordered = false
        popup.font = NSFont(name: "Newsreader-Regular", size: 12) ?? NSFont.systemFont(ofSize: 12)
        popup.target = context.coordinator
        popup.action = #selector(Coordinator.itemSelected(_:))
        popup.translatesAutoresizingMaskIntoConstraints = false
        (popup.cell as? NSPopUpButtonCell)?.arrowPosition = .arrowAtBottom
        // Accessibility: set the label for screen readers
        popup.setAccessibilityLabel(label)
        container.addSubview(popup)

        NSLayoutConstraint.activate([
            // Let the popup take its intrinsic ~22pt height and center
            // vertically in the 32pt container so the text reads as
            // centered. Stretching top-to-bottom shifted the text up
            // because `.inline + bordered: false` draws the title at
            // the popup's baseline, not the stretched frame's center.
            // ClickForwardingView already forwards clicks from the
            // padding strips, so we don't need the popup to fill.
            popup.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            popup.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            // Nudged down 1pt — the popup's intrinsic baseline still
            // reads slightly above the visual center of the 32pt
            // container, so a small offset lands the title where the
            // eye expects it.
            popup.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: 1),
        ])

        context.coordinator.popup = popup
        container.popup = popup

        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let popup = context.coordinator.popup else { return }
        context.coordinator.onSelect = onSelect

        popup.removeAllItems()
        popup.isEnabled = !isDisabled

        // Respect our manual `isEnabled = false` on group-header items. Without this,
        // NSMenu re-enables items via target/action validation and client headers
        // become selectable.
        popup.menu?.autoenablesItems = false

        let menuFont = NSFont(name: "Newsreader-Regular", size: 12) ?? NSFont.systemFont(ofSize: 12)
        let headerFont = NSFont(name: "DMSans-SemiBold", size: 10) ?? NSFont.boldSystemFont(ofSize: 10)

        // Add placeholder
        popup.addItem(withTitle: placeholder)
        popup.menu?.items.first?.tag = -1

        if let groups {
            // Grouped mode
            for (index, group) in groups.enumerated() {
                // Add separator before each group (except the first)
                if index > 0 {
                    popup.menu?.addItem(.separator())
                }

                // Group header (disabled, acts as label)
                if let groupLabel = group.label {
                    let headerItem = NSMenuItem()
                    headerItem.attributedTitle = NSAttributedString(
                        string: groupLabel.uppercased(),
                        attributes: [
                            .font: headerFont,
                            .foregroundColor: NSColor.secondaryLabelColor,
                        ]
                    )
                    headerItem.isEnabled = false
                    headerItem.tag = -1
                    popup.menu?.addItem(headerItem)
                }

                // Group items (indented)
                for item in group.items {
                    let menuItem = NSMenuItem()
                    menuItem.attributedTitle = Self.attributedTitle(
                        for: item.title,
                        font: menuFont,
                        isFavorited: favoritedIds.contains(item.id)
                    )
                    menuItem.tag = item.id
                    menuItem.indentationLevel = group.label != nil ? 1 : 0
                    popup.menu?.addItem(menuItem)
                }
            }
        } else if let richItems {
            // Rich mode — caller composed attributed titles per item.
            for (index, item) in richItems.enumerated() {
                if showsItemSeparators, index > 0 {
                    popup.menu?.addItem(.separator())
                }
                let menuItem = NSMenuItem()
                menuItem.attributedTitle = item.attributedTitle
                menuItem.tag = item.id
                popup.menu?.addItem(menuItem)
            }
        } else {
            // Flat mode
            for (index, item) in items.enumerated() {
                if showsItemSeparators, index > 0 {
                    popup.menu?.addItem(.separator())
                }
                popup.addItem(withTitle: item.title)
                popup.lastItem?.tag = item.id
                popup.lastItem?.attributedTitle = Self.attributedTitle(
                    for: item.title,
                    font: menuFont,
                    isFavorited: favoritedIds.contains(item.id)
                )
            }
        }

        // Style placeholder
        popup.menu?.items.first?.attributedTitle = NSAttributedString(
            string: placeholder,
            attributes: [.font: menuFont]
        )

        // Select the right item
        if let selectedId {
            let index = popup.indexOfItem(withTag: selectedId)
            if index >= 0 {
                popup.selectItem(at: index)
            }
        } else {
            popup.selectItem(at: 0)
        }

        // Update accessibility label
        popup.setAccessibilityLabel(label)
    }

    /// Container view that forwards clicks in its padding strips to the embedded
    /// popup button — without this, ~8pt strips on the left/right and any area
    /// outside the popup's intrinsic bounds aren't clickable.
    class ClickForwardingView: NSView {
        weak var popup: NSPopUpButton?

        override func mouseDown(with event: NSEvent) {
            guard let popup, popup.isEnabled else {
                super.mouseDown(with: event)
                return
            }
            popup.performClick(nil)
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: .arrow)
        }
    }

    class Coordinator {
        var onSelect: (Int) -> Void
        weak var popup: NSPopUpButton?

        init(onSelect: @escaping (Int) -> Void) {
            self.onSelect = onSelect
        }

        @objc func itemSelected(_ sender: NSPopUpButton) {
            let tag = sender.selectedItem?.tag ?? -1
            guard tag >= 0 else { return }
            onSelect(tag)
        }
    }
}
