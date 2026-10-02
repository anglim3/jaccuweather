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
const watchDir = path.join(root, 'JaccuweatherWatch');
const watchWidgetDir = path.join(root, 'JaccuweatherWatchWidgets');

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
const watchSources = walk(watchDir, '.swift').sort();
const watchWidgetSources = walk(watchWidgetDir, '.swift').sort();

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
  watchTarget: hid('watchTarget'),
  watchProduct: hid('watchProduct'),
  watchSourcesPhase: hid('watchSourcesPhase'),
  watchFrameworksPhase: hid('watchFrameworksPhase'),
  watchResourcesPhase: hid('watchResourcesPhase'),
  watchDebug: hid('watchDebug'),
  watchRelease: hid('watchRelease'),
  watchConfigs: hid('watchConfigs'),
  watchGroup: hid('watchGroup'),
  watchAssets: hid('watchAssets'),
  watchAssetsBuild: hid('watchAssetsBuild'),
  watchPlist: hid('watchPlist'),
  watchEmbed: hid('watchEmbed'),
  watchEmbedPhase: hid('watchEmbedPhase'),
  watchProxy: hid('watchProxy'),
  watchDep: hid('watchDep'),
  watchWidgetTarget: hid('watchWidgetTarget'),
  watchWidgetProduct: hid('watchWidgetProduct'),
  watchWidgetSourcesPhase: hid('watchWidgetSourcesPhase'),
  watchWidgetFrameworksPhase: hid('watchWidgetFrameworksPhase'),
  watchWidgetResourcesPhase: hid('watchWidgetResourcesPhase'),
  watchWidgetDebug: hid('watchWidgetDebug'),
  watchWidgetRelease: hid('watchWidgetRelease'),
  watchWidgetConfigs: hid('watchWidgetConfigs'),
  watchWidgetGroup: hid('watchWidgetGroup'),
  watchWidgetPlist: hid('watchWidgetPlist'),
  watchWidgetEmbed: hid('watchWidgetEmbed'),
  watchWidgetEmbedPhase: hid('watchWidgetEmbedPhase'),
  watchWidgetProxy: hid('watchWidgetProxy'),
  watchWidgetDep: hid('watchWidgetDep'),
  watchConnectivity: hid('watchConnectivity'),
  watchConnectivityAppBuild: hid('watchConnectivityAppBuild'),
  watchConnectivityWatchBuild: hid('watchConnectivityWatchBuild'),
  widgetKitWatchBuild: hid('widgetKitWatchBuild'),
  widgetKitWatchExtBuild: hid('widgetKitWatchExtBuild'),
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
const watchIds = {};
for (const file of watchSources) {
  watchIds[file] = {
    ref: hid('watch-ref:' + file),
    build: hid('watch-build:' + file),
    widgetBuild: hid('watch-widget-extra:' + file),
  };
}
const watchWidgetIds = {};
for (const file of watchWidgetSources) {
  watchWidgetIds[file] = { ref: hid('watch-widget-ref:' + file), build: hid('watch-widget-build:' + file) };
}
const watchSupportFiles = [
  { name: 'WidgetSnapshot.swift', ref: sharedIds['WidgetSnapshot.swift'].ref },
  { name: 'WatchMirror.swift', ref: sharedIds['WatchMirror.swift'].ref },
  { name: 'WatchAlertPayload.swift', ref: sharedIds['WatchAlertPayload.swift'].ref },
  { name: 'WidgetHorizon.swift', ref: widgetIds['WidgetHorizon.swift'].ref },
  { name: 'WidgetRefresh.swift', ref: widgetIds['WidgetRefresh.swift'].ref },
];
const watchSupportIds = {};
for (const file of watchSupportFiles) {
  watchSupportIds[file.name] = {
    app: hid('watch-support-app:' + file.name),
    widget: hid('watch-support-widget:' + file.name),
  };
}
const watchFilesInWidget = [
  'WatchConditionsLoader.swift',
  'WatchForecastClient.swift',
  'WatchHourlyPlan.swift',
  'WatchDailyPlan.swift',
  'WatchPlaceLink.swift',
  'WatchPlacePlan.swift',
  'WatchPlaceStore.swift',
];
for (const name of watchFilesInWidget) {
  if (!watchIds[name]) throw new Error(name + ' missing from the Watch app sources');
}

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
const watchBuildFiles = watchSources
  .map((f) => `\t\t${watchIds[f].build} /* ${path.basename(f)} in Sources */ = {isa = PBXBuildFile; fileRef = ${watchIds[f].ref} /* ${path.basename(f)} */; };`)
  .join('\n');
