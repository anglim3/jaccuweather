#!/usr/bin/env node
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

function hid(name) {
  return crypto.createHash('sha1').update('jaccuweather:' + name).digest('hex').slice(0, 24).toUpperCase();
}

const root = path.resolve(__dirname, '..');
const appDir = path.join(root, 'Jaccuweather');
const widgetDir = path.join(root, 'JaccuweatherWidgets');
const sharedDir = path.join(root, 'Shared');

function walk(dir, ext, base = dir, acc = []) {
  if (!fs.existsSync(dir)) return acc;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, ext, base, acc);
    else if (entry.name.endsWith(ext)) acc.push(path.relative(base, full).split(path.sep).join('/'));
  }
  return acc;
}

const sources = walk(appDir, '.swift').sort();
const sharedSources = walk(sharedDir, '.swift').sort();
const widgetSources = walk(widgetDir, '.swift').sort();

const ids = {
  project: hid('project'),
  target: hid('target'),
  product: hid('product'),
  sourcesPhase: hid('sourcesPhase'),
  resourcesPhase: hid('resourcesPhase'),
  frameworksPhase: hid('frameworksPhase'),
  embedPhase: hid('embedPhase'),
  widgetEmbed: hid('widgetEmbed'),
  widgetProxy: hid('widgetProxy'),
  widgetDep: hid('widgetDep'),
  jsCore: hid('jsCore'),
  jsCoreBuild: hid('jsCoreBuild'),
  mapKit: hid('mapKit'),
  mapKitBuild: hid('mapKitBuild'),
  webKit: hid('webKit'),
  webKitBuild: hid('webKitBuild'),
  widgetKit: hid('widgetKit'),
  widgetKitAppBuild: hid('widgetKitAppBuild'),
  widgetKitExtBuild: hid('widgetKitExtBuild'),
  mainGroup: hid('mainGroup'),
  productsGroup: hid('productsGroup'),
  appGroup: hid('appGroup'),
  modelsGroup: hid('modelsGroup'),
  servicesGroup: hid('servicesGroup'),
  viewModelsGroup: hid('viewModelsGroup'),
  viewsGroup: hid('viewsGroup'),
  configGroup: hid('configGroup'),
  sharedGroup: hid('sharedGroup'),
  widgetGroup: hid('widgetGroup'),
  assets: hid('assets'),
  assetsBuild: hid('assetsBuild'),
  logicFolder: hid('logicFolder'),
  logicBuild: hid('logicBuild'),
  iconsFolder: hid('iconsFolder'),
  iconsBuild: hid('iconsBuild'),
  projDebug: hid('projDebug'),
  projRelease: hid('projRelease'),
  targetDebug: hid('targetDebug'),
  targetRelease: hid('targetRelease'),
  widgetTarget: hid('widgetTarget'),
  widgetProduct: hid('widgetProduct'),
  widgetSourcesPhase: hid('widgetSourcesPhase'),
  widgetFrameworksPhase: hid('widgetFrameworksPhase'),
  widgetResourcesPhase: hid('widgetResourcesPhase'),
  widgetDebug: hid('widgetDebug'),
  widgetRelease: hid('widgetRelease'),
  widgetConfigs: hid('widgetConfigs'),
  debugXcconfig: hid('debugXcconfig'),
  releaseXcconfig: hid('releaseXcconfig'),
  secretsXcconfig: hid('secretsXcconfig'),
  secretsExample: hid('secretsExample'),
  plist: hid('plist'),
  appEntitlements: hid('appEntitlements'),
  widgetPlist: hid('widgetPlist'),
  widgetEntitlements: hid('widgetEntitlements'),
  projectConfigs: hid('projectConfigs'),
  targetConfigs: hid('targetConfigs'),
};

const fileIds = {};
for (const file of sources) fileIds[file] = { ref: hid('ref:' + file), build: hid('build:' + file) };
const sharedIds = {};
for (const file of sharedSources) {
  sharedIds[file] = {
    ref: hid('shared-ref:' + file),
    appBuild: hid('shared-app:' + file),
    widgetBuild: hid('shared-widget:' + file),
  };
}
const widgetIds = {};
for (const file of widgetSources) widgetIds[file] = { ref: hid('widget-ref:' + file), build: hid('widget-build:' + file) };

