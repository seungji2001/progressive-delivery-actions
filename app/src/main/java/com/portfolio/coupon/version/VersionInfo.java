package com.portfolio.coupon.version;

import java.net.InetAddress;
import java.net.UnknownHostException;
import java.time.Instant;

import org.springframework.beans.factory.ObjectProvider;
import org.springframework.boot.info.BuildProperties;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

/**
 * 현재 응답 중인 인스턴스의 버전 식별 정보.
 * 스모크 테스트 / 모니터 페이지가 blue·green, 카나리 비율을 판별하는 기준이다.
 */
@Component
public class VersionInfo {

	private final String version;
	private final String commit;
	private final String hostname;
	private final Instant startedAt = Instant.now();

	public VersionInfo(AppProperties properties, ObjectProvider<BuildProperties> buildProperties) {
		this.version = resolveVersion(properties.version(), buildProperties.getIfAvailable());
		this.commit = StringUtils.hasText(properties.commit()) ? properties.commit() : "unknown";
		this.hostname = resolveHostname();
	}

	private static String resolveVersion(String configured, BuildProperties build) {
		if (StringUtils.hasText(configured)) {
			return configured;
		}
		return build != null ? build.getVersion() : "unknown";
	}

	private static String resolveHostname() {
		String env = System.getenv("HOSTNAME");
		if (StringUtils.hasText(env)) {
			return env;
		}
		try {
			return InetAddress.getLocalHost().getHostName();
		}
		catch (UnknownHostException ex) {
			return "unknown";
		}
	}

	public String version() {
		return this.version;
	}

	public String commit() {
		return this.commit;
	}

	public String hostname() {
		return this.hostname;
	}

	public Instant startedAt() {
		return this.startedAt;
	}

}
