//
//  Corner_ClockApp.swift
//  Corner Clock
//
//  Created by 楊旻璇 on 2026/1/8.
//

import SwiftUI
import AppKit
import Combine

// --- 1. Apple 原生 HUD 毛玻璃 ---
struct BlurView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        // .hudWindow 搭配 .vibrantDark 是最接近 macOS 原生 OSD (音量/亮度顯示) 的質感
        view.material = .hudWindow
        view.blendingMode = .withinWindow
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// --- 2. 內容大小偵測工具 ---
struct ContentSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

// --- 3. 設定管理員 ---
class AppSettings: ObservableObject {
    @Published var showBackground: Bool {
        didSet { UserDefaults.standard.set(showBackground, forKey: "ShowBackground") }
    }
    @Published var isUserEnabled: Bool {
        didSet { UserDefaults.standard.set(isUserEnabled, forKey: "UserEnabledClock") }
    }

    init() {
        self.showBackground = UserDefaults.standard.bool(forKey: "ShowBackground")
        // 預設開啟
        if UserDefaults.standard.object(forKey: "UserEnabledClock") == nil {
            self.isUserEnabled = true
        } else {
            self.isUserEnabled = UserDefaults.standard.bool(forKey: "UserEnabledClock")
        }
    }
}

// --- 4. 時鐘介面 ---
// 1. 定義顯示時間的介面
struct ClockView: View {
    @EnvironmentObject var settings: AppSettings
    // 用來通知 AppDelegate 視窗需要變多大
    var onSizeChange: (CGSize) -> Void
    
    // [優化移除] 不需要 @State private var currentTime
    // [優化移除] 不需要 let timer = Timer.publish...

    // 靜態 Formatter
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE  MMM d  HH:mm"
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()

    var body: some View {
        // [核心修改] 改用 TimelineView
        // .periodic(from: .now, by: 1.0) 代表每 1 秒更新一次
        // context.date 就是當下的準確時間
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            Text(Self.dateFormatter.string(from: context.date))
                // .monospacedDigit() 讓數字等寬，防止跳動
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundColor(.white)
                
                // 背景與邊距邏輯
                .padding(.horizontal, settings.showBackground ? 10 : 4)
                .padding(.vertical, settings.showBackground ? 6 : 0)
                .background(
                    settings.showBackground ?
                        AnyView(BlurView().cornerRadius(10)) :
                        AnyView(Color.clear)
                )
                // 陰影
                .shadow(color: .black.opacity(settings.showBackground ? 0 : 0.6), radius: 2, x: 0, y: 1)
                
                // 自動寬度偵測
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 4)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: ContentSizePreferenceKey.self, value: geo.size)
                    }
                )
                .onPreferenceChange(ContentSizePreferenceKey.self) { newSize in
                    onSizeChange(newSize)
                }
        }
        // [優化移除] 不需要 .onReceive(timer)
    }
}

// --- 5. 程式入口 ---
@main
struct CornerClockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