const watchWidgetBuildFiles = watchWidgetSources
  .map((f) => `\t\t${watchWidgetIds[f].build} /* ${path.basename(f)} in Sources */ = {isa = PBXBuildFile; fileRef = ${watchWidgetIds[f].ref} /* ${path.basename(f)} */; };`)
  .join('\n');
const watchLoaderInWidget = watchFilesInWidget
  .map((name) => `\t\t${watchIds[name].widgetBuild} /* ${name} in Sources */ = {isa = PBXBuildFile; fileRef = ${watchIds[name].ref} /* ${name} */; };`)
  .join('\n');
const watchSupportAppBuilds = watchSupportFiles
  .map((f) => `\t\t${watchSupportIds[f.name].app} /* ${f.name} in Sources */ = {isa = PBXBuildFile; fileRef = ${f.ref} /* ${f.name} */; };`)
  .join('\n');
const watchSupportWidgetBuilds = watchSupportFiles
  .map((f) => `\t\t${watchSupportIds[f.name].widget} /* ${f.name} in Sources */ = {isa = PBXBuildFile; fileRef = ${f.ref} /* ${f.name} */; };`)
  .join('\n');
const watchRefs = watchSources
  .map((f) => `\t\t${watchIds[f].ref} /* ${path.basename(f)} */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ${path.basename(f)}; sourceTree = "<group>"; };`)
  .join('\n');
const watchWidgetRefs = watchWidgetSources
  .map((f) => `\t\t${watchWidgetIds[f].ref} /* ${path.basename(f)} */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ${path.basename(f)}; sourceTree = "<group>"; };`)
  .join('\n');
const watchSourceBuildPhase = watchSources
  .map((f) => `\t\t\t\t${watchIds[f].build} /* ${path.basename(f)} in Sources */,`)
  .concat(watchSupportFiles.map((f) => `\t\t\t\t${watchSupportIds[f.name].app} /* ${f.name} in Sources */,`))
  .join('\n');
const watchWidgetSourceBuildPhase = watchWidgetSources
  .map((f) => `\t\t\t\t${watchWidgetIds[f].build} /* ${path.basename(f)} in Sources */,`)
  .concat(watchFilesInWidget.map((name) => `\t\t\t\t${watchIds[name].widgetBuild} /* ${name} in Sources */,`))
  .concat(watchSupportFiles.map((f) => `\t\t\t\t${watchSupportIds[f.name].widget} /* ${f.name} in Sources */,`))
  .join('\n');
