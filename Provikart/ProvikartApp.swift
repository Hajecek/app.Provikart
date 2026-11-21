//
//  ProvikartApp.swift
//  Provikart
//
//  Created by Michal Hájek on 03.07.2025.
//

import SwiftUI
import FirebaseCore
import FirebaseMessaging
import UserNotifications

private let onboardingCompletedKey = "Provikart.hasCompletedOnboarding"
private let appearanceModeKey = "settings.appearance.mode"

/// API: POST s Authorization: Bearer <api_token>, body { "token": "<FCM token>" }
private let updateFCMTokenURL = "https://provikart.cz/api/update_fcm_token.php"

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate, ObservableObject {
  private var currentUserId: Int?
  private var currentUserRole: String?
  /// API token z přihlášení – pro hlavičku Authorization při odeslání FCM tokenu
  private var authToken: String?

  func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    FirebaseApp.configure()

    Messaging.messaging().delegate = self
    UNUserNotificationCenter.current().delegate = self

    // Svolení k notifikacím se vyžaduje v onboardingu (krok „Notifikace“), ne hned při startu.
    if UserDefaults.standard.bool(forKey: onboardingCompletedKey) {
      UNUserNotificationCenter.current().getNotificationSettings { settings in
        DispatchQueue.main.async {
          if settings.authorizationStatus == .authorized {
            UserDefaults.standard.set(true, forKey: "Provikart.notificationsEnabled")
            application.registerForRemoteNotifications()
            Log.push.debug("Notifikace povoleny – registruji APNs")
          }
        }
      }
    }

    return true
  }

  func application(_ application: UIApplication,
                    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Messaging.messaging().apnsToken = deviceToken

    Messaging.messaging().token { [weak self] token, error in
      DispatchQueue.main.async {
        if let error = error {
          Log.push.error("FCM token se nepodařilo načíst: \(error.localizedDescription, privacy: .public)")
          return
        }
        if let token = token {
          Log.push.info("APNs + FCM token připraven (\(token.suffix(8), privacy: .private)…)")
          self?.sendFCMTokenToBackend(fcmToken: token)
        }
        self?.syncNotificationTopics()
      }
    }
  }

  /// Na simulátoru se volá místo didRegister… – APNS tam není k dispozici.
  func application(_ application: UIApplication,
                    didFailToRegisterForRemoteNotificationsWithError error: Error) {
    Log.push.notice("APNs registrace selhala (na simulátoru normální): \(error.localizedDescription, privacy: .public)")
  }

  func subscribeToAllUsers() {
    syncNotificationTopics()
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    let userInfo = notification.request.content.userInfo
    Log.push.info("Push v popředí: \(Self.pushSummary(userInfo), privacy: .public)")
    guard NotificationPreferencesStore.shared.shouldPresent(
      userInfo: userInfo,
      role: UserRole(apiValue: currentUserRole)
    ) else {
      completionHandler([])
      return
    }
    AppIconBadgeSync.increment()
    NotificationCenter.default.post(
      name: Notification.Name("didReceiveRemoteNotification"),
      object: nil,
      userInfo: userInfo as? [String: Any]
    )
    completionHandler([.banner, .list, .sound])
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
    let userInfo = response.notification.request.content.userInfo
    Log.push.info("Klepnutí na push: \(Self.pushSummary(userInfo), privacy: .public)")
    // Badge se nezvyšuje při klepnutí – už se zvýšil při doručení.
    NotificationCenter.default.post(name: Notification.Name("didReceiveRemoteNotification"), object: nil, userInfo: userInfo as? [String: Any])
    completionHandler()
  }

  /// Pozadí / content-available – badge +1 i když appka není v popředí.
  func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    Log.push.info("Push na pozadí: \(Self.pushSummary(userInfo), privacy: .public)")
    let allowed = NotificationPreferencesStore.shared.shouldPresent(
      userInfo: userInfo,
      role: UserRole(apiValue: currentUserRole)
    )
    if allowed {
      NotificationCenter.default.post(
        name: Notification.Name("didReceiveRemoteNotification"),
        object: nil,
        userInfo: userInfo as? [String: Any]
      )
      // V popředí řeší +1 `willPresent` – tady jen když appka není active.
      if application.applicationState != .active {
        AppIconBadgeSync.increment()
      }
    }
    completionHandler(.newData)
  }

  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    // Na backend neposíláme tady – ukládáme až po přihlášení v updateUserInfo.
    if fcmToken == nil {
      Log.push.notice("FCM registration token je nil")
    }
  }

  /// Odešle FCM token na API. Vyžaduje přihlášení (authToken v hlavičce).
  /// Tělo: { "token": "<fcm>", "token_api": "<api>", "notification_preferences": { ... } }
  func sendFCMTokenToBackend(fcmToken: String) {
    guard let apiToken = authToken, !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      Log.push.debug("FCM token neodesílám – uživatel není přihlášen")
      return
    }
    guard let url = URL(string: updateFCMTokenURL) else { return }

    let cleanApiToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
    let role = UserRole(apiValue: currentUserRole)
    var body: [String: Any] = [
      "token": fcmToken,
      "token_api": cleanApiToken
    ]
    body["notification_preferences"] = NotificationPreferencesStore.shared.apiPayload(role: role)

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(cleanApiToken)", forHTTPHeaderField: "Authorization")
    // token_api v těle – PHP často nedostane hlavičku Authorization (Apache/nginx ji nepředá)
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

    URLSession.shared.dataTask(with: request) { data, response, error in
      if let error = error {
        Log.push.error("FCM token se nepodařilo odeslat: \(error.localizedDescription, privacy: .public)")
        return
      }
      let code = (response as? HTTPURLResponse)?.statusCode ?? 0
      if (200...299).contains(code) {
        Log.push.info("FCM token uložen na backendu")
      } else {
        Log.push.error("FCM token – backend HTTP \(code, privacy: .public): \(Log.preview(data ?? Data(), limit: 200), privacy: .private)")
      }
    }.resume()
  }

  func updateUserInfo(userId: Int, role: String, authToken: String?) {
    currentUserId = userId
    currentUserRole = role
    self.authToken = authToken
    // Uložení do DB až po přihlášení: při každém přihlášení (včetně přepnutí na jiného uživatele) odešli aktuální FCM token.
    if authToken != nil, let fcmToken = Messaging.messaging().fcmToken {
      sendFCMTokenToBackend(fcmToken: fcmToken)
    }
    syncNotificationTopics()
  }

  /// Synchronizuje FCM témata a pošle výběr notifikací na backend.
  func syncNotificationPreferences(role: UserRole? = nil) {
    let resolvedRole = role ?? UserRole(apiValue: currentUserRole)
    NotificationPreferencesStore.shared.applyTopicSubscriptions(role: resolvedRole)
    if let fcmToken = Messaging.messaging().fcmToken {
      sendFCMTokenToBackend(fcmToken: fcmToken)
    }
    Task {
      await NotificationPreferencesService().save(
        token: authToken,
        payload: NotificationPreferencesStore.shared.apiPayload(role: resolvedRole)
      )
    }
  }

  private func syncNotificationTopics() {
    NotificationPreferencesStore.shared.applyTopicSubscriptions(role: UserRole(apiValue: currentUserRole))
  }

  func clearUserInfo() {
    currentUserId = nil
    currentUserRole = nil
    authToken = nil
    AppIconBadgeSync.clear()
    Log.push.debug("Údaje uživatele pro push vymazány")
  }

  /// Krátký popis push notifikace pro log (typ + titulek), bez celého payloadu.
  private static func pushSummary(_ userInfo: [AnyHashable: Any]) -> String {
    let aps = userInfo["aps"] as? [String: Any]
    let alert = aps?["alert"] as? [String: Any]
    let title = (alert?["title"] as? String) ?? (aps?["alert"] as? String) ?? "—"
    let type = (userInfo["type"] as? String) ?? (userInfo["category"] as? String) ?? (aps?["category"] as? String)
    return type.map { "[\($0)] \(title)" } ?? title
  }
}

