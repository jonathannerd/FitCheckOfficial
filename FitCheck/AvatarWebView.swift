import SwiftUI
@preconcurrency import WebKit

struct AvatarWebView: UIViewRepresentable {
    var onAvatarSelected: (String) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.configuration.userContentController.add(context.coordinator, name: "avatarExport")
        
        if let url = URL(string: "https://readyplayer.me/avatar?frameApi&textureFormat=png") {
            print("🌐 WebView Loading URL: \(url)")
            webView.load(URLRequest(url: url))
        }
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: AvatarWebView

        init(_ parent: AvatarWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let jsScript = """
            window.addEventListener('message', (event) => {
                            if (event.data && event.data.type === "avatarExport" && typeof event.data.data === 'string') {
                                window.webkit.messageHandlers.avatarExport.postMessage(event.data.data);
                            }
                            else if (event.data && event.data.data && typeof event.data.data === 'string' && event.data.data.startsWith("https://models.readyplayer.me/")) {
                                window.webkit.messageHandlers.avatarExport.postMessage(event.data.data);
                            }
                            else if (typeof event.data === 'string' && event.data.startsWith("https://models.readyplayer.me/")) {
                                window.webkit.messageHandlers.avatarExport.postMessage(event.data);
                            }
                        }, false);
            """
            webView.evaluateJavaScript(jsScript) { result, error in
                if let error = error {
                    print("JavaScript injection error: \(error.localizedDescription)")
                } else {
                    print("JavaScript injected successfully.")
                }
            }
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "avatarExport", let avatarURL = message.body as? String {
                print("✅ Avatar URL Received via Message: \(avatarURL)")
                DispatchQueue.main.async {
                    self.parent.onAvatarSelected(avatarURL)
                }
            }
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let urlString = navigationAction.request.url?.absoluteString {
                print("🌐 WebView Loading URL: \(urlString)")
            }
            decisionHandler(.allow)
        }
    }
}