const watchGroupChildren = [
  ...watchSources.map((f) => `\t\t\t\t${watchIds[f].ref} /* ${path.basename(f)} */,`),
  `\t\t\t\t${ids.watchPlist} /* Info.plist */,`,
  `\t\t\t\t${ids.watchAssets} /* Assets.xcassets */,`,
].join('\n');
const watchWidgetGroupChildren = [
  ...watchWidgetSources.map((f) => `\t\t\t\t${watchWidgetIds[f].ref} /* ${path.basename(f)} */,`),
  `\t\t\t\t${ids.watchWidgetPlist} /* Info.plist */,`,
].join('\n');

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
${watchBuildFiles}
${watchWidgetBuildFiles}
${watchLoaderInWidget}
${watchSupportAppBuilds}
${watchSupportWidgetBuilds}
		${ids.assetsBuild} /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = ${ids.assets} /* Assets.xcassets */; };
		${ids.logicBuild} /* Logic in Resources */ = {isa = PBXBuildFile; fileRef = ${ids.logicFolder} /* Logic */; };
		${ids.iconsBuild} /* Icons in Resources */ = {isa = PBXBuildFile; fileRef = ${ids.iconsFolder} /* Icons */; };
		${ids.jsCoreBuild} /* JavaScriptCore.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = ${ids.jsCore} /* JavaScriptCore.framework */; };
		${ids.mapKitBuild} /* MapKit.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = ${ids.mapKit} /* MapKit.framework */; };
		${ids.webKitBuild} /* WebKit.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = ${ids.webKit} /* WebKit.framework */; };
		${ids.widgetKitAppBuild} /* WidgetKit.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = ${ids.widgetKit} /* WidgetKit.framework */; };
		${ids.widgetKitExtBuild} /* WidgetKit.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = ${ids.widgetKit} /* WidgetKit.framework */; };
		${ids.widgetEmbed} /* JaccuweatherWidgets.appex in Embed Foundation Extensions */ = {isa = PBXBuildFile; fileRef = ${ids.widgetProduct} /* JaccuweatherWidgets.appex */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };
		${ids.watchConnectivityAppBuild} /* WatchConnectivity.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = ${ids.watchConnectivity} /* WatchConnectivity.framework */; };
		${ids.watchConnectivityWatchBuild} /* WatchConnectivity.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = ${ids.watchConnectivity} /* WatchConnectivity.framework */; };
		${ids.widgetKitWatchBuild} /* WidgetKit.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = ${ids.widgetKit} /* WidgetKit.framework */; };
		${ids.widgetKitWatchExtBuild} /* WidgetKit.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = ${ids.widgetKit} /* WidgetKit.framework */; };
		${ids.watchEmbed} /* JaccuweatherWatch.app in Embed Watch Content */ = {isa = PBXBuildFile; fileRef = ${ids.watchProduct} /* JaccuweatherWatch.app */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };
		${ids.watchWidgetEmbed} /* JaccuweatherWatchWidgets.appex in Embed Foundation Extensions */ = {isa = PBXBuildFile; fileRef = ${ids.watchWidgetProduct} /* JaccuweatherWatchWidgets.appex */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };
		${ids.watchAssetsBuild} /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = ${ids.watchAssets} /* Assets.xcassets */; };
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		${ids.widgetProxy} /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = ${ids.project} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = ${ids.widgetTarget};
			remoteInfo = JaccuweatherWidgets;
		};
		${ids.watchProxy} /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = ${ids.project} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = ${ids.watchTarget};
			remoteInfo = JaccuweatherWatch;
		};
		${ids.watchWidgetProxy} /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = ${ids.project} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = ${ids.watchWidgetTarget};
			remoteInfo = JaccuweatherWatchWidgets;
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
		${ids.watchEmbedPhase} /* Embed Watch Content */ = {
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "$(CONTENTS_FOLDER_PATH)/Watch";
			dstSubfolderSpec = 16;
			files = (
				${ids.watchEmbed} /* JaccuweatherWatch.app in Embed Watch Content */,
			);
			name = "Embed Watch Content";
			runOnlyForDeploymentPostprocessing = 0;
		};
		${ids.watchWidgetEmbedPhase} /* Embed Foundation Extensions */ = {
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 13;
			files = (
				${ids.watchWidgetEmbed} /* JaccuweatherWatchWidgets.appex in Embed Foundation Extensions */,
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
		${ids.watchConnectivity} /* WatchConnectivity.framework */ = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = WatchConnectivity.framework; path = System/Library/Frameworks/WatchConnectivity.framework; sourceTree = SDKROOT; };
		${ids.watchProduct} /* JaccuweatherWatch.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = JaccuweatherWatch.app; sourceTree = BUILT_PRODUCTS_DIR; };
		${ids.watchWidgetProduct} /* JaccuweatherWatchWidgets.appex */ = {isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = JaccuweatherWatchWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; };
		${ids.watchAssets} /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; };
		${ids.watchPlist} /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
		${ids.watchWidgetPlist} /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