const groups = {
  Models: sources.filter((f) => f.startsWith('Models/')),
  Services: sources.filter((f) => f.startsWith('Services/')),
  ViewModels: sources.filter((f) => f.startsWith('ViewModels/')),
  Views: sources.filter((f) => f.startsWith('Views/')),
  root: sources.filter((f) => !f.includes('/')),
};

const swiftBuildFiles = sources
  .map((f) => `\t\t${fileIds[f].build} /* ${path.basename(f)} in Sources */ = {isa = PBXBuildFile; fileRef = ${fileIds[f].ref} /* ${path.basename(f)} */; };`)
  .join('\n');
const sharedAppBuilds = sharedSources
  .map((f) => `\t\t${sharedIds[f].appBuild} /* ${path.basename(f)} in Sources */ = {isa = PBXBuildFile; fileRef = ${sharedIds[f].ref} /* ${path.basename(f)} */; };`)
  .join('\n');
const sharedWidgetBuilds = sharedSources
  .map((f) => `\t\t${sharedIds[f].widgetBuild} /* ${path.basename(f)} in Sources */ = {isa = PBXBuildFile; fileRef = ${sharedIds[f].ref} /* ${path.basename(f)} */; };`)
  .join('\n');
const widgetBuildFiles = widgetSources
  .map((f) => `\t\t${widgetIds[f].build} /* ${path.basename(f)} in Sources */ = {isa = PBXBuildFile; fileRef = ${widgetIds[f].ref} /* ${path.basename(f)} */; };`)
  .join('\n');

const fileRefs = sources
  .map((f) => `\t\t${fileIds[f].ref} /* ${path.basename(f)} */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ${path.basename(f)}; sourceTree = "<group>"; };`)
  .join('\n');
const sharedRefs = sharedSources
  .map((f) => `\t\t${sharedIds[f].ref} /* ${path.basename(f)} */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ${path.basename(f)}; sourceTree = "<group>"; };`)
  .join('\n');
const widgetRefs = widgetSources
  .map((f) => `\t\t${widgetIds[f].ref} /* ${path.basename(f)} */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ${path.basename(f)}; sourceTree = "<group>"; };`)
  .join('\n');

function groupBlock(id, name, files, folderPath) {
  const children = files.map((f) => `\t\t\t\t${fileIds[f].ref} /* ${path.basename(f)} */,`).join('\n');
  return `\t\t${id} /* ${name} */ = {
			isa = PBXGroup;
			children = (
${children}
			);
			path = ${folderPath};
			sourceTree = "<group>";
		};`;
}

const sourceBuildPhase = sources
  .map((f) => `\t\t\t\t${fileIds[f].build} /* ${path.basename(f)} in Sources */,`)
  .concat(sharedSources.map((f) => `\t\t\t\t${sharedIds[f].appBuild} /* ${path.basename(f)} in Sources */,`))
  .join('\n');
const widgetSourceBuildPhase = widgetSources
  .map((f) => `\t\t\t\t${widgetIds[f].build} /* ${path.basename(f)} in Sources */,`)
  .concat(sharedSources.map((f) => `\t\t\t\t${sharedIds[f].widgetBuild} /* ${path.basename(f)} in Sources */,`))
  .join('\n');
const sharedGroupChildren = sharedSources
  .map((f) => `\t\t\t\t${sharedIds[f].ref} /* ${path.basename(f)} */,`)
  .join('\n');
const widgetGroupChildren = [
  ...widgetSources.map((f) => `\t\t\t\t${widgetIds[f].ref} /* ${path.basename(f)} */,`),
  `\t\t\t\t${ids.widgetPlist} /* Info.plist */,`,
  `\t\t\t\t${ids.widgetEntitlements} /* JaccuweatherWidgets.entitlements */,`,
].join('\n');

const signing = `CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION = YES;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = "";`;

