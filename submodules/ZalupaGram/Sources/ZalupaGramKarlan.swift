import Foundation
import UIKit
import WebKit
import Display
import SwiftSignalKit
import AccountContext
import TelegramPresentationData
import OverlayStatusController
import PresentationDataUtils

// «Карлан»: zapostit.com/shevtsov in its own tab next to the chats.
// The page stays loaded while other tabs are open, cookies (and the
// Cloudflare check) are kept by the default website data store.

private let karlanHomeUrl = URL(string: "https://zapostit.com/shevtsov")!
private let karlanTabKey = "zg_karlan_tab"

public enum ZalupaGramKarlan {
    public static var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: karlanTabKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: karlanTabKey)
    }

    private static let enabledPromise = ValuePromise<Bool>(ZalupaGramKarlan.isEnabled, ignoreRepeated: true)

    public static func setEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: karlanTabKey)
        self.enabledPromise.set(value)
    }

    public static var enabledValue: Signal<Bool, NoError> {
        return self.enabledPromise.get()
    }

    static func title(_ strings: PresentationStrings) -> String {
        return zalupaGramIsRussian(strings) ? "Карлан" : "Karlan"
    }
}

private func karlanIsTelegramLink(_ url: URL) -> Bool {
    if url.scheme?.lowercased() == "tg" {
        return true
    }
    let host = url.host?.lowercased() ?? ""
    return host == "t.me" || host == "telegram.me" || host == "telegram.dog" || host.hasSuffix(".t.me")
}

private func karlanIsSameSite(_ url: URL) -> Bool {
    let host = url.host?.lowercased() ?? ""
    return host == "zapostit.com" || host.hasSuffix(".zapostit.com")
}

private func karlanIsHome(_ url: URL?) -> Bool {
    guard let url else {
        return false
    }
    let trimmed: (String) -> String = { value in
        var value = value
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }
    return trimmed(url.absoluteString) == trimmed(karlanHomeUrl.absoluteString)
}

// Same 30x30 template size as the other tab icons.
private func karlanTabIcon() -> UIImage? {
    let configuration = UIImage.SymbolConfiguration(pointSize: 22.0, weight: .medium)
    guard let symbol = UIImage(systemName: "globe", withConfiguration: configuration) else {
        return nil
    }
    let size = CGSize(width: 30.0, height: 30.0)
    let image = UIGraphicsImageRenderer(size: size).image { _ in
        let symbolSize = symbol.size
        symbol.draw(in: CGRect(
            origin: CGPoint(x: floor((size.width - symbolSize.width) / 2.0), y: floor((size.height - symbolSize.height) / 2.0)),
            size: symbolSize
        ))
    }
    return image.withRenderingMode(.alwaysTemplate)
}

private func karlanBarIcon(_ name: String) -> UIImage? {
    let configuration = UIImage.SymbolConfiguration(pointSize: 19.0, weight: .medium)
    return UIImage(systemName: name, withConfiguration: configuration)?.withRenderingMode(.alwaysTemplate)
}

public final class ZalupaGramKarlanScreen: ViewController, WKNavigationDelegate, WKUIDelegate {
    private let context: AccountContext
    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?

    private var webView: WKWebView?
    private let progressView = UIView()
    private var observations: [NSKeyValueObservation] = []
    private var karlanLayout: ContainerViewLayout?

