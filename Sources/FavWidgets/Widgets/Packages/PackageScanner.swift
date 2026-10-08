import SwiftUI
import FavWidgetsCore
#if canImport(VisionKit) && os(iOS)
import VisionKit

/// Reads a tracking number off a shipping label (barcode or printed text).
struct PackageScanner: UIViewControllerRepresentable {
    let onFound: (String) -> Void

    static var isAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(), .text()], qualityLevel: .accurate,
                                                isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (String) -> Void
        private var done = false
        init(onFound: @escaping (String) -> Void) { self.onFound = onFound }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            consider(addedItems)
        }
        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) { consider([item]) }

        private func consider(_ items: [RecognizedItem]) {
            guard !done else { return }
            for item in items {
                let raw: String?
                switch item {
                case .barcode(let b): raw = b.payloadStringValue
                case .text(let t): raw = t.transcript
                @unknown default: raw = nil
                }
                // USPS labels encode 420+ZIP before the number; the detector takes it whole
                if let raw, CarrierDetector.looksLikeTrackingNumber(raw), CarrierDetector.detect(raw) != .other {
                    done = true
                    onFound(CarrierDetector.normalize(raw))
                    return
                }
            }
        }
    }
}
#else
struct PackageScanner: View {
    let onFound: (String) -> Void
    static var isAvailable: Bool { false }
    var body: some View { EmptyView() }
}
#endif
