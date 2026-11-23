import Foundation
import Network
import SwiftUI
import UIKit
import WebKit

// Serve bundled assets on loopback so WebKit's workers and offline cache get a stable origin.
final class BoardAssetServer {
    static let shared = BoardAssetServer()
    static let url = URL(string: "http://127.0.0.1:49321/")!
    private let queue = DispatchQueue(label: "vesper.board-assets")
    private var listener: NWListener?

    func open(_ completion: @escaping (Result<URL, Error>) -> Void) {
        queue.async {
            if self.listener?.state == .ready { completion(.success(Self.url)); return }
            do {
                let parameters = NWParameters.tcp
                parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 49321)
                let listener = try NWListener(using: parameters)
                self.listener = listener
                listener.newConnectionHandler = { [weak self] connection in
                    guard let self else { connection.cancel(); return }
                    connection.start(queue: self.queue)
                    self.receive(connection, request: Data())
                }
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    switch state {
                    case .ready:
                        listener?.stateUpdateHandler = nil
                        completion(.success(Self.url))
                    case .failed(let error):
                        listener?.cancel()
                        self?.listener = nil
                        completion(.failure(error))
                    default: break
                    }
                }
                listener.start(queue: self.queue)
            } catch { completion(.failure(error)) }
        }
    }

    private func receive(_ connection: NWConnection, request: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, error in
            guard let self, let data, error == nil else { connection.cancel(); return }
            let bytes = request + data
            guard bytes.count <= 16384 else { connection.cancel(); return }
            if bytes.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.respond(connection, request: bytes)
            } else if complete { connection.cancel() }
            else { self.receive(connection, request: bytes) }
        }
    }

    private func respond(_ connection: NWConnection, request: Data) {
        let firstLine = String(decoding: request, as: UTF8.self).prefix { $0 != "\r" && $0 != "\n" }
        let parts = firstLine.split(separator: " ")
        guard parts.count == 3, parts[0] == "GET" || parts[0] == "HEAD",
              let path = parts[1].split(separator: "?", maxSplits: 1).first,
              path.hasPrefix("/"), !path.contains(".."), !path.contains("%"),
              let root = Bundle.main.resourceURL?.appendingPathComponent("chess", isDirectory: true)
        else { connection.cancel(); return }
        let name = path == "/" ? "index.html" : String(path.dropFirst())
        let url = root.appendingPathComponent(name)
        let data = try? Data(contentsOf: url, options: .mappedIfSafe)
        let mime = ["html":"text/html; charset=utf-8", "js":"application/javascript",
                    "webmanifest":"application/manifest+json", "png":"image/png",
                    "zip":"application/zip"][url.pathExtension] ?? "application/octet-stream"
        let response = "HTTP/1.1 \(data == nil ? "404 Not Found" : "200 OK")\r\n" +
            "Content-Type: \(mime)\r\nContent-Length: \(data?.count ?? 0)\r\n" +
            "Cross-Origin-Opener-Policy: same-origin\r\nCross-Origin-Embedder-Policy: require-corp\r\n" +
            "Cross-Origin-Resource-Policy: same-origin\r\nConnection: close\r\n\r\n"
        let body = parts[0] == "GET" ? data ?? Data() : Data()
        connection.send(content: Data(response.utf8) + body,
                        completion: .contentProcessed { _ in connection.cancel() })
    }
}

struct BoardWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        BoardAssetServer.shared.open { [weak view] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let url): view?.load(URLRequest(url: url))
                case .failure: view?.loadHTMLString("<p>Не удалось открыть шахматную доску.</p>", baseURL: nil)
                }
            }
        }
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if url.host == BoardAssetServer.url.host || url.scheme == "about" || url.scheme == "blob" {
                decisionHandler(.allow)
            } else {
                if action.navigationType == .linkActivated && url.scheme == "https" { UIApplication.shared.open(url) }
                decisionHandler(.cancel)
            }
        }
    }
}
