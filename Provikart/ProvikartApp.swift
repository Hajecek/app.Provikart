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
            print("[FCM] Notifikace již povoleny, registruji na APNS…")
          }
        }
      }
    }

    return true
  }

  func application(_ application: UIApplication,
                    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    print("[FCM] APNS token přijat (\(deviceToken.count) B), předávám FCM…")
    Messaging.messaging().apnsToken = deviceToken

    Messaging.messaging().token { [weak self] token, error in
      DispatchQueue.main.async {
        if let error = error {
          print("[FCM] Chyba při načtení tokenu: \(error.localizedDescription)")
          return
        }
        if let token = token {
          print("[FCM] ✅ FCM token: \(token)")
        }
        self?.subscribeToAllUsers()
      }
    }
  }

  /// Na simulátoru se volá místo didRegister… – APNS tam není k dispozici.
  func application(_ application: UIApplication,
                    didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("[FCM] ⚠️ APNS registrace selhala (pravděpodobně simulátor): \(error.localizedDescription)")
    print("[FCM] FCM token získaš jen na reálném zařízení (iPhone/iPad).")
  }

  func subscribeToAllUsers() {
    Messaging.messaging().subscribe(toTopic: "all_users") { error in
      if let error = error {
        print("[FCM] Odběr tématu all_users selhal: \(error.localizedDescription)")
      } else {
        print("[FCM] Přihlášení k tématu all_users")
      }
    }
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    let userInfo = notification.request.content.userInfo
    print("[FCM] Notifikace při běhu aplikace: \(userInfo)")
    completionHandler([.banner, .list, .sound])
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
    let userInfo = response.notification.request.content.userInfo
    print("[FCM] Reakce na notifikaci: \(userInfo)")
    NotificationCenter.default.post(name: Notification.Name("didReceiveRemoteNotification"), object: nil, userInfo: userInfo as? [String: Any])
    completionHandler()
  }

  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    if let token = fcmToken {
      print("[FCM] Registration token: \(token)")
      // Na backend neposíláme tady – ukládáme až po přihlášení v updateUserInfo.
    } else {
      print("[FCM] Registration token je nil")
    }
  }

  /// Odešle FCM token na API. Vyžaduje přihlášení (authToken v hlavičce), body jen { "token": "<fcm>" }.
  func sendFCMTokenToBackend(fcmToken: String) {
    guard let apiToken = authToken, !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      print("[FCM] Přeskočeno – uživatel není přihlášen (chybí API token)")
      return
    }
    guard let url = URL(string: updateFCMTokenURL) else { return }

    let cleanApiToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(cleanApiToken)", forHTTPHeaderField: "Authorization")
    // token_api v těle – PHP často nedostane hlavičku Authorization (Apache/nginx ji nepředá)
    request.httpBody = try? JSONSerialization.data(withJSONObject: [
      "token": fcmToken,
      "token_api": cleanApiToken
    ])

    URLSession.shared.dataTask(with: request) { data, response, error in
      if let error = error {
        print("[FCM] Chyba odeslání tokenu na backend: \(error.localizedDescription)")
        return
      }
      let code = (response as? HTTPURLResponse)?.statusCode ?? 0
      if (200...299).contains(code) {
        print("[FCM] FCM token odeslán na backend (OK)")
      } else if let data = data, let body = String(data: data, encoding: .utf8) {
        print("[FCM] Backend odpověděl \(code): \(body.prefix(200))")
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
  }

  func clearUserInfo() {
    currentUserId = nil
    currentUserRole = nil
    authToken = nil
    print("[FCM] Údaje uživatele v AppDelegate vymazány")
  }
}

@main
struct ProvikartApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authState = AuthState()
    @StateObject private var appLoginApprovalState = AppLoginApprovalState()
    @StateObject private var networkMonitor = NetworkMonitor()
    @AppStorage(onboardingCompletedKey) private var hasCompletedOnboarding = false
    @State private var showLaunchScreen = true
    @State private var showBiometricVerification = false
    @State private var hasVerifiedBiometricThisSession = false
    @State private var backgroundedAt: Date?
    @Environment(\.scenePhase) private var scenePhase

    private var shouldShowBiometricOverlay: Bool {
        guard authState.isLoggedIn else { return false }
        if showBiometricVerification { return true }
        if !showLaunchScreen, hasCompletedOnboarding, !hasVerifiedBiometricThisSession { return true }
        return false
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showLaunchScreen {
                    LaunchView(onFinish: { showLaunchScreen = false })
                } else if !hasCompletedOnboarding {
                    OnboardingView(onFinish: { hasCompletedOnboarding = true })
                } else if authState.isLoggedIn {
                    ContentView()
                } else {
                    LoginView()
                }
                // Pouze když je aplikace v pozadí (uživatel odešel / app switcher), ne při .inactive (ovládací centrum, notifikace).
                if scenePhase == .background {
                    PrivacyScreen()
                        .ignoresSafeArea()
                        .zIndex(2)
                }
                if shouldShowBiometricOverlay {
                    BiometricVerificationView(onSuccess: {
                        showBiometricVerification = false
                        hasVerifiedBiometricThisSession = true
                    })
                    .ignoresSafeArea()
                    .zIndex(3)
                }
            }
            .environmentObject(authState)
            .environmentObject(appDelegate)
            .environmentObject(appLoginApprovalState)
            .environmentObject(networkMonitor)
            .onChange(of: authState.isLoggedIn) { _, isLoggedIn in
              if isLoggedIn, let user = authState.currentUser {
                appDelegate.updateUserInfo(userId: user.id ?? 0, role: user.role ?? "", authToken: authState.authToken)
              } else {
                appDelegate.clearUserInfo()
              }
            }
            .onAppear {
              if authState.isLoggedIn, let user = authState.currentUser {
                appDelegate.updateUserInfo(userId: user.id ?? 0, role: user.role ?? "", authToken: authState.authToken)
              }
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .background:
                    backgroundedAt = Date()
                    appLoginApprovalState.stopPolling()
                case .inactive:
                    if let at = backgroundedAt, Date().timeIntervalSince(at) >= 5, authState.isLoggedIn {
                        showBiometricVerification = true
                    }
                    appLoginApprovalState.stopPolling()
                case .active:
                    backgroundedAt = nil
                    if authState.isLoggedIn, !showLaunchScreen, hasCompletedOnboarding,
                       let username = authState.currentUser?.username {
                        appLoginApprovalState.startPolling(username: username, token: authState.authToken, interval: 2)
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
