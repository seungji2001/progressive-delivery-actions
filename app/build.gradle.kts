plugins {
	java
	id("org.springframework.boot") version "4.1.1"
	id("io.spring.dependency-management") version "1.1.7"
}

group = "com.portfolio"
version = "1.0.1"

java {
	toolchain {
		languageVersion = JavaLanguageVersion.of(21)
	}
}

// Spring Boot 4.1.1 의 내장 Tomcat 11.0.24 에 CRITICAL CVE 3건(CVE-2026-65182, -65905, -68525) → 수정 버전으로 고정.
// CI Trivy 게이트가 릴리즈를 차단해 발견. Boot 패치 릴리즈가 11.0.25+ 를 포함하면 이 줄을 제거한다.
extra["tomcat.version"] = "11.0.27"

repositories {
	mavenCentral()
}

dependencies {
	implementation("org.springframework.boot:spring-boot-starter-actuator")
	implementation("org.springframework.boot:spring-boot-starter-validation")
	implementation("org.springframework.boot:spring-boot-starter-webmvc")
	testImplementation("org.springframework.boot:spring-boot-starter-actuator-test")
	testImplementation("org.springframework.boot:spring-boot-starter-validation-test")
	testImplementation("org.springframework.boot:spring-boot-starter-webmvc-test")
	testImplementation("org.springframework.boot:spring-boot-resttestclient")
	testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

springBoot {
	buildInfo()
}

tasks.withType<Test> {
	useJUnitPlatform()
}