// --- 6. 核心控制器 ---
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var mouseCheckTimer: Timer?
    var statusItem: NSStatusItem?
    var settings = AppSettings()
    var cancellables = Set<AnyCancellable>()
    
    // 記錄上一次狀態，節省 CPU
    var lastShouldHideState: Bool? = nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        
        // 1. 初始化 View
        let clockView = ClockView { [weak self] newSize in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if abs(self.window.frame.width - newSize.width) > 1 || abs(self.window.frame.height - newSize.height) > 1 {
                    self.window.setContentSize(newSize)
                    self.updateWindowPosition()
                }
            }
        }
        
        let contentView = clockView.environmentObject(settings)

        // 2. 視窗初始化
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 32),
            styleMask: [.borderless],
            backing: .buffered, defer: false)

        window.contentView = NSHostingView(rootView: contentView)
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false

        window.orderFront(nil)
        
        // 3. 監聽螢幕變動 (例如插拔螢幕、解析度改變)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        
        setupMenuBarIcon()
        
        // 4. 綁定設定變化
        settings.$isUserEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                guard let self = self else { return }
                
                if !isEnabled {
                    self.window.alphaValue = 0.0
                } else {
                    // 開啟瞬間先透明，交給 checkStatus 決定是否淡入
                    self.window.alphaValue = 0.0
                    self.checkStatus()
                }
                
                DispatchQueue.main.async { self.updateMenu() }
            }.store(in: &cancellables)
        
        settings.$showBackground
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateMenu() }
            }.store(in: &cancellables)
            
        // 5. 啟動監測 (頻率稍微調高到 0.25s 讓反應更靈敏，但因為邏輯簡單所以不耗電)
        startMouseMonitoring()
        
        // 6. 開機立刻檢查
        self.checkStatus()
    }
    
    func setupMenuBarIcon() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "Corner Clock")
            button.image?.isTemplate = true
        }
        updateMenu()
    }
    
    func updateMenu() {
        let menu = NSMenu()
        let toggleText = settings.isUserEnabled ? "Hide Clock" : "Show Clock"
        let toggleItem = NSMenuItem(title: toggleText, action: #selector(toggleClock), keyEquivalent: "t")
        menu.addItem(toggleItem)
        menu.addItem(NSMenuItem.separator())
        let bgText = settings.showBackground ? "Hide Background" : "Show Background"
        let bgItem = NSMenuItem(title: bgText, action: #selector(toggleBackground), keyEquivalent: "b")
        menu.addItem(bgItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Corner Clock", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }
    
    @objc func toggleClock() { settings.isUserEnabled.toggle() }
    @objc func toggleBackground() { settings.showBackground.toggle() }
    @objc func quitApp() { NSApplication.shared.terminate(nil) }
    
    func updateWindowPosition() {
        if let screen = NSScreen.main {
            let screenRect = screen.frame
            let newOrigin = NSPoint(
                x: screenRect.maxX - window.frame.width,
                y: screenRect.maxY - window.frame.height
            )
            window.setFrameOrigin(newOrigin)
            window.orderFrontRegardless()
        }
    }
    
    @objc func screenChanged() {
        updateWindowPosition()
        checkStatus()
    }
    
    func startMouseMonitoring() {
        // [修改] 頻率改為 0.25 秒，反應會比 0.5 秒跟手，且邏輯簡單不會耗電
        mouseCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.checkStatus()
        }
    }
    
    // [極簡穩定版邏輯] 不猜測設定，只看物理狀態
    func checkStatus() {
        guard let screen = NSScreen.screens.first else { return }
        
        // 1. 最高優先級：使用者手動關閉
        if !self.settings.isUserEnabled {
            if self.window.alphaValue > 0 {
                self.window.animator().alphaValue = 0.0
            }
            return
        }
        
        // 2. 獲取物理狀態
        // Top Gap: 螢幕總高度 - 可用區域高度 (如果 Menu Bar 在，這個值會是 24~30；如果不在，會是 0)
        // 注意：這裡用 visibleFrame.maxY，這樣可以排除 Dock 在下方的影響，只看上方
        let topGap = screen.frame.maxY - screen.visibleFrame.maxY
        
        // Mouse Position
        let mouseLocation = NSEvent.mouseLocation
        
        // 判斷是否滑鼠在頂部危險區 (預留 5px 緩衝)
        let isMouseAtTop = mouseLocation.y > (screen.frame.maxY - 5) &&
                           mouseLocation.x >= screen.frame.minX &&
                           mouseLocation.x <= screen.frame.maxX

        // 3. 核心決策
        var shouldHide = false

        if topGap > 22 {
            // 情況 A: 物理上 Menu Bar 佔據了空間
            // (無論是「永遠顯示」模式，還是滑鼠移過去叫出了 Menu Bar，只要它在，我們就隱藏)
            shouldHide = true
        } else if isMouseAtTop {
            // 情況 B: 物理上 Menu Bar 雖然還沒出現 (Gap=0)，但滑鼠已經頂到最上面了
            // 預判使用者要叫出選單，先隱藏以示尊重
            shouldHide = true
        } else {
            // 情況 C: 上方沒東西，滑鼠也沒在上方 -> 安全，顯示時鐘
            shouldHide = false
        }
        
        // 4. 執行動畫 (僅在狀態改變時)
        if self.lastShouldHideState != shouldHide || self.lastShouldHideState == nil {
            self.lastShouldHideState = shouldHide
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                self.window.animator().alphaValue = shouldHide ? 0.0 : 1.0
            }
            
            if !shouldHide {
                self.window.orderFrontRegardless()
            }
        }
    }
}
