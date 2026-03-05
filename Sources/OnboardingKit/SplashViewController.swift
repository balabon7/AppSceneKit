//
// SplashViewController.swift
// AppSceneKit SDK
//
//  Created on 04.03.2026.
//

import Foundation
import UIKit

/// Білий екран з лоадером — показується поки онбординг завантажується.
/// Замінює MainTabBarController як початковий rootViewController.
final class SplashViewController: UIViewController {

    // MARK: - UI

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .systemGray
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        view.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        activityIndicator.startAnimating()
    }
}
