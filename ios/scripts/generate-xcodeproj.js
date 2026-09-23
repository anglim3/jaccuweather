#!/usr/bin/env node
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

function hid() {
  return crypto.randomBytes(12).toString('hex').toUpperCase();
}

const root = path.resolve(__dirname, '..');
const appDir = path.join(root, 'Jaccuweather');

function walk(dir, ext, acc = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, ext, acc);
    else if (entry.name.endsWith(ext)) acc.push(path.relative(appDir, full).split(path.sep).join('/'));
  }
  return acc;
}

const sources = walk(appDir, '.swift').sort();
const plistRel = 'Info.plist';

const ids = {
  project: hid(),
  target: hid(),
  product: hid(),
  sourcesPhase: hid(),
  resourcesPhase: hid(),
  frameworksPhase: hid(),
  jsCore: hid(),
  jsCoreBuild: hid(),
  mapKit: hid(),
  mapKitBuild: hid(),
  webKit: hid(),
  webKitBuild: hid(),
  mainGroup: hid(),
  productsGroup: hid(),
  appGroup: hid(),
  modelsGroup: hid(),
  servicesGroup: hid(),
  viewModelsGroup: hid(),
  viewsGroup: hid(),
  configGroup: hid(),
  assets: hid(),
  assetsBuild: hid(),
  resourcesFolder: hid(),
  resourcesBuild: hid(),
  projDebug: hid(),
  projRelease: hid(),
  targetDebug: hid(),
  targetRelease: hid(),
  debugXcconfig: hid(),
  releaseXcconfig: hid(),
  secretsXcconfig: hid(),
  secretsExample: hid(),
  plist: hid(),
};

const fileIds = {};
for (const file of sources) fileIds[file] = { ref: hid(), build: hid() };

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

const fileRefs = sources
  .map((f) => `\t\t${fileIds[f].ref} /* ${path.basename(f)} */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ${path.basename(f)}; sourceTree = "<group>"; };`)
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
  .join('\n');

