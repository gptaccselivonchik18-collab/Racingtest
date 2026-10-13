"""Generate a dependency-free Xcode project. Run after adding Swift source files."""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]
def uid(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def generate():
    files = sorted(p.relative_to(ROOT).as_posix() for folder in ('App', 'Core') for p in (ROOT / folder).glob('*.swift'))
    objects = []
    def obj(name, body):
        objects.append(f'{uid(name)} = {{ {body} }};')
    for file in files:
        obj('ref:'+file, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{file}"; sourceTree = "<group>";')
        obj('build:'+file, f'isa = PBXBuildFile; fileRef = {uid("ref:"+file)};')
    obj('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = MLBBNeuralCoach.app; sourceTree = BUILT_PRODUCTS_DIR;')
    obj('products', f'isa = PBXGroup; children = ({uid("product")},); name = Products; sourceTree = "<group>";')
    obj('rootgroup', 'isa = PBXGroup; children = (' + ','.join(uid('ref:'+f) for f in files) + f',{uid("products")},); sourceTree = "<group>";')
    obj('sources', 'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (' + ','.join(uid('build:'+f) for f in files) + ',); runOnlyForDeploymentPostprocessing = 0;')
    obj('resources', 'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    obj('frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    for config in ('Debug', 'Release'):
        obj('project:'+config, f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 26.0; CLANG_ENABLE_MODULES = YES; SWIFT_VERSION = 5.0; }};')
        obj('app:'+config, f'''isa = XCBuildConfiguration; name = {config}; buildSettings = {{
            PRODUCT_BUNDLE_IDENTIFIER = org.personal.MLBBNeuralCoach;
            PRODUCT_NAME = "$(TARGET_NAME)"; GENERATE_INFOPLIST_FILE = YES;
            INFOPLIST_KEY_CFBundleDisplayName = "MLBB Coach";
            INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.utilities";
            INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
            INFOPLIST_KEY_UILaunchScreen_Generation = YES;
            INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait;
            TARGETED_DEVICE_FAMILY = 1; CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 0.1.0;
            SWIFT_VERSION = 5.0; SWIFT_STRICT_CONCURRENCY = targeted;
            CODE_SIGN_STYLE = Automatic; ENABLE_USER_SCRIPT_SANDBOXING = YES;
            SWIFT_OPTIMIZATION_LEVEL = "{'-Onone' if config == 'Debug' else '-O'}";
        }};''')
    for kind in ('project', 'app'):
        obj(kind+'configs', f'isa = XCConfigurationList; buildConfigurations = ({uid(kind+":Debug")},{uid(kind+":Release")},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    obj('target', f'isa = PBXNativeTarget; buildConfigurationList = {uid("appconfigs")}; buildPhases = ({uid("sources")},{uid("frameworks")},{uid("resources")},); buildRules = (); dependencies = (); name = MLBBNeuralCoach; productName = MLBBNeuralCoach; productReference = {uid("product")}; productType = "com.apple.product-type.application";')
    obj('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2600; }}; buildConfigurationList = {uid("projectconfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = ru; hasScannedForEncodings = 0; knownRegions = (ru,en,Base,); mainGroup = {uid("rootgroup")}; productRefGroup = {uid("products")}; projectDirPath = ""; projectRoot = ""; targets = ({uid("target")},);')
    project = ROOT / 'MLBBNeuralCoach.xcodeproj'
    project.mkdir(exist_ok=True)
    (project / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {uid("project")}; }}\n', encoding='utf-8')
    scheme = project / 'xcshareddata/xcschemes/MLBBNeuralCoach.xcscheme'
    scheme.parent.mkdir(parents=True, exist_ok=True)
    ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target")}" BuildableName="MLBBNeuralCoach.app" BlueprintName="MLBBNeuralCoach" ReferencedContainer="container:MLBBNeuralCoach.xcodeproj"/>'
    scheme.write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug"/>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''', encoding='utf-8')
    print(f'Generated Xcode project: {len(files)} Swift sources')
if __name__ == '__main__':
    generate()
