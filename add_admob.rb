require 'xcodeproj'

project_path = 'UPME.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.first
has_admob = project.root_object.package_references.any? { |ref| ref.repositoryURL == 'https://github.com/googleads/swift-package-manager-google-mobile-ads.git' }

unless has_admob
  puts "Adding Google Mobile Ads Swift Package..."
  package_ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  package_ref.repositoryURL = 'https://github.com/googleads/swift-package-manager-google-mobile-ads.git'
  package_ref.requirement = {
    'kind' => 'upToNextMajorVersion',
    'minimumVersion' => '11.0.0'
  }
  project.root_object.package_references << package_ref

  package_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  package_dep.package = package_ref
  package_dep.product_name = 'GoogleMobileAds'

  frameworks_build_phase = target.frameworks_build_phase
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = package_dep
  frameworks_build_phase.files << build_file
  
  project.save
  puts "Saved project."
else
  puts "Already has GoogleMobileAds package."
end
