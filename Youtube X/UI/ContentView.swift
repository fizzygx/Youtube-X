//
//  ContentView.swift
//  Youtube X
//
//  Created by fizzyg on 30/4/26.
//

import SwiftUI
import WebKit
import AppKit
import Combine
import AVKit
import CoreMedia

// MARK: - URL Extension (YouTube detection)
extension URL {
    var isYouTube: Bool {
        host?.contains("youtube.com") == true || host?.contains("youtu.be") == true
    }
}
/// Presents the native macOS share sheet for a local file
func presentShareSheet(for url: URL) {
    guard let window = NSApp.keyWindow, let contentView = window.contentView else { return }
    let picker = NSSharingServicePicker(items: [url])
    picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
}

// MARK: - Notifications
extension Notification.Name {
    static let navigateToOffline = Notification.Name("navigateToOffline")
}

// MARK: - Subscription Model
struct SubscriptionChannel: Identifiable, Codable {
    var id = UUID()
    let channelId: String
    let name: String
    let avatarURL: String
    let hasNewContent: Bool
    let notificationCount: Int
}

// MARK: - WebView Store
class WebViewStore: NSObject, ObservableObject {
    let webView: WKWebView
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var currentURL: URL?
    @Published var isLoading = false
    @Published var estimatedProgress: Double = 0
    @Published var pageTitle: String = "New Tab"
    @Published var isOnVideoPage = false
    @Published var isOnShortsPage = false
    @Published var videoTitle = ""
    @Published var notificationCount: Int = 0
    @Published var accountAvatarURL: String = ""
    @Published var subscriptionsList: [SubscriptionChannel] = []
    @Published var isPlaying: Bool = false
    @Published var isMiniplayerActive: Bool = false
    @Published var canDownload = false
    @Published var currentlyPlayingTitle: String = ""
    @Published var showCurrentlyPlaying: Bool = false
    @Published var nowPlayingVideoId: String? = nil
    @Published var suppressNextNowPlayingClear = false
    @Published var suppressHomeNavigation = false

    private var cancellables = Set<AnyCancellable>()
    private var adSkipTimer: Timer?
    private var playCheckTimer: Timer?
    private var subscriptionsRetryCount = 0
    private var lastVideoTitle: String = ""

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let preferences = WKWebpagePreferences(); preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.configuration.preferences.isElementFullscreenEnabled = true
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        setupObservers()
        loadAdBlocker()
        installAdBlockCSSLayer()
        injectPiPHelper()
        loadURL("https://www.youtube.com")
        adSkipTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.webView.evaluateJavaScript("window.ytxSkip&&window.ytxSkip()")
        }
        playCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkPlaying()
        }
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refreshNotificationsAndAvatar()
        }
    }

    deinit { adSkipTimer?.invalidate(); playCheckTimer?.invalidate() }

    private func setupObservers() {
        webView.publisher(for: \.canGoBack).assign(to: &$canGoBack)
        webView.publisher(for: \.canGoForward).assign(to: &$canGoForward)
        webView.publisher(for: \.estimatedProgress).assign(to: &$estimatedProgress)

        webView.publisher(for: \.url)
            .sink { [weak self] url in
                guard let self = self, let url = url else {
                    self?.canDownload = false
                    return
                }
                let path = url.path
                if path == "/watch" || (path.hasPrefix("/shorts/") && path != "/shorts") {
                    self.canDownload = true
                } else {
                    self.canDownload = false
                }
                self.currentURL = url
            }
            .store(in: &cancellables)

        ThemeManager.shared.$currentTheme.sink { [weak self] _ in self?.injectThemeCSS() }.store(in: &cancellables)
        webView.publisher(for: \.url).sink { [weak self] _ in self?.checkIfVideoPage() }.store(in: &cancellables)
    }

    func loadAdBlocker() {
        guard let customPath = Bundle.main.path(forResource: "adblocker", ofType: "json"),
              let customJSON = try? String(contentsOfFile: customPath, encoding: .utf8) else {
            print("[AdBlock] adblocker.json not found in bundle - network-level ad blocking is INACTIVE.")
            return
        }
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "CustomBlockList",
            encodedContentRuleList: customJSON
        ) { [weak self] ruleList, error in
            guard let self = self else { return }
            if let ruleList = ruleList {
                self.webView.configuration.userContentController.add(ruleList)
                print("[AdBlock] Rule list compiled and active.")
            } else if let error = error {
                print("[AdBlock] FAILED to compile rule list - ad blocking is INACTIVE: \(error.localizedDescription)")
            }
        }
    }
