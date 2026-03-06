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
import java.util.Properties

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
        var compileSdkVersionValue: Int
        var buildToolsVersionValue: String
        var legacyNdkVersionValue: String
        var targetSdkVersionValue: Int

        val config = try {
          val fromRoot = project.rootProject.extensions.extraProperties.let { if (it.has("config")) it["config"] else null }
          val fromLocal = project.extensions.extraProperties.let { if (it.has("config")) it["config"] else null }
          (fromRoot ?: fromLocal) as? ApplicationConfig
        } catch (e: Exception) {
          project.logger.lifecycle("ModulePlugin: Error retrieving config for ${project.path}: ${e.message}")
          null
        }
        
        if (config != null) {
          compileSdkVersionValue = config.compileSdkVersion
          buildToolsVersionValue = config.buildToolsVersion
          legacyNdkVersionValue = config.legacyNdkVersion
          targetSdkVersionValue = config.targetSdkVersion
        } else {
          val versionsFile = File(project.rootProject.projectDir, "version.properties")
          val props = Properties()
          if (versionsFile.exists()) {
            versionsFile.inputStream().use { props.load(it) }
          }
          compileSdkVersionValue = props.getProperty("version.sdk_compile")?.toInt() ?: 35
          buildToolsVersionValue = props.getProperty("version.build_tools") ?: "35.0.0"
          targetSdkVersionValue = props.getProperty("version.sdk_target")?.toInt() ?: 35
          legacyNdkVersionValue = props.getProperty("version.ndk_legacy") ?: "26.3.11579264"
        }

        compileSdkVersion(compileSdkVersionValue)
        buildToolsVersion(buildToolsVersionValue)

        ndkVersion = legacyNdkVersionValue
        ndkPath = File(sdkDirectory, "ndk/$ndkVersion").absolutePath

        compileOptions {
          isCoreLibraryDesugaringEnabled = true
          sourceCompatibility = Config.JAVA_VERSION
          targetCompatibility = Config.JAVA_VERSION
        }
        
        // AGP creates coreLibraryDesugaring configuration if isCoreLibraryDesugaringEnabled is true
        project.dependencies.add("coreLibraryDesugaring", "com.android.tools:desugar_jdk_libs:2.1.5")

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
          targetSdk = targetSdkVersionValue
          multiDexEnabled = true
        }

        if (this is LibraryExtension) {
          flavorDimensions += "SDK"
          productFlavors {
            Sdk.VARIANTS.forEach { (_, variant) ->
              maybeCreate(variant.flavor).apply {
                dimension = "SDK"
                externalNativeBuild.cmake.arguments(
                  "-DANDROID_PLATFORM=android-${variant.minSdk}",
                  "-DTGX_FLAVOR=${variant.flavor}",
                  "-DINSTALL_MANPAGES=OFF"
                )
              }
            }
          }
          defaultConfig {
            consumerProguardFiles("consumer-rules.pro")
          }
        } else if (this is AppExtension) {
          config?.keystore?.let { keystore ->
            signingConfigs {
              arrayOf(
                getByName("debug"),
                maybeCreate("release")
              ).forEach { sc ->
                sc.storeFile = keystore.file
                sc.storePassword = keystore.password
                sc.keyAlias = keystore.keyAlias
                sc.keyPassword = keystore.keyPassword
                sc.enableV2Signing = true
              }
            }

            buildTypes {
              getByName("debug") {
                signingConfig = signingConfigs.getByName("debug")
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
                signingConfig = signingConfigs.getByName("release")
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
    }
  }
}