const pbxproj = `// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 56;
	objects = {

/* Begin PBXBuildFile section */
${swiftBuildFiles}
		${ids.assetsBuild} /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = ${ids.assets} /* Assets.xcassets */; };
		${ids.resourcesBuild} /* Resources in Resources */ = {isa = PBXBuildFile; fileRef = ${ids.resourcesFolder} /* Resources */; };
		${ids.jsCoreBuild} /* JavaScriptCore.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = ${ids.jsCore} /* JavaScriptCore.framework */; };
		${ids.mapKitBuild} /* MapKit.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = ${ids.mapKit} /* MapKit.framework */; };
		${ids.webKitBuild} /* WebKit.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = ${ids.webKit} /* WebKit.framework */; };
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		${ids.product} /* Jaccuweather.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Jaccuweather.app; sourceTree = BUILT_PRODUCTS_DIR; };
		${ids.assets} /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; };
		${ids.resourcesFolder} /* Resources */ = {isa = PBXFileReference; lastKnownFileType = folder; path = Resources; sourceTree = "<group>"; };
		${ids.debugXcconfig} /* Debug.xcconfig */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Debug.xcconfig; sourceTree = "<group>"; };
		${ids.releaseXcconfig} /* Release.xcconfig */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Release.xcconfig; sourceTree = "<group>"; };
		${ids.secretsXcconfig} /* Secrets.xcconfig */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Secrets.xcconfig; sourceTree = "<group>"; };
		${ids.secretsExample} /* Secrets.xcconfig.example */ = {isa = PBXFileReference; lastKnownFileType = text; path = Secrets.xcconfig.example; sourceTree = "<group>"; };
		${ids.plist} /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
		${ids.jsCore} /* JavaScriptCore.framework */ = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = JavaScriptCore.framework; path = System/Library/Frameworks/JavaScriptCore.framework; sourceTree = SDKROOT; };
		${ids.mapKit} /* MapKit.framework */ = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = MapKit.framework; path = System/Library/Frameworks/MapKit.framework; sourceTree = SDKROOT; };
		${ids.webKit} /* WebKit.framework */ = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = WebKit.framework; path = System/Library/Frameworks/WebKit.framework; sourceTree = SDKROOT; };
${fileRefs}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		${ids.frameworksPhase} /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				${ids.jsCoreBuild} /* JavaScriptCore.framework in Frameworks */,
				${ids.mapKitBuild} /* MapKit.framework in Frameworks */,
				${ids.webKitBuild} /* WebKit.framework in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		${ids.mainGroup} = {
			isa = PBXGroup;
			children = (
				${ids.appGroup} /* Jaccuweather */,
				${ids.productsGroup} /* Products */,
				${ids.jsCore} /* JavaScriptCore.framework */,
				${ids.mapKit} /* MapKit.framework */,
				${ids.webKit} /* WebKit.framework */,
			);
			sourceTree = "<group>";
		};
		${ids.productsGroup} /* Products */ = {
			isa = PBXGroup;
			children = (
				${ids.product} /* Jaccuweather.app */,
			);
			name = Products;
			sourceTree = "<group>";
		};
		${ids.appGroup} /* Jaccuweather */ = {
			isa = PBXGroup;
			children = (
${groups.root.map((f) => `\t\t\t\t${fileIds[f].ref} /* ${path.basename(f)} */,`).join('\n')}
				${ids.plist} /* Info.plist */,
				${ids.assets} /* Assets.xcassets */,
				${ids.resourcesFolder} /* Resources */,
				${ids.configGroup} /* Config */,
				${ids.modelsGroup} /* Models */,
				${ids.servicesGroup} /* Services */,
				${ids.viewModelsGroup} /* ViewModels */,
				${ids.viewsGroup} /* Views */,
			);
			path = Jaccuweather;
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
			buildConfigurationList = TARGET_CFGS /* Build configuration list for PBXNativeTarget "Jaccuweather" */;
			buildPhases = (
				${ids.sourcesPhase} /* Sources */,
				${ids.frameworksPhase} /* Frameworks */,
				${ids.resourcesPhase} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = Jaccuweather;
			productName = Jaccuweather;
			productReference = ${ids.product} /* Jaccuweather.app */;
			productType = "com.apple.product-type.application";
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
				};
			};
			buildConfigurationList = PROJECT_CFGS /* Build configuration list for PBXProject "Jaccuweather" */;
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
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		${ids.resourcesPhase} /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				${ids.assetsBuild} /* Assets.xcassets in Resources */,
				${ids.resourcesBuild} /* Resources in Resources */,
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
/* End PBXSourcesBuildPhase section */

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
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = "";
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
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = "";
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
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		PROJECT_CFGS /* Build configuration list for PBXProject "Jaccuweather" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				${ids.projDebug} /* Debug */,
				${ids.projRelease} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		TARGET_CFGS /* Build configuration list for PBXNativeTarget "Jaccuweather" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				${ids.targetDebug} /* Debug */,
				${ids.targetRelease} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */
	};
	rootObject = ${ids.project} /* Project object */;
}
`;

const outDir = path.join(root, 'Jaccuweather.xcodeproj');
fs.mkdirSync(path.join(outDir, 'xcshareddata', 'xcschemes'), { recursive: true });
fs.writeFileSync(path.join(outDir, 'project.pbxproj'), pbxproj);

const scheme = `<?xml version="1.0" encoding="UTF-8"?>
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
               BlueprintIdentifier = "${ids.target}"
               BuildableName = "Jaccuweather.app"
               BlueprintName = "Jaccuweather"
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
            BlueprintIdentifier = "${ids.target}"
            BuildableName = "Jaccuweather.app"
            BlueprintName = "Jaccuweather"
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
            BlueprintIdentifier = "${ids.target}"
            BuildableName = "Jaccuweather.app"
            BlueprintName = "Jaccuweather"
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
fs.writeFileSync(path.join(outDir, 'xcshareddata', 'xcschemes', 'Jaccuweather.xcscheme'), scheme);
console.log('Wrote project with', sources.length, 'swift files');
