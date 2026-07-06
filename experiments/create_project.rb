require 'xcodeproj'
project_name = 'DesktopPet'
project = Xcodeproj::Project.new("#{project_name}.xcodeproj")
app_target = project.new_target(:application, project_name, :osx)
app_target.build_configuration_list.set_setting('INFOPLIST_FILE', "#{project_name}/Info.plist")
app_target.build_configuration_list.set_setting('PRODUCT_BUNDLE_IDENTIFIER', "com.example.#{project_name}")
app_target.build_configuration_list.set_setting('SWIFT_VERSION', '5.0')
app_target.build_configuration_list.set_setting('MACOSX_DEPLOYMENT_TARGET', '14.0')
group = project.main_group.new_group(project_name, project_name)
Dir.mkdir(project_name) unless Dir.exist?(project_name)

file_ref = group.new_file("Info.plist")

Dir.glob("#{project_name}/*.swift").each do |file|
  file_ref = group.new_file(File.basename(file))
  app_target.source_build_phase.add_file_reference(file_ref)
end

project.save