    public init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }

        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))

        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBarStyle.style
        self.title = ZalupaGramKarlan.title(self.presentationData.strings)
        self.tabBarItem.title = ZalupaGramKarlan.title(self.presentationData.strings)
        let icon = karlanTabIcon()
        self.tabBarItem.image = icon
        self.tabBarItem.selectedImage = icon
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(image: karlanBarIcon("ellipsis.circle"), style: .plain, target: self, action: #selector(self.morePressed))

        self.scrollToTop = { [weak self] in
            self?.scrollToTopOrHome()
        }

        self.presentationDataDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            guard let self, presentationData.theme !== self.presentationData.theme else {
                return
            }
            self.presentationData = presentationData
            self.statusBar.statusBarStyle = presentationData.theme.rootController.statusBarStyle.style
            self.navigationBar?.updatePresentationData(NavigationBarPresentationData(presentationData: presentationData), transition: .immediate)
            self.applyTheme()
        })
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.presentationDataDisposable?.dispose()
        self.observations.removeAll()
    }

    override public func displayNodeDidLoad() {
        super.displayNodeDidLoad()

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: self.view.bounds, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.isOpaque = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(self.refreshPulled(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl

        self.displayNode.view.insertSubview(webView, at: 0)
        self.webView = webView

        self.progressView.alpha = 0.0
        self.displayNode.view.addSubview(self.progressView)

        self.observations.append(webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                self?.updateProgress(webView.estimatedProgress, loading: webView.isLoading)
            }
        })
        self.observations.append(webView.observe(\.canGoBack, options: [.new]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                self?.updateBackButton(webView.canGoBack)
            }
        })

        self.applyTheme()
        webView.load(URLRequest(url: karlanHomeUrl))
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.karlanLayout = layout

        guard let webView = self.webView else {
            return
        }
        let top = max(self.cleanNavigationHeight, layout.insets(options: [.statusBar]).top)
        let bottom = layout.intrinsicInsets.bottom
        if #available(iOS 26.0, *) {
            // The page goes under the glass bars, like in Safari.
            transition.updateFrame(view: webView, frame: CGRect(origin: .zero, size: layout.size))
            webView.obscuredContentInsets = UIEdgeInsets(top: top, left: layout.safeInsets.left, bottom: bottom, right: layout.safeInsets.right)
        } else {
            transition.updateFrame(view: webView, frame: CGRect(x: 0.0, y: top, width: layout.size.width, height: max(0.0, layout.size.height - top - bottom)))
        }
        self.layoutProgress(width: layout.size.width, top: top, transition: transition)
    }

    private func applyTheme() {
        let theme = self.presentationData.theme
        let background = theme.list.plainBackgroundColor
        self.displayNode.backgroundColor = background
        self.progressView.backgroundColor = theme.rootController.navigationBar.accentTextColor
        if let webView = self.webView {
            webView.backgroundColor = background
            webView.scrollView.backgroundColor = background
            // The site picks its dark or light look like the app does.
            webView.overrideUserInterfaceStyle = theme.overallDarkAppearance ? .dark : .light
        }
    }

    private var progress: Double = 0.0

    private func layoutProgress(width: CGFloat, top: CGFloat, transition: ContainedViewLayoutTransition) {
        let height: CGFloat = 2.0
        transition.updateFrame(view: self.progressView, frame: CGRect(x: 0.0, y: top, width: width * CGFloat(self.progress), height: height))
    }

    private func updateProgress(_ value: Double, loading: Bool) {
        guard let layout = self.karlanLayout else {
            return
        }
        let top = max(self.cleanNavigationHeight, layout.insets(options: [.statusBar]).top)
        if loading && value < 1.0 {
            if self.progressView.alpha == 0.0 {
                self.progress = 0.0
                self.layoutProgress(width: layout.size.width, top: top, transition: .immediate)
                self.progressView.alpha = 1.0
            }
            self.progress = max(self.progress, max(0.08, value))
            self.layoutProgress(width: layout.size.width, top: top, transition: .animated(duration: 0.2, curve: .easeInOut))
        } else {
            self.progress = 1.0
            self.layoutProgress(width: layout.size.width, top: top, transition: .animated(duration: 0.2, curve: .easeInOut))
            UIView.animate(withDuration: 0.25, delay: 0.2, options: [], animations: {
                self.progressView.alpha = 0.0
            })
        }
    }

    private func updateBackButton(_ canGoBack: Bool) {
        if canGoBack {
            if self.navigationItem.leftBarButtonItem == nil {
                self.navigationItem.setLeftBarButton(UIBarButtonItem(image: karlanBarIcon("chevron.backward"), style: .plain, target: self, action: #selector(self.backPressed)), animated: true)
            }
        } else if self.navigationItem.leftBarButtonItem != nil {
            self.navigationItem.setLeftBarButton(nil, animated: true)
        }
    }

    private func scrollToTopOrHome() {
        guard let webView = self.webView else {
            return
        }
        let scrollView = webView.scrollView
        let topOffset = -scrollView.adjustedContentInset.top
        if scrollView.contentOffset.y > topOffset + 1.0 {
            scrollView.setContentOffset(CGPoint(x: 0.0, y: topOffset), animated: true)
        } else if !karlanIsHome(webView.url) {
            webView.load(URLRequest(url: karlanHomeUrl))
        }
    }

    @objc private func backPressed() {
        self.webView?.goBack()
    }

    @objc private func refreshPulled(_ control: UIRefreshControl) {
        self.webView?.reload()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            control.endRefreshing()
        }
    }

    @objc private func morePressed() {
        let ru = zalupaGramIsRussian(self.presentationData.strings)
        let presentationData = self.presentationData
        let url = self.webView?.url ?? karlanHomeUrl
        let actionSheet = ActionSheetController(presentationData: presentationData)
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: ru ? "Обновить" : "Reload", action: { [weak self, weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    self?.webView?.reload()
                }),
                ActionSheetButtonItem(title: ru ? "На главную" : "Home", action: { [weak self, weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    self?.webView?.load(URLRequest(url: karlanHomeUrl))
                }),
                ActionSheetButtonItem(title: ru ? "Открыть в Safari" : "Open in Safari", action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    UIApplication.shared.open(url)
                }),
                ActionSheetButtonItem(title: ru ? "Скопировать ссылку" : "Copy link", action: { [weak self, weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    UIPasteboard.general.string = url.absoluteString
                    guard let self else {
                        return
                    }
                    self.present(OverlayStatusController(theme: presentationData.theme, type: .genericSuccess(ru ? "Ссылка скопирована" : "Link copied", false)), in: .window(.root))
                })
            ]),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })
            ])
        ])
        self.present(actionSheet, in: .window(.root))
    }

    private func openOutside(_ url: URL) {
        self.context.sharedContext.openExternalUrl(context: self.context, urlContext: .generic, url: url.absoluteString, forceExternal: false, presentationData: self.presentationData, navigationController: self.navigationController as? NavigationController, dismissInput: { [weak self] in
            self?.view.endEditing(true)
        })
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        let scheme = url.scheme?.lowercased() ?? ""
        if karlanIsTelegramLink(url) {
            // Channels and chats open right in the app.
            decisionHandler(.cancel)
            self.openOutside(url)
        } else if !["http", "https", "about", "data", "blob"].contains(scheme) {
            decisionHandler(.cancel)
            UIApplication.shared.open(url)
        } else {
            decisionHandler(.allow)
        }
    }

    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Links with target="_blank": the site itself stays in the tab,
        // other sites open the way Telegram opens links.
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            if karlanIsSameSite(url) {
                webView.load(navigationAction.request)
            } else if karlanIsTelegramLink(url) || ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                self.openOutside(url)
            }
        }
        return nil
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.updateProgress(1.0, loading: false)
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.updateProgress(1.0, loading: false)
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.updateProgress(1.0, loading: false)
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}