@main
struct ProvikartApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authState = AuthState()
    @StateObject private var appLoginApprovalState = AppLoginApprovalState()
    @StateObject private var networkMonitor = NetworkMonitor()
    @StateObject private var sessionUnlock = SessionUnlockState()
    @AppStorage(onboardingCompletedKey) private var hasCompletedOnboarding = false
    @AppStorage(appearanceModeKey) private var appearanceModeRaw: String = "system"
    @State private var showLaunchScreen = true
    @State private var isHandingOffToLogin = false
    @State private var didFinishLaunch = false
    @State private var loginLogoFrame: CGRect = .zero
    @State private var showBiometricVerification = false
    @State private var hasVerifiedBiometricThisSession = false
    @State private var backgroundedAt: Date?
    @Environment(\.scenePhase) private var scenePhase

    private var needsImmediateBiometricOnResume: Bool {
        guard authState.isLoggedIn, scenePhase == .active, let at = backgroundedAt else { return false }
        return Date().timeIntervalSince(at) >= 5
    }

    /// Aplikace je schovaná pod biometrickým zámkem (pro efekt odemčení).
    private var isUnlockRevealPending: Bool {
        shouldShowBiometricOverlay && scenePhase == .active
    }

    private var shouldShowBiometricOverlay: Bool {
        guard authState.isLoggedIn else { return false }
        if showBiometricVerification || needsImmediateBiometricOnResume { return true }
        if !showLaunchScreen, hasCompletedOnboarding, !hasVerifiedBiometricThisSession { return true }
        return false
    }

    private var launchesIntoLogin: Bool {
        hasCompletedOnboarding && !authState.isLoggedIn
    }

    @ViewBuilder
    private var rootContent: some View {
        if !hasCompletedOnboarding {
            OnboardingView(onFinish: { hasCompletedOnboarding = true })
        } else if authState.isLoggedIn {
            ContentView()
        } else {
            LoginView(showsBrandLogo: !showLaunchScreen)
        }
    }

    private func finishLaunch() {
        guard !didFinishLaunch else { return }
        didFinishLaunch = true

        guard launchesIntoLogin, loginLogoFrame.width > 0 else {
            withAnimation(.easeInOut(duration: 0.45)) {
                showLaunchScreen = false
            }
            return
        }

        withAnimation(.spring(response: 0.62, dampingFraction: 0.86)) {
            isHandingOffToLogin = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.68) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                showLaunchScreen = false
                isHandingOffToLogin = false
            }
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearanceModeRaw {
        case "light": return .light
        case "dark": return .dark
        default: return nil // system
        }
    }

    init() {
        PhoneSessionManager.shared.activate()
        CommissionBackgroundRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if !showLaunchScreen || launchesIntoLogin {
                    rootContent
                        .opacity(showLaunchScreen && !isHandingOffToLogin ? 0 : 1)
                        // Pod zámkem je aplikace lehce oddálená a rozmazaná,
                        // po odemčení se plynule „přiblíží“ na místo.
                        .scaleEffect(isUnlockRevealPending ? 0.94 : 1)
                        .blur(radius: isUnlockRevealPending ? 10 : 0)
                        .allowsHitTesting(!showLaunchScreen)
                }
                if showLaunchScreen {
                    LaunchView(
                        isHandingOff: isHandingOffToLogin,
                        targetFrame: loginLogoFrame,
                        onFinish: finishLaunch
                    )
                    .transition(.opacity)
                    .zIndex(1)
                }
                // Pouze když je aplikace v pozadí (uživatel odešel / app switcher), ne při .inactive (ovládací centrum, notifikace).
                if scenePhase == .background {
                    PrivacyScreen()
                        .ignoresSafeArea()
                        .zIndex(2)
                }
                if shouldShowBiometricOverlay {
                    BiometricVerificationView(onSuccess: {
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.9)) {
                            showBiometricVerification = false
                            hasVerifiedBiometricThisSession = true
                            sessionUnlock.unlock()
                        }
                        LuckyChestController.shared.resumeIfNeeded()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            LuckyChestController.shared.resumeIfNeeded()
                        }
                    })
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .opacity.combined(with: .scale(scale: 1.1))
                    ))
                    .zIndex(3)
                }
            }
            .onPreferenceChange(LoginLogoFrameKey.self) { loginLogoFrame = $0 }
            .preferredColorScheme(preferredColorScheme)
            .environmentObject(authState)
            .environmentObject(appDelegate)
            .environmentObject(appLoginApprovalState)
            .environmentObject(networkMonitor)
            .environmentObject(sessionUnlock)
            .environment(\.sessionUnlocked, sessionUnlock.isUnlocked)
            .onChange(of: authState.isLoggedIn) { _, isLoggedIn in
              if isLoggedIn, let user = authState.currentUser {
                appDelegate.updateUserInfo(userId: user.id ?? 0, role: user.role ?? "", authToken: authState.authToken)
              } else {
                appDelegate.clearUserInfo()
                sessionUnlock.lock()
                hasVerifiedBiometricThisSession = false
                CommissionLiveActivityManager.endAll()
                ManagerTeamLiveActivityManager.endAll()
                WidgetDataStore.clearCommission()
                WidgetDataStore.clearReports()
                WidgetDataStore.clearInstallations()
                WidgetDataStore.clearManagerData()
                WidgetDataStore.clearUserRole()
              }
            }
            .onAppear {
              if authState.isLoggedIn, let user = authState.currentUser {
                appDelegate.updateUserInfo(userId: user.id ?? 0, role: user.role ?? "", authToken: authState.authToken)
              }
              PhoneSessionManager.shared.sendCurrentTokenIfNeeded()
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .background:
                    backgroundedAt = Date()
                    appLoginApprovalState.stopPolling()
                    if authState.isLoggedIn {
                        CommissionBackgroundRefresh.scheduleNext()
                    }
                case .inactive:
                    // Biometrii nespouštět ve .inactive – systém často vrátí „vyžadována akce uživatele“
                    // (Face ID musí běžet až ve zcela aktivní scéně).
                    appLoginApprovalState.stopPolling()
                    // Při návratu z pozadí připrav overlay už ve .inactive, aby po přechodu do .active
                    // neproblikl hlavní obsah ještě před zobrazením biometrie.
                    if authState.isLoggedIn, let at = backgroundedAt, Date().timeIntervalSince(at) >= 5 {
                        showBiometricVerification = true
                        sessionUnlock.lock()
                    }
                case .active:
                    if authState.isLoggedIn, let at = backgroundedAt, Date().timeIntervalSince(at) >= 5 {
                        showBiometricVerification = true
                        sessionUnlock.lock()
                    }
                    backgroundedAt = nil
                    if authState.isLoggedIn {
                        CommissionBackgroundRefresh.scheduleNext()
                        if !showLaunchScreen, hasCompletedOnboarding,
                           let username = authState.currentUser?.username {
                            appLoginApprovalState.startPolling(username: username, token: authState.authToken, interval: 2)
                        }
                    }
                default:
                    break
                }
            }
            .onAppear {
                if authState.isLoggedIn, let user = authState.currentUser {
                    appDelegate.updateUserInfo(userId: user.id ?? 0, role: user.role ?? "", authToken: authState.authToken)
                }
                if authState.isLoggedIn, !showLaunchScreen, hasCompletedOnboarding,
                   scenePhase == .active, let username = authState.currentUser?.username {
                    appLoginApprovalState.startPolling(username: username, token: authState.authToken, interval: 2)
                }
            }
        }
    }
}
