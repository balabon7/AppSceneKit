//
//  OnboardingViewController.swift
//  DocScanPro
//
//  Created on 04.03.2026.
//

import Foundation
import UIKit

// MARK: - Model

struct OnboardingPage {
    let title: String
    let subtitle: String
    let iconName: String
    let iconBackgroundColor: UIColor
}

// MARK: - OnboardingViewController

final class OnboardingViewController: UIViewController {

    // MARK: - Completion Handler
    
    var onCompletion: (() -> Void)?

    // MARK: - Data

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "Scan Any\nDocument",
            subtitle: "Instantly capture contracts, receipts, IDs and photos with your camera — crisp, clear, ready to use.",
            iconName: "doc.text.viewfinder",
            iconBackgroundColor: UIColor(red: 1.0, green: 0.94, blue: 0.94, alpha: 1)
        ),
        OnboardingPage(
            title: "Organise Your\nLibrary",
            subtitle: "Create folders, sort by date, search instantly. All your important files in one tidy, secure place.",
            iconName: "folder.badge.plus",
            iconBackgroundColor: UIColor(red: 1.0, green: 0.95, blue: 0.93, alpha: 1)
        ),
        OnboardingPage(
            title: "Edit &\nAnnotate",
            subtitle: "Draw, add text, sign documents and erase mistakes. Full editing tools right at your fingertips.",
            iconName: "pencil.and.scribble",
            iconBackgroundColor: UIColor(red: 1.0, green: 0.93, blue: 0.94, alpha: 1)
        ),
        OnboardingPage(
            title: "Share with\nAnyone",
            subtitle: "Export as PDF, send via email or messenger. Your documents, delivered anywhere in seconds.",
            iconName: "square.and.arrow.up",
            iconBackgroundColor: UIColor(red: 1.0, green: 0.94, blue: 0.94, alpha: 1)
        )
    ]

    private var currentIndex: Int = 0
    private var isAnimating: Bool = false

    // MARK: - Accent Color

    private let accentColor = UIColor(red: 0.91, green: 0.137, blue: 0.102, alpha: 1)

    // MARK: - UI Elements

    private let skipButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("Skip", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        btn.setTitleColor(.systemGray, for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let illustrationContainer: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 90
        v.clipsToBounds = false
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let illustrationImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.tintColor = UIColor(red: 0.91, green: 0.137, blue: 0.102, alpha: 1)
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let titleLabel: UILabel = {
        let lbl = UILabel()
        lbl.numberOfLines = 2
        lbl.textColor = UIColor.label
        lbl.textAlignment = .left
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private let subtitleLabel: UILabel = {
        let lbl = UILabel()
        lbl.numberOfLines = 0
        lbl.font = .systemFont(ofSize: 15, weight: .regular)
        lbl.textColor = .systemGray
        lbl.textAlignment = .left
        lbl.lineBreakMode = .byWordWrapping
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private lazy var pageControl: AnimatedPageControl = {
        let pc = AnimatedPageControl()
        pc.numberOfPages = pages.count
        pc.currentPage = 0
        pc.activeColor = accentColor
        pc.inactiveColor = UIColor(white: 0.9, alpha: 1)
        pc.translatesAutoresizingMaskIntoConstraints = false
        pc.addTarget(self, action: #selector(pageControlTapped(_:)), for: .valueChanged)
        return pc
    }()

    private lazy var primaryButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.layer.cornerRadius = 16
        btn.backgroundColor = accentColor
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(primaryButtonTapped), for: .touchUpInside)
        btn.layer.shadowColor = UIColor(red: 0.91, green: 0.137, blue: 0.102, alpha: 0.35).cgColor
        btn.layer.shadowOffset = CGSize(width: 0, height: 4)
        btn.layer.shadowRadius = 12
        btn.layer.shadowOpacity = 1
        return btn
    }()

    private lazy var secondaryButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitleColor(.systemGray, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        btn.setTitle("Back", for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(secondaryButtonTapped), for: .touchUpInside)
        btn.alpha = 0
        return btn
    }()

    private var primaryButtonHeightConstraint: NSLayoutConstraint!
    private var secondaryButtonHeightConstraint: NSLayoutConstraint!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupGestures()
        configure(with: pages[currentIndex], animated: false, direction: .forward)
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .systemBackground

        view.addSubview(skipButton)
        view.addSubview(illustrationContainer)
        illustrationContainer.addSubview(illustrationImageView)
        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(pageControl)
        view.addSubview(primaryButton)
        view.addSubview(secondaryButton)

        primaryButtonHeightConstraint = primaryButton.heightAnchor.constraint(equalToConstant: 54)
        secondaryButtonHeightConstraint = secondaryButton.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            skipButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            skipButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            illustrationContainer.topAnchor.constraint(equalTo: skipButton.bottomAnchor, constant: 52),
            illustrationContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            illustrationContainer.widthAnchor.constraint(equalToConstant: 180),
            illustrationContainer.heightAnchor.constraint(equalToConstant: 180),

            illustrationImageView.centerXAnchor.constraint(equalTo: illustrationContainer.centerXAnchor),
            illustrationImageView.centerYAnchor.constraint(equalTo: illustrationContainer.centerYAnchor),
            illustrationImageView.widthAnchor.constraint(equalToConstant: 88),
            illustrationImageView.heightAnchor.constraint(equalToConstant: 88),

            titleLabel.topAnchor.constraint(equalTo: illustrationContainer.bottomAnchor, constant: 44),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),

            pageControl.bottomAnchor.constraint(equalTo: primaryButton.topAnchor, constant: -24),
            pageControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageControl.heightAnchor.constraint(equalToConstant: 8),

            primaryButton.bottomAnchor.constraint(equalTo: secondaryButton.topAnchor, constant: -12),
            primaryButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            primaryButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            primaryButtonHeightConstraint,

            secondaryButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            secondaryButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            secondaryButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            secondaryButtonHeightConstraint,
        ])

        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
    }

    private func setupGestures() {
        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeLeft.direction = .left
        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeRight.direction = .right
        view.addGestureRecognizer(swipeLeft)
        view.addGestureRecognizer(swipeRight)
    }

    // MARK: - Configuration

    enum TransitionDirection {
        case forward, backward
    }

    /// Animatable content views — ordered so stagger looks natural top→bottom.
    private var contentViews: [UIView] {
        [illustrationContainer, titleLabel, subtitleLabel]
    }

    private func configure(
        with page: OnboardingPage,
        animated: Bool,
        direction: TransitionDirection
    ) {
        let slideOffset: CGFloat = direction == .forward ? 60 : -60

        // ---------- helpers ----------

        let applyStaticContent = {
            self.pageControl.currentPage = self.currentIndex

            let isFirst = self.currentIndex == 0
            let isLast  = self.currentIndex == self.pages.count - 1

            self.skipButton.alpha = isLast ? 0 : 1
            self.primaryButton.setTitle(isLast ? "Get Started" : "Continue", for: .normal)

            self.animateBottomButtons(showBack: !isFirst, animated: animated)
        }

        let applyPageContent = {
            self.illustrationContainer.backgroundColor = page.iconBackgroundColor
            self.illustrationContainer.layer.shadowColor = UIColor(red: 0.91, green: 0.137, blue: 0.102, alpha: 0.12).cgColor
            self.illustrationContainer.layer.shadowOffset = CGSize(width: 0, height: 8)
            self.illustrationContainer.layer.shadowRadius = 24
            self.illustrationContainer.layer.shadowOpacity = 1

            let config = UIImage.SymbolConfiguration(pointSize: 52, weight: .light)
            self.illustrationImageView.image = UIImage(systemName: page.iconName, withConfiguration: config)

            let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle)
            if let serifDescriptor = descriptor.withDesign(.serif) {
                self.titleLabel.font = UIFont(descriptor: serifDescriptor, size: 32)
            } else {
                self.titleLabel.font = .systemFont(ofSize: 32, weight: .bold)
            }
            self.titleLabel.text = page.title
            self.subtitleLabel.text = page.subtitle
        }

        guard animated else {
            applyPageContent()
            applyStaticContent()
            return
        }

        isAnimating = true

        // 1. Slide + fade OUT current content
        let outOffset: CGFloat = -slideOffset
        let outDuration: TimeInterval = 0.22

        UIView.animate(
            withDuration: outDuration,
            delay: 0,
            options: [.curveEaseIn]
        ) {
            for (i, v) in self.contentViews.enumerated() {
                let staggeredOffset = outOffset - CGFloat(i) * 6
                v.transform = CGAffineTransform(translationX: staggeredOffset, y: 0)
                v.alpha = 0
            }
        } completion: { _ in

            // 2. Update content while invisible
            applyPageContent()
            applyStaticContent()

            // 3. Pre-position new content on the opposite side (ready to slide in)
            for v in self.contentViews {
                v.transform = CGAffineTransform(translationX: slideOffset, y: 0)
                v.alpha = 0
            }

            // 4. Slide + fade IN — staggered per element
            let inDuration: TimeInterval = 0.38
            let staggerDelay: TimeInterval = 0.045

            for (i, v) in self.contentViews.enumerated() {
                UIView.animate(
                    withDuration: inDuration,
                    delay: Double(i) * staggerDelay,
                    usingSpringWithDamping: 0.82,
                    initialSpringVelocity: 0.3,
                    options: [.curveEaseOut]
                ) {
                    v.transform = .identity
                    v.alpha = 1
                } completion: { _ in
                    if i == self.contentViews.count - 1 {
                        self.isAnimating = false
                    }
                }
            }

            // 5. Animate illustration icon scale bounce
            self.illustrationImageView.transform = CGAffineTransform(scaleX: 0.75, y: 0.75)
            UIView.animate(
                withDuration: 0.5,
                delay: 0,
                usingSpringWithDamping: 0.6,
                initialSpringVelocity: 0.4,
                options: []
            ) {
                self.illustrationImageView.transform = .identity
            }
        }
    }

    // MARK: - Bottom Buttons Animation

    private func animateBottomButtons(showBack: Bool, animated: Bool) {
        let targetHeight: CGFloat = showBack ? 54 : 0

        // Nothing changed — skip
        guard secondaryButtonHeightConstraint.constant != targetHeight else { return }

        secondaryButtonHeightConstraint.constant = targetHeight

        guard animated else {
            secondaryButton.alpha = showBack ? 1 : 0
            view.layoutIfNeeded()
            return
        }

        if showBack {
            // Appearing: slide primary button up, then fade-in Back underneath
            secondaryButton.alpha = 0
            secondaryButton.transform = CGAffineTransform(translationX: 0, y: 20)

            UIView.animate(
                withDuration: 0.42,
                delay: 0,
                usingSpringWithDamping: 0.72,
                initialSpringVelocity: 0.4,
                options: [.curveEaseOut]
            ) {
                self.view.layoutIfNeeded()          // primary button rises
            }

            UIView.animate(
                withDuration: 0.28,
                delay: 0.12,                        // slight delay so Back fades in after Continue has moved
                options: [.curveEaseOut]
            ) {
                self.secondaryButton.alpha = 1
                self.secondaryButton.transform = .identity
            }

        } else {
            // Disappearing: fade-out Back, then drop primary button down
            UIView.animate(
                withDuration: 0.18, delay: 0.1,
                options: [.curveEaseIn]
            ){
                self.secondaryButton.alpha = 0
                self.secondaryButton.transform = CGAffineTransform(translationX: 0, y: 12)
            } completion: { _ in
                self.secondaryButton.transform = .identity
                UIView.animate(
                    withDuration: 0.36,
                    delay: 0,
                    usingSpringWithDamping: 0.78,
                    initialSpringVelocity: 0.3,
                    options: [.curveEaseOut]
                ) {
                    self.view.layoutIfNeeded()      // primary button settles down
                }
            }
        }
    }

    // MARK: - Navigation

    private func goToNext() {
        guard !isAnimating else { return }
        guard currentIndex < pages.count - 1 else { finish(); return }
        currentIndex += 1
        configure(with: pages[currentIndex], animated: true, direction: .forward)
    }

    private func goToPrevious() {
        guard !isAnimating, currentIndex > 0 else { return }
        currentIndex -= 1
        configure(with: pages[currentIndex], animated: true, direction: .backward)
    }

    private func finish() {
        dismiss(animated: true) { [weak self] in
            self?.onCompletion?()
        }
    }

    // MARK: - Actions

    @objc private func primaryButtonTapped() {
        animateButtonPress(primaryButton)
        goToNext()
    }

    @objc private func secondaryButtonTapped() {
        goToPrevious()
    }

    @objc private func skipTapped() {
        finish()
    }

    @objc private func pageControlTapped(_ sender: AnimatedPageControl) {
        let target = sender.currentPage
        guard target != currentIndex, !isAnimating else { return }
        let direction: TransitionDirection = target > currentIndex ? .forward : .backward
        currentIndex = target
        configure(with: pages[currentIndex], animated: true, direction: direction)
    }

    @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        switch gesture.direction {
        case .left:  goToNext()
        case .right: goToPrevious()
        default: break
        }
    }

    // MARK: - Helpers

    private func animateButtonPress(_ button: UIButton) {
        UIView.animate(withDuration: 0.1, animations: {
            button.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                button.transform = .identity
            }
        }
    }
}

