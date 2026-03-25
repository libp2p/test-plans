plugins {
    kotlin("jvm") version "1.6.21"
    application
}

repositories {
    mavenCentral()
    maven { url = uri("https://dl.cloudsmith.io/public/libp2p/jvm-libp2p/maven/") }
    maven { url = uri("https://jitpack.io") }
    maven { url = uri("https://artifacts.consensys.net/public/maven/maven/") }
}

dependencies {
    implementation("io.libp2p:jvm-libp2p:1.2.2-RELEASE")
    implementation("com.fasterxml.jackson.module:jackson-module-kotlin:2.15.3")

    testImplementation(kotlin("test"))
}

application {
    mainClass.set("gossipsub.interop.MainKt")
}

tasks.test {
    useJUnitPlatform()
}
