package tgx.gradle.plugin

import ApplicationConfig
import Config
import com.android.build.gradle.AppExtension
import com.android.build.gradle.BaseExtension
import com.android.build.gradle.LibraryExtension
import com.android.build.gradle.ProguardFiles
import org.gradle.api.Plugin
import org.gradle.api.Project
import org.gradle.api.tasks.compile.JavaCompile
import java.io.File

open class ModulePlugin : Plugin<Project> {
  override fun apply(project: Project) {
    project.logger.lifecycle("ModulePlugin: Applying to ${project.path}")
    
    val androidExt = try {
        project.extensions.getByName("android")
    } catch (e: Exception) {
        project.logger.lifecycle("ModulePlugin: Extension 'android' NOT FOUND for ${project.path}")
        return
    }
    
    if (androidExt is BaseExtension) {
      androidExt.apply {
        var compileSdkVersion: Int
        var buildToolsVersion: String
        var legacyNdkVersion: String
        var targetSdkVersion: Int

        val config = try {
          project.extensions.extraProperties["config"] as ApplicationConfig
        } catch (_: Exception) {
          null
        }
        
        if (config != null) {
          compileSdkVersion = config.compileSdkVersion
          buildToolsVersion = config.buildToolsVersion
          legacyNdkVersion = config.legacyNdkVersion
          targetSdkVersion = config.targetSdkVersion
        } else {
          val versions = project.rootProject.file("version.properties")
          val props = java.util.Properties().apply { if (versions.exists()) versions.inputStream().use { load(it) } }
          compileSdkVersion = props.getProperty("version.sdk_compile")?.toInt() ?: 35
          buildToolsVersion = props.getProperty("version.build_tools") ?: "35.0.0"
          targetSdkVersion = props.getProperty("version.sdk_target")?.toInt() ?: 35
          legacyNdkVersion = props.getProperty("version.ndk_legacy") ?: "26.3.11579264"
        }

        compileSdkVersion(compileSdkVersion)
        buildToolsVersion(buildToolsVersion)

        ndkVersion = legacyNdkVersion
        ndkPath = File(sdkDirectory, "ndk/$ndkVersion").absolutePath

        compileOptions {
          isCoreLibraryDesugaringEnabled = true
          sourceCompatibility = Config.JAVA_VERSION
          targetCompatibility = Config.JAVA_VERSION
        }

        testOptions {
          unitTests.isReturnDefaultValues = true
        }

        sourceSets.configureEach {
          jniLibs.srcDirs("jniLibs")
        }

        project.afterEvaluate {
          tasks.withType(JavaCompile::class.java).configureEach {
            options.compilerArgs.addAll(listOf(
              "-Xmaxerrs", "2000",
              "-Xmaxwarns", "2000",
              "-Xlint:all",
              "-Xlint:unchecked",
              "-Xlint:-serial",
              "-Xlint:-lossy-conversions",
              "-Xlint:-overloads",
              "-Xlint:-overrides",
              "-Xlint:-this-escape",
              "-Xlint:-deprecation",
            ))
          }
        }

        defaultConfig {
          minSdk = Config.MIN_SDK_VERSION
          targetSdk = targetSdkVersion
          multiDexEnabled = true
        }

        if (this is LibraryExtension) {
          project.logger.lifecycle("ModulePlugin: Configuring ${project.path} as Library")
          flavorDimensions.add("SDK")
          productFlavors {
            Sdk.VARIANTS.forEach { (_, variant) ->
              maybeCreate(variant.flavor).apply {
                dimension = "SDK"
                externalNativeBuild.cmake.arguments(
                  "-DANDROID_PLATFORM=android-${variant.minSdk}",
                  "-DTGX_FLAVOR=${variant.flavor}"
                )
              }
            }
          }
          defaultConfig {
            consumerProguardFiles("consumer-rules.pro")
          }
        } else if (this is AppExtension) {
          project.logger.lifecycle("ModulePlugin: Configuring ${project.path} as App")
          config?.keystore?.let { keystore ->
            signingConfigs {
              arrayOf(
                getByName("debug"),
                maybeCreate("release")
              ).forEach { config ->
                config.storeFile = keystore.file
                config.storePassword = keystore.password
                config.keyAlias = keystore.keyAlias
                config.keyPassword = keystore.keyPassword
                config.enableV2Signing = true
              }
            }

            buildTypes {
              getByName("debug") {
                signingConfig = signingConfigs["debug"]
                isDebuggable = true
                isJniDebuggable = true
                isMinifyEnabled = false
                ndk.debugSymbolLevel = "full"
                if (config.forceOptimize) {
                  proguardFiles(
                    getDefaultProguardFile(ProguardFiles.ProguardFile.OPTIMIZE.fileName),
                    "proguard-rules.pro"
                  )
                  if (config.isHuaweiBuild) {
                    proguardFile("proguard-hms.pro")
                  }
                }
              }

              getByName("release") {
                signingConfig = signingConfigs["release"]
                isMinifyEnabled = !config.doNotObfuscate
                isShrinkResources = !config.doNotObfuscate
                ndk.debugSymbolLevel = "full"
                proguardFiles(
                  getDefaultProguardFile(ProguardFiles.ProguardFile.OPTIMIZE.fileName),
                  "proguard-rules.pro"
                )
                if (config.isHuaweiBuild) {
                  proguardFile("proguard-hms.pro")
                }
              }
            }
          }

          project.dependencies.add("implementation", "androidx.multidex:multidex:2.0.1")
        }
      }
      
      // Ensure coreLibraryDesugaring is added to ALL modules applying this plugin
      project.dependencies.add("coreLibraryDesugaring", "com.android.tools:desugar_jdk_libs:2.1.5")
    }
  }
}
