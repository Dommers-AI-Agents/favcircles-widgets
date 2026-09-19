import SwiftUI
import PhotosUI
import FavWidgetsCore

extension PostcardFullView {
    func photoSection(_ theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header("Photo", theme: theme)
            preview
            HStack(spacing: 10) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    secondaryLabel(photo == nil ? "Choose photo" : "Change photo", symbol: "photo.on.rectangle", theme: theme)
                }
                .buttonStyle(.plain)
                #if os(iOS)
                if PostcardCameraPicker.isAvailable {
                    Button { showCamera = true } label: {
                        secondaryLabel("Take photo", symbol: "camera", theme: theme)
                    }
                    .buttonStyle(.plain)
                }
                #endif
            }
        }
    }

    var preview: some View {
        GeometryReader { proxy in
            PostcardCanvasView(image: photo, templateId: templateId, caption: caption,
                               size: CGSize(width: proxy.size.width, height: proxy.size.width / PostcardTemplate.aspectRatio),
                               accent: context.accent)
        }
        .aspectRatio(PostcardTemplate.aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
    }

    func templateSection(_ theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header("Template", theme: theme)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(PostcardTemplate.allCases) { template in
                        let selected = template.rawValue == templateId
                        Button {
                            templateId = template.rawValue
                            context.host.haptic(.selection)
                        } label: {
                            VStack(spacing: 6) {
                                PostcardCanvasView(image: photo, templateId: template.rawValue, caption: caption,
                                                   size: CGSize(width: 132, height: 88), accent: context.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(selected ? context.accent : theme.separator, lineWidth: selected ? 3 : 1)
                                    )
                                Text(template.name)
                                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                                    .foregroundStyle(selected ? context.accent : theme.secondaryLabel)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(template.name) template")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    func captionSection(_ theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header("Caption on the card", theme: theme)
            HStack(spacing: 8) {
                Text("Greetings from")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.secondaryLabel)
                TextField("Where are you?", text: $placeName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(theme.label)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
            if let placeRef, !PostcardCopy.isCustom(placeRef) {
                Label(placeRef.city.map { "\(placeRef.name), \($0)" } ?? placeRef.name, systemImage: "mappin.and.ellipse")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryLabel)
            }
        }
    }

    func messageSection(_ theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                WidgetUI.header("Message", theme: theme)
                Text("\(message.count)/\(PostcardCopy.messageLimit)")
                    .font(.system(size: 12))
                    .foregroundStyle(message.count >= PostcardCopy.messageLimit ? theme.warning : theme.secondaryLabel)
            }
            ZStack(alignment: .topLeading) {
                if message.isEmpty {
                    Text("Wish you were here…")
                        .font(.system(size: 15))
                        .foregroundStyle(theme.secondaryLabel.opacity(0.6))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                }
                TextEditor(text: $message)
                    .font(.system(size: 15))
                    .foregroundStyle(theme.label)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
        }
    }

    func recipientSection(_ theme: WidgetTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetUI.header("Deliver to", theme: theme)
            Text("Pick any or all — one Send does them together.")
                .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            Button { showRecipientPicker = true } label: {
                HStack(spacing: 12) {
                    if let recipient {
                        PostcardContactRow(contact: recipient, theme: theme, accent: context.accent)
                    } else {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 22))
                            .foregroundStyle(context.accent)
                        Text("Choose a connection")
                            .font(.system(size: 16))
                            .foregroundStyle(theme.label)
                        Spacer()
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.secondaryLabel)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if recipient != nil {
                Button("Remove connection") { recipient = nil }
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(theme.secondaryLabel)
            }

            // Email: anyone, FavCircles user or not. The app sends the mail.
            HStack(spacing: 12) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(context.accent)
                TextField("Email addresses, comma separated", text: $emailText)
                    .font(.system(size: 16))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    #endif
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.secondaryBackground))
            if !emailAddresses.invalid.isEmpty {
                Text("Check: \(emailAddresses.invalid.joined(separator: ", "))")
                    .font(.system(size: 12)).foregroundStyle(theme.danger)
            } else if emailAddresses.valid.count > PostcardEmail.maxAddresses {
                Text("Up to \(PostcardEmail.maxAddresses) addresses per postcard.")
                    .font(.system(size: 12)).foregroundStyle(theme.danger)
            } else if !emailAddresses.valid.isEmpty {
                Text("Will email \(emailAddresses.valid.count == 1 ? emailAddresses.valid[0] : "\(emailAddresses.valid.count) people") with a link to view it online.")
                    .font(.system(size: 12)).foregroundStyle(theme.secondaryLabel)
            }

            if mailAvailable, let mailConfig {
                if mailOn && mailMessageTooLong {
                    Text("A printed postcard fits \(mailConfig.messageMaxChars) characters on the back — yours is \(message.trimmingCharacters(in: .whitespacesAndNewlines).count). Shorten it or turn off mailing.")
                        .font(.system(size: 12)).foregroundStyle(theme.danger)
                }
                PostcardMailForm(
                    theme: theme,
                    accent: context.accent,
                    config: mailConfig,
                    isOn: $mailOn,
                    address: $mailAddress,
                    quote: mailQuote,
                    quoteError: mailQuoteError,
                    isQuoting: isQuoting,
                    onAddressSettled: scheduleQuote,
                    onAcceptCorrection: acceptMailCorrection
                )
            }

            Toggle(isOn: $alsoShare) {
                Text("Also share by text or other apps after sending")
                    .font(.system(size: 14)).foregroundStyle(theme.label)
            }
            .tint(context.accent)
        }
    }
}
