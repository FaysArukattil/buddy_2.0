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

subprojects {
    if (project.name != "app") {
        val setSdk: () -> Unit = {
            extensions.findByType(com.android.build.api.dsl.LibraryExtension::class.java)?.let {
                it.compileSdk = 36
            }
        }
        if (state.executed) {
            setSdk()
        } else {
            afterEvaluate { setSdk() }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
