# 往 Runner.xcodeproj 加小组件扩展 target（幂等，可重复运行）。
# 需要 gem install xcodeproj。生成结果已提交，一般不用再跑；改了文件列表时再跑一次。
require 'xcodeproj'

ios = File.expand_path('..', __dir__)
proj = Xcodeproj::Project.open(File.join(ios, 'Runner.xcodeproj'))
runner = proj.targets.find { |t| t.name == 'Runner' }
NAME = 'HonghongWidgets'

ext = proj.targets.find { |t| t.name == NAME }
unless ext
  ext = proj.new_target(:app_extension, NAME, :ios, '17.0', nil, :swift)
end

group = proj.main_group[NAME] || proj.main_group.new_group(NAME, NAME)
shared = proj.main_group['Shared'] || proj.main_group.new_group('Shared', 'Shared')

def file_ref(group, path)
  group.files.find { |f| f.path == path } || group.new_reference(path)
end

swift = file_ref(group, 'HonghongWidgets.swift')
assets = file_ref(group, 'Assets.xcassets')
file_ref(group, 'Info.plist')
file_ref(group, 'HonghongWidgets.entitlements')
xcconfig = file_ref(group, 'Widgets.xcconfig')
shared_swift = file_ref(shared, 'HHShared.swift')

def add_once(phase, ref)
  phase.add_file_reference(ref, true) unless phase.files_references.include?(ref)
end

add_once(ext.source_build_phase, swift)
add_once(ext.source_build_phase, shared_swift)
add_once(ext.resources_build_phase, assets)

# Runner 也编译共享文件（实时活动的 LiveActivityIntent 在 App 进程执行）和桥接代码
runner_group = proj.main_group['Runner']
bridge = file_ref(runner_group, 'LiveActivityBridge.swift')
file_ref(runner_group, 'Runner.entitlements')
add_once(runner.source_build_phase, shared_swift)
add_once(runner.source_build_phase, bridge)

ext.build_configurations.each do |c|
  c.base_configuration_reference = xcconfig
  s = c.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.honghong.honghong.HonghongWidgets'
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['INFOPLIST_FILE'] = 'HonghongWidgets/Info.plist'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['CODE_SIGN_ENTITLEMENTS'] = 'HonghongWidgets/HonghongWidgets.entitlements'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  s['SWIFT_VERSION'] = '5.0'
  s['TARGETED_DEVICE_FAMILY'] = '1,2'
  s['SKIP_INSTALL'] = 'YES'
  s['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = ''
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
  s['CODE_SIGN_STYLE'] = 'Automatic'
  s['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
  s['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
end

# Profile 配置（Flutter 工程有 Debug/Release/Profile）
%w[Profile].each do |name|
  next if ext.build_configurations.any? { |c| c.name == name }
  rel = ext.build_configurations.find { |c| c.name == 'Release' }
  c = ext.add_build_configuration(name, :release)
  c.build_settings.merge!(rel.build_settings)
  c.base_configuration_reference = xcconfig
end

runner.build_configurations.each do |c|
  c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end

runner.add_dependency(ext) unless runner.dependencies.any? { |d| d.target == ext }

embed = runner.copy_files_build_phases.find { |p| p.name == 'Embed Foundation Extensions' }
unless embed
  embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
  embed.symbol_dst_subfolder_spec = :plug_ins
end
unless embed.files_references.include?(ext.product_reference)
  bf = embed.add_file_reference(ext.product_reference, true)
  bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
end
# 放到 "Thin Binary" 等脚本阶段之前，避免 Xcode 报构建依赖环
phases = runner.build_phases
phases.delete(embed)
idx = phases.index { |p| p.is_a?(Xcodeproj::Project::Object::PBXShellScriptBuildPhase) && p.name.to_s.include?('Thin Binary') } || phases.length
phases.insert(idx, embed)

proj.save
puts "ok: #{ext.name} (#{ext.uuid}) embedded in Runner"
