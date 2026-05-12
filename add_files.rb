require 'xcodeproj'

project_path = 'UPME.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

group = project.main_group.find_subpath('AppCode', true)

['StoreManager.swift', 'BannerAdView.swift'].each do |file_name|
  file_path = "AppCode/#{file_name}"
  unless group.files.any? { |f| f.path == file_name }
    file_ref = group.new_file(file_name)
    target.source_build_phase.add_file_reference(file_ref)
    puts "Added #{file_name} to target"
  else
    puts "#{file_name} already exists in project"
  end
end

project.save
puts "Saved project"
