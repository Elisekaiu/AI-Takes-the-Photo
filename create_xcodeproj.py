"""仅供维护者重建随仓库附带的 .xcodeproj；日常使用直接打开工程即可。"""
from pathlib import Path
from hashlib import sha1

root=Path(__file__).resolve().parent
files=sorted((root/'App').glob('*.swift'))

def uid(tag):return sha1(tag.encode()).hexdigest()[:24].upper()

P=uid('project'); MAIN=uid('main-group'); SRC=uid('source-group'); PROD=uid('products');
T=uid('target'); APP=uid('app-file-ref'); PBX_CONF=uid('project-config-list'); TAR_CONF=uid('target-config-list');
SRC_PHASE=uid('src-phase'); FRAMEWORK_PHASE=uid('framework-phase'); RESOURCE_PHASE=uid('resource-phase');

objects=[]
def obj(key,body):objects.append(f'\t\t{key} = {{{body}\n\t\t}};')
def pathlist(items):return '(\n'+''.join(f'\t\t\t\t{key},\n' for key in items)+'\t\t\t)'
for file in files:
    ref=uid('ref:'+file.name)
    bf=uid('build:'+file.name)
    obj(bf,f'\n\t\t\tisa = PBXBuildFile;\n\t\t\tfileRef = {ref}; /* {file.name} */')
    obj(ref,f'\n\t\t\tisa = PBXFileReference;\n\t\t\tlastKnownFileType = sourcecode.swift;\n\t\t\tpath = "{file.name}";\n\t\t\tsourceTree = "<group>";')
obj(APP,'\n\t\t\tisa = PBXFileReference;\n\t\t\texplicitFileType = wrapper.application;\n\t\t\tincludeInIndex = 0;\n\t\t\tpath = AIShutterDemo.app;\n\t\t\tsourceTree = BUILT_PRODUCTS_DIR;')
obj(MAIN,f'''\n\t\t\tisa = PBXGroup;
\t\t\tchildren = {pathlist([SRC,PROD])};
\t\t\tsourceTree = "<group>";''')
obj(SRC,f'''\n\t\t\tisa = PBXGroup;
\t\t\tchildren = {pathlist([uid('ref:'+x.name) for x in files])};
\t\t\tpath = App;
\t\t\tsourceTree = "<group>";''')
obj(PROD,f'''\n\t\t\tisa = PBXGroup;
\t\t\tchildren = {pathlist([APP])};
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";''')
obj(SRC_PHASE,f'''\n\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = {pathlist([uid('build:'+x.name) for x in files])};
\t\t\trunOnlyForDeploymentPostprocessing = 0;''')
obj(FRAMEWORK_PHASE,'\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = ();\n\t\t\trunOnlyForDeploymentPostprocessing = 0;')
obj(RESOURCE_PHASE,'\n\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = ();\n\t\t\trunOnlyForDeploymentPostprocessing = 0;')
obj(T,f'''\n\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {TAR_CONF};
\t\t\tbuildPhases = {pathlist([SRC_PHASE,FRAMEWORK_PHASE,RESOURCE_PHASE])};
\t\t\tbuildRules = ();
\t\t\tdependencies = ();
\t\t\tname = AIShutterDemo;
\t\t\tproductName = AIShutterDemo;
\t\t\tproductReference = {APP};
\t\t\tproductType = "com.apple.product-type.application";''')
obj(P,f'''\n\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastUpgradeCheck = 1530;
\t\t\t\tTargetAttributes = {{ {T} = {{ CreatedOnToolsVersion = 15.0; }}; }};
\t\t\t}};
\t\t\tbuildConfigurationList = {PBX_CONF};
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = "zh-Hans";
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = ( "zh-Hans", en, Base );
\t\t\tmainGroup = {MAIN};
\t\t\tproductRefGroup = {PROD};
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = {pathlist([T])};''')

def build_settings(config,target):
    data={
      'ALWAYS_SEARCH_USER_PATHS':'NO','CLANG_ENABLE_MODULES':'YES',
      'CODE_SIGN_STYLE':'Automatic','IPHONEOS_DEPLOYMENT_TARGET':'17.0',
      'SDKROOT':'iphoneos','SWIFT_VERSION':'5.0',
      'TARGETED_DEVICE_FAMILY':'"1"',
      'SWIFT_OPTIMIZATION_LEVEL':'"-Onone"' if config=='Debug' else '"-O"',
      'DEBUG_INFORMATION_FORMAT':'dwarf',
      'ENABLE_TESTABILITY':'YES' if config=='Debug' else 'NO',
    }
    if target:
        data.update({
            'ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS':'YES',
            'GENERATE_INFOPLIST_FILE':'YES',
            'INFOPLIST_KEY_CFBundleDisplayName':'"AI Takes the Photo"',
            'INFOPLIST_KEY_NSCameraUsageDescription':'"只有你主动打开相机时，才会预览并拍照。"',
            'INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription':'"把你选中的照片保存到 iPhone 相册。"',
            'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone':'"UIInterfaceOrientationPortrait"',
            'LD_RUNPATH_SEARCH_PATHS':'"$(inherited) @executable_path/Frameworks"',
            'PRODUCT_BUNDLE_IDENTIFIER':'dev.example.AIShutterDemo',
            'PRODUCT_NAME':'"$(TARGET_NAME)"',
            'SUPPORTED_PLATFORMS':'"iphoneos iphonesimulator"',
            'SWIFT_EMIT_LOC_STRINGS':'YES',
            'DEVELOPMENT_TEAM':'""',
        })
    return '{\n'+''.join(f'\t\t\t\t{k} = {v};\n' for k,v in sorted(data.items()))+'\t\t\t}'

for config in ('Debug','Release'):
  for target in (False,True):
    key=uid(('t-' if target else 'p-')+config)
    obj(key,f'\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {build_settings(config,target)};\n\t\t\tname = {config};')
for conf,kind in [(PBX_CONF,'p-'),(TAR_CONF,'t-')]:
    obj(conf, f'''\n\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = {pathlist([uid(kind+'Debug'),uid(kind+'Release')])};
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;''')

body='// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n'+'\n'.join(objects)+'\n\t};\n\trootObject = '+P+';\n}\n'
(root/'AIShutterDemo.xcodeproj'/'project.pbxproj').write_text(body,encoding='utf-8')
print('Generated',len(files),'Swift sources ->',root/'AIShutterDemo.xcodeproj'/'project.pbxproj')
