// SPDX-License-Identifier: MPL-2.0

#if os(iOS)
    import SwiftUI

    /// Section whose content can be collapsed to save vertical space.
    ///
    /// The header is always visible and carries the disclosure state; the
    /// content is only built while expanded, so a long synopsis does not
    /// reserve height when it is folded away.
    struct CollapsibleSection<Content: View>: View {
        let title: String
        @Binding var isExpanded: Bool
        @ViewBuilder var content: Content

        init(
            title: String,
            isExpanded: Binding<Bool>,
            @ViewBuilder content: () -> Content
        ) {
            self.title = title
            self._isExpanded = isExpanded
            self.content = content()
        }

        var body: some View {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Button {
                    withAnimation(.easeInOut(duration: DesignTokens.Animation.fast)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Text(title)
                            .font(Typography.headline)
                            .foregroundStyle(.primary)

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColor.onSurfaceVariant)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

                if isExpanded {
                    content
                }
            }
        }
    }
#endif
