import Flutter
import UIKit

/// Owns the window under the UIScene life cycle, which the tvOS 27 SDK makes
/// mandatory: an app built against it that still puts its window up from the
/// app delegate is killed at launch. The engine, the Flutter view controller
/// and the gamepad host that wraps it are still made in AppDelegate, since
/// the method channels hang off them and have to exist before the scene
/// connects. This only hosts them.
///
/// Deep links arrive here rather than through `application(_:open:)`, both the
/// one the app is launched with and any delivered while it runs.
class SceneDelegate: FlutterSceneDelegate {
    private var registeredEngine: FlutterEngine?

    override func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene,
            let appDelegate = UIApplication.shared.delegate as? AppDelegate,
            let gamepadHost = appDelegate.gamepadHost
        else {
            super.scene(scene, willConnectTo: session, options: connectionOptions)
            return
        }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = gamepadHost
        self.window = window
        window.makeKeyAndVisible()

        let engine = gamepadHost.flutterViewController.engine
        registerSceneLifeCycle(with: engine)
        registeredEngine = engine

        super.scene(scene, willConnectTo: session, options: connectionOptions)

        if let url = connectionOptions.urlContexts.first?.url {
            appDelegate.deliverDeepLink(url, isLaunch: true)
        }
    }

    override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        super.scene(scene, openURLContexts: URLContexts)
        guard let url = URLContexts.first?.url,
            let appDelegate = UIApplication.shared.delegate as? AppDelegate
        else { return }
        appDelegate.deliverDeepLink(url, isLaunch: false)
    }

    override func sceneDidDisconnect(_ scene: UIScene) {
        if let engine = registeredEngine {
            unregisterSceneLifeCycle(with: engine)
            registeredEngine = nil
        }
        super.sceneDidDisconnect(scene)
    }
}