const pbxproj = `// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 56;
	objects = {

/* Begin PBXBuildFile section */
${swiftBuildFiles}
${sharedAppBuilds}
${sharedWidgetBuilds}
${widgetBuildFiles}
		${ids.assetsBuild} /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = ${ids.assets} /* Assets.xcassets */; };
		${ids.logicBuild} /* Logic in Resources */ = {isa = PBXBuildFile; fileRef = ${ids.logicFolder} /* Logic */; };
		${ids.iconsBuild} /* Icons in Resources */ = {isa = PBXBuildFile; fileRef = ${ids.iconsFolder} /* Icons */; };
		${ids.jsCoreBuild} /* JavaScriptCore.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = ${ids.jsCore} /* JavaScriptCore.framework */; };
		${ids.mapKitBuild} /* MapKit.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = ${ids.mapKit} /* MapKit.framework */; };
		${ids.webKitBuild} /* WebKit.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = ${ids.webKit} /* WebKit.framework */; };
		${ids.widgetKitAppBuild} /* WidgetKit.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = ${ids.widgetKit} /* WidgetKit.framework */; };
		${ids.widgetKitExtBuild} /* WidgetKit.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = ${ids.widgetKit} /* WidgetKit.framework */; };
		${ids.widgetEmbed} /* JaccuweatherWidgets.appex in Embed Foundation Extensions */ = {isa = PBXBuildFile; fileRef = ${ids.widgetProduct} /* JaccuweatherWidgets.appex */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		${ids.widgetProxy} /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = ${ids.project} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = ${ids.widgetTarget};
			remoteInfo = JaccuweatherWidgets;
		};
/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
		${ids.embedPhase} /* Embed Foundation Extensions */ = {
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 13;
			files = (
				${ids.widgetEmbed} /* JaccuweatherWidgets.appex in Embed Foundation Extensions */,
			);
			name = "Embed Foundation Extensions";
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
		${ids.product} /* Jaccuweather.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Jaccuweather.app; sourceTree = BUILT_PRODUCTS_DIR; };
		${ids.widgetProduct} /* JaccuweatherWidgets.appex */ = {isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = JaccuweatherWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; };
		${ids.assets} /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; };
		${ids.logicFolder} /* Logic */ = {isa = PBXFileReference; lastKnownFileType = folder; name = Logic; path = Resources/Logic; sourceTree = "<group>"; };
		${ids.iconsFolder} /* Icons */ = {isa = PBXFileReference; lastKnownFileType = folder; name = Icons; path = Resources/Icons; sourceTree = "<group>"; };
		${ids.debugXcconfig} /* Debug.xcconfig */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Debug.xcconfig; sourceTree = "<group>"; };
		${ids.releaseXcconfig} /* Release.xcconfig */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Release.xcconfig; sourceTree = "<group>"; };
		${ids.secretsXcconfig} /* Secrets.xcconfig */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Secrets.xcconfig; sourceTree = "<group>"; };
		${ids.secretsExample} /* Secrets.xcconfig.example */ = {isa = PBXFileReference; lastKnownFileType = text; path = Secrets.xcconfig.example; sourceTree = "<group>"; };
		${ids.plist} /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
		${ids.appEntitlements} /* Jaccuweather.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = Jaccuweather.entitlements; sourceTree = "<group>"; };
		${ids.widgetPlist} /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
		${ids.widgetEntitlements} /* JaccuweatherWidgets.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = JaccuweatherWidgets.entitlements; sourceTree = "<group>"; };
		${ids.jsCore} /* JavaScriptCore.framework */ = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = JavaScriptCore.framework; path = System/Library/Frameworks/JavaScriptCore.framework; sourceTree = SDKROOT; };
		${ids.mapKit} /* MapKit.framework */ = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = MapKit.framework; path = System/Library/Frameworks/MapKit.framework; sourceTree = SDKROOT; };
		${ids.webKit} /* WebKit.framework */ = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = WebKit.framework; path = System/Library/Frameworks/WebKit.framework; sourceTree = SDKROOT; };
		${ids.widgetKit} /* WidgetKit.framework */ = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = WidgetKit.framework; path = System/Library/Frameworks/WidgetKit.framework; sourceTree = SDKROOT; };
${fileRefs}
${sharedRefs}
${widgetRefs}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		${ids.frameworksPhase} /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				${ids.jsCoreBuild} /* JavaScriptCore.framework in Frameworks */,
				${ids.mapKitBuild} /* MapKit.framework in Frameworks */,
				${ids.webKitBuild} /* WebKit.framework in Frameworks */,
				${ids.widgetKitAppBuild} /* WidgetKit.framework in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		${ids.widgetFrameworksPhase} /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				${ids.widgetKitExtBuild} /* WidgetKit.framework in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		${ids.mainGroup} = {
			isa = PBXGroup;
			children = (
				${ids.appGroup} /* Jaccuweather */,
				${ids.widgetGroup} /* JaccuweatherWidgets */,
				${ids.sharedGroup} /* Shared */,
				${ids.productsGroup} /* Products */,
				${ids.jsCore} /* JavaScriptCore.framework */,
				${ids.mapKit} /* MapKit.framework */,
				${ids.webKit} /* WebKit.framework */,
				${ids.widgetKit} /* WidgetKit.framework */,
			);
			sourceTree = "<group>";
		};
		${ids.productsGroup} /* Products */ = {
			isa = PBXGroup;
			children = (
				${ids.product} /* Jaccuweather.app */,
				${ids.widgetProduct} /* JaccuweatherWidgets.appex */,
			);
			name = Products;
			sourceTree = "<group>";
		};
		${ids.appGroup} /* Jaccuweather */ = {
			isa = PBXGroup;
			children = (
${groups.root.map((f) => `\t\t\t\t${fileIds[f].ref} /* ${path.basename(f)} */,`).join('\n')}
				${ids.plist} /* Info.plist */,
				${ids.appEntitlements} /* Jaccuweather.entitlements */,
				${ids.assets} /* Assets.xcassets */,
				${ids.logicFolder} /* Logic */,
				${ids.iconsFolder} /* Icons */,
				${ids.configGroup} /* Config */,
				${ids.modelsGroup} /* Models */,
				${ids.servicesGroup} /* Services */,
				${ids.viewModelsGroup} /* ViewModels */,
				${ids.viewsGroup} /* Views */,
			);
			path = Jaccuweather;
			sourceTree = "<group>";
		};
		${ids.widgetGroup} /* JaccuweatherWidgets */ = {
			isa = PBXGroup;
			children = (
${widgetGroupChildren}
			);
			path = JaccuweatherWidgets;
			sourceTree = "<group>";
		};
		${ids.sharedGroup} /* Shared */ = {
			isa = PBXGroup;
			children = (
${sharedGroupChildren}
			);
			path = Shared;
			sourceTree = "<group>";
		};
		${ids.configGroup} /* Config */ = {
			isa = PBXGroup;
			children = (
				${ids.debugXcconfig} /* Debug.xcconfig */,
				${ids.releaseXcconfig} /* Release.xcconfig */,
				${ids.secretsXcconfig} /* Secrets.xcconfig */,
				${ids.secretsExample} /* Secrets.xcconfig.example */,
			);
			path = Config;
			sourceTree = "<group>";
		};
${groupBlock(ids.modelsGroup, 'Models', groups.Models, 'Models')}
${groupBlock(ids.servicesGroup, 'Services', groups.Services, 'Services')}
${groupBlock(ids.viewModelsGroup, 'ViewModels', groups.ViewModels, 'ViewModels')}
${groupBlock(ids.viewsGroup, 'Views', groups.Views, 'Views')}
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		${ids.target} /* Jaccuweather */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = ${ids.targetConfigs} /* Build configuration list for PBXNativeTarget "Jaccuweather" */;
			buildPhases = (
				${ids.sourcesPhase} /* Sources */,
				${ids.frameworksPhase} /* Frameworks */,
				${ids.resourcesPhase} /* Resources */,
				${ids.embedPhase} /* Embed Foundation Extensions */,
			);
			buildRules = (
			);
			dependencies = (
				${ids.widgetDep} /* PBXTargetDependency */,
			);
			name = Jaccuweather;
			productName = Jaccuweather;
			productReference = ${ids.product} /* Jaccuweather.app */;
			productType = "com.apple.product-type.application";
		};
		${ids.widgetTarget} /* JaccuweatherWidgets */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = ${ids.widgetConfigs} /* Build configuration list for PBXNativeTarget "JaccuweatherWidgets" */;
			buildPhases = (
				${ids.widgetSourcesPhase} /* Sources */,
				${ids.widgetFrameworksPhase} /* Frameworks */,
				${ids.widgetResourcesPhase} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = JaccuweatherWidgets;
			productName = JaccuweatherWidgets;
			productReference = ${ids.widgetProduct} /* JaccuweatherWidgets.appex */;
			productType = "com.apple.product-type.app-extension";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		${ids.project} /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1500;
				LastUpgradeCheck = 1500;
				TargetAttributes = {
					${ids.target} = {
						CreatedOnToolsVersion = 15.0;
					};
					${ids.widgetTarget} = {
						CreatedOnToolsVersion = 15.0;
					};
				};
			};
			buildConfigurationList = ${ids.projectConfigs} /* Build configuration list for PBXProject "Jaccuweather" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = ${ids.mainGroup};
			productRefGroup = ${ids.productsGroup} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				${ids.target} /* Jaccuweather */,
				${ids.widgetTarget} /* JaccuweatherWidgets */,
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		${ids.resourcesPhase} /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				${ids.assetsBuild} /* Assets.xcassets in Resources */,
				${ids.logicBuild} /* Logic in Resources */,
				${ids.iconsBuild} /* Icons in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		${ids.widgetResourcesPhase} /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		${ids.sourcesPhase} /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
${sourceBuildPhase}
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		${ids.widgetSourcesPhase} /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
${widgetSourceBuildPhase}
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		${ids.widgetDep} /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = ${ids.widgetTarget} /* JaccuweatherWidgets */;
			targetProxy = ${ids.widgetProxy} /* PBXContainerItemProxy */;
		};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
		${ids.projDebug} /* Debug */ = {
			isa = XCBuildConfiguration;
			baseConfigurationReference = ${ids.debugXcconfig} /* Debug.xcconfig */;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
				GCC_DYNAMIC_NO_PIC = NO;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = iphoneos;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 5.0;
			};
			name = Debug;
		};
		${ids.projRelease} /* Release */ = {
			isa = XCBuildConfiguration;
			baseConfigurationReference = ${ids.releaseXcconfig} /* Release.xcconfig */;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				SDKROOT = iphoneos;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
				SWIFT_VERSION = 5.0;
				VALIDATE_PRODUCT = YES;
			};
			name = Release;
		};
		${ids.targetDebug} /* Debug */ = {
			isa = XCBuildConfiguration;
			baseConfigurationReference = ${ids.debugXcconfig} /* Debug.xcconfig */;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				${signing}
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = Jaccuweather/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = Jaccuweather;
				INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.weather";
				INFOPLIST_KEY_NSLocationWhenInUseUsageDescription = "Shows weather for your current location.";
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";
				MARKETING_VERSION = 0.2.0;
				PRODUCT_BUNDLE_IDENTIFIER = cloud.janglim.jaccuweather;
				PRODUCT_NAME = "$(TARGET_NAME)";
				CODE_SIGN_ENTITLEMENTS = Jaccuweather/Jaccuweather.entitlements;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Debug;
		};
		${ids.targetRelease} /* Release */ = {
			isa = XCBuildConfiguration;
			baseConfigurationReference = ${ids.releaseXcconfig} /* Release.xcconfig */;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				${signing}
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = Jaccuweather/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = Jaccuweather;
				INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.weather";
				INFOPLIST_KEY_NSLocationWhenInUseUsageDescription = "Shows weather for your current location.";
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";
				MARKETING_VERSION = 0.2.0;
				PRODUCT_BUNDLE_IDENTIFIER = cloud.janglim.jaccuweather;
				PRODUCT_NAME = "$(TARGET_NAME)";
				CODE_SIGN_ENTITLEMENTS = Jaccuweather/Jaccuweather.entitlements;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Release;
		};
		${ids.widgetDebug} /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				APPLICATION_EXTENSION_API_ONLY = YES;
				${signing}
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = JaccuweatherWidgets/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = Jaccuweather;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks";
				MARKETING_VERSION = 0.2.0;
				PRODUCT_BUNDLE_IDENTIFIER = cloud.janglim.jaccuweather.widgets;
				PRODUCT_NAME = "$(TARGET_NAME)";
				CODE_SIGN_ENTITLEMENTS = JaccuweatherWidgets/JaccuweatherWidgets.entitlements;
				SKIP_INSTALL = YES;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Debug;
		};
		${ids.widgetRelease} /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				APPLICATION_EXTENSION_API_ONLY = YES;
				${signing}
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = JaccuweatherWidgets/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = Jaccuweather;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks";
				MARKETING_VERSION = 0.2.0;
				PRODUCT_BUNDLE_IDENTIFIER = cloud.janglim.jaccuweather.widgets;
				PRODUCT_NAME = "$(TARGET_NAME)";
				CODE_SIGN_ENTITLEMENTS = JaccuweatherWidgets/JaccuweatherWidgets.entitlements;
				SKIP_INSTALL = YES;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		${ids.projectConfigs} /* Build configuration list for PBXProject "Jaccuweather" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				${ids.projDebug} /* Debug */,
				${ids.projRelease} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		${ids.targetConfigs} /* Build configuration list for PBXNativeTarget "Jaccuweather" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				${ids.targetDebug} /* Debug */,
				${ids.targetRelease} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		${ids.widgetConfigs} /* Build configuration list for PBXNativeTarget "JaccuweatherWidgets" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				${ids.widgetDebug} /* Debug */,
				${ids.widgetRelease} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */
	};
	rootObject = ${ids.project} /* Project object */;
}
`;