${fileRefs}
${sharedRefs}
${widgetRefs}
${watchRefs}
${watchWidgetRefs}
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
				${ids.watchConnectivityAppBuild} /* WatchConnectivity.framework in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		${ids.watchFrameworksPhase} /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				${ids.watchConnectivityWatchBuild} /* WatchConnectivity.framework in Frameworks */,
				${ids.widgetKitWatchBuild} /* WidgetKit.framework in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		${ids.watchWidgetFrameworksPhase} /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				${ids.widgetKitWatchExtBuild} /* WidgetKit.framework in Frameworks */,
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
				${ids.watchGroup} /* JaccuweatherWatch */,
				${ids.watchWidgetGroup} /* JaccuweatherWatchWidgets */,
				${ids.sharedGroup} /* Shared */,
				${ids.productsGroup} /* Products */,
				${ids.jsCore} /* JavaScriptCore.framework */,
				${ids.mapKit} /* MapKit.framework */,
				${ids.webKit} /* WebKit.framework */,
				${ids.widgetKit} /* WidgetKit.framework */,
				${ids.watchConnectivity} /* WatchConnectivity.framework */,
			);
			sourceTree = "<group>";
		};
		${ids.productsGroup} /* Products */ = {
			isa = PBXGroup;
			children = (
				${ids.product} /* Jaccuweather.app */,
				${ids.widgetProduct} /* JaccuweatherWidgets.appex */,
				${ids.watchProduct} /* JaccuweatherWatch.app */,
				${ids.watchWidgetProduct} /* JaccuweatherWatchWidgets.appex */,
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
		${ids.watchGroup} /* JaccuweatherWatch */ = {
			isa = PBXGroup;
			children = (
${watchGroupChildren}
			);
			path = JaccuweatherWatch;
			sourceTree = "<group>";
		};
		${ids.watchWidgetGroup} /* JaccuweatherWatchWidgets */ = {
			isa = PBXGroup;
			children = (
${watchWidgetGroupChildren}
			);
			path = JaccuweatherWatchWidgets;
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
				${ids.watchEmbedPhase} /* Embed Watch Content */,
			);
			buildRules = (
			);
			dependencies = (
				${ids.widgetDep} /* PBXTargetDependency */,
				${ids.watchDep} /* PBXTargetDependency */,
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
		${ids.watchTarget} /* JaccuweatherWatch */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = ${ids.watchConfigs} /* Build configuration list for PBXNativeTarget "JaccuweatherWatch" */;
			buildPhases = (
				${ids.watchSourcesPhase} /* Sources */,
				${ids.watchFrameworksPhase} /* Frameworks */,
				${ids.watchResourcesPhase} /* Resources */,
				${ids.watchWidgetEmbedPhase} /* Embed Foundation Extensions */,
			);
			buildRules = (
			);
			dependencies = (
				${ids.watchWidgetDep} /* PBXTargetDependency */,
			);
			name = JaccuweatherWatch;
			productName = JaccuweatherWatch;
			productReference = ${ids.watchProduct} /* JaccuweatherWatch.app */;
			/* application, not application.watchapp2: watchapp2 both links this executable and lipos the WatchKit stub onto the same path. */
			productType = "com.apple.product-type.application";
		};
		${ids.watchWidgetTarget} /* JaccuweatherWatchWidgets */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = ${ids.watchWidgetConfigs} /* Build configuration list for PBXNativeTarget "JaccuweatherWatchWidgets" */;
			buildPhases = (
				${ids.watchWidgetSourcesPhase} /* Sources */,
				${ids.watchWidgetFrameworksPhase} /* Frameworks */,
				${ids.watchWidgetResourcesPhase} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = JaccuweatherWatchWidgets;
			productName = JaccuweatherWatchWidgets;
			productReference = ${ids.watchWidgetProduct} /* JaccuweatherWatchWidgets.appex */;
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
					${ids.watchTarget} = {
						CreatedOnToolsVersion = 15.0;
					};
					${ids.watchWidgetTarget} = {
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
				${ids.watchTarget} /* JaccuweatherWatch */,
				${ids.watchWidgetTarget} /* JaccuweatherWatchWidgets */,
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
		${ids.watchResourcesPhase} /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				${ids.watchAssetsBuild} /* Assets.xcassets in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		${ids.watchWidgetResourcesPhase} /* Resources */ = {
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
		${ids.watchSourcesPhase} /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
${watchSourceBuildPhase}
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		${ids.watchWidgetSourcesPhase} /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
${watchWidgetSourceBuildPhase}
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
		${ids.watchDep} /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = ${ids.watchTarget} /* JaccuweatherWatch */;
			targetProxy = ${ids.watchProxy} /* PBXContainerItemProxy */;
		};
		${ids.watchWidgetDep} /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = ${ids.watchWidgetTarget} /* JaccuweatherWatchWidgets */;
			targetProxy = ${ids.watchWidgetProxy} /* PBXContainerItemProxy */;
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
		${ids.watchDebug} /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				${signing}
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = JaccuweatherWatch/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = Jaccuweather;
				INFOPLIST_KEY_WKApplication = YES;
				INFOPLIST_KEY_WKCompanionAppBundleIdentifier = cloud.janglim.jaccuweather;
				INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp = YES;
				LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";
				MARKETING_VERSION = 0.4.0;
				PRODUCT_BUNDLE_IDENTIFIER = cloud.janglim.jaccuweather.watchkitapp;
				PRODUCT_NAME = "$(TARGET_NAME)";
				ENABLE_DEBUG_DYLIB = NO;
				"EXCLUDED_ARCHS[sdk=watchsimulator*]" = x86_64;
				SDKROOT = watchos;
				SKIP_INSTALL = YES;
				SUPPORTED_PLATFORMS = "watchos watchsimulator";
				SUPPORTS_MACCATALYST = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = 4;
				WATCHOS_DEPLOYMENT_TARGET = 10.0;
			};
			name = Debug;
		};
		${ids.watchRelease} /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				${signing}
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = JaccuweatherWatch/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = Jaccuweather;
				INFOPLIST_KEY_WKApplication = YES;
				INFOPLIST_KEY_WKCompanionAppBundleIdentifier = cloud.janglim.jaccuweather;
				INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp = YES;
				LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";
				MARKETING_VERSION = 0.4.0;
				PRODUCT_BUNDLE_IDENTIFIER = cloud.janglim.jaccuweather.watchkitapp;
				PRODUCT_NAME = "$(TARGET_NAME)";
				ENABLE_DEBUG_DYLIB = NO;
				"EXCLUDED_ARCHS[sdk=watchsimulator*]" = x86_64;
				SDKROOT = watchos;
				SKIP_INSTALL = YES;
				SUPPORTED_PLATFORMS = "watchos watchsimulator";
				SUPPORTS_MACCATALYST = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = 4;
				WATCHOS_DEPLOYMENT_TARGET = 10.0;
			};
			name = Release;
		};
		${ids.watchWidgetDebug} /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				APPLICATION_EXTENSION_API_ONLY = YES;
				${signing}
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = JaccuweatherWatchWidgets/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = Jaccuweather;
				LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks";
				MARKETING_VERSION = 0.4.0;
				PRODUCT_BUNDLE_IDENTIFIER = cloud.janglim.jaccuweather.watchkitapp.widgets;
				PRODUCT_NAME = "$(TARGET_NAME)";
				ENABLE_DEBUG_DYLIB = NO;
				"EXCLUDED_ARCHS[sdk=watchsimulator*]" = x86_64;
				SDKROOT = watchos;
				SKIP_INSTALL = YES;
				SUPPORTED_PLATFORMS = "watchos watchsimulator";
				SUPPORTS_MACCATALYST = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = 4;
				WATCHOS_DEPLOYMENT_TARGET = 10.0;
			};
			name = Debug;
		};
		${ids.watchWidgetRelease} /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				APPLICATION_EXTENSION_API_ONLY = YES;
				${signing}
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = JaccuweatherWatchWidgets/Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = Jaccuweather;
				LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks";
				MARKETING_VERSION = 0.4.0;
				PRODUCT_BUNDLE_IDENTIFIER = cloud.janglim.jaccuweather.watchkitapp.widgets;
				PRODUCT_NAME = "$(TARGET_NAME)";
				ENABLE_DEBUG_DYLIB = NO;
				"EXCLUDED_ARCHS[sdk=watchsimulator*]" = x86_64;
				SDKROOT = watchos;
				SKIP_INSTALL = YES;
				SUPPORTED_PLATFORMS = "watchos watchsimulator";
				SUPPORTS_MACCATALYST = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = 4;
				WATCHOS_DEPLOYMENT_TARGET = 10.0;
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
		${ids.watchConfigs} /* Build configuration list for PBXNativeTarget "JaccuweatherWatch" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				${ids.watchDebug} /* Debug */,
				${ids.watchRelease} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		${ids.watchWidgetConfigs} /* Build configuration list for PBXNativeTarget "JaccuweatherWatchWidgets" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				${ids.watchWidgetDebug} /* Debug */,
				${ids.watchWidgetRelease} /* Release */,
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
const topLevelResources = ['path', '= Resources;'].join(' ');
if (pbxproj.includes(topLevelResources)) {
  throw new Error('Do not add a top-level Resources directory inside the app bundle');
}
if (/DEVELOPMENT_TEAM = "[A-Za-z0-9]+"/.test(pbxproj)) {
  throw new Error('Do not commit a DEVELOPMENT_TEAM id');
}
if (!pbxproj.includes('cloud.janglim.jaccuweather.watchkitapp')) {
  throw new Error('Watch app bundle id missing');
}
if (!pbxproj.includes('SDKROOT = watchos;')) {
  throw new Error('Watch targets must build with the watchOS SDK');
}
if (pbxproj.includes('JaccuweatherWatch.entitlements') || pbxproj.includes('JaccuweatherWatchWidgets.entitlements')) {
  throw new Error('Do not add entitlements files to the watch targets');
}
if (pbxproj.includes('application-groups')) {
  throw new Error('Do not put App Group identifiers in the Xcode project');
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
fs.writeFileSync(
  path.join(outDir, 'xcshareddata', 'xcschemes', 'JaccuweatherWatch.xcscheme'),
  scheme(ids.watchTarget, 'JaccuweatherWatch.app', 'JaccuweatherWatch')
);
console.log(
  'Wrote project with',
  sources.length,
  'app swift files,',
  sharedSources.length,
  'shared,',
  widgetSources.length,
  'widget,',
  watchSources.length,
  'watch,',
  watchWidgetSources.length,
  'watch widget'
);
