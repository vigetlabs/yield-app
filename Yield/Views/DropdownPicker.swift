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
                onSelect: onSelect
            )
            .frame(height: 32)
            .background(YieldColors.surfaceDefault)
            .clipShape(RoundedRectangle(cornerRadius: YieldRadius.dropdown))
            .overlay(
                RoundedRectangle(cornerRadius: YieldRadius.dropdown)
                    .strokeBorder(YieldColors.border, lineWidth: 1)
            )
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
        .frame(height: 32)
        .accessibilityLabel(label)
        .background(YieldColors.surfaceDefault)
        .clipShape(RoundedRectangle(cornerRadius: YieldRadius.dropdown))
        .overlay(
            RoundedRectangle(cornerRadius: YieldRadius.dropdown)
                .strokeBorder(YieldColors.border, lineWidth: 1)
        )
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
    let onSelect: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()

        // Popup button
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
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
            popup.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            popup.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            popup.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        context.coordinator.popup = popup

        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let popup = context.coordinator.popup else { return }
        context.coordinator.onSelect = onSelect

        popup.removeAllItems()
        popup.isEnabled = !isDisabled

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
                    menuItem.attributedTitle = NSAttributedString(
                        string: item.title,
                        attributes: [.font: menuFont]
                    )
                    menuItem.tag = item.id
                    menuItem.indentationLevel = group.label != nil ? 1 : 0
                    popup.menu?.addItem(menuItem)
                }
            }
        } else {
            // Flat mode
            for item in items {
                popup.addItem(withTitle: item.title)
                popup.lastItem?.tag = item.id
                popup.lastItem?.attributedTitle = NSAttributedString(
                    string: item.title,
                    attributes: [.font: menuFont]
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