// MARK: - AnimatedPageControl

final class AnimatedPageControl: UIControl {

    var numberOfPages: Int = 0 { didSet { rebuild() } }
    var currentPage: Int = 0   { didSet { updateDots() } }
    var activeColor: UIColor   = .systemRed
    var inactiveColor: UIColor = UIColor(white: 0.9, alpha: 1)

    private var dots: [UIView] = []
    private var widthConstraints: [NSLayoutConstraint] = []

    private let activeWidth: CGFloat   = 24
    private let inactiveWidth: CGFloat = 8
    private let dotHeight: CGFloat     = 8
    private let spacing: CGFloat       = 6

    override init(frame: CGRect) { super.init(frame: frame) }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    
    override var intrinsicContentSize: CGSize {
        guard numberOfPages > 0 else { return .zero }
        let totalWidth = activeWidth
            + CGFloat(numberOfPages - 1) * inactiveWidth
            + CGFloat(numberOfPages - 1) * spacing
        return CGSize(width: totalWidth, height: dotHeight)
    }

    private func rebuild() {
        dots.forEach { $0.removeFromSuperview() }
        dots = []
        widthConstraints = []
        var prev: UIView? = nil

        for i in 0..<numberOfPages {
            let dot = UIView()
            dot.layer.cornerRadius = dotHeight / 2
            dot.backgroundColor = i == currentPage ? activeColor : inactiveColor
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.isUserInteractionEnabled = true
            let tap = UITapGestureRecognizer(target: self, action: #selector(dotTapped(_:)))
            dot.addGestureRecognizer(tap)
            dot.tag = i
            addSubview(dot)

            let width = i == currentPage ? activeWidth : inactiveWidth

            let wc = dot.widthAnchor.constraint(equalToConstant: width)
            wc.priority = .defaultHigh
            widthConstraints.append(wc)

            NSLayoutConstraint.activate([
                dot.centerYAnchor.constraint(equalTo: centerYAnchor),
                dot.heightAnchor.constraint(equalToConstant: dotHeight),
                wc,
            ])

            if let prev = prev {
                let spacing = dot.leadingAnchor.constraint(equalTo: prev.trailingAnchor, constant: spacing)
                spacing.priority = .defaultHigh
                spacing.isActive = true
            } else {
                dot.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
            }

            dots.append(dot)
            prev = dot
        }

        if let last = dots.last {
            let trailing = last.trailingAnchor.constraint(equalTo: trailingAnchor)
            trailing.priority = .defaultHigh
            trailing.isActive = true
        }
    }

    private func updateDots() {
        guard dots.count == numberOfPages else { return }
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5) {
            for (i, dot) in self.dots.enumerated() {
                let isActive = i == self.currentPage
                self.widthConstraints[i].constant = isActive ? self.activeWidth : self.inactiveWidth
                dot.backgroundColor = isActive ? self.activeColor : self.inactiveColor
            }
            self.layoutIfNeeded()
        }
    }

    @objc private func dotTapped(_ gesture: UITapGestureRecognizer) {
        guard let dot = gesture.view else { return }
        currentPage = dot.tag
        sendActions(for: .valueChanged)
    }
}

// MARK: - UILabel Letter Spacing Helper

private extension UILabel {
    func letterSpacing(_ value: CGFloat) {
        guard let text = self.text else { return }
        let attributed = NSAttributedString(
            string: text,
            attributes: [.kern: value]
        )
        self.attributedText = attributed
    }
}
