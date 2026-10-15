import com.android.build.api.dsl.LibraryExtension
import com.android.build.api.variant.LibraryAndroidComponentsExtension
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// isar_flutter_libs 3.1.0+1 predates AGP's mandatory namespace property.
subprojects {
    plugins.withId("com.android.library") {
        if (project.name == "isar_flutter_libs") {
            extensions.configure<LibraryExtension> {
                namespace = "isar_flutter_libs"
            }
            extensions.configure<LibraryAndroidComponentsExtension> {
                finalizeDsl { extension ->
                    extension.compileSdk = 36
                }
            }
            tasks.matching { it.name.startsWith("process") && it.name.endsWith("Manifest") }
                .configureEach {
                    doFirst {
                        val manifest = project.file("src/main/AndroidManifest.xml")
                        if (manifest.exists()) {
                            manifest.writeText(
                                manifest.readText().replace(
                                    Regex("\\s+package=\"[^\"]+\""),
                                    "",
                                ),
                            )
                        }
                    }
                }
        }
    }
    if (project.name == "flutter_timezone") {
        tasks.withType<KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(JvmTarget.JVM_11)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