/// Second, faster layer on top of the network-level rule list and the reactive JS remover below: a CSS rule injected at document-start hides
/// known ad containers the instant they're parsed, before they ever get a chance to paint. Registered once as a WKUserScript rather than
/// re-injected via evaluateJavaScript on every navigation, so it applies automatically to every page load (including SPA soft-navigations)
/// with zero extra work per navigation.
    func installAdBlockCSSLayer() {
        let css = """
        .ytd-display-ad-renderer,.ytp-ad-module,.video-ads,#masthead-ad,#player-ads,
        .ytd-banner-promo-renderer,.ytd-statement-banner-renderer,ytd-promoted-video-renderer,
        .ytd-in-feed-ad-layout-renderer,.ytp-ad-image-overlay,.ytp-ad-text-overlay,
        .ytd-compact-promoted-video-renderer,.ytd-action-companion-ad-renderer,
        ytd-ad-slot-renderer,ytd-search-pyv-renderer,.ytp-ad-overlay-container,
        .ytp-ad-progress-list,.ytp-ad-player-overlay-instream-info,ytd-merch-shelf-renderer,
        ytd-primetime-promo-renderer,yt-mealbar-promo-renderer,
        ytd-companion-slot-renderer,#player-ads-container,.ytp-ad-skip-button-container,
        ytd-reel-shelf-renderer[is-ad],ytd-video-masthead-ad-v3-renderer,
        ytd-ad-inline-playback-meta-block,#panels ytd-ad-slot-renderer
        { display: none !important; }
        """
        let escaped = css.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "`", with: "\\`")
        let js = """
        (function(){
            var s = document.createElement('style');
            s.id = 'ytx-adblock-css';
            s.textContent = `\(escaped)`;
            (document.head || document.documentElement).appendChild(s);
        })();
        """
        let script = WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        webView.configuration.userContentController.addUserScript(script)
    }

    // MARK: - SponsorBlock
    /// Tracks which video the currently-injected segments belong to, so a fetch that completes after the user has already navigated elsewhere gets discarded instead of injected onto the wrong page.
    private var sponsorBlockVideoId: String?
    /// Called whenever a video/Shorts page is detected. Fetches segments from cache if available) only when the video actually changed, and no-ops entirely if SponsorBlock is off.
    func maybeApplySponsorBlock() {
        guard SponsorBlockManager.shared.isEnabled, let videoId = currentVideoId, !videoId.isEmpty else { return }
        guard videoId != sponsorBlockVideoId else { return }
        sponsorBlockVideoId = videoId
        SponsorBlockManager.shared.segments(for: videoId) { [weak self] segments in
            guard let self = self else { return }
            // Discard if the person already navigated to a different video
            // before this fetch completed
            guard self.currentVideoId == videoId else { return }
            self.injectSponsorBlockSkipper(segments: segments)
        }
    }
    /// Re-checks the current video against SponsorBlock - used when the toggle is switched on mid-playback, since maybeApplySponsorBlock() otherwise only fires on navigation.
    func refreshSponsorBlockForCurrentVideo() {
        sponsorBlockVideoId = nil
        if isOnVideoPage || isOnShortsPage {
            maybeApplySponsorBlock()
        }
    }

    private func injectSponsorBlockSkipper(segments: [SponsorSegment]) {
        guard !segments.isEmpty, let segmentsJSON = try? JSONEncoder().encode(segments),
              let segmentsString = String(data: segmentsJSON, encoding: .utf8) else {
            // No segments for this video (or fetch failed) - clear any
            // stale segments left over from a previous video on this page(DOnt touh it)
            webView.evaluateJavaScript("window.__ytxSponsorSegments = [];")
            return
        }
        let showNotice = SponsorBlockManager.shared.showSkipNotice
        let js = """
        (function(){
            window.__ytxSponsorSegments = \(segmentsString);
            window.__ytxSponsorShowNotice = \(showNotice);

            function showNotice(category) {
                if (!window.__ytxSponsorShowNotice) return;
                var el = document.getElementById('ytx-sponsor-notice');
                if (!el) {
                    el = document.createElement('div');
                    el.id = 'ytx-sponsor-notice';
                    el.style.cssText = 'position:fixed;top:70px;right:20px;background:rgba(24,24,24,0.92);' +
                        'color:#fff;padding:8px 14px;border-radius:10px;' +
                        'font:600 13px -apple-system,BlinkMacSystemFont,sans-serif;z-index:2147483647;' +
                        'opacity:0;transform:translateY(-4px);transition:opacity .25s ease,transform .25s ease;' +
                        'pointer-events:none;box-shadow:0 4px 14px rgba(0,0,0,0.35)';
                    document.body.appendChild(el);
                }
                var label = category.charAt(0).toUpperCase() + category.slice(1).replace('promo', '-Promo');
                el.textContent = 'Skipped ' + label;
                el.style.opacity = '1';
                el.style.transform = 'translateY(0)';
                clearTimeout(window.__ytxSponsorNoticeTimer);
                window.__ytxSponsorNoticeTimer = setTimeout(function(){
                    el.style.opacity = '0';
                    el.style.transform = 'translateY(-4px)';
                }, 1800);
            }

            if (window.__ytxSponsorInterval) { clearInterval(window.__ytxSponsorInterval); }
            window.__ytxSponsorInterval = setInterval(function() {
                var v = document.querySelector('video');
                if (!v || v.paused) return;
                var t = v.currentTime;
                var segs = window.__ytxSponsorSegments || [];
                for (var i = 0; i < segs.length; i++) {
                    var s = segs[i].segment;
                    if (t >= s[0] && t < s[1] - 0.3) {
                        v.currentTime = s[1];
                        showNotice(segs[i].category);
                        break;
                    }
                }
            }, 300);
        })();
        """
        webView.evaluateJavaScript(js)
    }

    func injectThemeCSS() {
        let palette = ThemeManager.shared.palette
        let bg = palette.webBackground; let surface = palette.webSurface
        let css = """
            :root{--yt-spec-brand-background-primary:\(bg)!important;--yt-spec-brand-background-secondary:\(surface)!important;--yt-spec-general-background-a:\(bg)!important;--yt-spec-general-background-b:\(surface)!important;--yt-spec-general-background-c:\(surface)!important;--yt-spec-base-background:\(bg)!important}
            html,body,ytd-app,ytd-browse,ytd-watch,ytd-watch-flexy,ytd-two-column-browse-results-renderer,ytd-rich-grid-renderer,#content,#page-manager,#primary,#secondary,#columns,.style-scope.ytd-app,.style-scope.ytd-browse,ytd-page-manager,tp-yt-app-drawer,ytd-masthead{background:\(bg)!important;background-color:\(bg)!important}
            #masthead-container,ytd-masthead{display:none!important}
        """
        webView.evaluateJavaScript("(function(){var o=document.getElementById('ytx-theme');if(o)o.remove();var s=document.createElement('style');s.id='ytx-theme';s.textContent='\(css.replacingOccurrences(of: "'", with: "\\'"))';document.head.appendChild(s)})();", completionHandler: nil)
    }

    func injectAdHider() {
        webView.evaluateJavaScript("""
            (function() {
                const selectors = [
                    '.ytd-display-ad-renderer','.ytp-ad-module','.video-ads',
                    '#masthead-ad','#player-ads','.ytd-banner-promo-renderer',
                    '.ytd-statement-banner-renderer','ytd-promoted-video-renderer',
                    '.ytd-in-feed-ad-layout-renderer','ytd-rich-item-renderer:has(ytd-display-ad-renderer)',
                    '.ytp-ad-image-overlay','.ytp-ad-text-overlay',
                    '.ytd-compact-promoted-video-renderer','.ytd-action-companion-ad-renderer',
                    'tp-yt-paper-dialog','ytd-engagement-panel-section-list-renderer[target-id="engagement-panel-ads"]',
                    'ytd-ad-slot-renderer','ytd-search-pyv-renderer',
                    '.ytp-ad-overlay-container','.ytp-ad-progress-list','.ytp-ad-player-overlay-instream-info',
                    'ytd-merch-shelf-renderer','ytd-primetime-promo-renderer',
                    'yt-mealbar-promo-renderer','ytd-popup-container:has(ytd-mealbar-promo-renderer)'
                ];

                function isInsideProtectedContainer(el) {
                    let node = el;
                    while (node) {
                        if (node.getAttribute && (node.getAttribute('aria-label') === 'Google Account' ||
                            node.getAttribute('aria-label') === 'Notifications')) return true;
                        if (node.id && (node.id === 'account-menu' || node.id === 'notification-menu')) return true;
                        if (node.classList && (node.classList.contains('ytd-multi-page-menu-renderer') ||
                            node.classList.contains('ytd-notification-topbar-button-renderer'))) return true;
                        if (node.tagName === 'YTD-NOTIFICATION-TOP-BUTTON-RENDERER') return true;
                        node = node.parentElement;
                    }
                    return false;
                }

                function removeAds() {
                    selectors.forEach(s => {
                        document.querySelectorAll(s).forEach(el => {
                            if (isInsideProtectedContainer(el)) return;
                            el.remove();
                        });
                    });
                }

                removeAds();
                let pending = false;
                const observer = new MutationObserver(function() {
                    if (pending) return;
                    pending = true;
                    requestAnimationFrame(function() { pending = false; removeAds(); });
                });
                observer.observe(document.body, { childList: true, subtree: true });
            })();
        """)
    }

    func injectAdSkipper() {
        let js = """
        (function() {
            try {
                Object.defineProperty(window, 'ytInitialPlayerResponse', {
                    get: function() { return this._ytInitialPlayerResponse; },
                    set: function(value) {
                        if (value && value.adPlacements) { value.adPlacements = []; }
                        if (value && value.playerAds) { value.playerAds = []; }
                        this._ytInitialPlayerResponse = value;
                    },
                    configurable: true
                });
            } catch(e) {}
            try {
                Object.defineProperty(window, 'ytcfg', {
                    get: function() { return this._ytcfg; },
                    set: function(v) {
                        if (v?.data_?.playerResponse?.adPlacements) { v.data_.playerResponse.adPlacements = []; }
                        this._ytcfg = v;
                    },
                    configurable: true
                });
            } catch(e) {}

            window.ytxSkip = function() {
                var b = document.querySelector('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button');
                if (b) {
                    b.style.cssText = 'display:block!important;visibility:visible!important;opacity:1!important;pointer-events:auto!important';
                    b.click();
                }
                var p = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
                if (p && typeof p.skipVideoAd === 'function') { p.skipVideoAd(); }
                if (window.yt && window.yt.player && window.yt.player.getPlayerByElement) {
                    var e = document.querySelector('.html5-video-player');
                    if (e) {
                        var pl = window.yt.player.getPlayerByElement(e);
                        if (pl && typeof pl.skipVideoAd === 'function') pl.skipVideoAd();
                    }
                }
                document.querySelectorAll('video').forEach(function(v) {
                    if (v.src.includes('&oad=')) v.currentTime = v.duration || 0;
                });
                var adBadge = document.querySelector('.ytp-ad-badge, .ytp-ad-preview-container');
                if (adBadge) adBadge.remove();
            };

            var video = document.querySelector('video');
            if (video) {
                setInterval(function() {
                    if (document.querySelector('.ad-showing, .ytp-ad-player-overlay')) {
                        video.muted = true;
                        video.playbackRate = 16;
                    } else {
                        video.muted = false;
                        video.playbackRate = 1;
                    }
                }, 500);
            }

            window.ytxSkip();
            if (window.ytxSkipInterval) { clearInterval(window.ytxSkipInterval); }
            window.ytxSkipInterval = setInterval(window.ytxSkip, 200);
        })();
        """
        webView.evaluateJavaScript(js)
    }

    func injectPiPHelper() {
        let js = """
        (function(){window.YoutubeX=window.YoutubeX||{};window.YoutubeX.togglePip=function(){function g(){var vs=document.querySelectorAll('video');for(var i=0;i<vs.length;i++)if(vs[i].src||vs[i].srcObject)return vs[i];return null}var v=g();if(!v)return false;if(document.pictureInPictureElement===v)document.exitPictureInPicture();else v.requestPictureInPicture();return true}})();
        """
        webView.evaluateJavaScript(js)
    }

    func checkIfVideoPage(retriesLeft: Int = 5) {
        let js = """
        (function() {
            const path = window.location.pathname;
            const isWatch = path === '/watch';
            const isShorts = path.startsWith('/shorts/') && path !== '/shorts' && path.split('/').filter(x=>x).length >= 2;

            let title = '';
            if (isWatch) {
                const titleEl = document.querySelector('h1 yt-formatted-string, h1.style-scope.ytd-watch-metadata yt-formatted-string');
                if (titleEl) title = titleEl.textContent.trim();
            } else if (isShorts) {
                const titleEl = document.querySelector(
                    'ytd-shorts-player h1, ytd-shorts-player .title, ytd-shorts-player yt-formatted-string, ' +
                    'ytd-reel-video-renderer h1, ytd-reel-video-renderer .title, ' +
                    'h1.ytd-shorts-player, .ytd-shorts-player h1'
                );
                if (titleEl) title = titleEl.textContent.trim();
            }
            if (!title) {
                // document.title is literally "YouTube" (not yet updated after
                // a fresh navigation, e.g. on a slow/interrupted load) until the
                // page finishes rendering - treat that as "not resolved yet"
                // rather than a real title, so callers can retry instead of
                // displaying the placeholder.
                const dt = document.title.replace(' - YouTube', '').trim();
                title = (dt && dt !== 'YouTube') ? dt : '';
            }
            return JSON.stringify({isVideo: isWatch, isShorts: isShorts, title: title});
        })();
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self = self else { return }
            if let jsonString = result as? String,
               let data = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let isVideo = json["isVideo"] as? Bool ?? false
                let isShorts = json["isShorts"] as? Bool ?? false
                let title = json["title"] as? String ?? ""
                self.isOnVideoPage = isVideo
                self.isOnShortsPage = isShorts

                if isVideo || isShorts {
                    self.maybeApplySponsorBlock()
                    if !title.isEmpty {
                        self.videoTitle = title
                        self.lastVideoTitle = title
                        WatchHistoryManager.shared.add(url: self.webView.url?.absoluteString ?? "", title: title)
                    } else if retriesLeft > 0 {
                        // Title not resolved yet (slow load / DOM not ready) -
                        // retry shortly rather than showing a placeholder.
                        // self.videoTitle deliberately isn't touched here, so
                        // it keeps whatever it last held until this resolves.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                            self?.checkIfVideoPage(retriesLeft: retriesLeft - 1)
                        }
                    }
                } else {
                    self.videoTitle = self.webView.url?.host ?? "New Tab"
                }
                self.pageTitle = self.videoTitle
            }
        }
    }

    func refreshNotificationsAndAvatar() {
        webView.evaluateJavaScript("""
            (function() {
                const bell = document.querySelector('button[aria-label="Notifications"]');
                if (!bell) return 0;
                const countEl = bell.querySelector('.yt-spec-icon-badge-shape__badge-count');
                return countEl ? parseInt(countEl.textContent) || 0 : 0;
            })();
        """) { [weak self] result, _ in
            if let count = result as? Int { self?.notificationCount = count }
        }
        webView.evaluateJavaScript("""
            (function() {
                const avatarImg = document.querySelector('#buttons ytd-topbar-account-button-renderer img');
                return avatarImg ? avatarImg.src : '';
            })();
        """) { [weak self] result, _ in
            if let url = result as? String { self?.accountAvatarURL = url }
        }
    }

    func fetchSubscriptions() {
        let js = """
        (function() {
            function scrape() {
                const items = [];
                const seen = new Set();
                const entries = document.querySelectorAll(
                    'ytd-guide-entry-renderer, ytd-mini-guide-entry-renderer, #items ytd-guide-entry-renderer'
                );
                entries.forEach(el => {
                    const link = el.querySelector('a#endpoint, a');
                    const href = link ? (link.getAttribute('href') || '') : '';
                    if (!href.startsWith('/channel/') && !href.startsWith('/@')) return;
                    const img = el.querySelector('img');
                    let avatar = '';
                    if (img) { avatar = img.getAttribute('src') || img.getAttribute('data-thumb') || ''; }
                    const nameEl = el.querySelector('#endpoint yt-formatted-string, .title, yt-formatted-string');
                    const name = nameEl ? nameEl.textContent.trim() : '';
                    if (!name || seen.has(name)) return;
                    seen.add(name);
                    const countEl = el.querySelector('.notification-badge, #notification-badge');
                    const count = countEl ? (parseInt(countEl.textContent) || 0) : 0;
                    items.push({
                        channelId: href,
                        name: name,
                        avatarURL: avatar,
                        hasNewContent: count > 0,
                        notificationCount: count
                    });
                });
                return items;
            }

            let items = scrape();
            if (items.length > 0) return JSON.stringify(items);

            const guideBtn = document.querySelector(
                'button[aria-label="Guide"], #guide-button button, ytd-topbar-menu-button-renderer button'
            );
            if (guideBtn) { guideBtn.click(); guideBtn.click(); }
            items = scrape();
            return JSON.stringify(items);
        })();
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self = self else { return }
            if let json = result as? String,
               let data = json.data(using: .utf8),
               let items = try? JSONDecoder().decode([SubscriptionChannel].self, from: data),
               !items.isEmpty {
                DispatchQueue.main.async {
                    self.subscriptionsList = items
                    self.subscriptionsRetryCount = 0
                }
            } else {
                if self.subscriptionsRetryCount < 5 {
                    self.subscriptionsRetryCount += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                        self?.fetchSubscriptions()
                    }
                } else {
                    self.subscriptionsRetryCount = 0
                }
            }
        }
    }

    func checkPlaying() {
        let js = """
        (function(){
            const v = document.querySelector('video');
            const playing = !!(v && !v.paused && !v.ended);
            const mini = !!document.querySelector('ytd-miniplayer[active], ytd-miniplayer.active-mode');
            return {playing: playing, mini: mini};
        })();
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self = self, let dict = result as? [String: Any] else { return }
            if let playing = dict["playing"] as? Bool { self.isPlaying = playing }
            if let mini = dict["mini"] as? Bool { self.isMiniplayerActive = mini }
            if self.isPlaying && (self.isOnVideoPage || self.isOnShortsPage) && UserDefaults.standard.object(forKey: "showNowPlaying") as? Bool ?? true {
                let title = self.videoTitle.isEmpty ? "Playing" : self.videoTitle
                if self.currentlyPlayingTitle != title {
                    self.currentlyPlayingTitle = title
                    self.nowPlayingVideoId = self.currentVideoId
                }
                self.showCurrentlyPlaying = true
            }
        }
    }

    func clearNowPlaying() {
        showCurrentlyPlaying = false
        currentlyPlayingTitle = ""
        nowPlayingVideoId = nil
    }

    func loadURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        webView.load(URLRequest(url: url))
    }

    func softNavigate(to urlString: String) {
        guard let url = URL(string: urlString) else { return }
        if currentURL?.absoluteString == urlString { return }
        let escaped = urlString.replacingOccurrences(of: "'", with: "\\'")
        func proceed() {
            let js = """
            (function(){
                try {
                    var a = document.createElement('a');
                    a.href = '\(escaped)';
                    a.style.display = 'none';
                    document.body.appendChild(a);
                    a.click();
                    document.body.removeChild(a);
                    return true;
                } catch(e) { return false; }
            })();
            """
            self.webView.evaluateJavaScript(js) { result, _ in
                let handled = (result as? Bool) ?? false
                if handled {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        self.currentURL = url
                        self.checkIfVideoPage()
                        self.refreshNotificationsAndAvatar()
                        self.injectThemeCSS()
                    }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.webView.evaluateJavaScript(js) { retryResult, _ in
                            if (retryResult as? Bool) == true {
                                self.currentURL = url
                                self.checkIfVideoPage()
                                self.refreshNotificationsAndAvatar()
                                self.injectThemeCSS()
                            }
                        }
                    }
                }
            }
        }
        guard ThemeManager.shared.autoPiP, isPlaying, !isMiniplayerActive else {
            proceed()
            return
        }
        pressMiniplayerShortcut()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { proceed() }
    }

    func pauseVideo() { webView.evaluateJavaScript("document.querySelector('video')?.pause();") }

    func pressMiniplayerShortcut() {
        webView.evaluateJavaScript("""
            (function(){
                function fire(type) {
                    var evt = new KeyboardEvent(type, {
                        key: 'i', code: 'KeyI', keyCode: 73, which: 73,
                        bubbles: true, cancelable: true
                    });
                    (document.activeElement || document.body).dispatchEvent(evt);
                }
                fire('keydown');
                fire('keyup');
            })();
        """)
        isMiniplayerActive.toggle()
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }

    func clickNotificationsButton() { webView.evaluateJavaScript("document.querySelector('button[aria-label=\"Notifications\"]')?.click()") }
    func clickAccountButton() {
        refreshNotificationsAndAvatar()
        webView.evaluateJavaScript("""
            (function() {
                const btn = document.querySelector('#buttons ytd-topbar-account-button-renderer button') ||
                            document.querySelector('button[aria-label=\"Google Account\"]');
                if (btn) btn.click();
                else {
                    const avatar = document.querySelector('#buttons ytd-topbar-account-button-renderer');
                    if (avatar) avatar.click();
                }
            })();
        """)
    }

    var currentVideoId: String? {
        guard let url = currentURL else { return nil }
        let id = extractVideoId(from: url)
        return id.isEmpty ? nil : id
    }

    var isPlaylistContext: Bool {
        guard let comps = currentURL.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) else { return false }
        return comps.queryItems?.contains { $0.name == "list" && !($0.value ?? "").isEmpty } ?? false
    }

    func fetchPlaylistInfo(completion: @escaping (_ playlistURL: String?, _ title: String?) -> Void) {
        guard let comps = currentURL.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }),
              let listId = comps.queryItems?.first(where: { $0.name == "list" })?.value, !listId.isEmpty else {
            completion(nil, nil); return
        }
        let playlistURL = "https://www.youtube.com/playlist?list=\(listId)"
        webView.evaluateJavaScript("""
            (function(){
                var el = document.querySelector(
                    'ytd-playlist-panel-renderer #playlist-title, yt-formatted-string.ytd-playlist-panel-renderer, ytd-playlist-header-renderer #title'
                );
                var text = el ? el.textContent.trim() : '';
                return text || document.title.replace(' - YouTube', '') || 'Playlist';
            })();
        """) { result, _ in
            let title = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            completion(playlistURL, (title?.isEmpty ?? true) ? "Playlist" : title)
        }
    }

    func setQuality(_ quality: String) {
        let js = """
        (function() {
            const player = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
            if (!player) return;
            const levels = player.getAvailableQualityLevels();
            let target = levels.find(l => l === '\(quality)');
            if (!target) target = 'auto';
            player.setPlaybackQualityRange(target);
            player.setPlaybackQuality(target);
        })();
        """
        webView.evaluateJavaScript(js)
    }

    func extractVideoId(from url: URL) -> String {
        if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let v = comps.queryItems?.first(where: { $0.name == "v" })?.value { return v }
        let path = url.path
        if path.hasPrefix("/shorts/") { return path.components(separatedBy: "/").last ?? "" }
        return ""
    }
}

// MARK: - WKNavigationDelegate & WKUIDelegate
extension WebViewStore: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        currentURL = webView.url; isLoading = false
        injectThemeCSS(); injectAdSkipper(); injectAdHider(); checkIfVideoPage()
        refreshNotificationsAndAvatar()
        checkPlaying()
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { isLoading = true }
}

extension WebViewStore: WKUIDelegate {
    func webView(_ w: WKWebView, createWebViewWith c: WKWebViewConfiguration, for a: WKNavigationAction, wf: WKWindowFeatures) -> WKWebView? {
        if a.targetFrame == nil { w.load(a.request) }; return nil
    }
}

// MARK: - WebView Container
struct WebViewContainer: NSViewRepresentable {
    let webViewStore: WebViewStore
    func makeNSView(context: Context) -> WKWebView {
        let wv = webViewStore.webView
        wv.navigationDelegate = webViewStore
        wv.uiDelegate = webViewStore
        wv.publisher(for: \.estimatedProgress)
            .sink { [weak webViewStore] v in DispatchQueue.main.async { webViewStore?.estimatedProgress = v } }
            .store(in: &context.coordinator.cancellables)
        ThemeManager.shared.$currentTheme
            .sink { _ in webViewStore.injectThemeCSS() }
            .store(in: &context.coordinator.cancellables)
        return wv
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator: NSObject { var cancellables = Set<AnyCancellable>() }
}

// MARK: - Player Manager (shared AVPlayer)
class PlayerManager: ObservableObject {
    static let shared = PlayerManager()
    let player = AVPlayer()
    @Published var currentVideoURL: URL?
    @Published var playlist: [URL] = []
    @Published var isShuffled = false
    @Published var isRepeating = false

    @Published var offlineNowPlayingTitle: String = ""
    @Published var isOfflinePlaying: Bool = false
    /// True while the current item is a Short being browsed in the offline
    /// Shorts tab - makes it loop itself on end instead of advancing to the next item in the general playlist.
    @Published var isLoopingCurrentItem: Bool = false
    /// True whenever the Offline or Downloads pane has its Shorts tab active. Read by KeyboardShortcuts' global monitor so Up/Down can navigate Shorts regardless of which specific control currently holds keyboard focus -
    /// SwiftUI's .onMoveCommand only fires when the List itself is first responder, which stops working the moment focus moves to the playing video.
    @Published var isBrowsingShorts: Bool = false

    var currentIndex: Int {
        guard let url = currentVideoURL else { return 0 }
        return playlist.firstIndex(of: url) ?? 0
    }

    func play(url: URL, playlist: [URL] = []) {
        currentVideoURL = url
        self.playlist = playlist
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.play()
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(itemDidEnd), name: .AVPlayerItemDidPlayToEndTime, object: player.currentItem)
    }

    @objc private func itemDidEnd() {
        if isLoopingCurrentItem {
            player.seek(to: .zero)
            player.play()
            return
        }
        if isRepeating { player.seek(to: .zero); player.play(); return }
        let nextIndex: Int = isShuffled ? Int.random(in: 0..<playlist.count) : currentIndex + 1
        if nextIndex < playlist.count { play(url: playlist[nextIndex], playlist: playlist) }
    }
    func togglePlayPause() {
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
    }
    /// Advances to the next item in the current playlist, if any.
    func playNext() {
        guard !playlist.isEmpty else { return }
        let nextIndex = isShuffled ? Int.random(in: 0..<playlist.count) : currentIndex + 1
        guard nextIndex < playlist.count else { return }
        play(url: playlist[nextIndex], playlist: playlist)
    }
    /// Goes back to the previous item in the current playlist, if any.
    func playPrevious() {
        guard !playlist.isEmpty else { return }
        let prevIndex = currentIndex - 1
        guard prevIndex >= 0 else { return }
        play(url: playlist[prevIndex], playlist: playlist)
    }
    func seek(bySeconds seconds: Double) {
        let current = player.currentTime()
        let target = CMTimeAdd(current, CMTime(seconds: seconds, preferredTimescale: 600))
        player.seek(to: target)
    }
    func toggleShuffle() { isShuffled.toggle() }
    func toggleRepeat() { isRepeating.toggle() }
    func movePlaylist(from source: IndexSet, to destination: Int) { playlist.move(fromOffsets: source, toOffset: destination) }
    /// Removes items from the queue without touching the files on disk this only affects what's queued, not the downloaded file itself.
    func removeFromPlaylist(at offsets: IndexSet) {
        let removingCurrent = offsets.contains(currentIndex)
    /// Captured before removal: currentIndex recomputes to 0 once currentVideoURL no longer exists in the array, which would
    /// otherwise always jump to the first track instead of whatever now sits where the removed item was before.
        let fallbackIndex = offsets.min() ?? 0
        playlist.remove(atOffsets: offsets)
        if removingCurrent {
            if playlist.isEmpty {
                stopOfflinePlayback()
            } else {
                let nextIndex = min(fallbackIndex, playlist.count - 1)
                play(url: playlist[nextIndex], playlist: playlist)
            }
        }
    }
    /// Adds files to the queue, picked from the in-app browser instead of Finder.
    func addToPlaylist(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        playlist.append(contentsOf: urls)
        if currentVideoURL == nil {
            play(url: urls[0], playlist: playlist)
        }
    }

    func savePlaylist(name: String) {
        let playlistsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            .appendingPathComponent("YouTube X Downloads/Playlists")
        try? FileManager.default.createDirectory(at: playlistsDir, withIntermediateDirectories: true)
        let fileURL = playlistsDir.appendingPathComponent("\(name).json")
        let urls = playlist.map { $0.absoluteString }
        if let data = try? JSONEncoder().encode(urls) { try? data.write(to: fileURL) }
    }

    func loadPlaylist(from url: URL) {
        guard let data = try? Data(contentsOf: url),
              let urls = try? JSONDecoder().decode([String].self, from: data) else { return }
        let playlistURLs = urls.compactMap { URL(string: $0) }
        if let first = playlistURLs.first { play(url: first, playlist: playlistURLs) }
    }

    func stopOfflinePlayback() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        offlineNowPlayingTitle = ""
        isOfflinePlaying = false
    }
}

// MARK: - Sidebar (separate Now Playing sections)
struct Sidebar: View {
    @Binding var selection: String?
    @EnvironmentObject var webViewStore: WebViewStore
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var playerManager = PlayerManager.shared
    @ObservedObject private var networkMonitor = NetworkMonitor.shared

    var body: some View {
        List(selection: $selection) {
            Section {
                HStack(spacing: 8) {
                    if let nsImage = NSApplication.shared.applicationIconImage {
                        Image(nsImage: nsImage).resizable().frame(width: 20, height: 20)
                    }
                    Text("YouTube X").font(.system(size: 15, weight: .semibold)).foregroundColor(Color.ytTextPrimary)
                    Spacer()
                }
                .listRowSeparator(.hidden).padding(.vertical, 2)
            }

            // YouTube Now Playing
            if webViewStore.showCurrentlyPlaying {
                Section {
                    NowPlayingRow(
                        title: webViewStore.currentlyPlayingTitle,
                        onTap: {
                            webViewStore.suppressNextNowPlayingClear = true
                            webViewStore.suppressHomeNavigation = true
                            selection = "home"
                        },
                        onDismiss: { webViewStore.clearNowPlaying() }
                    )
                } header: {
                    Text("Now Playing")
                }
            }

            // Offline Now Playing
            if playerManager.isOfflinePlaying {
                Section {
                    NowPlayingRow(
                        title: playerManager.offlineNowPlayingTitle,
                        onTap: {
                            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "miniplayer" }) {
                                window.makeKeyAndOrderFront(nil)
                            }
                        },
                        onDismiss: {
                            playerManager.stopOfflinePlayback()
                            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "miniplayer" }) {
                                window.close()
                            }
                        }
                    )
                } header: {
                    Text("YouTube X Now Playing")
                }
            }

            Section {
                Label("Home", systemImage: "house").tag("home")
                Label("Shorts", systemImage: "play.rectangle").tag("shorts")
                Label("Subscriptions", systemImage: "rectangle.stack.badge.person.crop").tag("subscriptions")
            }

            Section("Explore") {
                Label("Trending", systemImage: "flame").tag("trending")
                Label("Live", systemImage: "antenna.radiowaves.left.and.right").tag("live")
                Label("Gaming", systemImage: "gamecontroller").tag("gaming")
                Label("Music", systemImage: "music.note").tag("music")
                Label("News", systemImage: "newspaper").tag("news")
                Label("Sport", systemImage: "sportscourt").tag("sport")
                Label("Learning", systemImage: "book").tag("learning")
                Label("Fashion", systemImage: "tshirt").tag("fashion")
                Label("Memberships", systemImage: "person.crop.rectangle.stack").tag("memberships")
            }

            Section("Library") {
                Label("History", systemImage: "clock").tag("history")
                Label("Watch Later", systemImage: "bookmark").tag("watchlater")
                Label("Liked Videos", systemImage: "heart").tag("liked")
                Label("Playlists", systemImage: "list.bullet").tag("playlists")
            }

            Section {
                HStack {
                    Label("Downloads", systemImage: "arrow.down.circle")
                    if !networkMonitor.isConnected {
                        PulsingPlayIndicator()
                            .scaleEffect(0.7)
                            .help("Available offline")
                    }
                    Spacer()
                    if downloadManager.unseenCount > 0 {
                        Text("\(downloadManager.unseenCount)")
                            .font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Color.ytRed))
                    }
                }
                .tag("downloads")
                HStack {
                    Label("Offline Downloads", systemImage: "tray.and.arrow.down")
                    if !networkMonitor.isConnected {
                        PulsingPlayIndicator()
                            .scaleEffect(0.7)
                            .help("Available offline")
                    }
                    Spacer()
                }
                .tag("offline")
            }
        }
        .listStyle(.sidebar)
    }
}

private struct PulsingPlayIndicator: View {
    @State private var pulsing = false
    var body: some View {
        Image(systemName: "play.circle.fill")
            .foregroundColor(Color.ytRed)
            .scaleEffect(pulsing ? 1.15 : 0.9)
            .opacity(pulsing ? 1.0 : 0.6)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
    }
}

/// Shared row for both sidebar Now Playing sections the dismiss (x) only appears on hover instead of sitting there permanently while media plays because it was getting in the way of the initial title texts.
private struct NowPlayingRow: View {
    let title: String
    let onTap: () -> Void
    let onDismiss: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack {
            Button(action: onTap) {
                HStack {
                    PulsingPlayIndicator()
                    Text(title)
                        .lineLimit(1)
                        .foregroundColor(Color.ytTextPrimary)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            if hovering {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color.ytTextSecondary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
    }
}

// MARK: - Main ContentView
struct ContentView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var webViewStore: WebViewStore
    @StateObject private var downloadManager = DownloadManager.shared
    @StateObject private var watchHistory = WatchHistoryManager.shared
    @StateObject private var playerManager = PlayerManager.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @Environment(\.openWindow) var openWindow

    @State private var navigationSelection: String? = "home"
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var isInFullScreen = false
    @State private var previousSelection: String? = nil
    @State private var showSearch = false
    @State private var searchQuery = ""
    @State private var showOptionsPopover = false
    @State private var showAudioFormatPopover = false
    @State private var showPlaylistPrompt = false
    @State private var showDownloadsPopover = false
    @State private var pendingIsAudio = false
    @State private var pendingQuality: VideoQuality = .auto
    @State private var pendingAudioFormat: AudioFormat = .m4a
    @State private var capturedVideoTitle = ""          // Title grabbed at download click

    private let urlMap: [String: String] = [
        "home": "https://www.youtube.com",
        "shorts": "https://www.youtube.com/shorts",
        "subscriptions": "https://www.youtube.com/feed/subscriptions",
        "trending": "https://www.youtube.com/feed/trending",
        "live": "https://www.youtube.com/live",
        "gaming": "https://www.youtube.com/gaming",
        "music": "https://www.youtube.com/music",
        "news": "https://www.youtube.com/news",
        "sport": "https://www.youtube.com/sport",
        "learning": "https://www.youtube.com/learning",
        "fashion": "https://www.youtube.com/fashion",
        "memberships": "https://www.youtube.com/memberships",
        "history": "https://www.youtube.com/feed/history",
        "watchlater": "https://www.youtube.com/playlist?list=WL",
        "liked": "https://www.youtube.com/playlist?list=LL",
        "playlists": "https://www.youtube.com/feed/playlists"
    ]

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            Sidebar(selection: $navigationSelection)
                .frame(minWidth: 200)
        } detail: {
            detailView
        }
        .background(Color.ytDarkBackground)
        .toolbar { toolbarContent }
        .toolbar(isInFullScreen ? .hidden : .visible, for: .windowToolbar)
        .onAppear {
            KeyboardShortcuts.setup()
            YtDlpUpdater.shared.checkForUpdateIfNeeded()
            FfmpegUpdater.shared.checkForUpdateIfNeeded()

    /// Standard NSWindow fullscreen notifications rather than guessing at behavior differences between macOS versions -
    /// these are stable, documented APIs and fire consistently regardless of whether fullscreen was triggered by the green
    /// button, Cmd+Ctrl+F, or our own toggleFullScreen() call, on every macOS version that supports windowed fullscreen at all.
            NotificationCenter.default.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: nil, queue: .main) { _ in
                isInFullScreen = true
            }
            NotificationCenter.default.addObserver(forName: NSWindow.didExitFullScreenNotification, object: nil, queue: .main) { _ in
                isInFullScreen = false
            }
        }
        .onChange(of: navigationSelection) { newValue in
            guard let newValue = newValue else { return }

            let wasOfflinePanel = (previousSelection == "downloads" || previousSelection == "offline")
            let leavingOfflinePanel = wasOfflinePanel && (newValue != "downloads" && newValue != "offline")
            if leavingOfflinePanel, playerManager.player.timeControlStatus == .playing {
                openWindow(id: "miniplayer")
            }

            if newValue == "shorts" { webViewStore.pauseVideo() }

            if newValue.hasPrefix("subscription_") {
                if let channel = webViewStore.subscriptionsList.first(where: { "subscription_\($0.channelId)" == newValue }) {
                    webViewStore.softNavigate(to: "https://www.youtube.com\(channel.channelId)")
                }
            } else if newValue == "home" {
                // --- Home‑specific logic (runs BEFORE the generic else-if) ---
                if webViewStore.suppressNextNowPlayingClear {
                    webViewStore.suppressNextNowPlayingClear = false
                } else {
                    webViewStore.clearNowPlaying()
                }

                if webViewStore.suppressHomeNavigation {
                    webViewStore.suppressHomeNavigation = false
                    // Do NOT navigate – just switch the tab
                } else if let targetURL = urlMap[newValue] {
                    webViewStore.softNavigate(to: targetURL)
                }
            } else if let targetURL = urlMap[newValue] {
                webViewStore.softNavigate(to: targetURL)
            }

            if newValue == "downloads" { downloadManager.clearUnseenBadge() }

            previousSelection = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToHome)) { _ in navigationSelection = "home" }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSubscriptions)) { _ in navigationSelection = "subscriptions" }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToLibrary)) { _ in navigationSelection = "playlists" }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToDownloads)) { _ in navigationSelection = "downloads" }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToOffline)) { _ in navigationSelection = "offline" }
        .onReceive(NotificationCenter.default.publisher(for: .toggleCommandPalette)) { _ in withAnimation { showSearch.toggle() } }
        .onReceive(NotificationCenter.default.publisher(for: .toggleFullScreen)) { _ in
            if let window = NSApplication.shared.mainWindow { window.toggleFullScreen(nil) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mediaKeyPlayPause)) { _ in
            if isLocalPlayerActive {
                playerManager.togglePlayPause()
            } else {
                webViewStore.webView.evaluateJavaScript("(function(){const v=document.querySelector('video');if(v)v.paused?v.play():v.pause()})();")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mediaKeySkipForward)) { _ in
            if isLocalPlayerActive {
                playerManager.seek(bySeconds: 10)
            } else {
                webViewStore.webView.evaluateJavaScript("document.querySelector('video')?.currentTime+=10")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mediaKeySkipBackward)) { _ in
            if isLocalPlayerActive {
                playerManager.seek(bySeconds: -10)
            } else {
                webViewStore.webView.evaluateJavaScript("document.querySelector('video')?.currentTime-=10")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .autoPiP)) { _ in webViewStore.pressMiniplayerShortcut() }
        .alert("This video is part of a playlist", isPresented: $showPlaylistPrompt) {
            Button("Just This Video") { startSingleDownload(isAudio: pendingIsAudio, quality: pendingQuality, audioFormat: pendingAudioFormat) }
            Button("Entire Playlist") {
                webViewStore.fetchPlaylistInfo { playlistURL, title in
                    guard let playlistURL = playlistURL else { return }
                    downloadManager.startPlaylistDownload(playlistURL: playlistURL, title: title ?? "Playlist", isAudio: pendingIsAudio, quality: pendingQuality, audioFormat: pendingAudioFormat)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Download just this video, or the whole playlist into its own folder?") }
    }

    // MARK: - Download helpers (with instant title capture)
    private func captureTitle(retriesLeft: Int = 4, then handler: @escaping (String) -> Void) {
        let js = """
        (function() {
            var titleEl = document.querySelector('h1 yt-formatted-string, h1.style-scope.ytd-watch-metadata yt-formatted-string');
            if (titleEl && titleEl.textContent.trim()) return titleEl.textContent.trim();
            titleEl = document.querySelector('ytd-shorts-player h1, ytd-shorts-player .title');
            if (titleEl && titleEl.textContent.trim()) return titleEl.textContent.trim();
            // document.title is literally "YouTube" until the page finishes
            // rendering after a fresh navigation - don't return that as if it
            // were a real title.
            var dt = document.title.replace(' - YouTube', '').trim();
            return (dt && dt !== 'YouTube') ? dt : '';
        })();
        """
        webViewStore.webView.evaluateJavaScript(js) { [self] result, _ in
            let title = (result as? String) ?? ""
            if !title.isEmpty {
                handler(title)
            } else if retriesLeft > 0 {
        /// Slow load / network hiccup - the title element hasn't rendered yet or lag. Retry briefly rather than downloading with a placeholder name like [ (14) Youtube ] honestly.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    self.captureTitle(retriesLeft: retriesLeft - 1, then: handler)
                }
            } else {
        /// Genuinely couldn't resolve a title after retrying - fall back to whatever the general page tracker last had, which
        /// is more likely to be a real title than a bare placeholder.
                let fallback = webViewStore.videoTitle
                handler(fallback.isEmpty || fallback == "YouTube" ? "Video" : fallback)
            }
        }
    }

    private func beginDownload(isAudio: Bool, quality: VideoQuality, audioFormat: AudioFormat) {
        pendingIsAudio = isAudio
        pendingQuality = quality
        pendingAudioFormat = audioFormat
        if webViewStore.isPlaylistContext {
            showPlaylistPrompt = true
        } else {
            startSingleDownload(isAudio: isAudio, quality: quality, audioFormat: audioFormat)
        }
    }

    private func startSingleDownload(isAudio: Bool, quality: VideoQuality, audioFormat: AudioFormat) {
        let videoId = webViewStore.currentVideoId ?? (webViewStore.currentURL.flatMap { extractVideoIdDirectly(from: $0) })
        guard let videoId = videoId else {
            let alert = NSAlert(); alert.messageText = "Cannot Start Download"; alert.informativeText = "Make sure you are on a YouTube watch or shorts page."; alert.runModal(); return
        }
        let mediaType: MediaType = webViewStore.isOnShortsPage ? .shorts : .videos
        let title = capturedVideoTitle.isEmpty ? (isAudio ? "Audio" : "Video") : capturedVideoTitle
        if isAudio {
            downloadManager.addAudioDownload(videoId: videoId, title: title, mediaType: .audio, format: audioFormat)
        } else {
            let video = YouTubeVideo(videoId: videoId, title: title, thumbnailURL: "", channelName: "", channelAvatarURL: nil, viewCount: "", publishedAt: "", duration: "", mediaType: mediaType)
            downloadManager.addDownload(video: video, quality: quality)
        }
        capturedVideoTitle = ""
    }

    private func handleVideoDownload() {
        captureTitle { title in
            capturedVideoTitle = title
            beginDownload(isAudio: false, quality: .auto, audioFormat: .m4a)
        }
    }

    private func handleAudioDownload() {
        captureTitle { title in
            capturedVideoTitle = title
            showAudioFormatPopover = true
        }
    }

    private func extractVideoIdDirectly(from url: URL) -> String? {
        if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false), let v = comps.queryItems?.first(where: { $0.name == "v" })?.value { return v }
        let path = url.path
        if path.hasPrefix("/shorts/") { return path.components(separatedBy: "/").last }
        return nil
    }

    private var detailView: some View {
        ZStack {
    /// Full takeover only once there's nothing left buffering/playing to interrupt flag the connection issue quietly instead.
            if showWebView && !networkMonitor.isConnected && !webViewStore.showCurrentlyPlaying {
                OfflineStateView(
                    onRetry: { webViewStore.reload() },
                    onGoToOfflineDownloads: { navigationSelection = "offline" }
                )
            } else {
                WebViewContainer(webViewStore: webViewStore)
                    .opacity(showWebView ? 1 : 0).allowsHitTesting(showWebView)

                if showWebView && !networkMonitor.isConnected && webViewStore.showCurrentlyPlaying {
                    OfflineBadgeView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            if navigationSelection == "downloads" { DownloadsDetailView() }
            else if navigationSelection == "offline" { OfflineDetailView() }
        }
    }

    private var showWebView: Bool { navigationSelection != "downloads" && navigationSelection != "offline" }
    private var isMiniplayerWindowFocused: Bool {
        NSApp.keyWindow?.identifier?.rawValue == "miniplayer"
    }

    private var isLocalPlayerActive: Bool {
        isMiniplayerWindowFocused || navigationSelection == "offline" || navigationSelection == "downloads"
    }

    private var isSidebarVisible: Bool { sidebarVisibility != .detailOnly }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button(action: { webViewStore.goBack() }) { Image(systemName: "chevron.left") }.disabled(!webViewStore.canGoBack)
            Button(action: { webViewStore.goForward() }) { Image(systemName: "chevron.right") }.disabled(!webViewStore.canGoForward)
            Button(action: { webViewStore.reload() }) { Image(systemName: "arrow.clockwise") }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if showSearch {
                TextField("Search YouTube", text: $searchQuery).textFieldStyle(.roundedBorder).frame(width: 200)
                    .onSubmit {
                        if !searchQuery.isEmpty {
                            let encoded = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                            webViewStore.softNavigate(to: "https://www.youtube.com/results?search_query=\(encoded)")
                            showSearch = false; searchQuery = ""
                        }
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            Button(action: { withAnimation { showSearch.toggle() } }) { Image(systemName: "magnifyingglass") }.help("Search")

            Button(action: { handleVideoDownload() }) {
                Image(systemName: "arrow.down.circle.fill").resizable().aspectRatio(contentMode: .fit).frame(width: 18, height: 18)
            }
            .disabled(!webViewStore.canDownload).help("Download video")

            Button(action: { handleAudioDownload() }) {
                Image(systemName: "waveform.circle.fill").resizable().aspectRatio(contentMode: .fit).frame(width: 18, height: 18)
            }
            .disabled(!webViewStore.canDownload).help("Download audio only")
            .popover(isPresented: $showAudioFormatPopover) {
                DownloadAudioFormatPopover { format in
                    showAudioFormatPopover = false
                    beginDownload(isAudio: true, quality: .auto, audioFormat: format)
                }
            }

            ShareButton(url: webViewStore.currentURL ?? webViewStore.webView.url).id(webViewStore.currentURL).frame(width: 26, height: 22).help("Share")

            Button(action: { webViewStore.pressMiniplayerShortcut() }) { Image(systemName: "pip.enter") }.help("Toggle Miniplayer (i)")

            Button(action: { showDownloadsPopover.toggle() }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "arrow.down.circle")
                    if downloadManager.unseenCount > 0 {
                        Text("\(downloadManager.unseenCount)").font(.system(size: 8, weight: .bold)).foregroundColor(.white).padding(3).background(Circle().fill(Color.red)).offset(x: 6, y: -6)
                    }
                }
            }
            .popover(isPresented: $showDownloadsPopover) { DownloadsPopoverView() }
            .help("Downloads")

            // YouTube Now Playing in toolbar (when sidebar hidden)
            if webViewStore.showCurrentlyPlaying && !isSidebarVisible {
                Button(action: {
                    if let videoId = webViewStore.nowPlayingVideoId {
                        webViewStore.softNavigate(to: "https://www.youtube.com/watch?v=\(videoId)")
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.circle.fill").font(.system(size: 12))
                        Text(webViewStore.currentlyPlayingTitle)
                            .lineLimit(1).truncationMode(.tail).frame(maxWidth: 120)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.ytRed.opacity(0.2)))
                }
                .buttonStyle(.plain)
                .help("Now Playing – click to return to video")
            }

            // Offline Now Playing in toolbar (when sidebar hidden)
            if playerManager.isOfflinePlaying && !isSidebarVisible {
                Button(action: {
                    if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "miniplayer" }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.circle.fill").font(.system(size: 12))
                        Text(playerManager.offlineNowPlayingTitle)
                            .lineLimit(1).truncationMode(.tail).frame(maxWidth: 120)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.ytRed.opacity(0.2)))
                }
                .buttonStyle(.plain)
                .help("YouTube X Now Playing – click to show player")
            }

            Button(action: { showOptionsPopover.toggle() }) { Image(systemName: "ellipsis.circle") }
            .popover(isPresented: $showOptionsPopover) { OptionsPopover() }
            .help("More options")
        }
    }
}

// MARK: - Downloads Popover View (Safari‑style, with trash)
struct DownloadsPopoverView: View {
    @ObservedObject private var manager = DownloadManager.shared
    @State private var showClearConfirmation = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if manager.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 28))
                        .foregroundColor(Color.ytTextSecondary)
                    Text("No Downloads")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.ytTextSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(manager.items.sorted(by: { $0.addedDate > $1.addedDate }).prefix(6)) { item in
                            DownloadPopoverRow(item: item)
                            if item.id != manager.items.sorted(by: { $0.addedDate > $1.addedDate }).prefix(6).last?.id {
                                Divider().padding(.leading, 46)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 280)
            }
            Divider()
            footer
        }
        .frame(width: 300)
        .background(Color.ytSurfaceGray)
    }

    private var header: some View {
        HStack {
            Text("Downloads")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.ytTextPrimary)
            Spacer()
            if manager.items.contains(where: { $0.status == .completed }) {
                Button("Clear") { showClearConfirmation = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(Color.ytRed)
                    .confirmationDialog("Clear completed downloads?", isPresented: $showClearConfirmation) {
                        Button("Clear Completed", role: .destructive) {
                            manager.removeCompletedTasks()
                            manager.clearUnseenBadge()
                        }
                        Button("Cancel", role: .cancel) {}
                    }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        Button(action: { NotificationCenter.default.post(name: .navigateToDownloads, object: nil) }) {
            HStack {
                Text("Show All Downloads")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(Color.ytTextSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

private struct DownloadPopoverRow: View {
    let item: DownloadItem
    @ObservedObject private var manager = DownloadManager.shared
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            DownloadProgressRing(progress: item.progress, status: item.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.ytTextPrimary)
                    .lineLimit(1)
                Text(statusText)
                    .font(.system(size: 10.5))
                    .foregroundColor(statusColor)
            }
            Spacer(minLength: 4)
            if hovering || item.status == .failed {
                HStack(spacing: 6) {
                    trailingAction
                    Button(action: { manager.removeDownload(id: item.id) }) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(Color.ytTextSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Delete download")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var trailingAction: some View {
        switch item.status {
        case .completed:
            Button(action: {
                if let url = item.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }) {
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color.ytTextSecondary)
            }
            .buttonStyle(.plain)
            .help("Show in Finder")
        case .failed:
            Button(action: { manager.retry(id: item.id) }) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color.ytRed)
            }
            .buttonStyle(.plain)
            .help("Retry")
        default:
            Button(action: { manager.cancelDownload(id: item.id) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color.ytTextSecondary)
            }
            .buttonStyle(.plain)
            .help("Cancel")
        }
    }

    private var statusText: String {
        switch item.status {
        case .downloading: return "\(Int(item.progress * 100))%"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .queued: return "Waiting…"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .completed: return .green
        case .failed: return .red
        default: return Color.ytTextSecondary
        }
    }
}

private struct DownloadProgressRing: View {
    let progress: Double
    let status: DownloadStatus
    var body: some View {
        ZStack {
            Circle().stroke(Color.ytTextSecondary.opacity(0.25), lineWidth: 2.5)
            if status == .downloading || status == .queued {
                Circle()
                    .trim(from: 0, to: max(progress, 0.02))
                    .stroke(Color.ytRed, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.2), value: progress)
            }
            switch status {
            case .completed:
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundColor(.green)
            case .failed:
                Image(systemName: "exclamationmark").font(.system(size: 10, weight: .bold)).foregroundColor(.red)
            default: EmptyView()
            }
        }
        .frame(width: 22, height: 22)
    }
}
// MARK: - Options Popover
struct OptionsPopover: View {
    @EnvironmentObject var webViewStore: WebViewStore
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var watchHistory = WatchHistoryManager.shared
    @ObservedObject private var appUpdateChecker = AppUpdateChecker.shared
    @ObservedObject private var sponsorBlock = SponsorBlockManager.shared
    @State private var showThemeMenu = false
    @State private var showSponsorCategoryMenu = false

    var body: some View {
        VStack(spacing: 0) {
            Text("Options")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.ytTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            Divider()

            VStack(alignment: .leading, spacing: 0) {
                Group {
                    sectionLabel("Playback")
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle(isOn: $themeManager.autoPiP) { Label("Auto PiP", systemImage: "pip.enter") }
                        Text("Auto-trigger YouTube's miniplayer when you switch tabs")
                            .font(.caption2)
                            .foregroundColor(Color.ytTextSecondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    Toggle(isOn: $themeManager.incognitoMode) { Label("Incognito", systemImage: "theatermasks") }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                }

                Divider().padding(.vertical, 4)

                Group {
                    sectionLabel("Appearance")
                    DownloadOptionRow(
                        title: "Theme",
                        subtitle: themeManager.currentTheme == .system ? "System (\(themeManager.resolvedTheme.rawValue))" : themeManager.currentTheme.rawValue,
                        systemImage: "paintpalette.fill",
                        isSelected: false
                    ) { showThemeMenu = true }
                    .popover(isPresented: $showThemeMenu) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(AppTheme.allCases, id: \.self) { theme in
                                DownloadOptionRow(
                                    title: theme.rawValue,
                                    subtitle: nil,
                                    systemImage: theme == .system ? "circle.righthalf.filled" : "circle.fill",
                                    isSelected: themeManager.currentTheme == theme
                                ) {
                                    themeManager.currentTheme = theme
                                    showThemeMenu = false
                                }
                            }
                        }
                        .padding(.vertical, 6)
                        .frame(width: 200)
                    }
                }

                Divider().padding(.vertical, 4)

                Group {
                    sectionLabel("Maintenance")
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle(isOn: $sponsorBlock.isEnabled) { Label("SponsorBlock Auto-Skip", systemImage: "forward.fill") }
                            .onChange(of: sponsorBlock.isEnabled) { _ in webViewStore.refreshSponsorBlockForCurrentVideo() }
                        Text("Automatically skips sponsor segments using community-submitted data")
                            .font(.caption2)
                            .foregroundColor(Color.ytTextSecondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    if sponsorBlock.isEnabled {
                        DownloadOptionRow(
                            title: "Categories",
                            subtitle: "\(sponsorBlock.enabledCategories.count) of \(SponsorBlockManager.allCategories.count) selected",
                            systemImage: "slider.horizontal.3",
                            isSelected: false
                        ) { showSponsorCategoryMenu = true }
                        .popover(isPresented: $showSponsorCategoryMenu) {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(SponsorBlockManager.allCategories, id: \.id) { category in
                                    let isOn = sponsorBlock.enabledCategories.contains(category.id)
                                    DownloadOptionRow(title: category.label, subtitle: nil, systemImage: isOn ? "checkmark.circle.fill" : "circle", isSelected: false) {
                                        var current = sponsorBlock.enabledCategories
                                        if isOn { current.remove(category.id) } else { current.insert(category.id) }
                                        sponsorBlock.enabledCategories = current
                                        webViewStore.refreshSponsorBlockForCurrentVideo()
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                            .frame(width: 220)
                        }
                    }
                    if appUpdateChecker.updateAvailable {
                        DownloadOptionRow(
                            title: "Update Available",
                            subtitle: appUpdateChecker.latestVersion,
                            systemImage: "arrow.up.circle.fill",
                            isSelected: false
                        ) { NSWorkspace.shared.open(appUpdateChecker.releasesURL) }
                    }
                    DownloadOptionRow(title: "Check for Updates", subtitle: nil, systemImage: "arrow.triangle.2.circlepath", isSelected: false) {
                        YtDlpUpdater.shared.checkForUpdateIfNeeded(manual: true)
                        FfmpegUpdater.shared.checkForUpdateIfNeeded(manual: true)
                        appUpdateChecker.check()
                    }
                    DownloadOptionRow(title: "Open Downloads Folder", subtitle: nil, systemImage: "folder.fill", isSelected: false) {
                        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                            NSWorkspace.shared.open(downloads.appendingPathComponent("YouTube X Downloads"))
                        }
                    }
                    DownloadOptionRow(title: "Clear History", subtitle: nil, systemImage: "clock.arrow.circlepath", isSelected: false) {
                        WatchHistoryManager.shared.clear()
                    }
                    DownloadOptionRow(title: "Clear Cache", subtitle: nil, systemImage: "trash.fill", isSelected: false) {
                        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: Date(timeIntervalSince1970: 0)) {}
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .frame(width: 260)
        .background(Color.ytSurfaceGray)
        .onAppear { appUpdateChecker.checkIfNeeded() }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundColor(Color.ytTextSecondary)
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }
}

// MARK: - Download popovers (Audio only)
private struct DownloadOptionRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 20)
                    .foregroundColor(Color.ytRed)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    if let subtitle = subtitle {
                        Text(subtitle).font(.system(size: 11)).foregroundColor(Color.ytTextSecondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundColor(Color.ytRed)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Color.ytSurfaceGray.opacity(0.6) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct DownloadAudioFormatPopover: View {
    let onSelect: (AudioFormat) -> Void
    private let subtitles: [AudioFormat: String] = [
        .m4a: "Best quality, smaller size",
        .mp3: "Most compatible",
        .flac: "Lossless, largest size",
        .aac: "High efficiency"
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Audio Format").font(.system(size: 11, weight: .semibold)).foregroundColor(Color.ytTextSecondary)
                .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 2)
            ForEach(AudioFormat.allCases) { format in
                DownloadOptionRow(title: format.rawValue, subtitle: subtitles[format], systemImage: "waveform", isSelected: false) {
                    onSelect(format)
                }
            }
        }
        .padding(.vertical, 6)
        .frame(width: 220)
    }
}

// MARK: - Native macOS Share Button
struct ShareButton: NSViewRepresentable {
    let url: URL?

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: .zero)
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Share")
        button.target = context.coordinator
        button.action = #selector(Coordinator.share(_:))
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.url = url
        nsView.isEnabled = url != nil
    }

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, NSSharingServicePickerDelegate {
        var url: URL?
        init(url: URL?) { self.url = url }

        @objc func share(_ sender: NSButton) {
            guard let url = url else { return }
            let picker = NSSharingServicePicker(items: [url])
            picker.delegate = self
            picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }

        func sharingServicePicker(
            _ sharingServicePicker: NSSharingServicePicker,
            sharingServicesForItems items: [Any],
            proposedSharingServices proposedServices: [NSSharingService]
        ) -> [NSSharingService] {
            guard let url = items.first as? URL else { return proposedServices }
            let copyLink = NSSharingService(
                title: "Copy Link",
                image: NSImage(systemSymbolName: "link", accessibilityDescription: nil) ?? NSImage(),
                alternateImage: NSImage(systemSymbolName: "link", accessibilityDescription: nil) ?? NSImage(),
                handler: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
            )
            return [copyLink] + proposedServices
        }
    }
}

// MARK: - Apple-TV-style shared card chrome
private struct TVPlayButton: View {
    let action: () -> Void
    var size: CGFloat = 30
    var body: some View {
        Button(action: action) {
            Image(systemName: "play.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundColor(.black)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white))
        }
        .buttonStyle(.plain)
    }
}

enum TVMenuEntry {
    case item(title: String, destructive: Bool, action: () -> Void)
    case separator
    static func item(title: String, action: @escaping () -> Void) -> TVMenuEntry {
        .item(title: title, destructive: false, action: action)
    }
}

private struct TVMenuButton: View {
    let entries: [TVMenuEntry]
    var size: CGFloat = 28
    init(size: CGFloat = 28, @TVMenuBuilder entries: () -> [TVMenuEntry]) {
        self.size = size
        self.entries = entries()
    }
    var body: some View {
        TVMenuButtonRepresentable(entries: entries, size: size)
            .frame(width: size, height: size)
    }
}

@resultBuilder
enum TVMenuBuilder {
    static func buildBlock(_ components: [TVMenuEntry]...) -> [TVMenuEntry] { components.flatMap { $0 } }
    static func buildExpression(_ expression: TVMenuEntry) -> [TVMenuEntry] { [expression] }
    static func buildExpression(_ expression: [TVMenuEntry]) -> [TVMenuEntry] { expression }
    static func buildOptional(_ component: [TVMenuEntry]?) -> [TVMenuEntry] { component ?? [] }
    static func buildEither(first component: [TVMenuEntry]) -> [TVMenuEntry] { component }
    static func buildEither(second component: [TVMenuEntry]) -> [TVMenuEntry] { component }
}

private struct TVMenuButtonRepresentable: NSViewRepresentable {
    let entries: [TVMenuEntry]
    let size: CGFloat

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: size, height: size))
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More")
        button.image?.isTemplate = true
        button.contentTintColor = .white
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        button.layer?.cornerRadius = size / 2
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.entries = entries
        button.layer?.cornerRadius = size / 2
    }

    func makeCoordinator() -> Coordinator { Coordinator(entries: entries) }

    final class Coordinator: NSObject {
        var entries: [TVMenuEntry]
        init(entries: [TVMenuEntry]) { self.entries = entries }

        @objc func showMenu(_ sender: NSButton) {
            let menu = NSMenu()
            for entry in entries {
                switch entry {
                case .separator: menu.addItem(.separator())
                case .item(let title, let destructive, let action):
                    let menuItem = NSMenuItem(title: title, action: #selector(runAction(_:)), keyEquivalent: "")
                    menuItem.target = self
                    menuItem.representedObject = action
                    if destructive {
                        menuItem.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.systemRed])
                    }
                    menu.addItem(menuItem)
                }
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
        }

        @objc private func runAction(_ sender: NSMenuItem) {
            (sender.representedObject as? () -> Void)?()
        }
    }
}

// MARK: - Downloads Detail View
struct DownloadsDetailView: View {
    @ObservedObject private var manager = DownloadManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @StateObject private var playerManager = PlayerManager.shared
    @State private var mediaType: MediaType = .videos
    @State private var category: DownloadCategory = .all
    @State private var sideWidth: CGFloat = 360
    @State private var selectedIndex: Int?

    enum DownloadCategory: String, CaseIterable { case all = "All", downloading = "Downloading", finished = "Finished", queued = "Queued" }

    var body: some View {
        HStack(spacing: 0) {
            leftPanel
            divider
            rightPanel
        }
        .background(Color.ytDarkBackground)
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("Clear Completed") { manager.removeCompletedTasks() } } }
        .navigationTitle("Downloads")
        .onAppear {
            playerManager.isBrowsingShorts = (mediaType == .shorts)
        }
        .onDisappear {
            playerManager.isBrowsingShorts = false
        }
        .onChange(of: mediaType) { newValue in
            playerManager.isBrowsingShorts = (newValue == .shorts)
        }
        .onChange(of: playerManager.currentVideoURL) { newURL in
            guard let newURL = newURL else { return }
            if let idx = filteredItems.firstIndex(where: { $0.fileURL == newURL }) {
                selectedIndex = idx
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .shortsNavigateDown)) { _ in
            guard mediaType == .shorts else { return }
            let items = filteredItems.filter { $0.fileURL != nil }
            guard !items.isEmpty else { return }
            let current = selectedIndex ?? -1
            let next = min(current + 1, items.count - 1)
            selectedIndex = next
            if let url = items[next].fileURL {
                playerManager.isLoopingCurrentItem = true
                playerManager.play(url: url, playlist: items.compactMap { $0.fileURL })
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .shortsNavigateUp)) { _ in
            guard mediaType == .shorts else { return }
            let items = filteredItems.filter { $0.fileURL != nil }
            guard !items.isEmpty else { return }
            let current = selectedIndex ?? 0
            let previous = max(current - 1, 0)
            selectedIndex = previous
            if let url = items[previous].fileURL {
                playerManager.isLoopingCurrentItem = true
                playerManager.play(url: url, playlist: items.compactMap { $0.fileURL })
            }
        }
    }

    private var leftPanel: some View {
        VStack(spacing: 0) {
            Picker("Type", selection: $mediaType) {
                ForEach(MediaType.allCases, id: \.self) { type in Text(type.rawValue).tag(type) }
            }
            .pickerStyle(.segmented).padding()
            Picker("Category", selection: $category) { ForEach(DownloadCategory.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            .pickerStyle(.segmented).padding(.horizontal)
            if filteredItems.isEmpty {
                Spacer(); Text("No \(category.rawValue) \(mediaType.rawValue)").foregroundColor(Color.ytTextSecondary); Spacer()
            } else {
                downloadList
            }
        }
        .frame(width: sideWidth)
    }

    private var downloadList: some View {
        List(selection: $selectedIndex) {
            ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                DownloadItemRow(item: item, isSelected: selectedIndex == index,
                                onPlay: {
                                    guard let url = item.fileURL else { return }
                                    if item.mediaType == .playlists {
                                        NSWorkspace.shared.open(url)
                                        return
                                    }
                                    let playlist = filteredItems.compactMap { $0.fileURL }
                                    playerManager.play(url: url, playlist: playlist)
                                    selectedIndex = index
                                },
                                onDelete: { manager.removeDownload(id: item.id) })
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .contextMenu { contextMenu(for: item) }
            }
        }
        .listStyle(.plain)
        .onMoveCommand { direction in
            guard let current = selectedIndex else { return }
            switch direction {
            case .down: selectedIndex = min(current + 1, filteredItems.count - 1)
            case .up: selectedIndex = max(current - 1, 0)
            default: break
            }
        }
    }

    private func contextMenu(for item: DownloadItem) -> some View {
        Group {
            if let url = item.fileURL {
                Button("Share") { presentShareSheet(for: url) }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                Button("Copy URL") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.absoluteString, forType: .string) }
                Divider()
            }
            Button("Delete", role: .destructive) { manager.removeDownload(id: item.id) }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.ytDivider.opacity(0.3))
            .frame(width: 10)
            .overlay(Image(systemName: "line.3.horizontal").font(.caption).foregroundColor(Color.ytTextSecondary))
            .gesture(DragGesture().onChanged { v in sideWidth = max(250, min(sideWidth + v.translation.width, 600)) })
            .onHover { hover in hover ? NSCursor.resizeLeftRight.push() : NSCursor.pop() }
    }

    @ViewBuilder
    private var rightPanel: some View {
        if let selectedItem = selectedItem, selectedItem.mediaType == .playlists {
            Rectangle().fill(Color.ytDarkBackground)
                .overlay(
                    VStack(spacing: 12) {
                        Image(systemName: "folder.fill").font(.system(size: 48)).foregroundColor(Color.ytTextSecondary)
                        Text(selectedItem.title).foregroundColor(Color.ytTextPrimary)
                        if let url = selectedItem.fileURL { Button("Open in Finder") { NSWorkspace.shared.open(url) } }
                    }
                )
        } else if let selectedURL = selectedFileURL {
            if playerManager.currentVideoURL == selectedURL {
                PlayerViewWithControls(playerManager: playerManager)
            } else {
                ZStack {
                    ThumbnailOrIcon(url: selectedURL).frame(height: 200)
                    Button(action: {
                        let playlist = filteredItems.compactMap { $0.fileURL }
                        playerManager.play(url: selectedURL, playlist: playlist)
                    }) {
                        Image(systemName: "play.circle.fill").font(.system(size: 60)).foregroundColor(.white).shadow(radius: 2)
                    }
                    .buttonStyle(.plain)
                }
                .overlay(
                    Text(selectedURL.lastPathComponent as String)
                        .foregroundColor(Color.ytTextPrimary).padding(.top, 220),
                    alignment: .bottom
                )
            }
        } else {
            Rectangle().fill(Color.ytDarkBackground).overlay(Text("Select a video to preview").foregroundColor(Color.ytTextSecondary))
        }
    }

    private var selectedItem: DownloadItem? {
        guard let index = selectedIndex, index < filteredItems.count else { return nil }
        return filteredItems[index]
    }
    private var selectedFileURL: URL? {
        guard let index = selectedIndex, index < filteredItems.count else { return nil }
        return filteredItems[index].fileURL
    }
    private var filteredItems: [DownloadItem] {
        let base = manager.items.filter { $0.mediaType == mediaType }
        switch category {
        case .downloading: return base.filter { $0.status == .downloading }
        case .finished: return base.filter { $0.status == .completed }
        case .queued: return base.filter { $0.status == .queued }
        case .all: return base
        }
    }
}

// Style card row for downloads
private struct DownloadItemRow: View {
    let item: DownloadItem
    let isSelected: Bool
    let onPlay: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.ytSurfaceGray.opacity(0.6))
                    .frame(width: 96, height: 54)
                    .overlay(Image(systemName: "play.rectangle.fill").foregroundColor(Color.ytTextSecondary))
                if item.status == .completed {
                    TVPlayButton(action: onPlay, size: 26).padding(4).opacity(hovering ? 1 : 0)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).lineLimit(1).font(.system(size: 13, weight: .medium)).foregroundColor(Color.ytTextPrimary)
                statusView
            }
            Spacer()
            if case .failed = item.status {
                Button("Retry") { DownloadManager.shared.retry(id: item.id) }.buttonStyle(.plain).foregroundColor(Color.ytRed)
            }
            TVMenuButton {
                if let url = item.fileURL {
                    TVMenuEntry.item(title: "Share") { presentShareSheet(for: url) }
                    TVMenuEntry.item(title: "Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    TVMenuEntry.item(title: "Copy URL") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.absoluteString, forType: .string) }
                    TVMenuEntry.separator
                }
                TVMenuEntry.item(title: "Delete", destructive: true) { onDelete() }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12).fill(isSelected || hovering ? Color.ytSurfaceGray.opacity(0.4) : Color.clear))
        .scaleEffect(hovering ? 1.01 : 1.0)
        .shadow(color: .black.opacity(hovering ? 0.25 : 0), radius: 8, y: 4)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var statusView: some View {
        switch item.status {
        case .downloading:
            VStack(alignment: .leading) {
                ProgressView(value: item.progress, total: 1.0).tint(.ytRed)
                Text("\(Int(item.progress * 100))%").font(.caption).foregroundColor(Color.ytTextSecondary)
            }
        case .completed: Text("Completed").font(.caption).foregroundColor(.green)
        case .failed: Text("Failed").font(.caption).foregroundColor(.red)
        default: EmptyView()
        }
    }
}

struct ThumbnailOrIcon: View {
    let url: URL
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.3))
            .overlay(Image(systemName: "play.rectangle").font(.largeTitle).foregroundColor(.white))
    }
}

// MARK: - Offline Detail View (subdirectory scanning restored)
struct OfflineDetailView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @StateObject private var playerManager = PlayerManager.shared
    @State private var offlineVideos: [URL] = []
    @State private var offlineAudio: [URL] = []
    @State private var offlineShorts: [URL] = []
    @State private var thumbnails: [URL: NSImage] = [:]
    @State private var selectedIndex: Int?
    @State private var mediaType: OfflineMediaType = .videos
    @State private var category: OfflineCategory = .all
    @State private var viewStyle: ViewStyle = .list
    @State private var sideWidth: CGFloat = 360
    @Environment(\.openWindow) var openWindow

    enum OfflineMediaType: String, CaseIterable { case videos = "Videos", shorts = "Shorts", audio = "Audio" }
    enum OfflineCategory: String, CaseIterable { case all = "All", watching = "Watching", finished = "Finished", playlists = "Playlists" }
    enum ViewStyle: String, CaseIterable { case grid, list }

    let gridColumns = [GridItem(.adaptive(minimum: 250, maximum: 300), spacing: 16)]

    var body: some View {
        HStack(spacing: 0) {
            leftPanel
            divider
            rightPanel
        }
        .background(Color.ytDarkBackground)
        .toolbar { toolbarContent }
        .onAppear {
            loadOfflineFiles()
            playerManager.isBrowsingShorts = (mediaType == .shorts)
        }
        .onDisappear {
            playerManager.isBrowsingShorts = false
        }
        .onChange(of: mediaType) { newValue in
            playerManager.isBrowsingShorts = (newValue == .shorts)
        }
        .onChange(of: playerManager.currentVideoURL) { newURL in
            guard let newURL = newURL, category != .playlists else { return }
            if let idx = filteredItems().firstIndex(of: newURL) {
                selectedIndex = idx
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .shortsNavigateDown)) { _ in
            guard mediaType == .shorts, category != .playlists else { return }
            let urls = filteredItems()
            guard !urls.isEmpty else { return }
            let current = selectedIndex ?? -1
            let next = min(current + 1, urls.count - 1)
            selectedIndex = next
            playOfflineItem(urls[next], in: urls)
        }
        .onReceive(NotificationCenter.default.publisher(for: .shortsNavigateUp)) { _ in
            guard mediaType == .shorts, category != .playlists else { return }
            let urls = filteredItems()
            guard !urls.isEmpty else { return }
            let current = selectedIndex ?? 0
            let previous = max(current - 1, 0)
            selectedIndex = previous
            playOfflineItem(urls[previous], in: urls)
        }
    }

    private var leftPanel: some View {
        VStack(spacing: 0) {
            Picker("Type", selection: $mediaType) { ForEach(OfflineMediaType.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            .pickerStyle(.segmented).padding()
            Picker("Category", selection: $category) { ForEach(OfflineCategory.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            .pickerStyle(.segmented).padding(.horizontal)
            if category == .playlists {
                let playlists = loadPlaylists()
                if playlists.isEmpty {
                    Spacer(); Text("No Playlists").foregroundColor(Color.ytTextSecondary); Spacer()
                } else {
                    playlistsView(playlists)
                }
            } else {
                let filtered = filteredItems()
                if filtered.isEmpty {
                    Spacer(); Text("No \(category.rawValue) \(mediaType.rawValue)").foregroundColor(Color.ytTextSecondary); Spacer()
                } else if viewStyle == .list || mediaType == .shorts {
                    offlineListView(filtered)
                } else {
                    offlineGridView(filtered)
                }
            }
        }
        .frame(width: sideWidth)
    }

    private func filteredItems() -> [URL] {
        if category == .playlists { return [] }
        switch mediaType {
        case .videos: return offlineVideos
        case .shorts: return offlineShorts
        case .audio: return offlineAudio
        }
    }

   //Shorts behavior similar to Youtube in Offline and Download tab
    private func playOfflineItem(_ url: URL, in urls: [URL]) {
        playerManager.isLoopingCurrentItem = (mediaType == .shorts)
        playerManager.play(url: url, playlist: urls)
    }
  // Playlist Tab
    private struct OfflinePlaylistEntry: Identifiable {
        let id: URL
        let name: String
        let isDownloaded: Bool
        let source: URL
    }

    private func loadPlaylists() -> [OfflinePlaylistEntry] {
        let playlistsDir = downloadsDirectory().appendingPathComponent("Playlists")
        guard let contents = try? FileManager.default.contentsOfDirectory(at: playlistsDir, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var entries: [OfflinePlaylistEntry] = []
        for url in contents {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                entries.append(OfflinePlaylistEntry(id: url, name: url.lastPathComponent, isDownloaded: true, source: url))
            } else if url.pathExtension == "json" {
                entries.append(OfflinePlaylistEntry(id: url, name: url.deletingPathExtension().lastPathComponent, isDownloaded: false, source: url))
            }
        }
        return entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func loadOfflinePlaylistEntry(_ entry: OfflinePlaylistEntry) {
        if entry.isDownloaded {
            let mediaExtensions: Set<String> = ["mp4", "mkv", "mov", "m4a", "mp3", "flac", "aac"]
            guard let files = try? FileManager.default.contentsOfDirectory(at: entry.source, includingPropertiesForKeys: nil) else { return }
            let media = files.filter { mediaExtensions.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            guard let first = media.first else { return }
            playerManager.play(url: first, playlist: media)
        } else {
            playerManager.loadPlaylist(from: entry.source)
        }
        openWindow(id: "miniplayer")
    }

    private func playlistsView(_ playlists: [OfflinePlaylistEntry]) -> some View {
        List(selection: $selectedIndex) {
            ForEach(Array(playlists.enumerated()), id: \.element.id) { index, entry in
                HStack {
                    Image(systemName: entry.isDownloaded ? "folder.fill" : "list.bullet")
                        .foregroundColor(Color.ytTextSecondary)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: entry.name).font(.headline).foregroundColor(Color.ytTextPrimary)
                        Text(entry.isDownloaded ? "Downloaded Playlist" : "Saved Queue")
                            .font(.caption2)
                            .foregroundColor(Color.ytTextSecondary)
                    }
                    Spacer()
                    Button("Load") { loadOfflinePlaylistEntry(entry) }
                        .buttonStyle(.plain).foregroundColor(Color.ytRed)
                }
                .padding(.vertical, 4)
                .listRowSeparator(.visible)
                .onTapGesture { selectedIndex = index }
            }
        }
        .listStyle(.plain)
    }

    private func offlineListView(_ urls: [URL]) -> some View {
        List(selection: $selectedIndex) {
            ForEach(Array(urls.enumerated()), id: \.element) { index, fileURL in
                OfflineItemRow(
                    videoURL: fileURL, thumbnails: thumbnails, isSelected: selectedIndex == index,
                    onPlay: { playOfflineItem(fileURL, in: urls); selectedIndex = index },
                    onDelete: { deleteFile(fileURL) }
                )
                .listRowBackground(Color.clear).listRowSeparator(.hidden).onTapGesture { selectedIndex = index }
            }
        }
        .listStyle(.plain)
        .onMoveCommand { direction in
            guard let current = selectedIndex else { return }
            let newIndex: Int
            switch direction {
            case .down: newIndex = min(current + 1, urls.count - 1)
            case .up: newIndex = max(current - 1, 0)
            default: return
            }
            selectedIndex = newIndex
            if mediaType == .shorts, urls.indices.contains(newIndex) {
                // Shorts behave like a continuous feed - Up/Down immediately
                // plays the next/previous one instead of just moving the
                // list selection and waiting for a manual play.
                playOfflineItem(urls[newIndex], in: urls)
            }
        }
    }

    private func offlineGridView(_ urls: [URL]) -> some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(Array(urls.enumerated()), id: \.element) { index, fileURL in
                    OfflineGridCard(
                        videoURL: fileURL, thumbnails: thumbnails, isSelected: selectedIndex == index,
                        onPlay: { playOfflineItem(fileURL, in: urls); selectedIndex = index },
                        onDelete: { deleteFile(fileURL) }
                    )
                    .onTapGesture { selectedIndex = index }
                }
            }
            .padding()
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.ytDivider.opacity(0.3))
            .frame(width: 10)
            .overlay(Image(systemName: "line.3.horizontal").font(.caption).foregroundColor(Color.ytTextSecondary))
            .gesture(DragGesture().onChanged { v in sideWidth = max(250, min(sideWidth + v.translation.width, 600)) })
            .onHover { hover in hover ? NSCursor.resizeLeftRight.push() : NSCursor.pop() }
    }

    @ViewBuilder
    private var rightPanel: some View {
        if let selectedURL = selectedFileURL {
            if playerManager.currentVideoURL == selectedURL {
                PlayerViewWithControls(playerManager: playerManager)
            } else {
                ZStack {
                    OfflineThumbnailView(url: selectedURL, thumbnails: thumbnails, height: 200)
                    Button(action: {
                        let playlist = filteredItems()
                        playOfflineItem(selectedURL, in: playlist)
                    }) {
                        Image(systemName: "play.circle.fill").font(.system(size: 60)).foregroundColor(.white).shadow(radius: 2)
                    }
                    .buttonStyle(.plain)
                }
                .overlay(
                    Text(selectedURL.lastPathComponent as String)
                        .foregroundColor(Color.ytTextPrimary).padding(.top, 220),
                    alignment: .bottom
                )
            }
        } else {
            Rectangle().fill(Color.ytDarkBackground).overlay(Text("Select a video to preview").foregroundColor(Color.ytTextSecondary))
        }
    }

    private var selectedFileURL: URL? {
        guard let index = selectedIndex else { return nil }
        let filtered = filteredItems()
        guard index < filtered.count else { return nil }
        return filtered[index]
    }

    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Picker("View", selection: $viewStyle) {
                Image(systemName: "square.grid.2x2").tag(ViewStyle.grid)
                Image(systemName: "list.bullet").tag(ViewStyle.list)
            }
            .pickerStyle(.segmented)
            .disabled(mediaType == .shorts)
            .help(mediaType == .shorts ? "Shorts always show as a list" : "")
        }
    }

    private func loadOfflineFiles() {
        let root = downloadsDirectory()
        let shortsDir = root.appendingPathComponent("Shorts")
        let audioDir  = root.appendingPathComponent("Audio")

        if let rootContents = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            offlineVideos = rootContents.filter {
                ["mp4", "mkv", "mov"].contains($0.pathExtension) &&
                !$0.path.hasPrefix(shortsDir.path) &&
                !$0.path.hasPrefix(audioDir.path)
            }
        }

        if let shortsContents = try? FileManager.default.contentsOfDirectory(at: shortsDir, includingPropertiesForKeys: nil) {
            offlineShorts = shortsContents.filter { ["mp4", "mkv", "mov"].contains($0.pathExtension) }
        }

        if let audioContents = try? FileManager.default.contentsOfDirectory(at: audioDir, includingPropertiesForKeys: nil) {
            offlineAudio = audioContents.filter { ["mp3", "m4a", "flac", "aac"].contains($0.pathExtension) }
        }

        generateThumbnails(for: offlineVideos + offlineShorts)
    }

    private func downloadsDirectory() -> URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            .appendingPathComponent("YouTube X Downloads")
    }

    private func generateThumbnails(for videos: [URL]) {
        for video in videos {
            DispatchQueue.global(qos: .utility).async {
                let asset = AVAsset(url: video)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                let time = CMTime(seconds: 1, preferredTimescale: 600)
                do {
                    let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                    let thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: 320, height: 180))
                    DispatchQueue.main.async { self.thumbnails[video] = thumbnail }
                } catch {}
            }
        }
    }

    private func deleteFile(_ url: URL) { try? FileManager.default.removeItem(at: url); loadOfflineFiles() }
}

// Design Style for list row offline files
private struct OfflineItemRow: View {
    let videoURL: URL
    let thumbnails: [URL: NSImage]
    let isSelected: Bool
    let onPlay: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                OfflineThumbnailView(url: videoURL, thumbnails: thumbnails, height: 60).frame(width: 107, height: 60)
                TVPlayButton(action: onPlay, size: 28).opacity(hovering ? 1 : 0)
            }
            Text(videoURL.deletingPathExtension().lastPathComponent as String)
                .font(.system(size: 13, weight: .medium)).lineLimit(1).foregroundColor(Color.ytTextPrimary)
            Spacer()
            TVMenuButton {
                TVMenuEntry.item(title: "Share") { presentShareSheet(for: videoURL) }
                TVMenuEntry.item(title: "Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([videoURL]) }
                TVMenuEntry.item(title: "Copy URL") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(videoURL.absoluteString, forType: .string) }
                TVMenuEntry.separator
                TVMenuEntry.item(title: "Delete", destructive: true) { onDelete() }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12).fill(isSelected || hovering ? Color.ytSurfaceGray.opacity(0.4) : Color.clear))
        .scaleEffect(hovering ? 1.01 : 1.0)
        .shadow(color: .black.opacity(hovering ? 0.25 : 0), radius: 8, y: 4)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
    }
}

// Design style for grid card offline files
private struct OfflineGridCard: View {
    let videoURL: URL
    let thumbnails: [URL: NSImage]
    let isSelected: Bool
    let onPlay: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottom) {
                OfflineThumbnailView(url: videoURL, thumbnails: thumbnails, height: 140)
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                    .frame(height: 140).cornerRadius(10)
                TVPlayButton(action: onPlay, size: 34).opacity(hovering ? 1 : 0)
                HStack {
                    Text(videoURL.deletingPathExtension().lastPathComponent as String).font(.caption).lineLimit(1).foregroundColor(.white)
                    Spacer()
                    TVMenuButton(size: 24) {
                        TVMenuEntry.item(title: "Share") { presentShareSheet(for: videoURL) }
                        TVMenuEntry.item(title: "Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([videoURL]) }
                        TVMenuEntry.item(title: "Copy URL") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(videoURL.absoluteString, forType: .string) }
                        TVMenuEntry.separator
                        TVMenuEntry.item(title: "Delete", destructive: true) { onDelete() }
                    }
                }
                .padding(8)
            }
            .frame(height: 140).cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Color.ytRed : Color.clear, lineWidth: 2))
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.ytSurfaceGray.opacity(0.2)))
        .scaleEffect(hovering ? 1.03 : 1.0)
        .shadow(color: .black.opacity(hovering ? 0.35 : 0), radius: 10, y: 6)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
    }
}

// MARK: - Offline Thumbnail View
private struct OfflineThumbnailView: View {
    let url: URL
    let thumbnails: [URL: NSImage]
    let height: CGFloat
    var body: some View {
        if let thumb = thumbnails[url] {
            Image(nsImage: thumb).resizable().aspectRatio(16/9, contentMode: .fill).frame(height: height).cornerRadius(8)
        } else {
            RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.3)).frame(height: height)
                .overlay(Image(systemName: "play.rectangle").font(.largeTitle).foregroundColor(.white))
        }
    }
}

// MARK: - Native Player View
struct PlayerViewWrapper: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        return view
    }
    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}
/// Back and Next buttons hardwired in both Offline Mini and Downloads tabs
struct PlayerViewWithControls: View {
    @ObservedObject var playerManager: PlayerManager
    @State private var controlsVisible = true
    @State private var hideTask: DispatchWorkItem?

    var body: some View {
        ZStack(alignment: .bottom) {
            PlayerViewWrapper(player: playerManager.player)

            HStack(spacing: 16) {
                Button(action: { playerManager.playPrevious() }) {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .disabled(playerManager.currentIndex <= 0)
                .help("Previous")

                Button(action: { playerManager.playNext() }) {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .disabled(playerManager.currentIndex >= playerManager.playlist.count - 1)
                .help("Next")
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 46)
            .opacity(controlsVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: controlsVisible)
        }
    /// Fade when idle behavior: appears on hover/mouse movement, fades out after a couple seconds of no activity, same as the native bar underneath it (Next and Back buttons)
        .onHover { hovering in
            if hovering { showControlsAndScheduleHide() }
        }
        .onAppear { showControlsAndScheduleHide() }
    }

    private func showControlsAndScheduleHide() {
        controlsVisible = true
        hideTask?.cancel()
        let task = DispatchWorkItem { controlsVisible = false }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: task)
    }
}

// MARK: - Shortcuts Overlay
struct ShortcutsOverlay: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    let shortcuts: [(String, String)] = [
        ("⌘1", "Home"), ("⌘2", "Subscriptions"), ("⌘K", "Command Palette"),
        ("Space", "Play/Pause"), ("⌘→", "Skip Forward"), ("⌘←", "Skip Backward"),
        ("⌘⇧M", "Mini Player"), ("⌘⌃F", "Full Screen"),
    ]
    var body: some View {
        VStack(spacing: 4) {
            ForEach(shortcuts, id: \.0) { shortcut in
                HStack {
                    Text(shortcut.0).font(.system(.body, design: .monospaced)).frame(width: 80, alignment: .trailing)
                    Text(shortcut.1).frame(width: 150, alignment: .leading)
                }
            }
        }
        .padding().background(Color.ytSurfaceGray)
    }
}
