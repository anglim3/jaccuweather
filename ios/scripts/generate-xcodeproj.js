#!/usr/bin/env node
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

function hid() {
  return crypto.randomBytes(12).toString('hex').toUpperCase();
}

const root = path.resolve(__dirname, '..');
const sources = [
  'JaccuweatherApp.swift',
  'Theme.swift',
  'Info.plist',
  'Models/WeatherModels.swift',
  'Models/LocationModels.swift',
  'Models/PollenModels.swift',
  'Models/AlertModels.swift',
  'Services/APIEndpoints.swift',
  'Services/HTTPClient.swift',
  'Services/Secrets.swift',
  'Services/WeatherService.swift',
  'Services/GeocodingService.swift',
  'Services/PollenService.swift',
  'Services/AlertsService.swift',
  'Services/HealthScores.swift',
  'Services/FavoritesStore.swift',
  'ViewModels/WeatherViewModel.swift',
  'Views/ContentView.swift',
  'Views/CurrentConditionsView.swift',
  'Views/ForecastView.swift',
  'Views/HealthPollenView.swift',
  'Views/RadarView.swift',
  'Views/SearchSheet.swift',
];

const ids = {
  project: hid(),
  target: hid(),
  product: hid(),
  sourcesPhase: hid(),
  resourcesPhase: hid(),
  frameworksPhase: hid(),
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
  debugConfig: hid(),
  releaseConfig: hid(),
  projDebug: hid(),
  projRelease: hid(),
  targetDebug: hid(),
  targetRelease: hid(),
  debugXcconfig: hid(),
  releaseXcconfig: hid(),
  secretsXcconfig: hid(),
  secretsExample: hid(),
};

const fileIds = {};
for (const file of sources) {
  fileIds[file] = { ref: hid(), build: hid() };
}

function groupChildren(files) {
  return files.map((f) => fileIds[f].ref).join(',\n\t\t\t\t');
}

const swiftBuildFiles = sources
  .filter((f) => f.endsWith('.swift'))
  .map((f) => `\t\t${fileIds[f].build} /* ${path.basename(f)} in Sources */ = {isa = PBXBuildFile; fileRef = ${fileIds[f].ref} /* ${path.basename(f)} */; };`)
  .join('\n');

const fileRefs = sources
  .map((f) => {
    const last = path.basename(f);
    if (last === 'Info.plist') {
      return `\t\t${fileIds[f].ref} /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };`;
    }
    return `\t\t${fileIds[f].ref} /* ${last} */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ${last}; sourceTree = "<group>"; };`;
  })
  .join('\n');

const sourceBuildPhase = sources
  .filter((f) => f.endsWith('.swift'))
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
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		${ids.product} /* Jaccuweather.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Jaccuweather.app; sourceTree = BUILT_PRODUCTS_DIR; };
		${ids.assets} /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; };
		${ids.debugXcconfig} /* Debug.xcconfig */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Debug.xcconfig; sourceTree = "<group>"; };
		${ids.releaseXcconfig} /* Release.xcconfig */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Release.xcconfig; sourceTree = "<group>"; };
		${ids.secretsXcconfig} /* Secrets.xcconfig */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Secrets.xcconfig; sourceTree = "<group>"; };
		${ids.secretsExample} /* Secrets.xcconfig.example */ = {isa = PBXFileReference; lastKnownFileType = text; path = Secrets.xcconfig.example; sourceTree = "<group>"; };
${fileRefs}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		${ids.frameworksPhase} /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
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
				${fileIds['JaccuweatherApp.swift'].ref} /* JaccuweatherApp.swift */,
				${fileIds['Theme.swift'].ref} /* Theme.swift */,
				${fileIds['Info.plist'].ref} /* Info.plist */,
				${ids.assets} /* Assets.xcassets */,
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
		${ids.modelsGroup} /* Models */ = {
			isa = PBXGroup;
			children = (
				${fileIds['Models/WeatherModels.swift'].ref} /* WeatherModels.swift */,
				${fileIds['Models/LocationModels.swift'].ref} /* LocationModels.swift */,
				${fileIds['Models/PollenModels.swift'].ref} /* PollenModels.swift */,
				${fileIds['Models/AlertModels.swift'].ref} /* AlertModels.swift */,
			);
			path = Models;
			sourceTree = "<group>";
		};
		${ids.servicesGroup} /* Services */ = {
			isa = PBXGroup;
			children = (
				${fileIds['Services/APIEndpoints.swift'].ref} /* APIEndpoints.swift */,
				${fileIds['Services/HTTPClient.swift'].ref} /* HTTPClient.swift */,
				${fileIds['Services/Secrets.swift'].ref} /* Secrets.swift */,
				${fileIds['Services/WeatherService.swift'].ref} /* WeatherService.swift */,
				${fileIds['Services/GeocodingService.swift'].ref} /* GeocodingService.swift */,
				${fileIds['Services/PollenService.swift'].ref} /* PollenService.swift */,
				${fileIds['Services/AlertsService.swift'].ref} /* AlertsService.swift */,
				${fileIds['Services/HealthScores.swift'].ref} /* HealthScores.swift */,
				${fileIds['Services/FavoritesStore.swift'].ref} /* FavoritesStore.swift */,
			);
			path = Services;
			sourceTree = "<group>";
		};
		${ids.viewModelsGroup} /* ViewModels */ = {
			isa = PBXGroup;
			children = (
				${fileIds['ViewModels/WeatherViewModel.swift'].ref} /* WeatherViewModel.swift */,
			);
			path = ViewModels;
			sourceTree = "<group>";
		};
		${ids.viewsGroup} /* Views */ = {
			isa = PBXGroup;
			children = (
				${fileIds['Views/ContentView.swift'].ref} /* ContentView.swift */,
				${fileIds['Views/CurrentConditionsView.swift'].ref} /* CurrentConditionsView.swift */,
				${fileIds['Views/ForecastView.swift'].ref} /* ForecastView.swift */,
				${fileIds['Views/HealthPollenView.swift'].ref} /* HealthPollenView.swift */,
				${fileIds['Views/RadarView.swift'].ref} /* RadarView.swift */,
				${fileIds['Views/SearchSheet.swift'].ref} /* SearchSheet.swift */,
			);
			path = Views;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		${ids.target} /* Jaccuweather */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = ${ids.targetDebug.slice(0, 0)}${hid()} /* Build configuration list for PBXNativeTarget "Jaccuweather" */;
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
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";
				MARKETING_VERSION = 0.1.0;
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
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";
				MARKETING_VERSION = 0.1.0;
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

// Fix the accidental hid() in native target buildConfigurationList
const fixed = pbxproj
  .replace(
    /buildConfigurationList = [A-F0-9]{24} \/\* Build configuration list for PBXNativeTarget "Jaccuweather" \*\/;/,
    'buildConfigurationList = TARGET_CFGS /* Build configuration list for PBXNativeTarget "Jaccuweather" */;'
  );

const outDir = path.join(root, 'Jaccuweather.xcodeproj');
fs.mkdirSync(path.join(outDir, 'xcshareddata', 'xcschemes'), { recursive: true });
fs.writeFileSync(path.join(outDir, 'project.pbxproj'), fixed);

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
console.log('Wrote', path.join(outDir, 'project.pbxproj'));
console.log('target', ids.target);