if (!pbxproj.includes('name = Logic; path = Resources/Logic;')) {
  throw new Error('Logic folder reference must copy to the app root, not Resources/');
}
if (!pbxproj.includes('name = Icons; path = Resources/Icons;')) {
  throw new Error('Icons folder reference must copy to the app root, not Resources/');
}
if (/\bpath = Resources;/.test(pbxproj)) {
  throw new Error('Do not add a top-level Resources directory inside the app bundle');
}
if (/DEVELOPMENT_TEAM = "[A-Za-z0-9]+"/.test(pbxproj)) {
  throw new Error('Do not commit a DEVELOPMENT_TEAM id');
}

const outDir = path.join(root, 'Jaccuweather.xcodeproj');
fs.mkdirSync(path.join(outDir, 'xcshareddata', 'xcschemes'), { recursive: true });
fs.writeFileSync(path.join(outDir, 'project.pbxproj'), pbxproj);

function scheme(blueprintId, buildableName, blueprintName) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "${blueprintId}"
               BuildableName = "${buildableName}"
               BlueprintName = "${blueprintName}"
               ReferencedContainer = "container:Jaccuweather.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "${blueprintId}"
            BuildableName = "${buildableName}"
            BlueprintName = "${blueprintName}"
            ReferencedContainer = "container:Jaccuweather.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "${blueprintId}"
            BuildableName = "${buildableName}"
            BlueprintName = "${blueprintName}"
            ReferencedContainer = "container:Jaccuweather.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
`;
}

fs.writeFileSync(
  path.join(outDir, 'xcshareddata', 'xcschemes', 'Jaccuweather.xcscheme'),
  scheme(ids.target, 'Jaccuweather.app', 'Jaccuweather')
);
fs.writeFileSync(
  path.join(outDir, 'xcshareddata', 'xcschemes', 'JaccuweatherWidgets.xcscheme'),
  scheme(ids.widgetTarget, 'JaccuweatherWidgets.appex', 'JaccuweatherWidgets')
);
console.log('Wrote project with', sources.length, 'app swift files,', sharedSources.length, 'shared,', widgetSources.length, 'widget');
