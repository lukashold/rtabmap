import UIKit
import WebKit
import UniformTypeIdentifiers

/// Offline visualization only. This view neither owns a camera nor trains a
/// Gaussian Splat, and its rendering must not be treated as measurement geometry.
final class SplatViewController: UIViewController, UIDocumentPickerDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    var onClose: (() -> Void)?
    private let status = UILabel()
    private var webView: WKWebView!
    private var assetDirectory: URL?
    private var pending: SplatDocument?
    private var ready = false
    private var requestID = UUID()
    private var importButton: UIBarButtonItem!
    private var loadingTimeout: DispatchWorkItem?
    private var text: (String) -> String { MeasurementGuide.splatText }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = text("title")
        KanturaDesign.navigation(self)
        view.backgroundColor = KanturaDesign.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: MeasurementGuide.roomText("close"), style: .done, target: self, action: #selector(close))
        importButton = UIBarButtonItem(title: text("open"), style: .plain, target: self, action: #selector(openFile))
        importButton.isEnabled = false
        navigationItem.rightBarButtonItem = importButton
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.add(WeakSplatMessageHandler(self), name: "kanturaSplat")
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = KanturaDesign.background
        webView.translatesAutoresizingMaskIntoConstraints = false
        status.text = text("intro")
        status.numberOfLines = 0
        status.font = .preferredFont(forTextStyle: .subheadline)
        status.adjustsFontForContentSizeCategory = true
        status.textColor = KanturaDesign.text
        status.translatesAutoresizingMaskIntoConstraints = false
        let headerScroll = UIScrollView()
        headerScroll.translatesAutoresizingMaskIntoConstraints = false
        headerScroll.addSubview(status)
        view.addSubview(headerScroll)
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            headerScroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerScroll.heightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.heightAnchor, multiplier: 0.23),
            status.topAnchor.constraint(equalTo: headerScroll.contentLayoutGuide.topAnchor, constant: 16),
            status.leadingAnchor.constraint(equalTo: headerScroll.contentLayoutGuide.leadingAnchor, constant: 20),
            status.trailingAnchor.constraint(equalTo: headerScroll.contentLayoutGuide.trailingAnchor, constant: -20),
            status.bottomAnchor.constraint(equalTo: headerScroll.contentLayoutGuide.bottomAnchor, constant: -16),
            status.widthAnchor.constraint(equalTo: headerScroll.frameLayoutGuide.widthAnchor, constant: -40),
            webView.topAnchor.constraint(equalTo: headerScroll.bottomAnchor),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        // The bundled renderer targets Safari/WebKit 17. Older supported app
        // versions keep their LiDAR workflow and get an immediate clear result.
        guard #available(iOS 17.0, *) else {
            status.text = text("unavailable"); return
        }
        guard let index = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "SplatViewerAssets") else {
            status.text = text("unavailable"); importButton.isEnabled = false; return
        }
        assetDirectory = index.deletingLastPathComponent().standardizedFileURL
        webView.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
        armTimeout()
    }

    @objc private func openFile() {
        guard presentedViewController == nil else { return }
        if !ready, let directory = assetDirectory {
            webView.loadFileURL(directory.appendingPathComponent("index.html"), allowingReadAccessTo: directory)
            armTimeout()
        }
        let types = [UTType(filenameExtension: "ply") ?? .data, UTType(filenameExtension: "splat") ?? .data]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let identifier = UUID()
        requestID = identifier
        pending = nil
        status.text = text("loading")
        importButton.isEnabled = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            var coordinationError: NSError?
            var result: Result<SplatDocument, Error> = .failure(SplatDocument.Failure.invalidFile)
            NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
                result = Result { try SplatDocument.read(from: readable) }
            }
            if let error = coordinationError { result = .failure(error) }
            DispatchQueue.main.async {
                guard let self = self, self.requestID == identifier else { return }
                switch result {
                case .success(let document): self.pending = document; self.deliverIfReady()
                case .failure(let error):
                    self.importButton.isEnabled = true
                    if case SplatDocument.Failure.tooLarge = error { self.status.text = self.text("tooLarge") }
                    else { self.status.text = self.text("invalid") }
                }
            }
        }
    }

    private func deliverIfReady() {
        guard ready, let document = pending else { return }
        do {
            let payload = try document.javascriptPayload(language: MeasurementGuide.selectedLanguage)
            pending = nil
            armTimeout()
            // `void` avoids evaluating an async renderer's Promise as a native
            // result. Success/failure arrives through the bounded message bridge.
            webView.evaluateJavaScript("void window.loadKanturaSplat(" + payload + ");") { [weak self] _, error in
                guard let self = self else { return }
                if error != nil { self.showFailure() }
            }
        } catch { pending = nil; showFailure() }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "kanturaSplat", message.frameInfo.isMainFrame,
              let payload = message.body as? [String: Any], let type = payload["type"] as? String else { return }
        switch type {
        case "ready":
            // Apply the app's explicit selection before the first scene or
            // bundled demo; the WebKit navigator language can be different.
            guard let json = try? JSONEncoder().encode(["language": MeasurementGuide.selectedLanguage]),
                  let payload = String(data: json, encoding: .utf8) else { showFailure(); return }
            webView.evaluateJavaScript("window.configureKanturaSplat(" + payload + ");") { [weak self] _, error in
                guard let self = self else { return }
                guard error == nil else { self.showFailure(); self.status.text = self.text("unavailable"); return }
                self.ready = true
                self.loadingTimeout?.cancel()
                self.importButton.isEnabled = self.pending == nil
                self.deliverIfReady()
            }
        case "error":
            showFailure()
            if payload["code"] as? String == "splatLimit" { status.text = text("tooLarge") }
            if payload["code"] as? String == "viewerUnavailable" { status.text = text("unavailable") }
        case "status":
            if payload["state"] as? String == "ready" {
                loadingTimeout?.cancel()
                importButton.isEnabled = true
                status.text = text("viewing")
            } else { status.text = text("loading") }
        default: break
        }
    }

    private func armTimeout() {
        loadingTimeout?.cancel()
        let timeout = DispatchWorkItem { [weak self] in self?.showFailure() }
        loadingTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: timeout)
    }
    private func showFailure() {
        loadingTimeout?.cancel()
        pending = nil
        importButton.isEnabled = true
        status.text = text("invalid")
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let directory = assetDirectory, let url = navigationAction.request.url,
              url.isFileURL,
              navigationAction.targetFrame?.isMainFrame == true else { decisionHandler(.cancel); return }
        let path = url.standardizedFileURL.path
        if path == directory.appendingPathComponent("THIRD-PARTY-LICENSES.txt").path {
            decisionHandler(.cancel)
            showLicenses(at: url)
        } else {
            decisionHandler(path == directory.appendingPathComponent("index.html").path ? .allow : .cancel)
        }
    }

    private func showLicenses(at url: URL) {
        guard presentedViewController == nil, let value = try? String(contentsOf: url, encoding: .utf8) else { return }
        let controller = UIViewController()
        controller.title = "MIT / BSD"
        let textView = UITextView()
        textView.text = value
        textView.isEditable = false
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(top: 20, left: 16, bottom: 20, right: 16)
        controller.view = textView
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(title: MeasurementGuide.roomText("close"), image: nil, primaryAction: UIAction { [weak controller] _ in
            controller?.dismiss(animated: true)
        }, menu: nil)
        present(UINavigationController(rootViewController: controller), animated: true)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { ready = false; showFailure() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { ready = false; showFailure() }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { ready = false; showFailure() }

    @objc private func close() {
        requestID = UUID()
        pending = nil
        loadingTimeout?.cancel()
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "kanturaSplat")
        let closed = onClose
        dismiss(animated: true) { closed?() }
    }
    deinit { loadingTimeout?.cancel() }
}

private final class WeakSplatMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
