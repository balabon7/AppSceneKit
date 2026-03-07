Pod::Spec.new do |spec|
  spec.name         = "AppSceneKit"
  spec.version      = "1.0.0"
  spec.summary      = "UIKit library with Onboarding, Paywall and Rating modules"
  spec.description  = "AppSceneKit includes OnboardingKit, PaywallKit (Adapty) and RatingKit for iOS applications"
  spec.homepage     = "https://github.com/balabon7/AppSceneKit"
  spec.license      = { :type => "MIT", :file => "LICENSE" }
  spec.author       = { "Oleksandr Balabon" => "balabon7@gmail.com" }

  spec.ios.deployment_target = "15.0"
  spec.swift_versions = "5.9"

  spec.source = {
    :git => "https://github.com/balabon7/AppSceneKit.git",
    :tag => spec.version.to_s
  }

  spec.subspec "OnboardingKit" do |s|
    s.source_files = "Sources/OnboardingKit/**/*.swift"
  end

  spec.subspec "PaywallKit" do |s|
    s.source_files = "Sources/PaywallKit/**/*.swift"
    s.dependency "Adapty", "~> 3.0"
    s.dependency "AdaptyUI", "~> 3.0"
  end

  spec.subspec "RatingKit" do |s|
    s.source_files = "Sources/Ratingkit/**/*.swift"
    s.dependency "AppSceneKit/PaywallKit"
  end
end