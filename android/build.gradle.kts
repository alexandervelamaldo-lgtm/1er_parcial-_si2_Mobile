// Top-level build.gradle — sets the build directory and applies common
// settings to all subprojects (only `:app` in this template).
allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Re-route the build output to a shared location so Flutter can find the
// generated APK consistently across CI runs.
val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
