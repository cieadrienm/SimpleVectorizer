import AppKit
import SimpleVectorizerCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var isDropTargeted = false

    var body: some View {
        let _ = model.language
        VStack(spacing: 0) {
            TopBar(model: model)
            ScanProgressBar(fraction: model.vectorizer.progressFraction, active: model.vectorizer.isProcessing)
            Rectangle().fill(Theme.separator.swiftUI).frame(height: 1)

            HStack(spacing: 0) {
                if model.showSidebar {
                    ParameterSidebarView(model: model)
                        .frame(width: ParameterSidebarView.sidebarWidth)
                    Rectangle().fill(Theme.separator.swiftUI).frame(width: 1)
                }

                CanvasViewportView(model: model, isDropTargeted: $isDropTargeted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            StatusBar(model: model)
        }
        .background(Theme.background.swiftUI)
        .preferredColorScheme(.dark)
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .sheet(isPresented: $model.showAbout) {
            AboutSheet(
                model: model,
                openHelp: { model.showHelp = true },
                close: { model.showAbout = false }
            )
        }
        .sheet(isPresented: $model.showHelp) {
            HelpManualSheet(
                openShortcuts: { model.showShortcuts = true },
                close: { model.showHelp = false }
            )
        }
        .sheet(isPresented: $model.showShortcuts) {
            ShortcutsSheet(close: { model.showShortcuts = false })
        }
        .sheet(isPresented: $model.showOSCGuide) {
            OSCGuideSheet(model: model, close: { model.showOSCGuide = false })
        }
        .sheet(isPresented: $model.showExport) {
            ExportSheet(model: model)
        }
        .sheet(isPresented: $model.showUpdater) {
            UpdateSheet(model: model, close: { model.showUpdater = false })
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let resolvedURL: URL?
                    if let url = item as? URL {
                        resolvedURL = url
                    } else if let nsurl = item as? NSURL {
                        resolvedURL = nsurl as URL
                    } else if let data = item as? Data {
                        resolvedURL = URL(dataRepresentation: data, relativeTo: nil)
                    } else if let path = item as? String {
                        resolvedURL = URL(fileURLWithPath: path)
                    } else {
                        resolvedURL = nil
                    }
                    if let url = resolvedURL {
                        Task { @MainActor in
                            model.open(url)
                        }
                    }
                }
                return true
            }
            if provider.canLoadObject(ofClass: NSImage.self) {
                _ = provider.loadObject(ofClass: NSImage.self) { obj, _ in
                    if let nsImage = obj as? NSImage {
                        Task { @MainActor in
                            _ = model.vectorizer.loadNSImage(nsImage, title: L("Image déposée", "Dropped Image"))
                            model.clearSelection()
                            model.resetZoom(animated: false)
                        }
                    }
                }
                return true
            }
        }
        return false
    }
}
